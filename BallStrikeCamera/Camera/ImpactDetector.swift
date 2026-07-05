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
    }

    private let configuration: Configuration
    // Internal lock guards all mutable state so reset() is safe from any thread.
    private let lock = NSLock()

    private var baselineWhiteRatio: Double?
    private var consecutiveImpactFrames: Int = 0
    private var debugFrameCounter: Int = 0

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

    // Sets the baseline from the current frame if no baseline exists yet.
    func establishBaselineIfNeeded(pixelBuffer: CVPixelBuffer, roi: CGRect) {
        lock.lock()
        defer { lock.unlock() }
        guard baselineWhiteRatio == nil else { return }
        baselineWhiteRatio = whitePixelRatio(in: pixelBuffer, roi: roi)
    }

    // Returns true when consecutive impact-looking frames exceed the threshold.
    func checkForImpact(pixelBuffer: CVPixelBuffer, roi: CGRect) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let current = whitePixelRatio(in: pixelBuffer, roi: roi)

        // Init baseline inline if somehow called before establishBaselineIfNeeded.
        if baselineWhiteRatio == nil {
            baselineWhiteRatio = current
            return false
        }
        let baseline = baselineWhiteRatio!
        let threshold = baseline * configuration.dropRatioThreshold

        debugFrameCounter += 1
        if debugFrameCounter % configuration.debugPrintEveryNFrames == 0 {
            print(String(format: "ImpactDetector baseline=%.4f current=%.4f threshold=%.4f consecutive=%d",
                         baseline, current, threshold, consecutiveImpactFrames))
        }

        if current < threshold {
            consecutiveImpactFrames += 1
            if consecutiveImpactFrames >= configuration.minimumConsecutiveImpactFrames {
                // Print on first confirmation and then sparsely — when the caller suppresses
                // the trigger (lock-age gate) this fires every frame and was flooding the
                // console with 60+ identical lines per swing.
                if consecutiveImpactFrames == configuration.minimumConsecutiveImpactFrames
                    || consecutiveImpactFrames % 60 == 0 {
                    print(String(format: "ROI IMPACT DETECTED baseline=%.4f current=%.4f threshold=%.4f consecutive=%d",
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
    private func whitePixelRatio(in pixelBuffer: CVPixelBuffer, roi: CGRect) -> Double {
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
                if bright >= configuration.brightnessThreshold && spread <= configuration.maxChannelSpread {
                    whiteCount += 1
                }
            }
        }

        return totalCount > 0 ? Double(whiteCount) / Double(totalCount) : 0
    }
}
