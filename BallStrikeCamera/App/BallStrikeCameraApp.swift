import SwiftUI
import CoreNFC

@main
struct BallStrikeCameraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AuthSessionStore()
    @StateObject private var camera  = CameraController()

    init() {
        // Install crash/error reporting first so early failures are captured.
        // Reads an optional Sentry DSN from Secrets.plist (`SentryDSN`); nil = first-party only.
        CrashReporter.shared.configure(dsn: CrashReporter.secretsDSN())
        WatchConnectivityBridge.shared.activate()
        // Touch the singleton so CBCentralManager is created and begins scanning
        // as soon as Bluetooth is available — before any camera screen opens.
        _ = RFIDHubManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(camera)
                .task {
                    // Wire crash/error telemetry to the backend + report any prior crash.
                    CrashReporter.shared.attach(backend: session.backend)
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task { await session.refreshSessionAndEntitlement() }
                }
                // Silent NFC club detection — two delivery paths:
                // 1. URL routing: truecarry://nfc/{uuid} when app is backgrounded
                .onOpenURL { url in
                    if url.scheme == "truecarry" { print("[NFC] onOpenURL: \(url.absoluteString)") }
                    NFCManager.shared.handleNFCURL(url)
                }
                // 2. NSUserActivity: delivered directly to foreground app with zero UI
                // (requires NSUserActivityTypes in Info.plist)
                .onContinueUserActivity("com.apple.corenfc.tag") { activity in
                    print("[NFC] NSUserActivity received — records: \(activity.ndefMessagePayload.records.count)")
                    for record in activity.ndefMessagePayload.records {
                        print("[NFC] record typeNameFormat=\(record.typeNameFormat.rawValue)")
                        if let url = record.wellKnownTypeURIPayload() {
                            print("[NFC] URI: \(url.absoluteString)")
                            NFCManager.shared.handleNFCURL(url)
                            return
                        }
                    }
                }
        }
    }
}
