import Foundation
import UIKit
import Darwin

/// On-device field diagnostics logger.
///
/// The tracking/exposure/metrics pipeline already prints everything needed to diagnose a
/// failed shot — `[TrackSummary]`, `[ShotValidation]` (with the exact discard reason),
/// `[BD] rej [w=<brightPixels>]`, `[IMP] trigger suppressed — baseline < floor`, `[EXP] iso=…`.
/// The only problem is those lines go to the Xcode console, so you have to be tethered to see
/// them. This captures the SAME console output to a file on the phone so a range/sun session
/// can be debugged after the fact, with no cable.
///
/// Two artifacts, both under `Documents/BallStrike/diagnostics/`:
///   • `field-log.txt` — full console capture (stdout + stderr), the raw diagnostics.
///   • `shots.csv`     — one scannable row per analyzed shot (preset / exposure / lock /
///                       launch / speed / metrics / reason).
///
/// Export: share sheet (→ Google Drive / Files / AirDrop) or a one-tap upload straight to the
/// same "TrueCarry Frames" Google Drive folder the app already uses. Toggle-gated from the
/// Developer card; costs nothing when off.
final class FieldLog {

    static let shared = FieldLog()
    private init() {}

    /// Master on/off. Backed by `@AppStorage` in the Developer card.
    static let enabledKey = "tc_field_log_enabled"
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    // Serial queue guards every explicit file write (CSV rows, debugger-mode text lines).
    // The stdout/stderr redirect writes go through stdio's own internal lock, not this queue.
    private let queue = DispatchQueue(label: "com.truecarry.fieldlog")
    private var didRedirect = false

    /// Roll the text log once it passes this, so a long range day can't fill the disk.
    /// ~8 MB of text is thousands of shots' worth of diagnostics.
    private let maxBytes = 8 * 1024 * 1024

    // MARK: - Locations

    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BallStrike/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var logURL: URL { dir.appendingPathComponent("field-log.txt") }
    static var prevLogURL: URL { dir.appendingPathComponent("field-log.prev.txt") }
    static var csvURL: URL { dir.appendingPathComponent("shots.csv") }

    // MARK: - Start capture

    /// Call once at launch. When logging is enabled and no debugger is attached, redirects
    /// stdout + stderr into the log file so every existing `print(...)` in the pipeline is
    /// captured. When a debugger IS attached (developing in Xcode), the redirect is skipped so
    /// the console still works — explicit `event(...)`/`logShot(...)` calls are written to the
    /// file directly instead.
    func startIfEnabled() {
        guard isEnabled else { return }
        queue.sync {
            guard !didRedirect else { return }
            rollIfNeededLocked()
            if !Self.isDebuggerAttached() {
                let path = Self.logURL.path
                freopen(path, "a+", stdout)
                freopen(path, "a+", stderr)
                setvbuf(stdout, nil, _IOLBF, 0)   // line-buffered: lines land promptly, survive a crash
                setvbuf(stderr, nil, _IONBF, 0)
                didRedirect = true
            }
        }
        event("=== field log started · \(Self.deviceLine()) ===")
    }

    // MARK: - Explicit events

    /// Write a timestamped marker line. Always prints (so it shows in Xcode / is caught by the
    /// redirect); also written straight to the file when the redirect isn't active.
    func event(_ message: String) {
        guard isEnabled else { return }
        let line = "[\(Self.stamp())] \(message)"
        print(line)
        // If the redirect is live, `print` already put this in the file — don't double-write.
        guard !didRedirect else { return }
        queue.async { self.appendLocked(line + "\n", to: Self.logURL) }
    }

    // MARK: - Per-shot CSV row

    struct ShotDiag {
        var outcome: String          // "tracked" | "discarded" | "repositioned"
        var reason: String           // discard reason / impact-detection reason / "ok"
        var preset: String           // shutter preset label, e.g. "1/2000" or "Flash"
        var iso: Double?
        var shutterDenom: Double?    // e.g. 2000 for 1/2000
        var exposureOffsetEV: Double?
        var frameCount: Int
        var ballSpeedMph: Double?
        var carryYards: Double?
        var vlaDegrees: Double?
        var hlaDegrees: Double?
        var method: String?
    }

    private static let csvHeader =
        "time,outcome,reason,preset,iso,shutter,expOffsetEV,frames,ballSpeedMph,carryYards,vla,hla,method\n"

