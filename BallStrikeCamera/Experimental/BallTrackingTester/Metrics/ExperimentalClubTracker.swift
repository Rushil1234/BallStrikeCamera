#if DEBUG
import UIKit
import CoreGraphics

struct ExperimentalClubTracker {
    struct Configuration {
        var enabled: Bool = true
        var searchBehindBallEnabled: Bool = true
        var approachDirectionX: CGFloat = -1
        var approachDirectionY: CGFloat = 0
        var ballExclusionRadiusScale: CGFloat = 1.8
        var clubSearchROIScaleX: CGFloat = 8.0
        var clubSearchROIScaleY: CGFloat = 5.0
        var minClubDarknessOrEdgeThreshold: Int = 85
        var useFrameDifference: Bool = true
        var frameDifferenceThreshold: Int = 34
        var minClubBlobArea: Int = 5
        var maxClubBlobArea: Int = 6000
        var minClubConfidence: Double = 0.20
        var sampleStride: Int = 2
        var debugLoggingEnabled: Bool = true
        var normalizationMode: FrameNormalizationMode = .darkenedHighContrast
    }

    private struct Blob {
        var minX: Int
        var maxX: Int
        var minY: Int
        var maxY: Int
        var sumX: Int
        var sumY: Int
        var count: Int
        var closestX: Int
        var closestY: Int
        var closestDistanceSquared: Double
    }

    let configuration: Configuration
    private let normalizer = FrameNormalizer()

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func track(sequence: BallTrackingTestSequence, ballResult: BallTrackingTestResult) -> [ExperimentalClubObservation] {
        guard configuration.enabled else {
            print("Experimental club tracking disabled")
            return []
        }
        guard !sequence.frames.isEmpty else { return [] }

        let impact = ballResult.detectedImpactFrameIndex
        let start = max(0, impact - 10)
        let end = min(sequence.frames.count - 1, impact + 1)
        var observations: [ExperimentalClubObservation] = []

        for frameIndex in start...end {
            let frame = sequence.frames[frameIndex]
            guard let ball = nearestBallObservation(ballResult.observations, around: frame.frameIndex),
                  let ballX = ball.centerX,
                  let ballY = ball.centerY,
                  let ballDiameter = ball.diameter else {
                observations.append(emptyObservation(frame, reason: "no_ball_reference"))
                continue
            }

            guard let current = normalizedPixelBytes(from: frame.image) else {
                observations.append(emptyObservation(frame, reason: "no_current_pixel_data"))
                continue
            }

            let previous: (bytes: [UInt8], width: Int, height: Int)?
            if frameIndex > 0 {
                previous = normalizedPixelBytes(from: sequence.frames[frameIndex - 1].image)
            } else {
                previous = nil
            }

            let ballCenter = CGPoint(x: ballX, y: ballY)
            let roi = clubSearchROI(ballCenter: ballCenter, ballDiameter: ballDiameter)
            let selected = findClubBlob(
                current: current,
                previous: previous,
                roi: roi,
                ballCenter: ballCenter,
                ballDiameter: ballDiameter
            )

            let exclusionDiameter = ballDiameter * configuration.ballExclusionRadiusScale
            if let selected {
                let confidence = confidence(for: selected)
                if confidence < configuration.minClubConfidence {
                    let obs = emptyObservation(
                        frame,
                        roi: roi,
                        ballCenter: ballCenter,
                        ballExclusionDiameter: exclusionDiameter,
                        reason: String(format: "club_conf_low(%.2f<%.2f)", confidence, configuration.minClubConfidence)
                    )
                    observations.append(obs)
                    log(obs)
                    continue
                }

                let bboxNorm = CGRect(
                    x: CGFloat(selected.minX) / CGFloat(current.width),
                    y: CGFloat(selected.minY) / CGFloat(current.height),
                    width: CGFloat(max(1, selected.maxX - selected.minX + 1)) / CGFloat(current.width),
                    height: CGFloat(max(1, selected.maxY - selected.minY + 1)) / CGFloat(current.height)
                )
                let usedDiff = configuration.useFrameDifference && previous != nil
                let obs = ExperimentalClubObservation(
                    frameIndex: frame.frameIndex,
                    timestamp: frame.timestamp,
                    relativeTime: frame.relativeTime,
                    centerX: CGFloat(selected.sumX) / CGFloat(selected.count) / CGFloat(current.width),
                    centerY: CGFloat(selected.sumY) / CGFloat(selected.count) / CGFloat(current.height),
                    leadingEdgeX: CGFloat(selected.closestX) / CGFloat(current.width),
                    leadingEdgeY: CGFloat(selected.closestY) / CGFloat(current.height),
                    clubBoundingBox: bboxNorm,
                    confidence: confidence,
                    searchROI: roi,
                    ballExclusionCenterX: ballX,
                    ballExclusionCenterY: ballY,
                    ballExclusionDiameter: exclusionDiameter,
                    debugReason: "club_blob_frame_diff_or_dark",
                    detectionMode: usedDiff ? "frameDifference_or_dark" : "dark",
                    ballExclusionWasApplied: true,
                    frameDifferenceWasUsed: usedDiff
                )
                observations.append(obs)
                log(obs)
            } else {
                let obs = emptyObservation(
                    frame,
                    roi: roi,
                    ballCenter: ballCenter,
                    ballExclusionDiameter: exclusionDiameter,
                    reason: "no_club_blob"
                )
                observations.append(obs)
                log(obs)
            }
        }

        let found = observations.filter(\.isDetected).count
        print("Experimental club tracking complete")
        print("Club frames searched: \(observations.count)")
        print("Club frames detected: \(found)")
        return observations
    }

