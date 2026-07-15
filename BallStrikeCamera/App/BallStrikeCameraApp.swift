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

        #if DEBUG
        // Headless replay for simulator/CI: TC_REPLAY_EXPORTS=1 runs every export in
        // Documents/ShotExports + AllFramesArchive through the live-parity pipeline,
        // prints the full diagnostics, then exits. Nothing else in the app starts mattering.
        if ProcessInfo.processInfo.environment["TC_REPLAY_EXPORTS"] == "1" {
            Task.detached(priority: .userInitiated) {
                let loader = TestFrameLoader()
                let exports = loader.listAvailableExports()
                print("[Replay] headless mode — \(exports.count) export(s) found")
                for url in exports.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    do {
                        let seq = try loader.loadSequence(from: url)
                        print("\n[Replay] ================ \(seq.sourceName) (\(seq.frames.count) frames, impact=\(seq.impactFrameIndex)) ================")
                        _ = LiveParityTestRunner().run(sequence: seq)
                    } catch {
                        print("[Replay] FAILED to load \(url.lastPathComponent): \(error)")
                    }
                }
                print("\n[Replay] headless run complete — exiting")
                exit(0)
            }
        }
        #endif
    }

    // TC_OPEN_TESTER=1 (simulator/dev): boot straight into the Ball Tracking Tester so saved
    // shots can be replayed with overlays without navigating the app shell.
    private var openTesterDirectly: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TC_OPEN_TESTER"] == "1"
        #else
        return false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if openTesterDirectly {
                #if DEBUG
                BallTrackingTestView(onDismiss: {})
                #endif
            } else {
            ContentView()
                .environmentObject(session)
                .environmentObject(camera)
                .task {
                    // Wire crash/error telemetry to the backend + report any prior crash.
                    CrashReporter.shared.attach(backend: session.backend)
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        // Natural "done hitting" moment: push archived shots to Drive
                        // (verified, then freed locally) so the phone stays light.
                        GoogleDriveUploadService.shared.autoOffloadIfNeeded()
                        return
                    }
                    guard phase == .active else { return }
                    Task { await session.refreshSessionAndEntitlement() }
                }
                // Silent NFC club detection — two delivery paths:
                // 1. URL routing: truecarry://nfc/{uuid} when app is backgrounded
                .onOpenURL { url in
                    if url.scheme == "truecarry" { print("[DeepLink] onOpenURL: \(url.absoluteString)") }
                    // QR pairing: truecarry://livesim?code=XXXXXXXXX from the web sim.
                    if url.host == "livesim",
                       let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                           .queryItems?.first(where: { $0.name == "code" })?.value,
                       (6...10).contains(code.count), code.allSatisfy(\.isNumber) {
                        // State, not a fire-once notification: @Published re-emits to
                        // late subscribers, so the shell routes correctly no matter
                        // whether the URL beat the views to the party (cold start) or
                        // the tab content mounts lazily after this fires (warm scan).
                        DeepLinkRouter.shared.pendingSimCode = code
                        return
                    }
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
}
