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
        if frames.count == 41 {
            print("Warning: export received only 41 frames; exporter is not capping, capture source provided 41")
        }
        print("Exporting \(frames.count) original frames")
        for frame in frames {
            let name = String(format: "frame_%03d.png", frame.frameIndex)
            if let data = frame.originalFrame.image.pngData() {
                try data.write(to: packageDir.appendingPathComponent(name))
            }
        }
        print("Wrote \(frames.count) frame PNGs")

        let tsData = try JSONSerialization.data(
            withJSONObject: timestampsJSON(frames: frames), options: [.prettyPrinted])
        try tsData.write(to: packageDir.appendingPathComponent("timestamps.json"))
        print("Wrote timestamps.json entries=\(frames.count)")

        let metaData = try JSONSerialization.data(
            withJSONObject: metadataJSON(analysis: analysis), options: [.prettyPrinted])
        try metaData.write(to: packageDir.appendingPathComponent("metadata.json"))
        print("Wrote metadata.json")

        let trackData = try JSONSerialization.data(
            withJSONObject: trackingJSON(frames: frames), options: [.prettyPrinted])
        try trackData.write(to: packageDir.appendingPathComponent("tracking.json"))
        print("Wrote tracking.json")

        let metricsData = try JSONSerialization.data(
            withJSONObject: metricsJSON(analysis: analysis), options: [.prettyPrinted])
        try metricsData.write(to: packageDir.appendingPathComponent("metrics.json"))
        print("Wrote metrics.json")

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
        let n = analysis.frames.count
        let impactIdx = analysis.impactFrameIndex
        let preHit  = impactIdx
        let postHit = max(0, n - impactIdx - 1)
        var d: [String: Any] = [
            "export_version": 1,
            "created_at": ISO8601DateFormatter().string(from: analysis.createdAt),
            "frame_count": n,
            "exported_frame_count": n,
            "first_frame_index": 0,
            "last_frame_index": max(0, n - 1),
            "pre_hit_frames": preHit,
            "post_hit_frames": postHit,
            "expected_frame_count": n,
            "impact_frame_index": impactIdx,
            "fallback_impact_frame_index": analysis.fallbackImpactFrameIndex,
            "detected_impact_frame_index": analysis.detectedImpactFrameIndex,
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

    private func metricsJSON(analysis: ShotAnalysisResult) -> [String: Any] {
        guard let metrics = analysis.metrics else {
            return [
                "schema": "ballstrike.shot_metrics.v2",
                "metrics_available": false,
                "detectedImpactFrameIndex": analysis.detectedImpactFrameIndex,
                "fallbackImpactFrameIndex": analysis.fallbackImpactFrameIndex,
                "warnings": ["Metrics were not calculated for this shot."]
            ]
        }

        return [
            "schema": "ballstrike.shot_metrics.v2",
            "metrics_available": true,
            "detectedImpactFrameIndex": metrics.detectedImpactFrameIndex,
            "fallbackImpactFrameIndex": metrics.fallbackImpactFrameIndex,
            "zeroDegreeReferenceAngleDegrees": metrics.zeroDegreeReferenceAngleDegrees,
            "ballSpeedMph": jsonNumber(metrics.ballLaunch.ballSpeedMph),
            "hlaDegrees": jsonNumber(metrics.ballLaunch.hlaDegrees),
            "hlaDisplay": metrics.ballLaunch.hlaDisplay,
            "hla3DRawDegrees": jsonNumber(metrics.ballLaunch.hla3DRawDegrees),
            "hlaReferenceAngleDegrees": metrics.ballLaunch.hlaReferenceAngleDegrees,
            "hlaForwardComponent": jsonNumber(metrics.ballLaunch.hlaForwardComponent),
            "hlaLateralComponent": jsonNumber(metrics.ballLaunch.hlaLateralComponent),
            "vlaDegrees": jsonNumber(metrics.ballLaunch.vlaDegrees),
            "clubSpeedMph": jsonNumber(metrics.club.clubSpeedMph),
            "smashFactor": jsonNumber(metrics.smashFactor),
            "idealCarryYards": jsonNumber(metrics.distance.idealCarryYards),
            "carryCorrectionFactor": metrics.distance.carryCorrectionFactor,
            "carryYards": jsonNumber(metrics.distance.carryYards),
            "rolloutYards": jsonNumber(metrics.distance.rolloutYards),
            "totalYards": jsonNumber(metrics.distance.totalYards),
            "rolloutFraction": jsonNumber(metrics.distance.rolloutFraction),
            "vlaBucket": metrics.distance.vlaBucket,
            "estimatedBackspinRpm": jsonNumber(metrics.spin.estimatedBackspinRpm),
            "estimatedSidespinRpmSigned": jsonNumber(metrics.spin.estimatedSidespinRpmSigned),
            "estimatedSidespinDisplay": metrics.spin.estimatedSidespinDisplay,
            "estimatedSpinAxisDegreesSigned": jsonNumber(metrics.spin.estimatedSpinAxisDegreesSigned),
            "estimatedSpinAxisDisplay": metrics.spin.estimatedSpinAxisDisplay,
            "spinEstimateMethod": metrics.spin.spinEstimateMethod,
            "clubPathDegreesSigned": jsonNumber(metrics.clubPath.clubPathDegreesSigned),
            "clubPathDisplay": metrics.clubPath.clubPathDisplay,
            "estimatedFaceAngleDegreesSigned": jsonNumber(metrics.faceAngle.faceAngleDegreesSigned),
            "estimatedFaceAngleDisplay": metrics.faceAngle.faceAngleDisplay,
            "faceAngleConfidence": metrics.faceAngle.confidence,
            "faceToPathDegreesSigned": jsonNumber(metrics.faceAngle.faceToPathDegreesSigned),
            "faceToPathDisplay": metrics.faceAngle.faceToPathDisplay,
            "ballQuality": metrics.ballLaunch.quality,
            "clubQuality": metrics.club.quality,
            "ballPointsUsed": metrics.ballLaunch.pointsUsed,
            "clubPointsUsed": metrics.club.pointsUsed,
            "ballMethod": metrics.ballLaunch.method,
            "clubMethod": metrics.club.method,
            "distanceMethod": metrics.distance.method,
            "clubSpeedFrameIndices": metrics.club.speedFrameIndices,
            "warnings": metrics.warnings,
            "calibration": calibrationJSON(metrics.calibration),
            "ball3DObservations": metrics.ball3DObservations.map(ball3DJSON),
            "clubObservations": metrics.clubObservations.map(clubObservationJSON)
        ]
    }

    private func calibrationJSON(_ calibration: CameraCalibration) -> [String: Any] {
        [
            "horizontalFOVDegrees": calibration.horizontalFOVDegrees,
            "verticalFOVDegrees": calibration.verticalFOVDegrees,
            "imageWidthPixels": calibration.imageWidthPixels,
            "imageHeightPixels": calibration.imageHeightPixels,
            "realBallDiameterMeters": calibration.realBallDiameterMeters,
            "cameraHeightMeters": jsonNumber(calibration.cameraHeightMeters),
            "cameraTiltDegrees": jsonNumber(calibration.cameraTiltDegrees),
            "focalLengthPixelsX": calibration.focalLengthPixelsX,
            "focalLengthPixelsY": calibration.focalLengthPixelsY
        ]
    }

    private func ball3DJSON(_ observation: Ball3DObservation) -> [String: Any] {
        [
            "frameIndex": observation.frameIndex,
            "timestamp": observation.timestamp,
            "relativeTime": observation.relativeTime,
            "imageX": observation.imageX,
            "imageY": observation.imageY,
            "diameterNorm": observation.diameterNorm,
            "diameterPixels": observation.diameterPixels,
            "positionMeters": [
                "x": observation.positionMeters.x,
                "y": observation.positionMeters.y,
                "z": observation.positionMeters.z
            ],
            "confidence": observation.confidence
        ]
    }

    private func clubObservationJSON(_ observation: ClubObservation) -> [String: Any] {
        [
            "frameIndex": observation.frameIndex,
            "timestamp": observation.timestamp,
            "relativeTime": observation.relativeTime,
            "centerX": jsonNumber(observation.centerX.map(Double.init)),
            "centerY": jsonNumber(observation.centerY.map(Double.init)),
            "leadingEdgeX": jsonNumber(observation.leadingEdgeX.map(Double.init)),
            "leadingEdgeY": jsonNumber(observation.leadingEdgeY.map(Double.init)),
            "clubBoundingBox": rectJSON(observation.clubBoundingBox),
            "confidence": observation.confidence,
            "searchROI": rectJSON(observation.searchROI),
            "ballExclusionCenterX": jsonNumber(observation.ballExclusionCenterX.map(Double.init)),
            "ballExclusionCenterY": jsonNumber(observation.ballExclusionCenterY.map(Double.init)),
            "ballExclusionDiameter": jsonNumber(observation.ballExclusionDiameter.map(Double.init)),
            "debugReason": observation.debugReason,
            "detectionMode": observation.detectionMode,
            "ballExclusionWasApplied": observation.ballExclusionWasApplied,
            "frameDifferenceWasUsed": observation.frameDifferenceWasUsed
        ]
    }

    private func rectJSON(_ rect: CGRect?) -> Any {
        guard let rect else { return NSNull() }
        return ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    private func jsonNumber(_ value: Double?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return value
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
