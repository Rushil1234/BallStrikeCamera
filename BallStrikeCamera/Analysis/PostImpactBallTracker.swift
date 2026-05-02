import UIKit
import CoreGraphics

final class PostImpactBallTracker {

    // MARK: - Configuration

    struct Configuration {
        // Pixel extraction
        var sampleStride: Int = 2

        // ── Pre-impact / impact thresholds (ball is stationary, sharp) ──
        var preBrightnessThreshold:  Int    = 90
        var preMaxChannelSpread:     Int    = 90
        var preMinBrightSamples:     Int    = 6
        var preMinNormWidth:         CGFloat = 0.008
        var preMaxNormWidth:         CGFloat = 0.090
        var preMinNormHeight:        CGFloat = 0.012
        var preMaxNormHeight:        CGFloat = 0.130
        var preMinAspect:            CGFloat = 0.30
        var preMaxAspect:            CGFloat = 2.00

        // ── Post-impact thresholds (ball moving fast, motion blur, dimmer) ──
        var postBrightnessThreshold: Int    = 115
        var postMaxChannelSpread:    Int    = 110
        var postMinBrightSamples:    Int    = 4
        var postMinNormWidth:        CGFloat = 0.005
        var postMaxNormWidth:        CGFloat = 0.120   // wider for blur
        var postMinNormHeight:       CGFloat = 0.005
        var postMaxNormHeight:       CGFloat = 0.150
        var postMinAspect:           CGFloat = 0.12    // elongated in direction of travel
        var postMaxAspect:           CGFloat = 5.00

        // ── ROI scales ──
        var preImpactSearchScale:    CGFloat = 5.67
        var impactSearchScale:       CGFloat = 8.66
        // Post-impact grows rapidly so a fast-moving ball stays in view.
        // scale(offset) = min(maxScale, base + offset × growth)
        var postImpactBaseScale:     CGFloat = 5.03
        var postImpactScaleGrowth:   CGFloat = 5.00
        var postImpactMaxScale:      CGFloat = 30.0

        var isPostImpactDebugLoggingEnabled: Bool = true
    }

    // Internal per-scan threshold set.
    private struct ScanConfig {
        let brightnessThreshold: Int
        let maxChannelSpread:    Int
        let minimumBrightSamples: Int
        let minNormWidth:        CGFloat
        let maxNormWidth:        CGFloat
        let minNormHeight:       CGFloat
        let maxNormHeight:       CGFloat
        let minAspect:           CGFloat
        let maxAspect:           CGFloat
    }

    private struct Candidate {
        let center:     CGPoint
        let diameter:   CGFloat
        let confidence: Double
        let normWidth:  CGFloat
        let normHeight: CGFloat
    }

    // Scan returns both the candidate (if any) and diagnostic data for the review UI.
    private struct ScanResult {
        let candidate:       Candidate?
        let brightPixelCount: Int
        let rejectionReason: String?
    }

    private let cfg: Configuration

    init(configuration: Configuration = Configuration()) {
        self.cfg = configuration
    }

    // MARK: - Public

