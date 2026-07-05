import CoreVideo
import CoreGraphics

/// A tiny CPU-only detector meant as a replaceable first pass.
///
/// Current heuristic: look for a compact, bright, low-saturation blob. This works best for a white ball
/// against darker grass/turf/backgrounds. Replace this with a CoreML/Vision model later if needed.
final class BallDetector {
    struct Configuration {
        var sampleStride: Int = 6
        var minimumBrightPixels: Int = 18
        var brightnessThreshold: Int = 155
        var maxChannelSpread: Int = 72
        var minimumAspectRatio: CGFloat = 0.55
        var maximumAspectRatio: CGFloat = 1.85
        var minimumNormalizedArea: CGFloat = 0.00002
        var maximumNormalizedArea: CGFloat = 0.04
        // Bright pixels must fill at least this fraction of the bounding-box grid cells.
        // A golf ball fills ~40–70%; scattered glare (tee, mat reflections) fills ~4–10%.
        // This prevents multiple distant bright spots from merging into one oversized blob.
        var minimumFillRatio: Double = 0.18
    }

    private let configuration: Configuration

    // Diagnostic throttling — this runs at up to 240fps, so only a fraction of calls print.
    // `frameCounter` is only ever touched from the serial video-capture queue that calls detect().
    private var frameCounter: Int = 0
    private let diagnosticLogInterval = 60   // ~4x/sec at 240fps, ~2x/sec at 120fps
    private var hasLoggedFormatError = false
    private var rejectedCandidateCount = 0

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func detect(in pixelBuffer: CVPixelBuffer, roi: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> BallObservation? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            if !hasLoggedFormatError {
                hasLoggedFormatError = true
                print("BallDetector: pixel buffer is not 32BGRA (or has no base address) — detection can never run. format=\(CVPixelBufferGetPixelFormatType(pixelBuffer))")
            }
            return nil
        }

        frameCounter += 1
        let shouldLogSnapshot = frameCounter % diagnosticLogInterval == 0

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let sampleStride = max(1, configuration.sampleStride)

        // Clamp ROI to valid pixel bounds
        let xStart = max(0, Int(roi.minX * CGFloat(width)))
        let xEnd   = min(width,  Int(roi.maxX * CGFloat(width)))
        let yStart = max(0, Int(roi.minY * CGFloat(height)))
        let yEnd   = min(height, Int(roi.maxY * CGFloat(height)))

        guard xStart < xEnd, yStart < yEnd else {
            print("BallDetector: degenerate ROI in pixel space — roi=\(roi) frame=\(width)x\(height) bounds=(\(xStart),\(yStart))-(\(xEnd),\(yEnd))")
            return nil
        }

        // Diagnostics only — doesn't affect detection, just explains *why* count stayed low.
        var maxBrightnessSeen = 0
        var brightIgnoringSpread = 0   // brightness passed, but spread (saturation) did not
        var sampledPixels = 0

        // Collect qualifying sample points instead of folding them into one running bbox —
        // a single stray bright pixel elsewhere in the ROI (glare, a bright blade of grass)
        // used to inflate that one global bbox to the whole ROI and permanently fail the
        // fill-ratio check below, even when the ball itself formed a perfectly tight blob.
        // Clustering by adjacency first (below) fixes that without changing the scan itself.
        var brightX: [Int] = []
        var brightY: [Int] = []

        // Scan only within ROI, downsampled. BGRA byte order.
        // normalizedRect output is always relative to the full frame so overlay mapping is unchanged.
        for y in stride(from: yStart, to: yEnd, by: sampleStride) {
            let row = pointer + y * bytesPerRow
            for x in stride(from: xStart, to: xEnd, by: sampleStride) {
                sampledPixels += 1
                let idx = x * 4
                let b = Int(row[idx])
                let g = Int(row[idx + 1])
                let r = Int(row[idx + 2])
                let maxChannel = max(r, max(g, b))
                let minChannel = min(r, min(g, b))
                let brightness = (r + g + b) / 3
                let spread = maxChannel - minChannel

                if brightness > maxBrightnessSeen { maxBrightnessSeen = brightness }

                // White balls tend to be bright with modest channel spread.
                if brightness >= configuration.brightnessThreshold {
                    if spread <= configuration.maxChannelSpread {
                        brightX.append(x)
                        brightY.append(y)
                    } else {
                        brightIgnoringSpread += 1
                    }
                }
            }
        }

        if shouldLogSnapshot {
            print("BallDetector scan: roi=\(roi) pxBounds=(\(xStart),\(yStart))-(\(xEnd),\(yEnd)) sampled=\(sampledPixels) maxBrightness=\(maxBrightnessSeen)/\(configuration.brightnessThreshold) bright+lowSpread=\(brightX.count) bright+highSpread=\(brightIgnoringSpread) needBright=\(configuration.minimumBrightPixels)")
        }

        guard brightX.count >= configuration.minimumBrightPixels else {
            if shouldLogSnapshot {
                let reason = maxBrightnessSeen < configuration.brightnessThreshold
                    ? "nothing in ROI reached brightness threshold — too dark / ball outside ROI / exposure too fast"
                    : "bright pixels present but too saturated/colored (spread > \(configuration.maxChannelSpread)) or too few (\(brightX.count) < \(configuration.minimumBrightPixels))"
                print("BallDetector: NO CANDIDATE — \(reason)")
            }
            return nil
        }

