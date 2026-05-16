import SwiftUI

@main
struct BallStrikeCameraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = AuthSessionStore()
    @StateObject private var camera  = CameraController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(camera)
        }
    }
}
