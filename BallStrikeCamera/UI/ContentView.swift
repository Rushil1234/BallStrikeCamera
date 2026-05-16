import SwiftUI

struct ContentView: View {
    var body: some View {
        AppRootView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthSessionStore())
        .environmentObject(CameraController())
}
