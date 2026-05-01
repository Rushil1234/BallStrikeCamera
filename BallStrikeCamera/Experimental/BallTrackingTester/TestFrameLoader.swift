import Foundation
import UIKit

final class TestFrameLoader {

    func listAvailableExports() -> [URL] {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return [] }
        let exportsDir = docs.appendingPathComponent("ShotExports")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: exportsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func loadSequence(from exportURL: URL) throws -> BallTrackingTestSequence {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: exportURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

        let pngURLs = contents.filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !pngURLs.isEmpty else { throw LoaderError.noFramesFound }

        var timestampMap: [Int: (timestamp: TimeInterval, relativeTime: TimeInterval)] = [:]
        var impactFrameIndex = 20
        var lockedBallRect: CGRect? = nil

        if let tsData = try? Data(contentsOf: exportURL.appendingPathComponent("timestamps.json")),
           let tsJSON = try? JSONSerialization.jsonObject(with: tsData) as? [String: Any],
           let list   = tsJSON["timestamps"] as? [[String: Any]] {
            for entry in list {
                if let idx = entry["frame_index"] as? Int,
                   let ts  = entry["timestamp"]   as? TimeInterval,
                   let rt  = entry["relative_time"] as? TimeInterval {
                    timestampMap[idx] = (ts, rt)
                }
            }
        }

        if let metaData = try? Data(contentsOf: exportURL.appendingPathComponent("metadata.json")),
           let meta     = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] {
            if let idx = meta["impact_frame_index"] as? Int { impactFrameIndex = idx }
            if let r   = meta["locked_ball_rect"]   as? [String: Double] {
                lockedBallRect = CGRect(
                    x: r["x"] ?? 0, y: r["y"] ?? 0,
                    width: r["width"] ?? 0, height: r["height"] ?? 0)
            }
        }

        var frames: [BallTrackingTestFrame] = []
        for url in pngURLs {
            let stem = url.deletingPathExtension().lastPathComponent
            guard let idx   = Int(stem.replacingOccurrences(of: "frame_", with: "")),
                  let image = UIImage(contentsOfFile: url.path) else { continue }
            let ts = timestampMap[idx]
            let relTime = ts?.relativeTime ?? (Double(idx - impactFrameIndex) / 240.0)
            frames.append(BallTrackingTestFrame(
                frameIndex: idx,
                timestamp: ts?.timestamp ?? 0,
                relativeTime: relTime,
                image: image))
        }
        frames.sort { $0.frameIndex < $1.frameIndex }

        return BallTrackingTestSequence(
            frames: frames,
            impactFrameIndex: impactFrameIndex,
            sourceName: exportURL.lastPathComponent,
            lockedBallRect: lockedBallRect)
    }

    enum LoaderError: LocalizedError {
        case noFramesFound
        var errorDescription: String? { "No PNG frames found in export directory" }
    }
}
