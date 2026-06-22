import SwiftUI
import CoreNFC

struct RangeCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rangeVM: RangeSessionViewModel
    @ObservedObject private var nfcManager = NFCManager.shared
    @AppStorage("tc_save_original_frames") private var defaultSaveOriginalFrames = false
    @AppStorage("tc_default_visibility") private var defaultVisibilityRaw = ShotVisibility.friends.rawValue

    @State private var selectedClub = "7 Iron"
    @State private var selectedClubId: UUID?
    @State private var clubs: [UserClub] = []
    @State private var showClubPicker = false
    @State private var showSavePage = false
    @State private var isFinishing = false
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
            onChooseClub: {
                // Manual picker only. NFC club scanning lives in Manage Bag →
                // Add Club; the camera should never trigger the phone's NFC reader.
                showClubPicker = true
            },
            onDismiss: {
                if !isCourseMode && !rangeVM.shots.isEmpty {
                    beginSaveSessionFlow()
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
            onSaveSession: isCourseMode ? nil : {
                beginSaveSessionFlow()
            },
            canSaveSession: !isCourseMode && rangeVM.sessionActive && !rangeVM.shots.isEmpty,
            onShotSaved: isCourseMode ? externalOnShotSaved : nil,
            onShotComplete: {}
        )
        // NFC foreground scan — fires when user taps a tagged club during picker session
        .onChange(of: nfcManager.lastScannedClubId) { clubId in
            guard let clubId else { return }
            if let match = clubs.first(where: { $0.id == clubId }) {
                selectedClub   = match.name
                selectedClubId = match.id
                ClubPreference.remember(match)
                showClubPicker = false
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                publishWatchRangeState()
            }
        }
        // Cancel the NFC session if the picker is dismissed without tapping a tag
        .onChange(of: showClubPicker) { isShowing in
            if !isShowing { nfcManager.cancelRead() }
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
            OrientationManager.shared.unlockAllButUpsideDown()
            camera.stop()
            if !isCourseMode {
                WatchConnectivityBridge.shared.unregisterRangeCommandHandler()
            }
        }
        // Save flow is a full-screen page in the user's natural orientation (not a popup over
        // the landscape camera). Continue → back to camera (re-lock landscape); Save/Delete →
        // leave the camera entirely back to Play.
        .fullScreenCover(isPresented: $showSavePage, onDismiss: {
            if !isFinishing { OrientationManager.shared.lockLandscape() }
        }) {
            SessionSaveSheet(
                config: SessionSaveConfig(
                    type: .range,
                    defaultName: saveSheetDefaultName,
                    date: rangeVM.activeSession?.startedAt ?? Date()
                ),
                onSave: { name, desc in
                    isFinishing = true
                    Task { await rangeVM.endSessionWithDetails(name: name, description: desc); publishWatchRangeState(); exitClean() }
                },
                onDelete: {
                    isFinishing = true
                    Task { await rangeVM.discardSession(); publishWatchRangeState(); exitClean() }
                }
            )
        }
        .confirmationDialog("Select Club", isPresented: $showClubPicker, titleVisibility: .visible) {
            ForEach(clubs) { club in
                Button(club.name) {
                    selectedClub = club.name
                    selectedClubId = club.id
                    ClubPreference.remember(club)
                    publishWatchRangeState()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func beginSaveSessionFlow() {
        guard rangeVM.sessionActive, !rangeVM.shots.isEmpty else { return }
        isFinishing = false
        // Drop the landscape lock so the save page uses the phone's natural orientation.
        OrientationManager.shared.unlockAllButUpsideDown()
        Task {
            saveSheetDefaultName = await rangeVM.computeDefaultName()
            showSavePage = true
        }
    }

    private func autoSave(analysis: ShotAnalysisResult, metrics: SavedShotMetrics) async {
        guard metrics.carryYards > 0 || metrics.ballSpeedMph > 0 else { return }
        // Every shot belongs to a session — autostart one if needed (also resolves the frame cap).
        await rangeVM.ensureSessionStarted()
        let composite = ShotCompositeRenderer().render(analysis: analysis, mode: .darkenedHighContrast)
        let service = ShotPersistenceService(userId: userId, backend: backend)
        let framesToSave = impactFrames(from: analysis, fullSet: rangeVM.saveOriginalFrames)
        guard let shot = try? await service.saveShot(
            metrics: metrics,
            compositeImage: composite,
            originalFrames: framesToSave,
            clubId: selectedClubId,
            clubName: selectedClub,
            mode: .range,
            saveOriginalFrames: rangeVM.saveOriginalFrames,
            framesAllowed: rangeVM.framesAllowed,
            visibility: ShotVisibility(rawValue: defaultVisibilityRaw) ?? .friends,
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

    /// Returns the 11 frames centered on impact (±5), or all frames if fullSet=true.
    private func impactFrames(from analysis: ShotAnalysisResult, fullSet: Bool) -> [UIImage] {
        let sorted = analysis.frames.sorted { $0.frameIndex < $1.frameIndex }
        if fullSet { return sorted.map { $0.originalFrame.image } }
        let impact = analysis.detectedImpactFrameIndex
        return sorted
            .filter { abs($0.frameIndex - impact) <= 5 }
            .map { $0.originalFrame.image }
    }

    private func exitClean() {
        OrientationManager.shared.unlockAllButUpsideDown()
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
        if let preferred = ClubPreference.preferred(in: clubs) {
            selectedClub = preferred.name
            selectedClubId = preferred.id
        }
    }
}
