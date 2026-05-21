import SwiftUI

struct RangeCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rangeVM: RangeSessionViewModel

    @State private var selectedClub = "7 Iron"
    @State private var selectedClubId: UUID?
    @State private var clubs: [UserClub] = []
    @State private var showClubPicker = false
    @State private var showEndConfirmation = false
    @State private var showSaveSheet = false
    @State private var saveSheetDefaultName = "Range Session"

    var context: ShotContext? = nil
    var externalOnShotSaved: ((SavedShot) -> Void)? = nil

    private var isCourseMode: Bool { context?.sourceMode == .course }

    init(userId: UUID,
         backend: AppBackend,
         initialClubId: UUID? = nil,
         initialClubName: String? = nil,
         context: ShotContext? = nil,
         onShotSaved: ((SavedShot) -> Void)? = nil) {
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
                        exitClean()
                    }
                } else {
                    exitClean()
                }
            },
            onShotSaved: { shot in
                if let handler = externalOnShotSaved {
                    handler(shot)
                } else {
                    Task { await rangeVM.addShot(shot) }
                }
            },
            onShotComplete: {}
        )
        .onAppear {
            OrientationManager.shared.lockLandscape()
            camera.start()
            if !isCourseMode {
                Task {
                    await loadClubs()
                    await rangeVM.startSession()
                }
            } else {
                Task { await loadClubs() }
            }
        }
        .onDisappear {
            OrientationManager.shared.lockPortrait()
            camera.stop()
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
                )
            ) { name, desc in
                Task {
                    await rangeVM.endSessionWithDetails(name: name, description: desc)
                    exitClean()
                }
            }
        }
        .confirmationDialog("Select Club", isPresented: $showClubPicker, titleVisibility: .visible) {
            ForEach(clubs) { club in
                Button(club.name) {
                    selectedClub = club.name
                    selectedClubId = club.id
                }
            }
            Button("Cancel", role: .cancel) {}
        }
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
