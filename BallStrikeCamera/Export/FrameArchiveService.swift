import Foundation
import UIKit

/// Dev/testing tool. When enabled, persists every shot's raw 41-frame burst to disk so the frames
/// can be batch-exported (ZIP → share sheet → AirDrop/Files) and compared offline against a
/// reference launch monitor (e.g. Garmin). Frames are saved at CAPTURE time — before analysis and
/// the plausibility check — so even shots the app would discard as false triggers are preserved.
final class FrameArchiveService {

    static let shared = FrameArchiveService()
    private init() {}

    /// Persisted toggle key. Read via UserDefaults so non-UI code (CameraController) can check it.
    static let enabledKey = "tc_save_all_frames"

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private let queue = DispatchQueue(label: "com.truecarry.framearchive", qos: .utility)
    private let fm = FileManager.default

    private var archiveDir: URL? {
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("AllFramesArchive", isDirectory: true)
    }

    // MARK: - Save

    /// Persist a shot's raw frames as PNGs + a timestamps.json in a per-shot folder. Non-blocking:
    /// the encode/write happens on a utility queue so the capture path is never stalled.
    /// `force` writes even when the dev "save all frames" toggle is off — used when the
    /// user explicitly chooses to keep an untracked shot's frames for model training.
    func archive(frames: [CapturedFrame], impactIndex: Int?,
                 lockedBallRect: CGRect? = nil, lockedImpactROI: CGRect? = nil,
                 force: Bool = false) {
        guard isEnabled || force, !frames.isEmpty, let root = archiveDir else { return }
        // Snapshot (image, timestamp) off the capture path — UIImage is safe to read across threads.
        // Archive the 720px hi-res copy when present (July 17): labels and training data
        // inherit 2× precision; the replay loader rebuilds the 360 analysis frame from it.
        let snapshot: [(Int, UIImage, TimeInterval)] = frames.enumerated().map {
            ($0.offset, $0.element.hiRes ?? $0.element.image, $0.element.timestamp)
        }
        let capturedAt = Date()
        queue.async { [fm] in
            let shotDir = root.appendingPathComponent("shot_\(Self.folderStamp(capturedAt))", isDirectory: true)
            do {
                try fm.createDirectory(at: shotDir, withIntermediateDirectories: true)
            } catch {
                print("[FrameArchive] could not create folder: \(error)")
                return
            }
            var timestamps: [[String: Any]] = []
            for (idx, image, t) in snapshot {
                let name = String(format: "frame_%03d.jpg", idx)
                if let data = image.jpegData(compressionQuality: 0.9) {
                    try? data.write(to: shotDir.appendingPathComponent(name))
                }
                timestamps.append(["frame_index": idx, "timestamp": t])
            }
            let meta: [String: Any] = [
                "captured_at": ISO8601DateFormatter().string(from: capturedAt),
                "frame_count": snapshot.count,
                "impact_frame_index": impactIndex as Any,
                "timestamps": timestamps
            ]
            if let d = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted]) {
                try? d.write(to: shotDir.appendingPathComponent("timestamps.json"))
            }
            // metadata.json carries the live pipeline's lock state so the offline tester
            // (BallTrackingTester) can replay the shot through the EXACT same analysis the
            // device ran — the tracker is anchored to this rect, so without it a replay
            // has to re-derive the lock and parity is approximate.
            var extra: [String: Any] = ["impact_frame_index": impactIndex as Any]
            if let r = lockedBallRect {
                extra["locked_ball_rect"] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
            }
            if let r = lockedImpactROI {
                extra["locked_impact_roi"] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
            }
            if let d = try? JSONSerialization.data(withJSONObject: extra, options: [.prettyPrinted]) {
                try? d.write(to: shotDir.appendingPathComponent("metadata.json"))
            }
            print("[FrameArchive] saved \(snapshot.count) frames → \(shotDir.lastPathComponent)")
        }
    }

    // MARK: - Inspect

    /// Number of archived shots currently on disk.
    func shotCount() -> Int {
        shotFolders().count
    }

    /// Per-shot folder URLs on disk, oldest first. Folder names are the capture timestamp,
    /// so lexicographic order is chronological order.
    func shotFolders() -> [URL] {
        guard let root = archiveDir,
              let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return items
            .filter { $0.hasDirectoryPath && $0.lastPathComponent.hasPrefix("shot_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Total bytes used by the archive (for a human-readable size in the UI).
    func totalBytes() -> Int64 {
        guard let root = archiveDir,
              let en = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in en {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Export / clear

    /// Zip the whole archive into a temp file for the share sheet. Returns nil if nothing is stored.
    func exportZip() throws -> URL? {
        guard let root = archiveDir, shotCount() > 0 else { return nil }
        let out = fm.temporaryDirectory.appendingPathComponent("TrueCarryFrames_\(Self.folderStamp(Date())).zip")
        try StoredZip.zip(directory: root, to: out)
        return out
    }

    func clear() {
        guard let root = archiveDir else { return }
        try? fm.removeItem(at: root)
    }

    // MARK: - Helpers

    private static func folderStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return f.string(from: date)
    }
}
