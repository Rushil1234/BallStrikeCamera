import Foundation
import UIKit

struct ExportResult {
    let zipURL: URL
    let packageDirectory: URL
    let frameCount: Int
}

enum ExportError: LocalizedError {
    case noDocumentsDirectory
    case failedToCreateZip

    var errorDescription: String? {
        switch self {
        case .noDocumentsDirectory: return "Cannot access Documents directory"
        case .failedToCreateZip:    return "Failed to create export ZIP"
        }
    }
}

final class ShotExportService {

    func export(from analysis: ShotAnalysisResult) throws -> ExportResult {
        print("Preparing clean shot export package")

        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { throw ExportError.noDocumentsDirectory }

        let exportsDir = docs.appendingPathComponent("ShotExports", isDirectory: true)
        let dirName    = "ShotExport_\(dirTimestamp(analysis.createdAt))"
        let packageDir = exportsDir.appendingPathComponent(dirName, isDirectory: true)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        let frames = analysis.frames
        print("Exporting \(frames.count) original frames")
        for frame in frames {
            let name = String(format: "frame_%03d.png", frame.frameIndex)
            if let data = frame.originalFrame.image.pngData() {
                try data.write(to: packageDir.appendingPathComponent(name))
            }
        }

        let tsData = try JSONSerialization.data(
            withJSONObject: timestampsJSON(frames: frames), options: [.prettyPrinted])
        try tsData.write(to: packageDir.appendingPathComponent("timestamps.json"))
        print("Wrote timestamps.json")

        let metaData = try JSONSerialization.data(
            withJSONObject: metadataJSON(analysis: analysis), options: [.prettyPrinted])
        try metaData.write(to: packageDir.appendingPathComponent("metadata.json"))
        print("Wrote metadata.json")

        let trackData = try JSONSerialization.data(
            withJSONObject: trackingJSON(frames: frames), options: [.prettyPrinted])
        try trackData.write(to: packageDir.appendingPathComponent("tracking.json"))
        print("Wrote tracking.json")

        let zipURL = exportsDir.appendingPathComponent("\(dirName).zip")
        try buildStoredZip(from: packageDir, to: zipURL)
        print("Created shot export zip: \(zipURL.lastPathComponent)")
        print("Presenting share sheet for shot export")

        return ExportResult(zipURL: zipURL, packageDirectory: packageDir, frameCount: frames.count)
    }

    // MARK: - JSON builders

    private func timestampsJSON(frames: [AnalyzedShotFrame]) -> [String: Any] {
        ["timestamps": frames.map { f -> [String: Any] in
            ["frame_index": f.frameIndex, "timestamp": f.timestamp, "relative_time": f.relativeTime]
        }]
    }

    private func metadataJSON(analysis: ShotAnalysisResult) -> [String: Any] {
        var d: [String: Any] = [
            "export_version": 1,
            "created_at": ISO8601DateFormatter().string(from: analysis.createdAt),
            "frame_count": analysis.frames.count,
            "impact_frame_index": analysis.impactFrameIndex,
            "fps_estimate": 240
        ]
        if let r = analysis.lockedBallRect {
            d["locked_ball_rect"] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
        }
        return d
    }

    private func trackingJSON(frames: [AnalyzedShotFrame]) -> [String: Any] {
        ["observations": frames.map { f -> [String: Any] in
            var obs: [String: Any] = [
                "frame_index": f.frameIndex,
                "detected": f.ballObservation?.centerX != nil,
                "confidence": f.ballObservation?.confidence ?? 0.0
            ]
            if let b = f.ballObservation, let cx = b.centerX, let cy = b.centerY, let d = b.diameter {
                obs["center_x"] = cx
                obs["center_y"] = cy
                obs["diameter"]  = d
            }
            return obs
        }]
    }

    // MARK: - ZIP (stored method, no compression)

    private func buildStoredZip(from directory: URL, to outputURL: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        fm.createFile(atPath: outputURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: outputURL.path) else {
            throw ExportError.failedToCreateZip
        }
        defer { handle.closeFile() }

        var cdEntries: [(name: [UInt8], crc: UInt32, size: UInt32, offset: UInt32)] = []
        var offset: UInt32 = 0

        for item in items {
            let fileData = try Data(contentsOf: item)
            let nameBytes = Array(item.lastPathComponent.utf8)
            let crc  = storedCRC32(fileData)
            let size = UInt32(fileData.count)

            cdEntries.append((nameBytes, crc, size, offset))

            var hdr = Data()
            hdr.le(UInt32(0x04034b50))
            hdr.le(UInt16(20));  hdr.le(UInt16(0))
            hdr.le(UInt16(0))    // stored
            hdr.le(UInt16(0));   hdr.le(UInt16(0))
            hdr.le(crc);         hdr.le(size);  hdr.le(size)
            hdr.le(UInt16(nameBytes.count)); hdr.le(UInt16(0))
            hdr.append(contentsOf: nameBytes)

            handle.write(hdr)
            handle.write(fileData)
            offset += UInt32(hdr.count) + size
        }

        let cdStart = offset
        var cdSize: UInt32 = 0

        for e in cdEntries {
            var cd = Data()
            cd.le(UInt32(0x02014b50))
            cd.le(UInt16(20));   cd.le(UInt16(20))
            cd.le(UInt16(0));    cd.le(UInt16(0))
            cd.le(UInt16(0));    cd.le(UInt16(0))
            cd.le(e.crc);        cd.le(e.size);  cd.le(e.size)
            cd.le(UInt16(e.name.count))
            cd.le(UInt16(0));    cd.le(UInt16(0))
            cd.le(UInt16(0));    cd.le(UInt16(0))
            cd.le(UInt32(0));    cd.le(e.offset)
            cd.append(contentsOf: e.name)
            handle.write(cd)
            cdSize += UInt32(cd.count)
        }

        var eocd = Data()
        eocd.le(UInt32(0x06054b50))
        eocd.le(UInt16(0));  eocd.le(UInt16(0))
        eocd.le(UInt16(cdEntries.count))
        eocd.le(UInt16(cdEntries.count))
        eocd.le(cdSize);     eocd.le(cdStart)
        eocd.le(UInt16(0))
        handle.write(eocd)
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1 }
        return c
    }

    private func storedCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { ptr in
            for byte in ptr { crc = (crc >> 8) ^ Self.crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] }
        }
        return crc ^ 0xFFFFFFFF
    }

    private func dirTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: date)
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        self += Data(bytes: &v, count: MemoryLayout<T>.size)
    }
}
