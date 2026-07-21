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
    @State private var saveSheetDefaultName = "TCSim Session"

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: "TCSim",
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
        .overlay(alignment: .top) {
            if simVM.isMultiPlayer { whoseTurnPill.padding(.top, 60) }
        }
        // Fires when analysis completes with a real result. showShotResult can NOT be the
        // trigger: the analyzing cover flips it true at capture time, before metrics exist —
        // onChange fired once against a nil latestShotAnalysis and never again when the
        // result landed (the flag was already true), so real shots showed on the phone but
        // never reached the sim. isAnalyzingShot goes true → false exactly once per shot,
        // strictly after latestShotAnalysis is assigned.
        .onChange(of: camera.isAnalyzingShot) { isAnalyzing in
            guard !isAnalyzing, camera.showShotResult,
                  let analysis = camera.latestShotAnalysis,
                  let metrics = analysis.metrics else { return }

            let savedMetrics = SavedShotMetrics(metrics)

            // Broadcast to browser sim first so the ball flies immediately.
            Task {
                await liveSimService.broadcast(
                    metrics: savedMetrics,
                    playerIndex: simVM.currentPlayerIndex,
                    playerName: simVM.currentPlayerName
                )
            }

            // Then the real-swing composite for the sim's picture-in-picture.
            Task {
                if let composite = ShotCompositeRenderer().render(analysis: analysis) {
                    await liveSimService.broadcastSwingImage(composite)
                }
            }

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
            // Multi-player: tell the sim the full roster once so it can track each player's
            // own ball position from their very first tee shot. No-op for single-player.
            if simVM.isMultiPlayer {
                Task { await liveSimService.broadcastPlayers(names: simVM.players) }
            }
        }
        .onDisappear {
            OrientationManager.shared.unlockAllButUpsideDown()
            camera.stop()
            GoogleDriveUploadService.shared.autoOffloadIfNeeded()
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
                        // Attach the web sim's real round result (course, score,
                        // holes) to the saved session automatically.
                        let summary = liveSimService.liveState?.roundSummary?.display
                        let fullDesc = [desc, summary]
                            .compactMap { $0?.isEmpty == false ? $0 : nil }
                            .joined(separator: "\n")
                        await simVM.endSessionWithDetails(
                            name: name,
                            description: fullDesc.isEmpty ? nil : fullDesc,
                            usedOGS: false
                        )
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

        // Multi-player: another player's shot already broadcast to the browser sim above
        // (untouched) — it just doesn't get saved to the account holder's own shot history.
        guard simVM.isCurrentPlayerAccountHolder else {
            simVM.advanceToNextPlayerIfNeeded()
            return
        }

        let composite = ShotCompositeRenderer().render(analysis: analysis)

        await simVM.ensureSessionStarted()
        let service = ShotPersistenceService(userId: uid, backend: session.backend)
        let visRaw = UserDefaults.standard.string(forKey: "tc_default_visibility") ?? ShotVisibility.friends.rawValue
        guard let shot = try? await service.saveShot(
            metrics: metrics,
            compositeImage: composite,
            replayFrames: analysis.frames.map { $0.brightenedImage ?? $0.originalFrame.image },
            clubId: selectedClubId,
            clubName: selectedClub,
            mode: .sim,
            visibility: ShotVisibility(rawValue: visRaw) ?? .friends,
            sessionId: simVM.activeSession?.id
        ) else { return }

        await simVM.addShot(shot)
        simVM.advanceToNextPlayerIfNeeded()
    }

    // MARK: - Whose turn

    private var whoseTurnPill: some View {
        Menu {
            ForEach(simVM.players.indices, id: \.self) { i in
                Button {
                    simVM.selectPlayer(i)
                } label: {
                    if i == simVM.currentPlayerIndex {
                        Label(simVM.players[i], systemImage: "checkmark")
                    } else {
                        Text(simVM.players[i])
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                Text("Up: \(simVM.currentPlayerName)")
                Image(systemName: "chevron.down")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.55)))
        }
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
