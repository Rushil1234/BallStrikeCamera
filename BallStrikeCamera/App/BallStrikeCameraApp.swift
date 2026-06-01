import SwiftUI

@main
struct BallStrikeCameraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AuthSessionStore()
    @StateObject private var camera  = CameraController()

    init() {
        WatchConnectivityBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(camera)
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task { await session.refreshSessionAndEntitlement() }
                }
        }
    }
}