    private func clubSearchROI(ballCenter: CGPoint, ballDiameter: CGFloat) -> CGRect {
        let width = ballDiameter * configuration.clubSearchROIScaleX
        let height = ballDiameter * configuration.clubSearchROIScaleY
        var centerX = ballCenter.x
        var centerY = ballCenter.y
        if configuration.searchBehindBallEnabled {
            centerX += configuration.approachDirectionX * width * 0.32
            centerY += configuration.approachDirectionY * height * 0.32
        }
        return CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func findClubBlob(
        current: (bytes: [UInt8], width: Int, height: Int),
        previous: (bytes: [UInt8], width: Int, height: Int)?,
        roi: CGRect,
        ballCenter: CGPoint,
        ballDiameter: CGFloat
    ) -> Blob? {
        let step = max(1, configuration.sampleStride)
        let xStart = max(0, Int(roi.minX * CGFloat(current.width)))
        let xEnd = min(current.width, Int(roi.maxX * CGFloat(current.width)))
        let yStart = max(0, Int(roi.minY * CGFloat(current.height)))
        let yEnd = min(current.height, Int(roi.maxY * CGFloat(current.height)))
        guard xEnd > xStart, yEnd > yStart else { return nil }

        let cols = (xEnd - xStart + step - 1) / step
        let rows = (yEnd - yStart + step - 1) / step
        var active = [Bool](repeating: false, count: cols * rows)
        var visited = [Bool](repeating: false, count: cols * rows)
        let ballPx = CGPoint(x: ballCenter.x * CGFloat(current.width), y: ballCenter.y * CGFloat(current.height))
        let exclusionRadius = Double(ballDiameter * CGFloat(current.width) * configuration.ballExclusionRadiusScale / 2)
        let canUseDiff = configuration.useFrameDifference
            && previous?.width == current.width
            && previous?.height == current.height

        for row in 0..<rows {
            let py = yStart + row * step
            for col in 0..<cols {
                let px = xStart + col * step
                let dx = Double(CGFloat(px) - ballPx.x)
                let dy = Double(CGFloat(py) - ballPx.y)
                if sqrt(dx * dx + dy * dy) <= exclusionRadius {
                    continue
                }

                let i = py * current.width * 4 + px * 4
                let r = Int(current.bytes[i])
                let g = Int(current.bytes[i + 1])
                let b = Int(current.bytes[i + 2])
                let brightness = (r + g + b) / 3
                var frameDiff = 0
                if canUseDiff, let previous {
                    let pr = Int(previous.bytes[i])
                    let pg = Int(previous.bytes[i + 1])
                    let pb = Int(previous.bytes[i + 2])
                    frameDiff = (abs(r - pr) + abs(g - pg) + abs(b - pb)) / 3
                }

                let darkCandidate = brightness <= configuration.minClubDarknessOrEdgeThreshold
                let movingCandidate = canUseDiff && frameDiff >= configuration.frameDifferenceThreshold
                active[row * cols + col] = darkCandidate || movingCandidate
            }
        }

        var blobs: [Blob] = []
        for startRow in 0..<rows {
            for startCol in 0..<cols {
                let startIndex = startRow * cols + startCol
                guard active[startIndex], !visited[startIndex] else { continue }

                var blob = Blob(
                    minX: Int.max,
                    maxX: 0,
                    minY: Int.max,
                    maxY: 0,
                    sumX: 0,
                    sumY: 0,
                    count: 0,
                    closestX: 0,
                    closestY: 0,
                    closestDistanceSquared: .greatestFiniteMagnitude
                )
                var queue = [startIndex]
                var head = 0
                visited[startIndex] = true

                while head < queue.count {
                    let index = queue[head]
                    head += 1
                    let col = index % cols
                    let row = index / cols
                    let px = xStart + col * step
                    let py = yStart + row * step

                    blob.count += 1
                    blob.sumX += px
                    blob.sumY += py
                    if px < blob.minX { blob.minX = px }
                    if px > blob.maxX { blob.maxX = px }
                    if py < blob.minY { blob.minY = py }
                    if py > blob.maxY { blob.maxY = py }

                    let dx = Double(CGFloat(px) - ballPx.x)
                    let dy = Double(CGFloat(py) - ballPx.y)
                    let dist2 = dx * dx + dy * dy
                    if dist2 < blob.closestDistanceSquared {
                        blob.closestDistanceSquared = dist2
                        blob.closestX = px
                        blob.closestY = py
                    }

                    for offset in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nextCol = col + offset.0
                        let nextRow = row + offset.1
                        guard nextCol >= 0, nextCol < cols, nextRow >= 0, nextRow < rows else { continue }
                        let nextIndex = nextRow * cols + nextCol
                        if active[nextIndex], !visited[nextIndex] {
                            visited[nextIndex] = true
                            queue.append(nextIndex)
                        }
                    }
                }

                if blob.count >= configuration.minClubBlobArea,
                   blob.count <= configuration.maxClubBlobArea {
                    blobs.append(blob)
                }
            }
        }

        return blobs.min {
            score($0, ballPx: ballPx, imageWidth: current.width, imageHeight: current.height)
                < score($1, ballPx: ballPx, imageWidth: current.width, imageHeight: current.height)
        }
    }

