import CoreVideo
import CoreGraphics

final class ImpactDetector {
    struct Configuration {
        var sampleStride: Int = 3
        var brightnessThreshold: Int = 155
        var maxChannelSpread: Int = 85
        var dropRatioThreshold: Double = 0.55
        var minimumConsecutiveImpactFrames: Int = 2
        var debugPrintEveryNFrames: Int = 60
        /// A real locked ball fills ~12% of the impact ROI (the ROI is the ball rect padded
        /// 2.5× — see expandedImpactROI), so a baseline far below that means the lock is on
        /// something that isn't a ball (dim indoor blob, reflection). Triggering off such a
        /// baseline captures 41 frames of nothing and shows a phantom shot.
        var minimumBaselineRatio: Double = 0.045
    }

    private let configuration: Configuration
    // Internal lock guards all mutable state so reset() is safe from any thread.
    private let lock = NSLock()

    private var baselineWhiteRatio: Double?
    private var consecutiveImpactFrames: Int = 0
    private var debugFrameCounter: Int = 0
    /// current/baseline from the last checkForImpact. In shade the ball is barely brighter than
    /// the background, so the white-ratio drop alone never clears dropRatioThreshold (measured
    /// floor ~0.78 vs the 0.55 gate). The caller pairs THIS partial-dim signal with ball-departure
    /// (ball no longer at the lock) for a shade-robust trigger — the dim rules out detection
    /// hiccups (ball still there = still bright), the departure rules out club pull-back.
    private(set) var lastDropRatio: Double = 1.0

    /// True once a real ball (baseline ≥ the floor) has been locked — gates the departure trigger.
    var hasValidBaseline: Bool {
        lock.lock(); defer { lock.unlock() }
        return (baselineWhiteRatio ?? 0) >= configuration.minimumBaselineRatio
    }

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        baselineWhiteRatio = nil
        consecutiveImpactFrames = 0
        debugFrameCounter = 0
    }

    // Sets the baseline from the current frame if no baseline exists yet. `brightnessThreshold`
    // is the detector's live (adaptive) threshold — the ball must be counted at the same brightness
    // it was located at, or a dim flashlight/indoor ball reads a near-zero baseline and never fires.
    func establishBaselineIfNeeded(pixelBuffer: CVPixelBuffer, roi: CGRect, brightnessThreshold: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard baselineWhiteRatio == nil else { return }
        baselineWhiteRatio = whitePixelRatio(in: pixelBuffer, roi: roi, brightnessThreshold: brightnessThreshold)
    }

    // Returns true when consecutive impact-looking frames exceed the threshold.
    func checkForImpact(pixelBuffer: CVPixelBuffer, roi: CGRect, brightnessThreshold: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let current = whitePixelRatio(in: pixelBuffer, roi: roi, brightnessThreshold: brightnessThreshold)

        // Init baseline inline if somehow called before establishBaselineIfNeeded.
        if baselineWhiteRatio == nil {
            baselineWhiteRatio = current
            return false
        }
        let baseline = baselineWhiteRatio!
        let threshold = baseline * configuration.dropRatioThreshold
        lastDropRatio = baseline > 0 ? current / baseline : 1.0

        debugFrameCounter += 1
        if debugFrameCounter % configuration.debugPrintEveryNFrames == 0 {
            print(String(format: "[IMP] b=%.3f c=%.3f t=%.3f n=%d",
                         baseline, current, threshold, consecutiveImpactFrames))
        }

        if current < threshold {
            consecutiveImpactFrames += 1
            if consecutiveImpactFrames >= configuration.minimumConsecutiveImpactFrames {
                guard baseline >= configuration.minimumBaselineRatio else {
                    if consecutiveImpactFrames == configuration.minimumConsecutiveImpactFrames
                        || consecutiveImpactFrames % 240 == 0 {
                        print(String(format: "[IMP] trigger suppressed — baseline %.3f < %.3f floor (lock isn't a real ball)",
                                     baseline, configuration.minimumBaselineRatio))
                    }
                    return false
                }
                // Print on first confirmation and then sparsely — when the caller suppresses
                // the trigger (lock-age gate) this fires every frame and was flooding the
                // console with 60+ identical lines per swing.
                if consecutiveImpactFrames == configuration.minimumConsecutiveImpactFrames
                    || consecutiveImpactFrames % 60 == 0 {
                    print(String(format: "[IMP] TRIGGERED b=%.3f c=%.3f t=%.3f n=%d",
                                 baseline, current, threshold, consecutiveImpactFrames))
                }
                return true
            }
        } else {
            consecutiveImpactFrames = 0
            // Slow exponential moving average — don't let a single bright flash skew baseline.
            baselineWhiteRatio = baseline * 0.95 + current * 0.05
        }

        return false
    }

    // Scans only within the clamped ROI, downsampled by sampleStride. BGRA byte order.
    // `brightnessThreshold` comes from the detector's live adaptive threshold (capped here at the
    // configured value so a bright scene behaves exactly as before).
    private func whitePixelRatio(in pixelBuffer: CVPixelBuffer, roi: CGRect, brightnessThreshold: Int) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0
        }

        let width       = CVPixelBufferGetWidth(pixelBuffer)
        let height      = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer     = baseAddress.assumingMemoryBound(to: UInt8.self)
        let step        = max(1, configuration.sampleStride)

        let xStart = max(0,      Int(roi.minX * CGFloat(width)))
        let xEnd   = min(width,  Int(roi.maxX * CGFloat(width)))
        let yStart = max(0,      Int(roi.minY * CGFloat(height)))
        let yEnd   = min(height, Int(roi.maxY * CGFloat(height)))

        guard xEnd > xStart, yEnd > yStart else { return 0 }

        // Count the ball at the detector's live threshold, but never ABOVE the configured ceiling
        // (so bright/range scenes, where the adaptive value pins to the ceiling, are unchanged).
        let thr = min(brightnessThreshold, configuration.brightnessThreshold)

        var whiteCount = 0
        var totalCount = 0

        for y in stride(from: yStart, to: yEnd, by: step) {
            let row = pointer + y * bytesPerRow
            for x in stride(from: xStart, to: xEnd, by: step) {
                let idx    = x * 4
                let b      = Int(row[idx])
                let g      = Int(row[idx + 1])
                let r      = Int(row[idx + 2])
                let bright = (r + g + b) / 3
                let spread = max(r, max(g, b)) - min(r, min(g, b))
                totalCount += 1
                // Ball-pixel census: white (bright, low spread) OR lime range ball
                // (green-dominant, collapsed blue — same signature as BallDetector).
                // Without the lime path the baseline was ~zero for lime balls and the
                // departure trigger could never fire: lock succeeded, capture never did.
                let isLime = g - b >= 110 && r < g && r * 2 > g && bright >= 130
                if (bright >= thr && spread <= configuration.maxChannelSpread) || isLime {
                    whiteCount += 1
                }
            }
        }

        return totalCount > 0 ? Double(whiteCount) / Double(totalCount) : 0
    }
}
