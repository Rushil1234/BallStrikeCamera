import SwiftUI
import CoreNFC

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
                // Silent NFC club detection — two delivery paths:
                // 1. URL routing: truecarry://nfc/{uuid} when app is backgrounded
                .onOpenURL { url in
                    NFCManager.shared.handleNFCURL(url)
                }
                // 2. NSUserActivity: delivered directly to foreground app with zero UI
                .onContinueUserActivity("com.apple.corenfc.tag") { activity in
                    guard let message = activity.ndefMessagePayload else { return }
                    for record in message.records {
                        if let url = record.wellKnownTypeURIPayload() {
                            NFCManager.shared.handleNFCURL(url)
                            return
                        }
                        // Also handle text records (fallback)
                        if let text = String(data: record.payload.dropFirst(min(3, record.payload.count)), encoding: .utf8),
                           let uuid = UUID(uuidString: text) {
                            NFCManager.shared.lastScannedClubId = uuid
                            return
                        }
                    }
                }
        }
    }
}