    func track(
        frames: [AnalyzedShotFrame],
        lockedBallRect: CGRect,
        impactFrameIndex: Int
    ) -> (observations: [ShotBallObservation], debugInfos: [ShotFrameDebugInfo]) {

        print("PostImpactBallTracker live defaults: preBright=\(cfg.preBrightnessThreshold) preROI=\(cfg.preImpactSearchScale) impactScale=\(cfg.impactSearchScale) postBase=\(cfg.postImpactBaseScale) postGrowth=\(cfg.postImpactScaleGrowth) postMax=\(cfg.postImpactMaxScale)")
        print("PostImpactBallTracker analysis mode: DarkenedHighContrast")
        let pixelData: [(bytes: [UInt8], width: Int, height: Int)?] = frames.map {
            pixelBytes(from: $0.darkenedHighContrastImage ?? $0.originalFrame.image)
        }

        var observations: [ShotBallObservation] = []
        var debugInfos:   [ShotFrameDebugInfo]  = []

        var lastPreCenter  = lockedBallRect.center
        var lastPostCenter: CGPoint? = nil

        let preConfig = ScanConfig(
            brightnessThreshold:  cfg.preBrightnessThreshold,
            maxChannelSpread:     cfg.preMaxChannelSpread,
            minimumBrightSamples: cfg.preMinBrightSamples,
            minNormWidth:         cfg.preMinNormWidth,
            maxNormWidth:         cfg.preMaxNormWidth,
            minNormHeight:        cfg.preMinNormHeight,
            maxNormHeight:        cfg.preMaxNormHeight,
            minAspect:            cfg.preMinAspect,
            maxAspect:            cfg.preMaxAspect
        )
        let postConfig = ScanConfig(
            brightnessThreshold:  cfg.postBrightnessThreshold,
            maxChannelSpread:     cfg.postMaxChannelSpread,
            minimumBrightSamples: cfg.postMinBrightSamples,
            minNormWidth:         cfg.postMinNormWidth,
            maxNormWidth:         cfg.postMaxNormWidth,
            minNormHeight:        cfg.postMinNormHeight,
            maxNormHeight:        cfg.postMaxNormHeight,
            minAspect:            cfg.postMinAspect,
            maxAspect:            cfg.postMaxAspect
        )

        for (i, frame) in frames.enumerated() {
            let idx = frame.frameIndex
            guard let pd = pixelData[i] else {
                observations.append(miss(frame))
                debugInfos.append(ShotFrameDebugInfo(frameIndex: idx, searchROI: nil,
                                                      candidateCount: 0,
                                                      rejectionReason: "no_pixel_data"))
                continue
            }

            let obs: ShotBallObservation

            if idx < impactFrameIndex {
                let roi    = expanded(lockedBallRect, scale: cfg.preImpactSearchScale)
                let result = scan(pd, roi: roi, config: preConfig)
                if let c = result.candidate {
                    obs = hit(frame, c)
                    lastPreCenter = c.center
                } else {
                    obs = miss(frame)
                }
                debugInfos.append(ShotFrameDebugInfo(frameIndex: idx, searchROI: roi,
                                                      candidateCount: result.brightPixelCount,
                                                      rejectionReason: result.rejectionReason))

            } else if idx == impactFrameIndex {
                let roi    = expanded(lockedBallRect, scale: cfg.impactSearchScale)
                let result = scan(pd, roi: roi, config: preConfig)
                if let c = result.candidate {
                    obs = hit(frame, c)
                    lastPreCenter = c.center
                } else {
                    obs = miss(frame)
                }
                debugInfos.append(ShotFrameDebugInfo(frameIndex: idx, searchROI: roi,
                                                      candidateCount: result.brightPixelCount,
                                                      rejectionReason: result.rejectionReason))

            } else {
                let postOffset = idx - impactFrameIndex
                let (postObs, postDebug) = trackPostImpact(
                    pd: pd,
                    frame: frame,
                    postOffset: postOffset,
                    lockedBallRect: lockedBallRect,
                    lastPostCenter: lastPostCenter,
                    postConfig: postConfig
                )
                obs = postObs
                debugInfos.append(postDebug)
                if let cx = obs.centerX, let cy = obs.centerY {
                    lastPostCenter = CGPoint(x: cx, y: cy)
                }
            }

            observations.append(obs)
        }

        return (observations, debugInfos)
    }

    // MARK: - Post-Impact Tracking

    private func trackPostImpact(
        pd: (bytes: [UInt8], width: Int, height: Int),
        frame: AnalyzedShotFrame,
        postOffset: Int,
        lockedBallRect: CGRect,
        lastPostCenter: CGPoint?,
        postConfig: ScanConfig
    ) -> (observation: ShotBallObservation, debugInfo: ShotFrameDebugInfo) {

        let maxScale = min(cfg.postImpactMaxScale,
                          cfg.postImpactBaseScale + CGFloat(postOffset) * cfg.postImpactScaleGrowth)

        let roiCenter  = lastPostCenter ?? lockedBallRect.center
        let scalePass1 = min(maxScale, max(cfg.postImpactBaseScale, maxScale * 0.5))
        let rois: [CGRect] = [
            expandedAround(roiCenter, rect: lockedBallRect, scale: scalePass1),
            expandedAround(roiCenter, rect: lockedBallRect, scale: maxScale)
        ]

        var found:      Candidate?  = nil
        var usedROI:    CGRect      = rois[0]
        var lastResult              = ScanResult(candidate: nil, brightPixelCount: 0,
                                                  rejectionReason: nil)

        for roi in rois {
            usedROI    = roi
            let result = scan(pd, roi: roi, config: postConfig)
            lastResult = result
            if let c = result.candidate {
                found = c
                break
            }
        }

        if cfg.isPostImpactDebugLoggingEnabled {
            let roiStr = String(format: "(x=%.3f y=%.3f w=%.3f h=%.3f)",
                                usedROI.minX, usedROI.minY, usedROI.width, usedROI.height)
            if let c = found {
                print(String(format: "frame=%02d postROI=%@ selected=(x=%.4f y=%.4f d=%.4f conf=%.2f)",
                             frame.frameIndex, roiStr, c.center.x, c.center.y, c.diameter, c.confidence))
            } else {
                print(String(format: "frame=%02d postROI=%@ selected=nil reason=%@ bright=%d",
                             frame.frameIndex, roiStr,
                             lastResult.rejectionReason ?? "unknown",
                             lastResult.brightPixelCount))
            }
        }

        let obs       = found.map { hit(frame, $0) } ?? miss(frame)
        let debugInfo = ShotFrameDebugInfo(
            frameIndex:      frame.frameIndex,
            searchROI:       usedROI,
            candidateCount:  lastResult.brightPixelCount,
            rejectionReason: found != nil ? nil : (lastResult.rejectionReason ?? "no_candidate")
        )
        return (obs, debugInfo)
    }

