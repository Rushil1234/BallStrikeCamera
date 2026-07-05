import CoreVideo
import CoreGraphics

/// Luma-based ball detector with adaptive thresholding and connected-component scoring.
/// Replaces the stride-sampled BGRA BallDetector. Works across lighting conditions
/// without manual shutter tuning: the threshold adapts to local ROI mean/stddev.
final class LightweightBallDetector {

    struct Config {
        var brightnessThresholdCap: UInt8 = 165   // adaptive threshold is capped here
        // Raised from 4.0 — the real ball measured 10-48px radius across a session (varies with
        // ROI zoom/distance), while glints/grass texture were producing spurious 1.5-3px "ball"
        // candidates that competed with the real one for the stability lock.
        var minBallRadiusPx: Float = 8.0
        var maxBallRadiusPx: Float = 45.0
        var maxCandidates: Int = 6
        // Scanning every pixel in a ~400x400 ROI three times (stats/mask/BFS) is ~500k pixel
        // touches/frame — far too slow to sustain 240fps (measured 92-97% frame drop). The old
        // BallDetector used stride 6 and ran at full framerate; matching that here keeps the
        // better per-blob clustering algorithm without reintroducing the same bottleneck.
        var sampleStride: Int = 6
    }

    private let config: Config

    // Reusable scratch buffers — grown lazily, never shrunk, reallocated on first use.
    private var maskBuf:    [UInt8] = []
    private var visitedBuf: [UInt8] = []
    private var queueX:     [Int32] = []
    private var queueY:     [Int32] = []

    // Diagnostic throttling — detect() runs at up to 240fps.
    private var frameCounter: Int = 0
    private let diagnosticLogInterval = 60   // ~4x/sec at 240fps

    init(config: Config = Config()) {
        self.config = config
    }

    /// Detect the best bright, compact ball candidate inside `roi` (normalized 0…1 rect).
    /// The ellipse-boundary filter from the old pipeline is handled internally.
    func detect(in pixelBuffer: CVPixelBuffer, roi: CGRect) -> BallObservation? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr    = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Pixel bounds for this ROI
        let x0 = max(0, Int(roi.minX * CGFloat(width)))
        let x1 = min(width  - 1, Int(roi.maxX * CGFloat(width)))
        let y0 = max(0, Int(roi.minY * CGFloat(height)))
        let y1 = min(height - 1, Int(roi.maxY * CGFloat(height)))
        guard x0 < x1, y0 < y1 else { return nil }

        frameCounter += 1
        let shouldLog = frameCounter % diagnosticLogInterval == 0

        // ROI pixel center (for candidate scoring and ellipse check)
        let roiCX = Int(roi.midX * CGFloat(width))
        let roiCY = Int(roi.midY * CGFloat(height))
        let halfRX = max(1.0, roi.width  / 2.0 * CGFloat(width))
        let halfRY = max(1.0, roi.height / 2.0 * CGFloat(height))

        let step = max(1, config.sampleStride)

        // ── ROI statistics (adaptive threshold) ──────────────────────────────
        var totalSum: Int = 0
        var totalSqSum: Int64 = 0
        var totalCount: Int = 0
        var maxLuma: UInt8 = 0

        for y in Swift.stride(from: y0, through: y1, by: step) {
            let row = ptr + y * bpr
            for x in Swift.stride(from: x0, through: x1, by: step) {
                let luma = lumaAt(row: row, x: x)
                totalSum   += Int(luma)
                totalSqSum += Int64(luma) * Int64(luma)
                totalCount += 1
                if luma > maxLuma { maxLuma = luma }
            }
        }
        guard totalCount > 20 else { return nil }

        let mean    = Float(totalSum) / Float(totalCount)
        let variance = Float(totalSqSum) / Float(totalCount) - mean * mean
        let stddev  = sqrt(max(0, variance))

        let adaptive = UInt8(min(255.0, max(mean + 18.0, mean + 1.35 * stddev)))
        let thr      = min(config.brightnessThresholdCap, adaptive)

        if shouldLog {
            print("LightweightBallDetector scan: roiPx=\(x1 - x0 + 1)x\(y1 - y0 + 1) mean=\(String(format: "%.1f", mean)) stddev=\(String(format: "%.1f", stddev)) adaptiveThr=\(thr) (cap \(config.brightnessThresholdCap)) maxLuma=\(maxLuma)")
        }

