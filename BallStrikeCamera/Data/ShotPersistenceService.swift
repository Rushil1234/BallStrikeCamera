import Foundation
import UIKit

// MARK: - Shot Persistence Service

enum ShotPersistenceError: Error {
    /// A shot flagged as a bad shot — by rule, these are never stored (no metrics, no frames).
    case discardedBadShot
}

extension Notification.Name {
    /// Posted when a previously-saved shot is discarded (marked bad). userInfo["id"] = shot UUID.
    /// Active session view models listen so the shot leaves their counts immediately.
    static let tcShotDiscarded = Notification.Name("tc.shot.discarded")
}

final class ShotPersistenceService {

    private let userId: UUID
    private let backend: AppBackend

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
    }

    // MARK: - Save Shot

    /// Persist a shot from the camera pipeline.
    /// - Parameters:
    ///   - metrics: Calculated launch monitor metrics.
    ///   - compositeImage: The single per-shot composite image (saved as JPEG + uploaded to cloud).
    ///   - clubId: Selected club UUID.
    ///   - clubName: Selected club display name.
    ///   - mode: Shot capture mode.
    /// - Returns: The persisted SavedShot.
    @discardableResult
    func saveShot(metrics: SavedShotMetrics,
                  compositeImage: UIImage?,
                  replayFrames: [UIImage] = [],
                  clubId: UUID? = nil,
                  clubName: String? = nil,
                  mode: ShotMode = .range,
                  visibility: ShotVisibility = .friends,
                  sessionId: UUID? = nil,
                  roundId: UUID? = nil,
                  holeNumber: Int? = nil,
                  isBadShot: Bool = false,
                  badShotReason: String? = nil,
                  notes: String? = nil,
                  shotLatitude: Double? = nil,
                  shotLongitude: Double? = nil) async throws -> SavedShot {

        // Rule: bad shots are never saved — no metrics, no frames, nothing persisted.
        guard !isBadShot else { throw ShotPersistenceError.discardedBadShot }

        // Each shot stores ONE composite image (saved as JPEG + uploaded); raw frames are never
        // persisted, so there's no per-session frame cap.
        let shotId = UUID()
        let mediaDir = AppStorageManager.shotFramesDir(userId: userId, shotId: shotId)
        AppStorageManager.ensureDirectory(mediaDir)

        var media = SavedShotMedia()
        media.frameCount = 0   // no frames; the composite is the replay

        // Composite (single JPEG) + thumbnail. The composite is uploaded to cloud storage so
        // replay works cross-device / after reinstall, the role frames used to serve.
        var compositeJPEG: Data? = nil
        if let img = compositeImage {
            let compPath = mediaDir.appendingPathComponent("composite.jpg")
            if let data = img.jpegData(compressionQuality: 0.85) {
                compositeJPEG = data
                try? data.write(to: compPath)
                media.compositePath = compPath.path
                if let thumb = img.resizedToWidth(120),
                   let thumbData = thumb.jpegData(compressionQuality: 0.8) {
                    let thumbPath = mediaDir.appendingPathComponent("thumb.jpg")
                    try? thumbData.write(to: thumbPath)
                    media.thumbnailPath = thumbPath.path
                }
            }
        }

        // NOTE: we intentionally no longer persist a per-shot "replay burst" (the ~40
        // downscaled JPEGs that used to land in media/shotFrames/<id>/). Nothing read them
        // back: the scrubbing ReplayPlayerView is unused, history shows the composite only
        // (ShotDetailView), and the post-shot "Frame Replay" plays the in-memory analysis
        // frames. So the burst was pure dead storage (~1 MB/shot). The composite JPEG remains
        // the saved/cross-device replay image; the raw 41-frame burst still goes to the
        // AllFramesArchive when "Save All Frames" is on (deletable), which is where it belongs.
        // `replayFrames` is kept in the signature for source compatibility but is unused.
        _ = replayFrames

        // Metrics JSON sidecar
        if let jsonData = try? AppStorageManager.encoder.encode(metrics) {
            let jsonPath = mediaDir.appendingPathComponent("metrics.json")
            try? jsonData.write(to: jsonPath)
            media.metricsJsonPath = jsonPath.path
        }

        var shot = SavedShot(
            id: shotId,
            userId: userId,
            mode: mode,
            clubId: clubId,
            clubName: clubName,
            metrics: metrics,
            media: media,
            isBadShot: isBadShot,
            badShotReason: badShotReason,
            notes: notes,
            sessionId: sessionId,
            roundId: roundId,
            holeNumber: holeNumber
        )
        shot.shotLatitude  = shotLatitude
        shot.shotLongitude = shotLongitude
        shot.visibility    = visibility

        try await backend.saveShot(shot)
        await backend.logAnalyticsEvent("shot_saved", properties: [
            "club": shot.clubName ?? "",
            "carry": Int(shot.metrics.carryYards.rounded()),
            "mode": mode.rawValue
        ], sessionId: sessionId)
        // Mirror the composite to cloud storage so the replay image survives a reinstall and works
        // on other devices. Retry once on failure and record the outcome so it's observable (the
        // previous frame upload silently swallowed errors, which hid that uploads were being denied).
        if let jpeg = compositeJPEG {
            var uploaded = false
            for attempt in 1...2 {
                do {
                    try await backend.uploadShotComposite(userId: userId, shotId: shotId, jpeg: jpeg)
                    uploaded = true
                    break
                } catch {
                    print("composite upload failed (attempt \(attempt)) for shot \(shotId): \(error)")
                }
            }
            if uploaded {
                shot.media.framesUploaded = true
                try? await backend.saveShot(shot)   // persist the uploaded flag
            }
        }
        return shot
    }

    /// Returns a local file URL for the shot's composite image, downloading it from cloud storage
    /// first if it isn't already on this device (captured elsewhere / after a reinstall). nil if none.
    func ensureCompositeAvailable(for shot: SavedShot) async -> URL? {
        let compURL = AppStorageManager.shotFramesDir(userId: userId, shotId: shot.id)
            .appendingPathComponent("composite.jpg")
        let fm = FileManager.default
        if fm.fileExists(atPath: compURL.path) { return compURL }
        // Fall back to a path already recorded on the model (older PNG composites).
        if let p = shot.media.compositePath, fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        // Pull from cloud.
        let fetched = try? await backend.downloadShotComposite(userId: userId, shotId: shot.id)
        guard let data = fetched ?? nil, !data.isEmpty else { return nil }
        AppStorageManager.ensureDirectory(compURL.deletingLastPathComponent())
        try? data.write(to: compURL)
        return compURL
    }

    // MARK: - Load

    func loadShots(limit: Int? = nil) async throws -> [SavedShot] {
        let all = try await backend.loadShots(userId: userId)
        if let limit { return Array(all.prefix(limit)) }
        return all
    }

    func deleteShot(id: UUID) async throws {
        try await backend.deleteShot(shotId: id, userId: userId)
        // Also remove media directory
        let mediaDir = AppStorageManager.shotFramesDir(userId: userId, shotId: id)
        try? FileManager.default.removeItem(at: mediaDir)
        await MainActor.run {
            NotificationCenter.default.post(name: .tcDataChanged, object: nil)
        }
    }

    // MARK: - Dead replay-burst cleanup

    /// Older builds wrote a per-shot "replay burst" (`frame_*.jpg`, ~40 downscaled frames)
    /// into every shot's media folder. Nothing ever read them back — the scrubbing
    /// ReplayPlayerView is unused and history renders the composite — so they were pure dead
    /// storage (~1 MB/shot). This deletes them, keeping `composite.jpg`/`thumb.jpg`/`metrics.json`.
    /// Only touches `…/media/shotFrames/<id>/` — never the AllFramesArchive or the composite.
    @discardableResult
    static func purgeDeadReplayBursts(userId: UUID) -> (files: Int, bytes: Int64) {
        let fm = FileManager.default
        let root = AppStorageManager.userRoot(for: userId).appendingPathComponent("media/shotFrames")
        guard let shotDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return (0, 0)
        }
        var files = 0
        var bytes: Int64 = 0
        for shotDir in shotDirs {
            // A non-directory (stray file) makes this throw → skipped.
            guard let items = try? fm.contentsOfDirectory(at: shotDir, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for url in items where url.lastPathComponent.hasPrefix("frame_") && url.pathExtension == "jpg" {
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                if (try? fm.removeItem(at: url)) != nil {
                    files += 1
                    bytes += size
                }
            }
        }
        return (files, bytes)
    }

    /// Runs the dead-burst purge at most once per install (background), so existing devices
    /// self-heal after this update without any user action. Call when a user id is known.
    private static let purgeDoneKey = "tc_purged_dead_replay_bursts_v1"
    static func purgeDeadReplayBurstsOnce(userId: UUID) {
        guard !UserDefaults.standard.bool(forKey: purgeDoneKey) else { return }
        Task.detached(priority: .utility) {
            let r = purgeDeadReplayBursts(userId: userId)
            // Set the flag only after a completed pass so an interrupted run finishes next launch.
            UserDefaults.standard.set(true, forKey: purgeDoneKey)
            if r.files > 0 {
                let mb = Double(r.bytes) / 1_000_000
                let msg = "[ShotMedia] purged \(r.files) dead replay frames, freed \(String(format: "%.1f", mb)) MB"
                print(msg)
                FieldLog.shared.event(msg)
            }
        }
    }
}

// MARK: - UIImage resize helper

private extension UIImage {
    func resizedToWidth(_ targetWidth: CGFloat) -> UIImage? {
        let scale  = targetWidth / size.width
        let newSize = CGSize(width: targetWidth, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
