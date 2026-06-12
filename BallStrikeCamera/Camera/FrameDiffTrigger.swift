import CoreVideo
import CoreGraphics

/// Detects ball departure by comparing every live frame against a captured reference.
/// Two-layer confirmation required: a brightness drop across the ROI AND at least one
/// spatial confirmation (centroid missing/shifted, radius change, bounding-box moved,
/// or near-zero bright-pixel count). This prevents hot-spot flicker from false-firing.
final class FrameDiffTrigger {

    struct Config {
        /// Frames of sustained soft-drop (ratio < softDropRatio) before departure considered
        var softDropWindow: Int = 4
        /// Frames of sustained hard-drop (ratio < hardDropRatio) before departure considered
        var hardDropWindow: Int = 3
        var softDropRatio: Float = 0.32
        var hardDropRatio: Float = 0.16
        /// Minimum consecutive stable frames before the trigger is armed
        var stableFramesToArm: Int = 8
        /// Spatial: fraction of max(roiW, roiH) that centroid must shift to count as moved
        var centroidShiftFraction: Float = 0.18
        /// Spatial: fraction change in detected radius to count as size change
        var radiusChangeFraction: Float = 0.30
        var brightCountNearZeroFraction: Float = 0.04
    }

    private let config: Config
    private let lock = NSLock()

    // Reference state (guarded by lock)
    private var refBrightSum:  Int = 0
    private var refBrightCount: Int = 0
    private var refCentroidX:  Float = 0
    private var refCentroidY:  Float = 0
    private var refRadius:     Float = 0
    private var refBoundingX0: Int = 0, refBoundingX1: Int = 0
    private var refBoundingY0: Int = 0, refBoundingY1: Int = 0
    private var hasReference:  Bool = false

    // Rolling departure counters (guarded by lock)
    private var softDropCount: Int = 0
    private var hardDropCount: Int = 0

    /// Once this fires it stays true until reset — caller reads it every frame.
    nonisolated(unsafe) private(set) var hasTriggered: Bool = false

    // Arming latch
    private var stableCount: Int = 0
    private var hasBeenStableEnough: Bool = false

    init(config: Config = Config()) {
        self.config = config
    }

    /// Capture a reference snapshot from the bright ball currently in the ROI.
    /// Call this once after lock is confirmed stable.
    func captureReference(in pixelBuffer: CVPixelBuffer, roiCenter: CGPoint, roiRadius: CGFloat) {
        guard let stats = computeROIStats(pixelBuffer, center: roiCenter, radius: roiRadius) else { return }
        lock.lock()
        refBrightSum   = stats.brightSum
        refBrightCount = stats.brightCount
        refCentroidX   = stats.centroidX
        refCentroidY   = stats.centroidY
        refRadius      = stats.radius
        refBoundingX0  = stats.bx0; refBoundingX1 = stats.bx1
        refBoundingY0  = stats.by0; refBoundingY1 = stats.by1
        hasReference   = true
        softDropCount  = 0
        hardDropCount  = 0
        lock.unlock()
    }

    /// Call every frame after the reference is captured. Returns true when departure is detected.
    /// Result is latched — remains true after first trigger until `reset()`.
    @discardableResult
    func check(in pixelBuffer: CVPixelBuffer, roiCenter: CGPoint, roiRadius: CGFloat) -> Bool {
        if hasTriggered { return true }

        guard let stats = computeROIStats(pixelBuffer, center: roiCenter, radius: roiRadius) else { return false }

        lock.lock()
        defer { lock.unlock() }
        guard hasReference else { return false }

        // Arming: require N stable frames with a similar bright count to reference
        let stableRatio = refBrightCount > 0
            ? Float(stats.brightCount) / Float(refBrightCount) : 0
        if stableRatio >= 0.70 && stableRatio <= 1.35 {
            stableCount += 1
            if stableCount >= config.stableFramesToArm { hasBeenStableEnough = true }
        } else {
            if stableCount > 0 { stableCount = max(0, stableCount - 1) }
        }
        guard hasBeenStableEnough else { return false }

        // ── Layer 1: brightness ratio ──────────────────────────────────────────
        let liveBrightSum = stats.brightSum
        let ratio = refBrightSum > 0 ? Float(liveBrightSum) / Float(refBrightSum) : 1.0

        if ratio < config.hardDropRatio {
            hardDropCount += 1; softDropCount += 1
        } else if ratio < config.softDropRatio {
            softDropCount += 1; hardDropCount = max(0, hardDropCount - 1)
        } else {
            softDropCount = max(0, softDropCount - 1)
            hardDropCount = max(0, hardDropCount - 1)
        }

        let brightnessDeparted =
            softDropCount >= config.softDropWindow ||
            hardDropCount >= config.hardDropWindow

        guard brightnessDeparted else { return false }

        // ── Layer 2: spatial confirmation ──────────────────────────────────────
        let roiDiam = Float(roiRadius * 2)
        let shiftThr = config.centroidShiftFraction * roiDiam

        // Centroid: missing or shifted
        let centroidMissing = stats.brightCount < 8
        let centroidShift   = hypotf(stats.centroidX - refCentroidX,
                                     stats.centroidY - refCentroidY) > shiftThr

        // Radius change
        let radiusChanged = refRadius > 1 &&
            abs(stats.radius - refRadius) / refRadius > config.radiusChangeFraction

        // Bounding-box moved (top-left corner shifted)
        let bboxMoved = abs(stats.bx0 - refBoundingX0) > Int(shiftThr) ||
                        abs(stats.by0 - refBoundingY0) > Int(shiftThr)

        // Near-zero bright pixels
        let roiArea = stats.roiPixelCount
        let nearZero = roiArea > 0 &&
            Float(stats.brightCount) / Float(roiArea) < config.brightCountNearZeroFraction

        let spatialConfirmed = centroidMissing || centroidShift || radiusChanged || bboxMoved || nearZero
        guard spatialConfirmed else { return false }

        hasTriggered = true
        return true
    }

