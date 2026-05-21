import SwiftUI

struct ContentView: View {
    @State private var launchComplete = false

    var body: some View {
        ZStack {
            AppRootView()

            if !launchComplete {
                TrueCarryLaunchView {
                    withAnimation(.easeOut(duration: 0.5)) { launchComplete = true }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthSessionStore())
        .environmentObject(CameraController())
}