        guard maxLuma >= thr else {
            if shouldLog {
                print("LightweightBallDetector: NO CANDIDATE — nothing in ROI reached adaptive threshold \(thr) (maxLuma=\(maxLuma))")
            }
            return nil
        }

        // ── Binary mask (grid space — one cell per sampled pixel, `step` apart) ─
        let roiW    = (x1 - x0) / step + 1
        let roiH    = (y1 - y0) / step + 1
        let roiArea = roiW * roiH

        if maskBuf.count < roiArea {
            maskBuf    = [UInt8](repeating: 0, count: roiArea)
            visitedBuf = [UInt8](repeating: 0, count: roiArea)
            queueX     = [Int32](repeating: 0, count: roiArea)
            queueY     = [Int32](repeating: 0, count: roiArea)
        } else {
            // Zero only the slice we'll use
            maskBuf.withUnsafeMutableBytes    { _ = memset($0.baseAddress!, 0, roiArea) }
            visitedBuf.withUnsafeMutableBytes { _ = memset($0.baseAddress!, 0, roiArea) }
        }

        for y in Swift.stride(from: y0, through: y1, by: step) {
            let row    = ptr + y * bpr
            let localY = (y - y0) / step
            for x in Swift.stride(from: x0, through: x1, by: step) {
                if lumaAt(row: row, x: x) >= thr {
                    maskBuf[localY * roiW + (x - x0) / step] = 1
                }
            }
        }

        // ── Connected components (BFS) ────────────────────────────────────────
        struct Candidate {
            let cxPx: Float, cyPx: Float
            let radiusPx: Float
            let confidence: Float
            let sizePass: Bool, aspectPass: Bool, fillPass: Bool
        }
        var candidates = [Candidate]()
        candidates.reserveCapacity(config.maxCandidates)

        for startY in 0..<roiH {
            for startX in 0..<roiW {
                let si = startY * roiW + startX
                guard maskBuf[si] == 1, visitedBuf[si] == 0 else { continue }

                var head = 0, tail = 0
                queueX[tail] = Int32(startX); queueY[tail] = Int32(startY); tail += 1
                visitedBuf[si] = 1

                var pixCount = 0
                var sumX: Float = 0, sumY: Float = 0, sumBright: Float = 0
                var minLX = startX, maxLX = startX, minLY = startY, maxLY = startY

                while head < tail {
                    // lx/ly are grid coordinates (mask/visited/queue bookkeeping); gx/gy are the
                    // corresponding real pixel coordinates, `step` apart, used for sums/output.
                    let lx = Int(queueX[head]); let ly = Int(queueY[head]); head += 1
                    let gx = x0 + lx * step;    let gy = y0 + ly * step
                    let luma = Float(lumaAt(row: ptr + gy * bpr, x: gx))

                    pixCount += 1
                    sumX     += Float(gx); sumY += Float(gy); sumBright += luma
                    if lx < minLX { minLX = lx }; if lx > maxLX { maxLX = lx }
                    if ly < minLY { minLY = ly }; if ly > maxLY { maxLY = ly }

                    let nyLo = max(0, ly - 1); let nyHi = min(roiH - 1, ly + 1)
                    let nxLo = max(0, lx - 1); let nxHi = min(roiW - 1, lx + 1)
                    for ny in nyLo...nyHi {
                        for nx in nxLo...nxHi {
                            let ni = ny * roiW + nx
                            if maskBuf[ni] == 1, visitedBuf[ni] == 0 {
                                visitedBuf[ni] = 1
                                queueX[tail] = Int32(nx); queueY[tail] = Int32(ny); tail += 1
                            }
                        }
                    }
                }
                // Lowered from 8 — at stride 6 a ball right at minBallRadiusPx only covers a
                // handful of grid samples, so the old full-resolution floor would reject it.
                guard pixCount >= 4 else { continue }

                // bbox in grid units for fill/aspect (scale-invariant ratios, correct either way);
                // radius converts to real pixels via `step` since size thresholds are pixel-based.
                let bboxWGrid = Float(maxLX - minLX + 1)
                let bboxHGrid = Float(maxLY - minLY + 1)
                let radius  = (bboxWGrid + bboxHGrid) * 0.25 * Float(step)
                let aspect  = max(bboxWGrid, bboxHGrid) / max(1, min(bboxWGrid, bboxHGrid))
                let fill    = Float(pixCount) / max(1, bboxWGrid * bboxHGrid)
                let meanBr  = sumBright / Float(pixCount)
                let meanDk  = Float(totalSum - Int(sumBright)) / Float(max(1, totalCount - pixCount))
                let contrast   = max(0, min(1, (meanBr - meanDk) / 100.0))
                let compactness = min(1, fill / 0.785)
                // Expected sample count for a "full" blob scales down by step² versus full-res.
                let countScore  = min(1, Float(pixCount) / max(1, 100.0 / Float(step * step)))
                let aspectScore = max(0, 1 - min(1, (aspect - 1) / 1.4))
                let sizeScore: Float = {
                    if radius < config.minBallRadiusPx { return radius / max(1, config.minBallRadiusPx) }
                    if radius > config.maxBallRadiusPx { return config.maxBallRadiusPx / max(radius, 1) }
                    return 1
                }()

                let candCX   = sumX / Float(pixCount)
                let candCY   = sumY / Float(pixCount)
                let ddx      = (candCX - Float(roiCX)) / Float(halfRX)
                let ddy      = (candCY - Float(roiCY)) / Float(halfRY)
                let normDist = sqrt(ddx * ddx + ddy * ddy)
                let centerScore = max(0, 1 - min(1, normDist / 1.1))

                // Reject candidates whose center lies outside the search ellipse
                guard ddx * ddx + ddy * ddy <= 1.0 else { continue }

                let sizePass   = radius >= max(3, config.minBallRadiusPx * 0.65) &&
                                 radius <= config.maxBallRadiusPx * 1.35
                let aspectPass = aspect <= 2.4
                let fillPass   = fill   >= 0.16

                let rawConf = min(1, max(0,
                    0.26 * contrast    +
                    0.20 * compactness +
                    0.14 * aspectScore +
                    0.18 * countScore  +
                    0.10 * sizeScore   +
                    0.12 * centerScore
                ))
                let conf = min(1, max(0, (rawConf - 0.42) / 0.30))

                candidates.append(Candidate(
                    cxPx: candCX, cyPx: candCY,
                    radiusPx: radius,
                    confidence: conf,
                    sizePass: sizePass, aspectPass: aspectPass, fillPass: fillPass
                ))

                // Keep only the best N
                if candidates.count > config.maxCandidates {
                    candidates.sort { $0.confidence > $1.confidence }
                    candidates.removeLast()
                }
            }
        }

