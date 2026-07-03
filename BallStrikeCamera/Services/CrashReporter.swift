import Foundation

/// Provider-agnostic crash & error reporting.
///
/// Works today with zero external dependencies:
///   • Records uncaught NSExceptions to disk and reports them as a `client_crash`
///     analytics event on the next launch (backend visibility via analytics_events).
///   • `capture(_:)` reports handled errors as `client_error` events immediately.
///
/// To add full crash coverage (Swift traps, signals, mach exceptions) drop in Sentry:
///   1. Xcode → Package Dependencies → add https://github.com/getsentry/sentry-cocoa
///   2. In `configure(dsn:)` below, uncomment the SentrySDK.start block.
///   3. Pass your DSN from Secrets.plist. Everything else already routes through here.
final class CrashReporter {
    static let shared = CrashReporter()

    private let markerURL: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("tc_last_crash.json")

    private var backend: AppBackend?
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    private init() {}

    /// Reads the optional Sentry DSN from Secrets.plist (`SentryDSN`). Returns nil
    /// if not configured, so crash reporting stays first-party until you add it.
    static func secretsDSN() -> String? {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let dsn = dict["SentryDSN"] as? String, !dsn.isEmpty else { return nil }
        return dsn
    }

    /// Call once at launch (before UI). Installs the uncaught-exception handler and,
    /// optionally, starts a third-party crash SDK.
    func configure(dsn: String? = nil) {
        installExceptionHandler()

        // ── Sentry (optional) — uncomment after adding the sentry-cocoa package ──
        // guard let dsn, !dsn.isEmpty else { return }
        // SentrySDK.start { options in
        //     options.dsn = dsn
        //     options.tracesSampleRate = 0.2
        //     options.enableAppHangTracking = true
        // }
        _ = dsn
    }

    /// Wire the backend so pending crashes and captured errors can be reported.
    /// Call once a session/backend exists; also flushes any crash from last launch.
    func attach(backend: AppBackend) {
        self.backend = backend
        flushPendingCrash()
    }

    /// Report a handled error (fire-and-forget). Use at meaningful catch sites.
    func capture(_ error: Error, context: String = "") {
        NSLog("[CrashReporter] captured: \(context) \(error)")
        let props: [String: Any] = [
            "context": context,
            "error": String(describing: error),
            "domain": (error as NSError).domain,
            "code": (error as NSError).code,
        ]
        // SentrySDK.capture(error: error)   // when Sentry is enabled
        let backend = self.backend
        Task { await backend?.logAnalyticsEvent("client_error", properties: props, sessionId: nil) }
    }

    // MARK: - Uncaught NSException capture

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            // Runs in the failing process; keep it minimal & synchronous.
            let payload: [String: Any] = [
                "name": exception.name.rawValue,
                "reason": exception.reason ?? "",
                "stack": exception.callStackSymbols.prefix(30).joined(separator: "\n"),
                "at": ISO8601DateFormatter().string(from: Date()),
            ]
            let url = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("tc_last_crash.json")
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func flushPendingCrash() {
        guard let data = try? Data(contentsOf: markerURL),
              var props = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        try? FileManager.default.removeItem(at: markerURL)
        props["app_version"] = appVersion
        let backend = self.backend
        Task { await backend?.logAnalyticsEvent("client_crash", properties: props, sessionId: nil) }
    }
}