    private func score(_ blob: Blob, ballPx: CGPoint, imageWidth: Int, imageHeight: Int) -> Double {
        let cx = Double(blob.sumX) / Double(blob.count)
        let cy = Double(blob.sumY) / Double(blob.count)
        let dx = cx - Double(ballPx.x)
        let dy = cy - Double(ballPx.y)
        let distanceNorm = sqrt(dx * dx + dy * dy) / Double(max(imageWidth, imageHeight))
        let width = Double(max(1, blob.maxX - blob.minX + 1))
        let height = Double(max(1, blob.maxY - blob.minY + 1))
        let elongation = max(width / height, height / width)
        return distanceNorm - min(0.04, elongation * 0.004) - confidence(for: blob) * 0.02
    }

    private func confidence(for blob: Blob) -> Double {
        let areaScore = min(1.0, Double(blob.count) / Double(max(1, configuration.minClubBlobArea * 10)))
        let width = Double(max(1, blob.maxX - blob.minX + 1))
        let height = Double(max(1, blob.maxY - blob.minY + 1))
        let elongation = max(width / height, height / width)
        let elongationScore = min(1.0, elongation / 4.0)
        return min(1.0, 0.65 * areaScore + 0.35 * elongationScore)
    }

    private func nearestBallObservation(
        _ observations: [BallTrackingTestObservation],
        around frameIndex: Int
    ) -> BallTrackingTestObservation? {
        if let current = observations.first(where: { $0.frameIndex == frameIndex && $0.centerX != nil }) {
            return current
        }
        return observations
            .filter { $0.centerX != nil }
            .min { abs($0.frameIndex - frameIndex) < abs($1.frameIndex - frameIndex) }
    }

    private func emptyObservation(
        _ frame: BallTrackingTestFrame,
        roi: CGRect? = nil,
        ballCenter: CGPoint? = nil,
        ballExclusionDiameter: CGFloat? = nil,
        reason: String
    ) -> ExperimentalClubObservation {
        ExperimentalClubObservation(
            frameIndex: frame.frameIndex,
            timestamp: frame.timestamp,
            relativeTime: frame.relativeTime,
            centerX: nil,
            centerY: nil,
            leadingEdgeX: nil,
            leadingEdgeY: nil,
            clubBoundingBox: nil,
            confidence: 0,
            searchROI: roi,
            ballExclusionCenterX: ballCenter?.x,
            ballExclusionCenterY: ballCenter?.y,
            ballExclusionDiameter: ballExclusionDiameter,
            debugReason: reason,
            detectionMode: "none",
            ballExclusionWasApplied: ballCenter != nil,
            frameDifferenceWasUsed: false
        )
    }

    private func log(_ observation: ExperimentalClubObservation) {
        guard configuration.debugLoggingEnabled else { return }
        if let x = observation.leadingEdgeX, let y = observation.leadingEdgeY {
            print(String(format: "ExperimentalClubTracker frame=%02d leading=(%.4f, %.4f) conf=%.2f reason=%@",
                         observation.frameIndex, x, y, observation.confidence, observation.debugReason))
        } else {
            print("ExperimentalClubTracker frame=\(observation.frameIndex) miss reason=\(observation.debugReason)")
        }
    }

    private func normalizedPixelBytes(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let source = configuration.normalizationMode == .original
            ? image
            : normalizer.normalizedImage(from: image, mode: configuration.normalizationMode)
        return pixelBytes(from: source)
    }

    private func pixelBytes(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return (bytes, width, height)
    }
}
#endif
