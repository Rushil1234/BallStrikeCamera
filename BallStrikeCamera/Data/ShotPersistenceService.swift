import Foundation
import UIKit

// MARK: - Shot Persistence Service

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
    ///   - compositeImage: The ball-flight composite image (39-frame overlay).
    ///   - originalFrames: The 41 raw captured frames (only saved when opted-in).
    ///   - clubId: Selected club UUID.
    ///   - clubName: Selected club display name.
    ///   - mode: Shot capture mode.
    ///   - saveOriginalFrames: Whether to persist the raw frames.
    /// - Returns: The persisted SavedShot.
    @discardableResult
    func saveShot(metrics: SavedShotMetrics,
                  compositeImage: UIImage?,
                  originalFrames: [UIImage] = [],
                  clubId: UUID? = nil,
                  clubName: String? = nil,
                  mode: ShotMode = .range,
                  saveOriginalFrames: Bool = false,
                  sessionId: UUID? = nil,
                  roundId: UUID? = nil,
                  holeNumber: Int? = nil,
                  isBadShot: Bool = false,
                  badShotReason: String? = nil,
                  notes: String? = nil) async throws -> SavedShot {

        let shotId = UUID()
        let mediaDir = AppStorageManager.shotFramesDir(userId: userId, shotId: shotId)
        AppStorageManager.ensureDirectory(mediaDir)

        var media = SavedShotMedia()
        media.saveOriginalFrames = saveOriginalFrames

        // Thumbnail & composite
        if let img = compositeImage {
            let compPath = mediaDir.appendingPathComponent("composite.png")
            if let data = img.pngData() {
                try? data.write(to: compPath)
                media.compositePath = compPath.path
                // Thumbnail: scale down to 120px wide
                if let thumb = img.resizedToWidth(120),
                   let thumbData = thumb.pngData() {
                    let thumbPath = mediaDir.appendingPathComponent("thumb.png")
                    try? thumbData.write(to: thumbPath)
                    media.thumbnailPath = thumbPath.path
                }
            }
        }

        // Impact frames — always saved when provided (enables shot replay)
        if !originalFrames.isEmpty {
            let framesDir = mediaDir.appendingPathComponent("frames")
            AppStorageManager.ensureDirectory(framesDir)
            let limit = saveOriginalFrames ? 41 : 11
            for (idx, frame) in originalFrames.prefix(limit).enumerated() {
                if let data = frame.pngData() {
                    let name = String(format: "frame_%03d.png", idx)
                    try? data.write(to: framesDir.appendingPathComponent(name))
                }
            }
            media.originalFramesFolderPath = framesDir.path
            media.frameCount = min(limit, originalFrames.count)
        }

        // Metrics JSON sidecar
        if let jsonData = try? AppStorageManager.encoder.encode(metrics) {
            let jsonPath = mediaDir.appendingPathComponent("metrics.json")
            try? jsonData.write(to: jsonPath)
            media.metricsJsonPath = jsonPath.path
        }

        let shot = SavedShot(
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

        try await backend.saveShot(shot)
        return shot
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