    /// Record a stable pre-trigger frame; used by the caller to track whether
    /// the trigger is armed (same counting the caller does, surfaced here for logging).
    func notifyStableFrame() {
        // The internal counter handles arming; this is a no-op hook for future use.
    }

    /// Reset all state. Call after each shot or when the camera phase changes.
    func reset() {
        lock.lock()
        refBrightSum   = 0; refBrightCount = 0
        refCentroidX   = 0; refCentroidY   = 0
        refRadius      = 0
        refBoundingX0  = 0; refBoundingX1  = 0
        refBoundingY0  = 0; refBoundingY1  = 0
        hasReference   = false
        softDropCount  = 0; hardDropCount  = 0
        stableCount    = 0; hasBeenStableEnough = false
        lock.unlock()
        hasTriggered = false
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private struct ROIStats {
        let brightSum, brightCount, roiPixelCount: Int
        let centroidX, centroidY, radius: Float
        let bx0, bx1, by0, by1: Int
    }

    private func computeROIStats(
        _ pixelBuffer: CVPixelBuffer, center: CGPoint, radius: CGFloat
    ) -> ROIStats? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr    = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return nil }

        let ptr  = base.assumingMemoryBound(to: UInt8.self)
        let r    = Int(radius * CGFloat(max(width, height)))
        let cx   = Int(center.x * CGFloat(width))
        let cy   = Int(center.y * CGFloat(height))
        let x0   = max(0, cx - r); let x1 = min(width  - 1, cx + r)
        let y0   = max(0, cy - r); let y1 = min(height - 1, cy + r)
        guard x0 < x1, y0 < y1 else { return nil }

        // Adaptive threshold — same formula as LightweightBallDetector
        var totalSum: Int = 0; var totalCount = 0
        var totalSqSum: Int64 = 0
        for y in y0...y1 {
            let row = ptr + y * bpr
            for x in x0...x1 {
                let luma = Int(lumaAt(row: row, x: x))
                totalSum   += luma
                totalSqSum += Int64(luma) * Int64(luma)
                totalCount += 1
            }
        }
        guard totalCount > 16 else { return nil }
        let mean   = Float(totalSum) / Float(totalCount)
        let variance = Float(totalSqSum) / Float(totalCount) - mean * mean
        let stddev = sqrt(max(0, variance))
        let thr    = UInt8(min(165.0, max(mean + 18.0, mean + 1.35 * stddev)))

        // Bright-pixel stats for departure detection
        var brightSum = 0, brightCount = 0
        var sumBX: Float = 0, sumBY: Float = 0
        var bx0 = x1, bx1 = x0, by0 = y1, by1 = y0

        for y in y0...y1 {
            let row = ptr + y * bpr
            for x in x0...x1 {
                let luma = lumaAt(row: row, x: x)
                brightSum += Int(luma)
                if luma >= thr {
                    brightCount += 1
                    sumBX += Float(x); sumBY += Float(y)
                    if x < bx0 { bx0 = x }; if x > bx1 { bx1 = x }
                    if y < by0 { by0 = y }; if y > by1 { by1 = y }
                }
            }
        }

        let centX    = brightCount > 0 ? sumBX / Float(brightCount) : Float(cx)
        let centY    = brightCount > 0 ? sumBY / Float(brightCount) : Float(cy)
        let blobW    = brightCount > 0 ? Float(bx1 - bx0 + 1) : 0
        let blobH    = brightCount > 0 ? Float(by1 - by0 + 1) : 0
        let blobR    = (blobW + blobH) * 0.25

        return ROIStats(
            brightSum: brightSum, brightCount: brightCount,
            roiPixelCount: totalCount,
            centroidX: centX, centroidY: centY, radius: blobR,
            bx0: bx0, bx1: bx1, by0: by0, by1: by1
        )
    }

    @inline(__always)
    private func lumaAt(row: UnsafePointer<UInt8>, x: Int) -> UInt8 {
        let i = x * 4
        let b = Int(row[i]); let g = Int(row[i + 1]); let r = Int(row[i + 2])
        return UInt8((77 * r + 150 * g + 29 * b) >> 8)
    }
}