        candidates.sort { $0.confidence > $1.confidence }
        guard let best = candidates.first else {
            if shouldLog {
                print("LightweightBallDetector: NO CANDIDATE — 0 compact blobs (>=8px) survived masking/ellipse filter out of a bright ROI")
            }
            return nil
        }
        guard best.confidence >= 0.18, best.sizePass, best.aspectPass, best.fillPass else {
            if shouldLog {
                print("LightweightBallDetector: candidate rejected — radius=\(String(format: "%.1f", best.radiusPx))px confidence=\(String(format: "%.2f", best.confidence)) (need >=0.18) sizePass=\(best.sizePass) aspectPass=\(best.aspectPass) fillPass=\(best.fillPass) [\(candidates.count) blobs total]")
            }
            return nil
        }

        // Build normalizedRect centred on detected blob
        let padR = CGFloat(best.radiusPx) * 1.30
        let nCX  = CGFloat(best.cxPx) / CGFloat(width)
        let nCY  = CGFloat(best.cyPx) / CGFloat(height)
        let nRX  = padR / CGFloat(width)
        let nRY  = padR / CGFloat(height)
        let rect = CGRect(x: nCX - nRX, y: nCY - nRY, width: nRX * 2, height: nRY * 2)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        if shouldLog {
            print("LightweightBallDetector: CANDIDATE FOUND — center=(\(Int(best.cxPx)),\(Int(best.cyPx)))px radius=\(String(format: "%.1f", best.radiusPx))px confidence=\(String(format: "%.2f", best.confidence)) rect=\(rect)")
        }
        return BallObservation(normalizedRect: rect, confidence: Double(best.confidence))
    }

    @inline(__always)
    private func lumaAt(row: UnsafePointer<UInt8>, x: Int) -> UInt8 {
        let i = x * 4
        let b = Int(row[i]); let g = Int(row[i + 1]); let r = Int(row[i + 2])
        return UInt8((77 * r + 150 * g + 29 * b) >> 8)
    }
}
