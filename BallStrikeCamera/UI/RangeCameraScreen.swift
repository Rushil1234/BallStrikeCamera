import SwiftUI

struct RangeCameraScreen: View {
    @EnvironmentObject private var camera: CameraController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClub = "7 Iron"

    var body: some View {
        LaunchMonitorScaffoldView(
            camera: camera,
            modeTitle: "Range",
            selectedClub: $selectedClub,
            shotCount: 12,
            onDismiss: {
                print("Dismiss RangeCameraScreen")
                OrientationManager.shared.lockPortrait()
                dismiss()
            }
        )
        .onAppear {
            print("Navigating to RangeCameraScreen")
            OrientationManager.shared.lockLandscape()
        }
        .onDisappear {
            OrientationManager.shared.lockPortrait()
        }
    }
}
