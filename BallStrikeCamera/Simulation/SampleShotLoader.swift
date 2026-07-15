import UIKit
import Foundation

struct SampleShotLoader {

    // Raw PNG frames + capture context only. Never touches metrics/tracking JSON.
    struct RawShot {
        let frames: [CapturedFrame]
        let lockedBallRect: CGRect?
        let lockedImpactROI: CGRect?
        let sourceName: String
    }

    static func loadRawFramesOnly(shotName: String = "SampleShot_001") throws -> RawShot {
        print("Simulate Shot: raw-frame replay mode")
        let folderURL = try locateFolder(named: shotName)
        return try loadContents(from: folderURL, shotName: shotName)
    }

    // MARK: - Folder Location

    private static func locateFolder(named name: String) throws -> URL {
        // 1. App bundle: Resources/SampleShots/<name>
        if let url = Bundle.main.url(forResource: name,
                                     withExtension: nil,
                                     subdirectory: "SampleShots") {
            print("Simulate Shot: loading bundled sample \(name)")
            return url
        }

        // Alternate bundle lookup via resourceURL for folder references
        if let base = Bundle.main.resourceURL {
            let candidate = base.appendingPathComponent("SampleShots").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                print("Simulate Shot: loading bundled sample \(name)")
                return candidate
            }
        }

        // 2. Documents: SampleShots/<name>
        if let docsBase = FileManager.default.urls(for: .documentDirectory,
                                                    in: .userDomainMask).first {
            let docsURL = docsBase
                .appendingPathComponent("SampleShots")
                .appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: docsURL.path) {
                print("Simulate Shot: loading Documents sample \(name)")
                return docsURL
            }
        }

        // 3. DEBUG simulator fallback (never ships on device)
        #if DEBUG
        let fallback = URL(fileURLWithPath: "/Users/noahtobias/Downloads/ShotExport_20260501_114631")
        if FileManager.default.fileExists(atPath: fallback.path) {
            print("Simulate Shot: loading DEBUG simulator fallback \(fallback.path)")
            return fallback
        }
        #endif

        print("Simulate Shot failed: no sample frames found")
        throw LoadError.notFound(name)
    }

    // MARK: - Contents Loading

    // Names of analysis output files that must never be loaded in raw-frame mode
    private static let staleAnalysisFilenames: Set<String> = [
        "metrics.json",
        "tracking.json",
        "python_experimental_metrics.json",
        "experimental_metrics.json"
    ]

    private static func loadContents(from folderURL: URL, shotName: String) throws -> RawShot {
        let fm = FileManager.default
        let allFiles = try fm.contentsOfDirectory(at: folderURL,
                                                   includingPropertiesForKeys: nil)

        // Detect and log stale analysis files — explicitly ignored
        let staleFound = allFiles.filter { staleAnalysisFilenames.contains($0.lastPathComponent) }
        if !staleFound.isEmpty {
            let names = staleFound.map { $0.lastPathComponent }.sorted().joined(separator: ", ")
            print("Simulate Shot: found saved metrics/tracking files but intentionally ignored them (\(names))")
        } else {
            print("Simulate Shot: ignoring saved metrics/tracking files")
        }

        let framePaths = allFiles
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("frame_") && (name.hasSuffix(".png") || name.hasSuffix(".jpg"))
            }
            .sorted { a, b in
                (frameIndex(from: a.lastPathComponent) ?? 0) < (frameIndex(from: b.lastPathComponent) ?? 0)
            }

        guard !framePaths.isEmpty else {
            print("Simulate Shot failed: no sample frames found")
            throw LoadError.noFrames(shotName)
        }

        let timestampMap = loadTimestamps(in: folderURL)
        let (lockedBallRect, lockedImpactROI, fallbackImpactIndex) = loadMetadata(in: folderURL,
                                                                                   fallbackIndex: framePaths.count / 2)
        // Build per-frame timestamps. impactFrameIndex from metadata is used only for
        // timestamp anchoring — it is NOT passed to the analysis pipeline.
        let impactTS = timestampMap[fallbackImpactIndex]?.timestamp
            ?? (Double(fallbackImpactIndex) / 240.0)

        var frames: [CapturedFrame] = []
        for (arrayIdx, path) in framePaths.enumerated() {
            guard let image = UIImage(contentsOfFile: path.path) else { continue }
            let frameIdx = frameIndex(from: path.lastPathComponent) ?? arrayIdx
            let ts = timestampMap[frameIdx]?.timestamp
                ?? (impactTS + Double(frameIdx - fallbackImpactIndex) / 240.0)
            frames.append(CapturedFrame(image: image, timestamp: ts))
        }

        print("Simulate Shot: loaded \(frames.count) raw frames")
        return RawShot(
            frames: frames,
            lockedBallRect: lockedBallRect,
            lockedImpactROI: lockedImpactROI,
            sourceName: shotName
        )
    }

    // MARK: - JSON Helpers

    private static func loadTimestamps(
        in folder: URL
    ) -> [Int: (timestamp: TimeInterval, relativeTime: Double)] {
        var map: [Int: (timestamp: TimeInterval, relativeTime: Double)] = [:]
        let url = folder.appendingPathComponent("timestamps.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = root["timestamps"] as? [[String: Any]] else { return map }
        for entry in array {
            // relative_time is OPTIONAL: archive-format timestamps.json only carries
            // frame_index + timestamp, and requiring the third key silently emptied the
            // whole map — every Simulate Shot then ran on synthesized perfect-240fps
            // spacing, compressing the real (frame-dropped) dt 3× and inflating ball
            // speed 3× (252.6 vs 84.2 mph) while starving the launch chain's velocity
            // gate. relativeTime is never read downstream; timestamp is what matters.
            if let idx = entry["frame_index"] as? Int,
               let ts  = entry["timestamp"]    as? Double {
                map[idx] = (timestamp: ts, relativeTime: entry["relative_time"] as? Double ?? 0)
            }
        }
        return map
    }

    private static func loadMetadata(
        in folder: URL,
        fallbackIndex: Int
    ) -> (lockedBallRect: CGRect?, lockedImpactROI: CGRect?, impactIndex: Int) {
        let url = folder.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: url),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, fallbackIndex)
        }

        var lockedBallRect: CGRect? = nil
        if let rd = meta["locked_ball_rect"] as? [String: Double],
           let x = rd["x"], let y = rd["y"], let w = rd["width"], let h = rd["height"] {
            lockedBallRect = CGRect(x: x, y: y, width: w, height: h)
        }

        let impactIndex = (meta["detected_impact_frame_index"] as? Int)
            ?? (meta["impact_frame_index"] as? Int)
            ?? fallbackIndex

        return (lockedBallRect, nil, impactIndex)
    }

    private static func frameIndex(from filename: String) -> Int? {
        guard filename.hasPrefix("frame_"),
              filename.hasSuffix(".png") || filename.hasSuffix(".jpg") else { return nil }
        let numStr = filename.dropFirst("frame_".count).dropLast(4)
        return Int(numStr)
    }

    // MARK: - Errors

    enum LoadError: LocalizedError {
        case notFound(String)
        case noFrames(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let name): return "Sample '\(name)' not found in bundle, Documents, or fallback path"
            case .noFrames(let name): return "No frame_NNN.png files found in sample '\(name)'"
            }
        }
    }
}