    func logShot(_ d: ShotDiag) {
        guard isEnabled else { return }
        let f = { (v: Double?) in v.map { String(format: "%.1f", $0) } ?? "" }
        let row = [
            Self.stamp(),
            d.outcome,
            Self.csvEscape(d.reason),
            d.preset,
            d.iso.map { String(format: "%.0f", $0) } ?? "",
            d.shutterDenom.map { "1/\(Int($0))" } ?? "",
            d.exposureOffsetEV.map { String(format: "%+.2f", $0) } ?? "",
            String(d.frameCount),
            f(d.ballSpeedMph),
            f(d.carryYards),
            f(d.vlaDegrees),
            f(d.hlaDegrees),
            Self.csvEscape(d.method ?? "")
        ].joined(separator: ",") + "\n"

        queue.async {
            if !FileManager.default.fileExists(atPath: Self.csvURL.path) {
                self.appendLocked(Self.csvHeader, to: Self.csvURL)
            }
            self.appendLocked(row, to: Self.csvURL)
        }
        // Mirror a compact one-liner into the text log so the CSV and the raw console stay in sync.
        event("[FieldShot] \(d.outcome) · \(d.reason) · preset=\(d.preset) "
              + "iso=\(d.iso.map { String(format: "%.0f", $0) } ?? "-") "
              + "speed=\(d.ballSpeedMph.map { String(format: "%.1f", $0) } ?? "-") "
              + "metrics=\(d.ballSpeedMph != nil)")
    }

    // MARK: - Export

    /// Files that currently exist, for a share sheet (`ShareSheet(items:)`).
    func exportURLs() -> [URL] {
        [Self.logURL, Self.prevLogURL, Self.csvURL]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Copy the artifacts into a single timestamped zip in temp, for sharing or Drive upload.
    /// Returns nil if nothing has been logged yet.
    func makeExportZip() -> URL? {
        let urls = exportURLs()
        guard !urls.isEmpty else { return nil }
        let fm = FileManager.default
        let stamp = Self.fileStamp()
        let work = fm.temporaryDirectory.appendingPathComponent("fieldlog_\(stamp)", isDirectory: true)
        try? fm.removeItem(at: work)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        for u in urls {
            try? fm.copyItem(at: u, to: work.appendingPathComponent(u.lastPathComponent))
        }
        let zipURL = fm.temporaryDirectory.appendingPathComponent("TrueCarry-fieldlog-\(stamp).zip")
        try? fm.removeItem(at: zipURL)
        do { try StoredZip.zip(directory: work, to: zipURL) } catch { return nil }
        return zipURL
    }

    /// Total bytes across both text logs + the CSV (for the UI status line).
    func totalBytes() -> Int64 {
        exportURLs().reduce(0) { sum, url in
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return sum + ((attrs?[.size] as? Int64) ?? 0)
        }
    }

    func clear() {
        queue.sync {
            fflush(stdout); fflush(stderr)
            for url in [Self.logURL, Self.prevLogURL, Self.csvURL] {
                try? FileManager.default.removeItem(at: url)
            }
            // If we're mid-redirect, reopen a fresh (now-empty) file so capture continues.
            if didRedirect {
                let path = Self.logURL.path
                freopen(path, "a+", stdout)
                freopen(path, "a+", stderr)
                setvbuf(stdout, nil, _IOLBF, 0)
                setvbuf(stderr, nil, _IONBF, 0)
            }
        }
    }

    // MARK: - Internals

    /// Append; creates the file first if needed (FileHandle(forWritingTo:) requires it to exist).
    /// Must be called on `queue`.
    private func appendLocked(_ string: String, to url: URL) {
        guard let data = string.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Roll the text log to `.prev` when it passes the cap. Must be called on `queue`.
    private func rollIfNeededLocked() {
        let path = Self.logURL.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        try? FileManager.default.removeItem(at: Self.prevLogURL)
        try? FileManager.default.moveItem(at: Self.logURL, to: Self.prevLogURL)
    }

    // MARK: - Helpers

    private static func csvEscape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
    private static func stamp() -> String { stampFormatter.string(from: Date()) }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
    private static func fileStamp() -> String { fileStampFormatter.string(from: Date()) }

    private static func deviceLine() -> String {
        let d = UIDevice.current
        return "\(d.model) iOS \(d.systemVersion) · thermal \(ProcessInfo.processInfo.thermalState.rawValue)"
    }

    /// True when a debugger (Xcode) is attached — then we DON'T hijack stdout.
    private static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
