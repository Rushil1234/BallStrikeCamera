import SwiftUI

struct RangeCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rangeVM: RangeSessionViewModel
    @AppStorage("tc_save_original_frames") private var defaultSaveOriginalFrames = false

    @State private var selectedClub = "7 Iron"
    @State private var selectedClubId: UUID?
    @State private var clubs: [UserClub] = []
    @State private var showClubPicker = false
    @State private var showEndConfirmation = false
    @State private var showSaveSheet = false
    @State private var saveSheetDefaultName = "Range Session"

    var context: ShotContext? = nil
    var externalOnShotSaved: ((SavedShot) -> Void)? = nil

    private let userId: UUID
    private let backend: AppBackend
    private var isCourseMode: Bool { context?.sourceMode == .course }

    init(userId: UUID,
         backend: AppBackend,
         initialClubId: UUID? = nil,
         initialClubName: String? = nil,
         context: ShotContext? = nil,
         onShotSaved: ((SavedShot) -> Void)? = nil) {
        self.userId = userId
        self.backend = backend
        _rangeVM = StateObject(wrappedValue: RangeSessionViewModel(userId: userId, backend: backend))
        _selectedClub = State(initialValue: initialClubName ?? "7 Iron")
        _selectedClubId = State(initialValue: initialClubId)
        self.context = context
        self.externalOnShotSaved = onShotSaved
    }

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: isCourseMode ? "Course" : "Range",
            selectedClub: $selectedClub,
            selectedClubId: selectedClubId,
            shotCount: isCourseMode ? 0 : rangeVM.shots.count,
            context: context,
            onChooseClub: { showClubPicker = true },
            onDismiss: {
                if !isCourseMode && !rangeVM.shots.isEmpty {
                    showEndConfirmation = true
                } else if !isCourseMode && rangeVM.sessionActive {
                    // Empty session — just discard silently
                    Task {
                        await rangeVM.discardSession()
                        publishWatchRangeState()
                        exitClean()
                    }
                } else {
                    exitClean()
                }
            },
            onShotSaved: isCourseMode ? externalOnShotSaved : nil,
            onShotComplete: {}
        )
        // Silent NFC club detection — updates selected club without any UI interruption
        .onChange(of: NFCManager.shared.lastScannedClubId) { clubId in
            guard let clubId,
                  let match = clubs.first(where: { $0.id == clubId }) else { return }
            selectedClub   = match.name
            selectedClubId = match.id
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onChange(of: camera.showShotResult) { isShowing in
            guard isShowing, !isCourseMode,
                  let analysis = camera.latestShotAnalysis,
                  let metrics = analysis.metrics else { return }
            Task { await autoSave(analysis: analysis, metrics: SavedShotMetrics(metrics)) }
        }
        .onAppear {
            OrientationManager.shared.lockLandscape()
            camera.start()
            if !isCourseMode {
                Task {
                    await loadClubs()
                    await rangeVM.startSession()
                    registerWatchRangeControls()
                    publishWatchRangeState()
                }
            } else {
                Task { await loadClubs() }
            }
        }
        .onDisappear {
            OrientationManager.shared.lockPortrait()
            camera.stop()
            if !isCourseMode {
                WatchConnectivityBridge.shared.unregisterRangeCommandHandler()
            }
        }
        // Phase 1: Save / Delete / Continue choice
        .confirmationDialog(
            "End Range Session?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save Session") {
                Task {
                    saveSheetDefaultName = await rangeVM.computeDefaultName()
                    showSaveSheet = true
                }
            }
            Button("Delete Session", role: .destructive) {
                Task {
                    await rangeVM.discardSession()
                    publishWatchRangeState()
                    exitClean()
                }
            }
            Button("Continue Session", role: .cancel) {}
        } message: {
            Text(rangeVM.shots.count > 0
                 ? "Save this session to History or delete it? You have \(rangeVM.shots.count) shot\(rangeVM.shots.count == 1 ? "" : "s")."
                 : "Save this session to History or delete it?")
        }
        // Phase 2: Name + description entry
        .sheet(isPresented: $showSaveSheet) {
            SessionSaveSheet(
                config: SessionSaveConfig(
                    type: .range,
                    defaultName: saveSheetDefaultName,
                    date: rangeVM.activeSession?.startedAt ?? Date()
                ),
                onSave: { name, desc in
                    Task { await rangeVM.endSessionWithDetails(name: name, description: desc); publishWatchRangeState(); exitClean() }
                },
                onDelete: {
                    Task { await rangeVM.discardSession(); exitClean() }
                }
            )
        }
        .confirmationDialog("Select Club", isPresented: $showClubPicker, titleVisibility: .visible) {
            ForEach(clubs) { club in
                Button(club.name) {
                    selectedClub = club.name
                    selectedClubId = club.id
                    publishWatchRangeState()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func autoSave(analysis: ShotAnalysisResult, metrics: SavedShotMetrics) async {
        let composite = ShotCompositeRenderer().render(analysis: analysis, mode: .darkenedHighContrast)
        let service = ShotPersistenceService(userId: userId, backend: backend)
        guard let shot = try? await service.saveShot(
            metrics: metrics,
            compositeImage: composite,
            clubId: selectedClubId,
            clubName: selectedClub,
            mode: .range,
            saveOriginalFrames: rangeVM.saveOriginalFrames,
            sessionId: rangeVM.activeSession?.id
        ) else { return }
        await rangeVM.addShot(shot)
        publishWatchRangeState()
    }

    private func registerWatchRangeControls() {
        WatchConnectivityBridge.shared.registerRangeCommandHandler { command in
            await handleWatchRangeCommand(command)
        }
    }

    private func handleWatchRangeCommand(_ command: WatchCommand) async -> WatchCommandResult {
        switch command.kind {
        case .refresh, .rangeRefresh:
            publishWatchRangeState()
            return .success()
        case .rangeStart:
            if !rangeVM.sessionActive {
                await rangeVM.startSession()
            }
            publishWatchRangeState()
            return .success()
        case .rangeEnd:
            if rangeVM.sessionActive {
                await rangeVM.endSession()
            }
            publishWatchRangeState()
            return .success()
        case .roundNextHole, .roundPreviousHole, .roundSetScore:
            return .failure("That command is for Round mode.")
        }
    }

    private func publishWatchRangeState() {
        guard !isCourseMode else { return }
        let summary = rangeVM.summary
        WatchConnectivityBridge.shared.publishRange(
            WatchCompanionRangeSnapshot(
                isActive: rangeVM.sessionActive,
                selectedClubName: selectedClub,
                shotCount: summary.shotCount,
                averageCarryYards: Int(summary.avgCarry.rounded()),
                bestCarryYards: Int(summary.bestCarry.rounded()),
                averageBallSpeedMph: Int(summary.avgBallSpeed.rounded())
            ),
            latestShot: rangeVM.shots.last.map { shot in
                WatchCompanionShotSnapshot(
                    clubName: shot.clubName,
                    carryYards: Int(shot.metrics.carryYards.rounded()),
                    totalYards: Int(shot.metrics.totalYards.rounded()),
                    ballSpeedMph: Int(shot.metrics.ballSpeedMph.rounded()),
                    smashFactor: shot.metrics.smashFactor,
                    timestamp: shot.timestamp
                )
            }
        )
    }

    private func exitClean() {
        OrientationManager.shared.lockPortrait()
        dismiss()
    }

    private func loadClubs() async {
        await rangeVM.loadClubs()
        clubs = rangeVM.clubs

        if let selectedClubId,
           let match = clubs.first(where: { $0.id == selectedClubId }) {
            selectedClub = match.name
            return
        }
        if let nameMatch = clubs.first(where: { $0.name == selectedClub }) {
            selectedClubId = nameMatch.id
            selectedClub = nameMatch.name
            return
        }
        if let preferred = clubs.first(where: { $0.name == "7 Iron" }) ?? clubs.first {
            selectedClub = preferred.name
            selectedClubId = preferred.id
        }
    }
}
