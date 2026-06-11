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

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: "Sim",
            selectedClub: $selectedClub,
            selectedClubId: selectedClubId,
            shotCount: simVM.shots.count,
            onChooseClub: {
            showClubPicker = true
            if NFCNDEFReaderSession.readingAvailable {
                nfcManager.beginReading(alertMessage: "Or tap your NFC club to auto-select")
            }
        },
            onDismiss: { dismiss() },
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
                Task { await ogsVM.sendMetrics(savedMetrics) }
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
            OrientationManager.shared.lockPortrait()
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
    }

    // MARK: - Auto-save

    private func autoSave(analysis: ShotAnalysisResult, metrics: SavedShotMetrics) async {
        guard let uid = session.currentUser?.id else { return }

        // Render the ball-flight composite so it appears in History.
        let composite = ShotCompositeRenderer().render(analysis: analysis, mode: .darkenedHighContrast)

        let service = ShotPersistenceService(userId: uid, backend: session.backend)
        guard let shot = try? await service.saveShot(
            metrics: metrics,
            compositeImage: composite,
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
        } else if let preferred = clubs.first(where: { $0.name == "7 Iron" }) ?? clubs.first {
            selectedClub = preferred.name
            selectedClubId = preferred.id
            simVM.selectedClub = preferred
        }
    }
}
