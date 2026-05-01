import UIKit
import CoreGraphics

// Independent mirror of PostImpactBallTracker that works directly on raw images
// loaded from a ShotExport package (no pre-computed normalized images).
final class ExperimentalBallTracker {

    struct Configuration {
        var sampleStride: Int = 2

        var preBrightnessThreshold:  Int     = 145
        var preMaxChannelSpread:     Int     = 90
        var preMinBrightSamples:     Int     = 6
        var preMinNormWidth:         CGFloat = 0.008
        var preMaxNormWidth:         CGFloat = 0.090
        var preMinNormHeight:        CGFloat = 0.012
        var preMaxNormHeight:        CGFloat = 0.130
        var preMinAspect:            CGFloat = 0.30
        var preMaxAspect:            CGFloat = 2.00

        var postBrightnessThreshold: Int     = 115
        var postMaxChannelSpread:    Int     = 110
        var postMinBrightSamples:    Int     = 4
        var postMinNormWidth:        CGFloat = 0.005
        var postMaxNormWidth:        CGFloat = 0.120
        var postMinNormHeight:       CGFloat = 0.005
        var postMaxNormHeight:       CGFloat = 0.150
        var postMinAspect:           CGFloat = 0.12
        var postMaxAspect:           CGFloat = 5.00

        var preImpactSearchScale:    CGFloat = 2.0
        var impactSearchScale:       CGFloat = 3.5
        var postImpactBaseScale:     CGFloat = 7.0
        var postImpactScaleGrowth:   CGFloat = 2.0
        var postImpactMaxScale:      CGFloat = 30.0
    }

    private struct ScanConfig {
        let brightnessThreshold:  Int
        let maxChannelSpread:     Int
        let minimumBrightSamples: Int
        let minNormWidth:         CGFloat
        let maxNormWidth:         CGFloat
        let minNormHeight:        CGFloat
        let maxNormHeight:        CGFloat
        let minAspect:            CGFloat
        let maxAspect:            CGFloat
    }

    private struct Candidate {
        let center:     CGPoint
        let diameter:   CGFloat
        let confidence: Double
    }

    private struct ScanResult {
        let candidate:        Candidate?
        let brightPixelCount: Int
        let rejectionReason:  String?
    }

    private let cfg:        Configuration
    private let normalizer: FrameNormalizer

    init(configuration: Configuration = Configuration()) {
        self.cfg        = configuration
        self.normalizer = FrameNormalizer()
    }

    // MARK: - Public

