import SwiftUI
import CoreNFC

/// Camera screen for Sim Mode. Reuses LaunchMonitorScaffoldView.
/// Auto-saves each shot (with composite image) as soon as analysis completes,
/// and fires the metrics to OpenGolfSim immediately so the ball flies right away.
struct SimCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var simVM: SimSessionViewModel
    @ObservedObject var ogsVM: OpenGolfSimViewModel
    @ObservedObject var gsproVM: GSProViewModel
    @ObservedObject var bleVM: SimBLEViewModel
    @ObservedObject private var nfcManager = NFCManager.shared

    @State private var selectedClub = "7 Iron"
    @State private var selectedClubId: UUID?
    @State private var clubs: [UserClub] = []
    @State private var showClubPicker = false
    @State private var showSaveSheet = false
    @State private var saveSheetDefaultName = "Sim Session"

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: "Sim",
            selectedClub: $selectedClub,
            selectedClubId: selectedClubId,
            shotCount: simVM.shots.count,
            onChooseClub: {
            // Manual picker only. NFC club scanning lives in Manage Bag → Add
            // Club; the camera should never trigger the phone's NFC reader.
            showClubPicker = true
        },
            onDismiss: { dismiss() },
            onSaveSession: {
                beginSaveSessionFlow()
            },
            canSaveSession: simVM.sessionActive && !simVM.shots.isEmpty,
            onShotSaved: nil,   // auto-saved below; review screen is informational only
            onShotComplete: {}  // stay armed for next shot
        )
        // Fires the moment analysis completes and the result card appears.
        .onChange(of: camera.showShotResult) { isShowing in
            guard isShowing, let analysis = camera.latestShotAnalysis,
                  let metrics = analysis.metrics else { return }

            let savedMetrics = SavedShotMetrics(metrics)

            // Send to simulator — network first, BLE bridge as fallback.
            if ogsVM.connectionState.isConnected {
                Task { await ogsVM.sendMetrics(savedMetrics, club: selectedClub) }
            } else if gsproVM.connectionState.isConnected {
                Task { await gsproVM.sendMetrics(savedMetrics) }
            } else if bleVM.state.isReady {
                Task { await bleVM.sendMetrics(savedMetrics) }
            }

            // Auto-save the shot (True Carry stats + composite jpg) to the session.
            Task { await autoSave(analysis: analysis, metrics: savedMetrics) }
        }
        // Hub or NFC tap while in sim mode — auto-select without opening picker
        .onChange(of: nfcManager.lastScannedClubId) { clubId in
            guard let clubId else { return }
            if let match = clubs.first(where: { $0.id == clubId }) {
                selectedClub   = match.name
                selectedClubId = match.id
                showClubPicker = false
                simVM.selectedClub = match
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .onChange(of: showClubPicker) { isShowing in
            if !isShowing { nfcManager.cancelRead() }
        }
        .onAppear {
            OrientationManager.shared.lockLandscape()
            camera.start()
            Task { await loadClubs() }
        }
        .onDisappear {
            OrientationManager.shared.unlockAllButUpsideDown()
            camera.stop()
        }
        .confirmationDialog("Select Club", isPresented: $showClubPicker, titleVisibility: .visible) {
            ForEach(clubs) { club in
                Button(club.name) {
                    selectedClub = club.name
                    selectedClubId = club.id
                    simVM.selectedClub = club
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSaveSheet) {
            SessionSaveSheet(
                config: SessionSaveConfig(
                    type: .sim,
                    defaultName: saveSheetDefaultName,
                    date: simVM.activeSession?.startedAt ?? Date()
                ),
                onSave: { name, desc in
                    Task {
                        await simVM.endSessionWithDetails(
                            name: name,
                            description: desc,
                            usedOGS: ogsVM.connectionState.isConnected
                        )
                        dismiss()
                    }
                },
                onDelete: {
                    Task {
                        await simVM.discardSession()
                        dismiss()
                    }
                }
            )
        }
    }

    // MARK: - Auto-save

    private func beginSaveSessionFlow() {
        guard simVM.sessionActive, !simVM.shots.isEmpty else { return }
        Task {
            saveSheetDefaultName = await simVM.computeDefaultName()
            showSaveSheet = true
        }
    }

    private func autoSave(analysis: ShotAnalysisResult, metrics: SavedShotMetrics) async {
        guard let uid = session.currentUser?.id else { return }

        let composite = ShotCompositeRenderer().render(analysis: analysis, mode: .darkenedHighContrast)
        let impact = analysis.detectedImpactFrameIndex
        let frames = analysis.frames
            .sorted { $0.frameIndex < $1.frameIndex }
            .filter { abs($0.frameIndex - impact) <= 5 }
            .map { $0.originalFrame.image }

        let service = ShotPersistenceService(userId: uid, backend: session.backend)
        guard let shot = try? await service.saveShot(
            metrics: metrics,
            compositeImage: composite,
            originalFrames: frames,
            clubId: selectedClubId,
            clubName: selectedClub,
            mode: .sim,
            saveOriginalFrames: false,
            sessionId: simVM.activeSession?.id
        ) else { return }

        await simVM.addShot(shot)
    }

    // MARK: - Club loading

    private func loadClubs() async {
        await simVM.loadClubs()
        clubs = simVM.clubs
        if let selected = simVM.selectedClub {
            selectedClub = selected.name
            selectedClubId = selected.id
        } else if let preferred = ClubPreference.preferred(in: clubs) {
            selectedClub = preferred.name
            selectedClubId = preferred.id
            simVM.selectedClub = preferred
        }
    }
}