    // MARK: - Pixel Scanner

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
                let i = row + x * 4
                let r = Int(bytes[i]), g = Int(bytes[i+1]), b = Int(bytes[i+2])
                let brightness = (r + g + b) / 3
                let spread = max(r, max(g, b)) - min(r, min(g, b))
                if brightness >= config.brightnessThreshold && spread <= config.maxChannelSpread {
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
            return ScanResult(candidate: nil, brightPixelCount: count,
                              rejectionReason: "degenerate_bbox")
        }

        let nW     = boxW / CGFloat(width)
        let nH     = boxH / CGFloat(height)
        let aspect = nW / nH

        guard nW >= config.minNormWidth,  nW <= config.maxNormWidth,
              nH >= config.minNormHeight, nH <= config.maxNormHeight,
              aspect >= config.minAspect, aspect <= config.maxAspect else {
            let reason: String
            if nW < config.minNormWidth {
                reason = "width_too_small(\(String(format: "%.4f", nW)))"
            } else if nW > config.maxNormWidth {
                reason = "width_too_large(\(String(format: "%.4f", nW)))"
            } else if nH < config.minNormHeight {
                reason = "height_too_small(\(String(format: "%.4f", nH)))"
            } else if nH > config.maxNormHeight {
                reason = "height_too_large(\(String(format: "%.4f", nH)))"
            } else {
                reason = "aspect_out_of_range(\(String(format: "%.2f", aspect)))"
            }
            return ScanResult(candidate: nil, brightPixelCount: count, rejectionReason: reason)
        }

        let cx  = CGFloat(sumX) / CGFloat(count) / CGFloat(width)
        let cy  = CGFloat(sumY) / CGFloat(count) / CGFloat(height)
        let dia = (nW + nH) / 2.0
        let confidence = min(1.0, Double(count) / Double(config.minimumBrightSamples * 4))

        let candidate = Candidate(center: CGPoint(x: cx, y: cy), diameter: dia,
                                  confidence: confidence, normWidth: nW, normHeight: nH)
        return ScanResult(candidate: candidate, brightPixelCount: count, rejectionReason: nil)
    }

    // MARK: - Summary

    static func printSummary(_ observations: [ShotBallObservation], impactFrameIndex: Int) {
        let preObs    = observations.filter { $0.frameIndex < impactFrameIndex }
        let impactObs = observations.first   { $0.frameIndex == impactFrameIndex }
        let postObs   = observations.filter { $0.frameIndex > impactFrameIndex }

        let preTracked    = preObs.filter  { $0.centerX != nil }.count
        let postTracked   = postObs.filter { $0.centerX != nil }
        let impactTracked = impactObs?.centerX != nil

        let allTracked = observations.filter { $0.centerX != nil }
        let avgConf = allTracked.isEmpty ? 0.0
            : allTracked.reduce(0.0) { $0 + $1.confidence } / Double(allTracked.count)

        print("Post-impact tracking complete")
        print("Pre-impact tracked:  \(preTracked)/\(preObs.count)")
        print("Impact frame tracked: \(impactTracked ? "yes" : "no")")
        print("Post-impact tracked: \(postTracked.count)/\(postObs.count)")
        if let first = postTracked.first { print("First post-impact tracked frame: index \(first.frameIndex)") }
        if let last  = postTracked.last  { print("Last post-impact tracked frame: index \(last.frameIndex)") }
        print(String(format: "Average confidence (tracked): %.2f", avgConf))

        print("--- Per-frame tracking table ---")
        for obs in observations {
            let marker = obs.frameIndex == impactFrameIndex ? " ← impact" : ""
            if let cx = obs.centerX, let cy = obs.centerY, let d = obs.diameter {
                print(String(format: "frame=%02d t=%+.4f x=%.4f y=%.4f d=%.4f conf=%.2f%@",
                             obs.frameIndex, obs.relativeTime, cx, cy, d, obs.confidence, marker))
            } else {
                print(String(format: "frame=%02d t=%+.4f x=nil   y=nil   d=nil   conf=0.00%@",
                             obs.frameIndex, obs.relativeTime, marker))
            }
        }
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

    // MARK: - Geometry

    private func expanded(_ rect: CGRect, scale: CGFloat) -> CGRect {
        expandedAround(rect.center, rect: rect, scale: scale)
    }

    private func expandedAround(_ center: CGPoint, rect: CGRect, scale: CGFloat) -> CGRect {
        let w = rect.width * scale, h = rect.height * scale
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Helpers

    private func hit(_ frame: AnalyzedShotFrame, _ c: Candidate) -> ShotBallObservation {
        ShotBallObservation(frameIndex: frame.frameIndex, timestamp: frame.timestamp,
                            relativeTime: frame.relativeTime,
                            centerX: c.center.x, centerY: c.center.y,
                            diameter: c.diameter, confidence: c.confidence,
                            wasInterpolated: false)
    }

    private func miss(_ frame: AnalyzedShotFrame) -> ShotBallObservation {
        ShotBallObservation(frameIndex: frame.frameIndex, timestamp: frame.timestamp,
                            relativeTime: frame.relativeTime,
                            centerX: nil, centerY: nil, diameter: nil,
                            confidence: 0, wasInterpolated: false)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
