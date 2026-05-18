import SwiftUI

struct RangeCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClub = "7 Iron"
    @State private var selectedClubId: UUID?
    @State private var clubs: [UserClub] = []
    @State private var showClubPicker = false

    var context: ShotContext? = nil
    var shotCount: Int = 0
    var onShotSaved: ((SavedShot) -> Void)? = nil
    var onShotComplete: (() -> Void)? = nil

    init(initialClubId: UUID? = nil,
         initialClubName: String? = nil,
         shotCount: Int = 0,
         context: ShotContext? = nil,
         onShotSaved: ((SavedShot) -> Void)? = nil,
         onShotComplete: (() -> Void)? = nil) {
        self._selectedClub = State(initialValue: initialClubName ?? "7 Iron")
        self._selectedClubId = State(initialValue: initialClubId)
        self.shotCount = shotCount
        self.context = context
        self.onShotSaved = onShotSaved
        self.onShotComplete = onShotComplete
    }

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: context?.sourceMode == .course ? "Course" : "Range",
            selectedClub: $selectedClub,
            selectedClubId: selectedClubId,
            shotCount: shotCount,
            context: context,
            onChooseClub: { showClubPicker = true },
            onDismiss: {
                OrientationManager.shared.lockPortrait()
                dismiss()
            },
            onShotSaved: onShotSaved,
            onShotComplete: {
                onShotComplete?()
                OrientationManager.shared.lockPortrait()
                dismiss()
            }
        )
        .onAppear  { OrientationManager.shared.lockLandscape() }
        .onDisappear { OrientationManager.shared.lockPortrait() }
        .task { await loadClubs() }
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

    private func loadClubs() async {
        guard let uid = session.currentUser?.id else { return }
        let loaded = ((try? await session.backend.loadClubs(userId: uid)) ?? [])
            .filter { $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
        clubs = loaded

        if let selectedClubId,
           let match = loaded.first(where: { $0.id == selectedClubId }) {
            selectedClub = match.name
            return
        }

        if let nameMatch = loaded.first(where: { $0.name == selectedClub }) {
            selectedClubId = nameMatch.id
            selectedClub = nameMatch.name
            return
        }

        if let preferred = loaded.first(where: { $0.name == "7 Iron" }) ?? loaded.first {
            selectedClub = preferred.name
            selectedClubId = preferred.id
        }
    }
}