    func run(on sequence: BallTrackingTestSequence) -> BallTrackingTestResult {
        print("ExperimentalBallTracker: starting on \(sequence.sourceName)")
        print("ExperimentalBallTracker: \(sequence.frames.count) frames, impact=\(sequence.impactFrameIndex)")

        // Normalize all frames to DarkenedHighContrast upfront.
        let normalized: [(bytes: [UInt8], width: Int, height: Int)?] = sequence.frames.map { frame in
            let img = normalizer.normalizedImage(from: frame.image, mode: .darkenedHighContrast)
            return pixelBytes(from: img)
        }

        let impact = sequence.impactFrameIndex
        let lockedRect = sequence.lockedBallRect ?? CGRect(x: 0.45, y: 0.45, width: 0.10, height: 0.10)

        let preConfig = ScanConfig(
            brightnessThreshold: cfg.preBrightnessThreshold,
            maxChannelSpread: cfg.preMaxChannelSpread, minimumBrightSamples: cfg.preMinBrightSamples,
            minNormWidth: cfg.preMinNormWidth, maxNormWidth: cfg.preMaxNormWidth,
            minNormHeight: cfg.preMinNormHeight, maxNormHeight: cfg.preMaxNormHeight,
            minAspect: cfg.preMinAspect, maxAspect: cfg.preMaxAspect)
        let postConfig = ScanConfig(
            brightnessThreshold: cfg.postBrightnessThreshold,
            maxChannelSpread: cfg.postMaxChannelSpread, minimumBrightSamples: cfg.postMinBrightSamples,
            minNormWidth: cfg.postMinNormWidth, maxNormWidth: cfg.postMaxNormWidth,
            minNormHeight: cfg.postMinNormHeight, maxNormHeight: cfg.postMaxNormHeight,
            minAspect: cfg.postMinAspect, maxAspect: cfg.postMaxAspect)

        var observations: [BallTrackingTestObservation] = []
        var lastPreCenter  = lockedRect.center
        var lastPostCenter: CGPoint? = nil

        for (i, frame) in sequence.frames.enumerated() {
            let idx = frame.frameIndex
            guard let pd = normalized[i] else {
                observations.append(miss(frame, reason: "no_pixel_data"))
                continue
            }

            let obs: BallTrackingTestObservation

            if idx < impact {
                let roi    = expanded(lockedRect, scale: cfg.preImpactSearchScale)
                let result = scan(pd, roi: roi, config: preConfig)
                if let c = result.candidate {
                    obs = hit(frame, c, reason: "ok")
                    lastPreCenter = c.center
                } else {
                    obs = miss(frame, reason: result.rejectionReason ?? "no_candidate")
                }

            } else if idx == impact {
                let roi    = expanded(lockedRect, scale: cfg.impactSearchScale)
                let result = scan(pd, roi: roi, config: preConfig)
                if let c = result.candidate {
                    obs = hit(frame, c, reason: "ok")
                    lastPreCenter = c.center
                } else {
                    obs = miss(frame, reason: result.rejectionReason ?? "no_candidate")
                }

            } else {
                let postOffset = idx - impact
                let maxScale   = min(cfg.postImpactMaxScale,
                                     cfg.postImpactBaseScale + CGFloat(postOffset) * cfg.postImpactScaleGrowth)
                let roiCenter  = lastPostCenter ?? lockedRect.center
                let scalePass1 = min(maxScale, max(cfg.postImpactBaseScale, maxScale * 0.5))
                let rois: [CGRect] = [
                    expandedAround(roiCenter, rect: lockedRect, scale: scalePass1),
                    expandedAround(roiCenter, rect: lockedRect, scale: maxScale)
                ]

                var found:      Candidate? = nil
                var lastResult = ScanResult(candidate: nil, brightPixelCount: 0, rejectionReason: nil)
                for roi in rois {
                    let result = scan(pd, roi: roi, config: postConfig)
                    lastResult = result
                    if let c = result.candidate { found = c; break }
                }

                if let c = found {
                    obs = hit(frame, c, reason: "ok")
                    lastPostCenter = c.center
                } else {
                    obs = miss(frame, reason: lastResult.rejectionReason ?? "no_candidate")
                }
            }
            observations.append(obs)
        }

        printSummary(observations, impact: impact)

        let tracked = observations.filter { $0.centerX != nil }
        let avgConf = tracked.isEmpty ? 0.0
            : tracked.reduce(0.0) { $0 + $1.confidence } / Double(tracked.count)

        return BallTrackingTestResult(
            observations: observations,
            trackedCount: tracked.count,
            missingCount: observations.count - tracked.count,
            averageConfidence: avgConf)
    }

    // MARK: - Scanner

