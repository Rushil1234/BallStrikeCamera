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
    // Falls back to a name match for the "7 Iron" default before clubs finish loading — matches
    // the same club-type lookup the capture pipeline needs before a shot is ever hit.
    private var isPutterSelected: Bool {
        if let match = clubs.first(where: { $0.id == selectedClubId }) {
            return match.type == .putter
        }
        return selectedClub.localizedCaseInsensitiveContains("putter")
    }

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
        // First-time beginner hint: how to set up the phone as a launch monitor.
        .firstTimeHint(
            id: "cameraSetup",
            icon: "iphone.gen3",
            text: "Stand your iPhone on a tripod about waist-high, 6-8 ft to the side of the ball, framing the hitting area. Then take your normal swing."
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
        .onChange(of: selectedClub) { _ in syncPutterMode() }
        .onChange(of: selectedClubId) { _ in syncPutterMode() }
        // Keyed on the analysis timestamp: the result cover now presents before analysis
        // completes, so showShotResult flips while latestShotAnalysis is still nil.
        .onChange(of: camera.latestShotAnalysis?.createdAt) { _ in
            guard camera.showShotResult, !isCourseMode,
                  let analysis = camera.latestShotAnalysis,
                  let metrics = analysis.metrics else { return }
            Task { await autoSave(analysis: analysis, metrics: SavedShotMetrics(metrics)) }
        }
        .onAppear {
            OrientationManager.shared.lockLandscape()
            syncPutterMode()
            camera.start()
            if !isCourseMode {
                Task {
                    await loadClubs()
                    syncPutterMode()
                    await rangeVM.startSession()
                    registerWatchRangeControls()
                    publishWatchRangeState()
                }
            } else {
                Task {
                    await loadClubs()
                    syncPutterMode()
                }
            }
        }
        .onDisappear {
            OrientationManager.shared.unlockAllButUpsideDown()
            camera.stop()
            GoogleDriveUploadService.shared.autoOffloadIfNeeded()
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

    private func syncPutterMode() {
        camera.isPutterMode = isPutterSelected
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
        // This fires the instant the result screen starts presenting. The composite render +
        // JPEG encoding of the replay frames are seconds of work — running them on the main
        // actor (the default for a view method) froze the presentation animation. Hop off.
        let userId = self.userId
        let backend = self.backend
        let clubId = selectedClubId
        let clubName = selectedClub
        let visibility = ShotVisibility(rawValue: defaultVisibilityRaw) ?? .friends
        let sessionId = rangeVM.activeSession?.id
        let shot = await Task.detached(priority: .userInitiated) { () -> SavedShot? in
            let composite = ShotCompositeRenderer().render(analysis: analysis)
            let service = ShotPersistenceService(userId: userId, backend: backend)
            return try? await service.saveShot(
                metrics: metrics,
                compositeImage: composite,
                replayFrames: analysis.frames.map { $0.brightenedImage ?? $0.originalFrame.image },
                clubId: clubId,
                clubName: clubName,
                mode: .range,
                visibility: visibility,
                sessionId: sessionId
            )
        }.value
        guard let shot else { return }
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
