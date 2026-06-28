import SwiftUI
import CoreNFC

/// Camera screen for Live Sim mode. Identical to SimCameraScreen but also
/// broadcasts each shot to the browser sim via Supabase Realtime.
struct LiveSimCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var simVM: SimSessionViewModel
    @ObservedObject var liveSimService: LiveSimService
    @ObservedObject private var nfcManager = NFCManager.shared

    @State private var selectedClub = "7 Iron"
    @State private var selectedClubId: UUID?
    @State private var clubs: [UserClub] = []
    @State private var showClubPicker = false
    @State private var showSaveSheet = false
    @State private var saveSheetDefaultName = "Live Sim Session"

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: "Live Sim",
            selectedClub: $selectedClub,
            selectedClubId: selectedClubId,
            shotCount: simVM.shots.count,
            onChooseClub: {
                // Manual picker only. NFC club scanning lives in Manage Bag →
                // Add Club; the camera should never trigger the phone's NFC reader.
                showClubPicker = true
            },
            onDismiss: { dismiss() },
            onSaveSession: { beginSaveSessionFlow() },
            canSaveSession: simVM.sessionActive && !simVM.shots.isEmpty,
            onShotSaved: nil,
            onShotComplete: {}
        )
        .onChange(of: camera.showShotResult) { isShowing in
            guard isShowing, let analysis = camera.latestShotAnalysis,
                  let metrics = analysis.metrics else { return }

            let savedMetrics = SavedShotMetrics(metrics)

            // Broadcast to browser sim first so the ball flies immediately.
            Task { await liveSimService.broadcast(metrics: savedMetrics) }

            // Auto-save to session history.
            Task { await autoSave(analysis: analysis, metrics: savedMetrics) }
        }
        .onChange(of: selectedClub) { clubName in
            Task { await liveSimService.broadcastClub(clubName) }
        }
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
                        await simVM.endSessionWithDetails(name: name, description: desc, usedOGS: false)
                        dismiss()
                    }
                },
                onDelete: {
                    Task { await simVM.discardSession(); dismiss() }
                }
            )
        }
    }

    private func beginSaveSessionFlow() {
        guard simVM.sessionActive, !simVM.shots.isEmpty else { return }
        Task {
            saveSheetDefaultName = await simVM.computeDefaultName()
            showSaveSheet = true
        }
    }

    private func autoSave(analysis: ShotAnalysisResult, metrics: SavedShotMetrics) async {
        guard let uid = session.currentUser?.id else { return }

        let composite = ShotCompositeRenderer().render(analysis: analysis)

        await simVM.ensureSessionStarted()
        let service = ShotPersistenceService(userId: uid, backend: session.backend)
        let visRaw = UserDefaults.standard.string(forKey: "tc_default_visibility") ?? ShotVisibility.friends.rawValue
        guard let shot = try? await service.saveShot(
            metrics: metrics,
            compositeImage: composite,
            clubId: selectedClubId,
            clubName: selectedClub,
            mode: .sim,
            visibility: ShotVisibility(rawValue: visRaw) ?? .friends,
            sessionId: simVM.activeSession?.id
        ) else { return }

        await simVM.addShot(shot)
    }

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
        // Push current club to sim on connect (onChange won't fire if value didn't change)
        await liveSimService.broadcastClub(selectedClub)
    }
}