    private func scan(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        roi: CGRect,
        config: ScanConfig
    ) -> ScanResult {
        let (bytes, width, height) = pd
        let step = max(1, cfg.sampleStride)

        let xStart = max(0,      Int(roi.minX * CGFloat(width)))
        let xEnd   = min(width,  Int(roi.maxX * CGFloat(width)))
        let yStart = max(0,      Int(roi.minY * CGFloat(height)))
        let yEnd   = min(height, Int(roi.maxY * CGFloat(height)))
        guard xEnd > xStart, yEnd > yStart else {
            return ScanResult(candidate: nil, brightPixelCount: 0, rejectionReason: "empty_roi")
        }

        var count = 0
        var minX = width, minY = height, maxX = 0, maxY = 0
        var sumX = 0, sumY = 0

        for y in stride(from: yStart, to: yEnd, by: step) {
            let row = y * width * 4
            for x in stride(from: xStart, to: xEnd, by: step) {
                let i  = row + x * 4
                let r  = Int(bytes[i]), g = Int(bytes[i+1]), b = Int(bytes[i+2])
                let br = (r + g + b) / 3
                let sp = max(r, max(g, b)) - min(r, min(g, b))
                if br >= config.brightnessThreshold && sp <= config.maxChannelSpread {
                    count += 1
                    if x < minX { minX = x }; if x > maxX { maxX = x }
                    if y < minY { minY = y }; if y > maxY { maxY = y }
                    sumX += x; sumY += y
                }
            }
        }

        guard count >= config.minimumBrightSamples else {
            return ScanResult(candidate: nil, brightPixelCount: count,
                              rejectionReason: "too_few_bright_pixels(\(count)<\(config.minimumBrightSamples))")
        }

        let boxW = CGFloat(maxX - minX + step)
        let boxH = CGFloat(maxY - minY + step)
        guard boxW > 0, boxH > 0 else {
            return ScanResult(candidate: nil, brightPixelCount: count, rejectionReason: "degenerate_bbox")
        }

        let nW     = boxW / CGFloat(width)
        let nH     = boxH / CGFloat(height)
        let aspect = nW / nH

        guard nW >= config.minNormWidth,  nW <= config.maxNormWidth,
              nH >= config.minNormHeight, nH <= config.maxNormHeight,
              aspect >= config.minAspect, aspect <= config.maxAspect else {
            let reason: String
            if      nW < config.minNormWidth  { reason = "width_too_small(\(String(format: "%.4f", nW)))" }
            else if nW > config.maxNormWidth  { reason = "width_too_large(\(String(format: "%.4f", nW)))" }
            else if nH < config.minNormHeight { reason = "height_too_small(\(String(format: "%.4f", nH)))" }
            else if nH > config.maxNormHeight { reason = "height_too_large(\(String(format: "%.4f", nH)))" }
            else                              { reason = "aspect_out_of_range(\(String(format: "%.2f", aspect)))" }
            return ScanResult(candidate: nil, brightPixelCount: count, rejectionReason: reason)
        }

        let cx  = CGFloat(sumX) / CGFloat(count) / CGFloat(width)
        let cy  = CGFloat(sumY) / CGFloat(count) / CGFloat(height)
        let dia = (nW + nH) / 2.0
        let conf = min(1.0, Double(count) / Double(config.minimumBrightSamples * 4))
        return ScanResult(candidate: Candidate(center: CGPoint(x: cx, y: cy), diameter: dia, confidence: conf),
                          brightPixelCount: count, rejectionReason: nil)
    }

    // MARK: - Summary

    private func printSummary(_ obs: [BallTrackingTestObservation], impact: Int) {
        let preObs   = obs.filter { $0.frameIndex < impact }
        let postObs  = obs.filter { $0.frameIndex > impact }
        let preHit   = preObs.filter  { $0.centerX != nil }.count
        let postHit  = postObs.filter { $0.centerX != nil }.count
        let impactOk = obs.first { $0.frameIndex == impact }?.centerX != nil

        print("ExperimentalBallTracker results:")
        print("  Pre-impact:  \(preHit)/\(preObs.count)")
        print("  Impact:      \(impactOk ? "tracked" : "missed")")
        print("  Post-impact: \(postHit)/\(postObs.count)")
        print("--- Per-frame table ---")
        for o in obs {
            let marker = o.frameIndex == impact ? " ← impact" : ""
            if let cx = o.centerX, let cy = o.centerY, let d = o.diameter {
                print(String(format: "frame=%02d t=%+.4f x=%.4f y=%.4f d=%.4f conf=%.2f%@",
                             o.frameIndex, 0.0, cx, cy, d, o.confidence, marker))
            } else {
                print(String(format: "frame=%02d t=%+.4f miss reason=\(o.debugReason)%@",
                             o.frameIndex, 0.0, marker))
            }
        }
    }

    // MARK: - Geometry

    private func expanded(_ rect: CGRect, scale: CGFloat) -> CGRect {
        expandedAround(rect.center, rect: rect, scale: scale)
    }

    private func expandedAround(_ center: CGPoint, rect: CGRect, scale: CGFloat) -> CGRect {
        let w = rect.width * scale, h = rect.height * scale
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Pixel Extraction

    private func pixelBytes(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return (bytes, w, h)
    }

    // MARK: - Helpers

    private func hit(_ frame: BallTrackingTestFrame, _ c: Candidate, reason: String) -> BallTrackingTestObservation {
        BallTrackingTestObservation(
            frameIndex: frame.frameIndex, centerX: c.center.x, centerY: c.center.y,
            diameter: c.diameter, confidence: c.confidence, debugReason: reason)
    }

    private func miss(_ frame: BallTrackingTestFrame, reason: String) -> BallTrackingTestObservation {
        BallTrackingTestObservation(
            frameIndex: frame.frameIndex, centerX: nil, centerY: nil,
            diameter: nil, confidence: 0, debugReason: reason)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