        // Group bright samples into spatially-connected clusters (8-neighbor adjacency on the
        // sample grid, same grid the stride already samples on) so each blob is tested for
        // fill/aspect/area independently instead of as one merged region.
        var gridIndex: [Int64: Int] = [:]
        gridIndex.reserveCapacity(brightX.count * 2)
        for i in 0..<brightX.count {
            let key = Int64(brightX[i] / sampleStride) * 1_000_000 + Int64(brightY[i] / sampleStride)
            gridIndex[key] = i
        }

        var visited = [Bool](repeating: false, count: brightX.count)
        var bestObservation: BallObservation?
        var bestCount = 0
        var bestRejectReason: String?

        for start in 0..<brightX.count {
            guard !visited[start] else { continue }
            visited[start] = true
            var stack = [start]
            var clusterIndices: [Int] = []

            while let i = stack.popLast() {
                clusterIndices.append(i)
                let gx = brightX[i] / sampleStride
                let gy = brightY[i] / sampleStride
                for dgx in -1...1 {
                    for dgy in -1...1 {
                        if dgx == 0 && dgy == 0 { continue }
                        let key = Int64(gx + dgx) * 1_000_000 + Int64(gy + dgy)
                        if let ni = gridIndex[key], !visited[ni] {
                            visited[ni] = true
                            stack.append(ni)
                        }
                    }
                }
            }

            guard clusterIndices.count >= configuration.minimumBrightPixels else { continue }

            var minX = width, minY = height, maxX = 0, maxY = 0
            var sumX = 0, sumY = 0
            for i in clusterIndices {
                let x = brightX[i], y = brightY[i]
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                sumX += x; sumY += y
            }
            let count = clusterIndices.count

            // Reject scattered glare: bright pixels must fill a meaningful fraction of their
            // bounding box. A ball fills ~40–70% of its grid; multiple distant bright spots
            // (tee, mat glare) fill ~4–10%, causing a huge bounding box and center drift.
            let gridW = max(1, (maxX - minX) / sampleStride + 1)
            let gridH = max(1, (maxY - minY) / sampleStride + 1)
            let fillRatio = Double(count) / Double(gridW * gridH)
            guard fillRatio >= configuration.minimumFillRatio else {
                bestRejectReason = "cluster too scattered, fillRatio=\(String(format: "%.3f", fillRatio)) need >= \(configuration.minimumFillRatio) (grid=\(gridW)x\(gridH), count=\(count))"
                continue
            }

            let boxWidth = CGFloat(maxX - minX + sampleStride)
            let boxHeight = CGFloat(maxY - minY + sampleStride)
            guard boxWidth > 0, boxHeight > 0 else { continue }

            let aspect = boxWidth / boxHeight
            let normalizedArea = (boxWidth * boxHeight) / CGFloat(width * height)
            guard aspect >= configuration.minimumAspectRatio,
                  aspect <= configuration.maximumAspectRatio,
                  normalizedArea >= configuration.minimumNormalizedArea,
                  normalizedArea <= configuration.maximumNormalizedArea else {
                bestRejectReason = "aspect=\(String(format: "%.2f", aspect)) (need \(configuration.minimumAspectRatio)-\(configuration.maximumAspectRatio)), normalizedArea=\(String(format: "%.5f", normalizedArea)) (need \(configuration.minimumNormalizedArea)-\(configuration.maximumNormalizedArea)), boxPx=\(Int(boxWidth))x\(Int(boxHeight))"
                continue
            }

            // Keep the largest passing cluster — the real ball should be the biggest
            // compact, correctly-shaped bright blob in frame.
            if count > bestCount {
                bestCount = count
                let centerX = CGFloat(sumX) / CGFloat(count)
                let centerY = CGFloat(sumY) / CGFloat(count)
                let side = max(boxWidth, boxHeight) * 1.35
                let rect = CGRect(
                    x: max(0, centerX - side / 2) / CGFloat(width),
                    y: max(0, centerY - side / 2) / CGFloat(height),
                    width: min(side, CGFloat(width)) / CGFloat(width),
                    height: min(side, CGFloat(height)) / CGFloat(height)
                ).standardized
                let confidence = min(1.0, Double(count) / 240.0)
                bestObservation = BallObservation(normalizedRect: rect, confidence: confidence,
                                                  fillRatio: fillRatio)
            }
        }

        guard let observation = bestObservation else {
            rejectedCandidateCount += 1
            if shouldLogSnapshot || rejectedCandidateCount % 30 == 1 {
                print("BallDetector: candidate rejected #\(rejectedCandidateCount) — \(bestRejectReason ?? "no cluster passed") [\(brightX.count) bright samples total]")
            }
            return nil
        }

        if shouldLogSnapshot {
            print("BallDetector: CANDIDATE FOUND — confidence=\(String(format: "%.2f", observation.confidence)) rect=\(observation.normalizedRect)")
        }
        return observation
    }
}

