import UIKit
import CoreGraphics

// MARK: - Diameter combine mode

enum DiameterCombineMode { case average, max }

// MARK: - ExperimentalBallTracker

final class ExperimentalBallTracker {

    // MARK: - Diameter Refinement Configuration

    struct DiameterRefinementConfig {
        var enabled:              Bool            = true
        var localMaskWindowScale: CGFloat         = 1.8
        var maskBrightness:       Int             = 30
        var maskMaxSpread:        Int             = 65
        var minDiameterNorm:      CGFloat         = 0.004
        var maxDiameterNorm:      CGFloat         = 0.120
        var combineMode:          DiameterCombineMode = .average
        var smoothingEnabled:     Bool            = true
        var smoothingWindowSize:  Int             = 5
    }

    // MARK: - Configuration

    struct Configuration {
        var sampleStride: Int = 2

        var preBrightnessThreshold:  Int     = 90
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

        var preImpactSearchScale:    CGFloat = 5.67
        var impactSearchScale:       CGFloat = 8.66
        var postImpactBaseScale:     CGFloat = 5.03
        var postImpactScaleGrowth:   CGFloat = 5.00
        var postImpactMaxScale:      CGFloat = 30.0

        var normalizationMode:   FrameNormalizationMode  = .darkenedHighContrast
        var diameterRefinement:  DiameterRefinementConfig = DiameterRefinementConfig()
        var impactDetection:     ImpactDetectionConfig    = ImpactDetectionConfig()
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

    private struct RawBlob {
        var minX: Int; var maxX: Int; var minY: Int; var maxY: Int
        var sumX: Int; var sumY: Int; var count: Int
    }

    private struct MaskComponent {
        var indices: [Int]
        var minCol: Int
        var maxCol: Int
        var minRow: Int
        var maxRow: Int
        var distanceSquared: CGFloat

        var count: Int { indices.count }
    }

    private struct MaskRefineOutput {
        let diameter: CGFloat?
        let boundsRect: CGRect?
        let whitePixelCount: Int
        let reason: String
        let previewImage: UIImage?
        let cropNormRect: CGRect?
        let candidateDiamInCrop: CGFloat?
        let refinedDiamInCrop: CGFloat?
    }

    private let cfg:        Configuration
    private let normalizer: FrameNormalizer

    // Temporal diameter smoothing — reset at start of each tracking pass
    private var recentDiameters: [CGFloat] = []

    init(configuration: Configuration = Configuration()) {
        self.cfg        = configuration
        self.normalizer = FrameNormalizer()
    }

    // MARK: - Public entry point

    func run(on sequence: BallTrackingTestSequence) -> BallTrackingTestResult {
        print("ExperimentalBallTracker: starting on \(sequence.sourceName)")
        print("ExperimentalBallTracker: \(sequence.frames.count) frames, fallbackImpact=\(sequence.impactFrameIndex), mode=\(cfg.normalizationMode)")
        print("ExperimentalBallTracker: maskRefinement=\(cfg.diameterRefinement.enabled) maskBright=\(cfg.diameterRefinement.maskBrightness)")

        // Normalize all frames once
        let normalized: [(bytes: [UInt8], width: Int, height: Int)?] = sequence.frames.map { frame in
            let img = cfg.normalizationMode == .original
                ? frame.image
                : normalizer.normalizedImage(from: frame.image, mode: cfg.normalizationMode)
            return pixelBytes(from: img)
        }

        let lockedRect = sequence.lockedBallRect ?? CGRect(x: 0.45, y: 0.45, width: 0.10, height: 0.10)
        let preConfig  = makeScanConfig(pre: true)
        let postConfig = makeScanConfig(pre: false)

        // Pass 1: track with metadata fallback impact index
        let pass1Obs = runTrackingPass(frames: sequence.frames, normalized: normalized,
                                       impact: sequence.impactFrameIndex,
                                       lockedRect: lockedRect,
                                       preConfig: preConfig, postConfig: postConfig)

        // Dynamic impact detection from pass-1 observations
        let detector     = ExperimentalImpactFrameDetector(config: cfg.impactDetection)
        let impactResult = detector.detect(observations: pass1Obs,
                                           fallbackImpactIndex: sequence.impactFrameIndex)
        let effectiveImpact = impactResult.detectedImpactFrameIndex

        // Pass 2 only if detected impact differs from fallback
        let finalObs: [BallTrackingTestObservation]
        if effectiveImpact != sequence.impactFrameIndex {
            print("ExperimentalBallTracker: re-tracking with detectedImpact=\(effectiveImpact)")
            finalObs = runTrackingPass(frames: sequence.frames, normalized: normalized,
                                       impact: effectiveImpact,
                                       lockedRect: lockedRect,
                                       preConfig: preConfig, postConfig: postConfig)
        } else {
            print("ExperimentalBallTracker: detected impact matches fallback — reusing pass-1")
            finalObs = pass1Obs
        }

        printSummary(finalObs, impact: effectiveImpact, impactResult: impactResult)

        let tracked = finalObs.filter { $0.centerX != nil }
        let avgConf = tracked.isEmpty ? 0.0
            : tracked.reduce(0.0) { $0 + $1.confidence } / Double(tracked.count)

        return BallTrackingTestResult(
            observations:              finalObs,
            trackedCount:              tracked.count,
            missingCount:              finalObs.count - tracked.count,
            averageConfidence:         avgConf,
            detectedImpactFrameIndex:  impactResult.detectedImpactFrameIndex,
            fallbackImpactFrameIndex:  impactResult.fallbackImpactFrameIndex,
            impactDetectionReason:     impactResult.impactDetectionReason,
            initialBallCenter:         impactResult.initialBallCenter,
            movementThresholdNorm:     impactResult.movementThresholdNorm)
    }

    // MARK: - Tracking pass (runs the full 41-frame loop for a given impact index)

    private func runTrackingPass(
        frames: [BallTrackingTestFrame],
        normalized: [(bytes: [UInt8], width: Int, height: Int)?],
        impact: Int,
        lockedRect: CGRect,
        preConfig: ScanConfig,
        postConfig: ScanConfig
    ) -> [BallTrackingTestObservation] {

        recentDiameters = []  // reset temporal smoothing for each pass

        var observations: [BallTrackingTestObservation] = []
        var lastPreCenter  = lockedRect.center
        var lastPostCenter: CGPoint? = nil

        for (i, frame) in frames.enumerated() {
            let idx = frame.frameIndex
            guard let pd = normalized[i] else {
                let dbg = BallTrackingFrameDebug(frameIndex: idx, searchROI: nil,
                    searchCenterSource: "none", searchScale: 0,
                    candidates: [], selectedCandidate: nil, reason: "no_pixel_data")
                observations.append(miss(frame, reason: "no_pixel_data", debug: dbg))
                continue
            }

            let obs: BallTrackingTestObservation

            if idx < impact {
                let roi = expanded(lockedRect, scale: cfg.preImpactSearchScale)
                let (cands, chosen) = findCandidates(pd, roi: roi, config: preConfig,
                                                      preferredCenter: lastPreCenter)
                let dbg = BallTrackingFrameDebug(
                    frameIndex: idx, searchROI: roi,
                    searchCenterSource: "lockedBall", searchScale: cfg.preImpactSearchScale,
                    candidates: cands, selectedCandidate: chosen,
                    reason: chosen == nil ? firstRejectionReason(cands) : nil)
                if let c = chosen {
                    obs = makeHit(frame, c, pd: pd, debug: dbg)
                    lastPreCenter = CGPoint(x: c.centerX, y: c.centerY)
                } else {
                    obs = miss(frame, reason: dbg.reason ?? "no_candidate", debug: dbg)
                }

            } else if idx == impact {
                let roi = expanded(lockedRect, scale: cfg.impactSearchScale)
                let (cands, chosen) = findCandidates(pd, roi: roi, config: preConfig,
                                                      preferredCenter: lastPreCenter)
                let dbg = BallTrackingFrameDebug(
                    frameIndex: idx, searchROI: roi,
                    searchCenterSource: "lockedBall", searchScale: cfg.impactSearchScale,
                    candidates: cands, selectedCandidate: chosen,
                    reason: chosen == nil ? firstRejectionReason(cands) : nil)
                if let c = chosen {
                    obs = makeHit(frame, c, pd: pd, debug: dbg)
                    lastPreCenter = CGPoint(x: c.centerX, y: c.centerY)
                } else {
                    obs = miss(frame, reason: dbg.reason ?? "no_candidate", debug: dbg)
                }

            } else {
                let postOffset = idx - impact
                let maxScale   = min(cfg.postImpactMaxScale,
                                     cfg.postImpactBaseScale + CGFloat(postOffset) * cfg.postImpactScaleGrowth)
                let roiCenter    = lastPostCenter ?? lockedRect.center
                let centerSource = lastPostCenter != nil ? "previousDetection" : "lockedBall_fallback"
                let scalePass1   = min(maxScale, max(cfg.postImpactBaseScale, maxScale * 0.5))

                let passes: [(CGRect, CGFloat)] = [
                    (expandedAround(roiCenter, rect: lockedRect, scale: scalePass1), scalePass1),
                    (expandedAround(roiCenter, rect: lockedRect, scale: maxScale),   maxScale)
                ]

                var allCands: [BallTrackingCandidateDebug] = []
                var chosen:    BallTrackingCandidateDebug? = nil
                var finalROI   = passes.last!.0
                var usedScale  = passes.last!.1

                for (roi, scale) in passes {
                    finalROI  = roi; usedScale = scale
                    let (cands, c) = findCandidates(pd, roi: roi, config: postConfig,
                                                     preferredCenter: roiCenter)
                    allCands = cands
                    if let found = c { chosen = found; break }
                }

                let dbg = BallTrackingFrameDebug(
                    frameIndex: idx, searchROI: finalROI,
                    searchCenterSource: centerSource, searchScale: usedScale,
                    candidates: allCands, selectedCandidate: chosen,
                    reason: chosen == nil ? firstRejectionReason(allCands) : nil)

                if let c = chosen {
                    obs = makeHit(frame, c, pd: pd, debug: dbg)
                    lastPostCenter = CGPoint(x: c.centerX, y: c.centerY)
                } else {
                    obs = miss(frame, reason: dbg.reason ?? "no_candidate", debug: dbg)
                }
            }
            observations.append(obs)
        }
        return observations
    }

    // MARK: - Hit builder (mask refinement + temporal smoothing)

    private func makeHit(
        _ frame: BallTrackingTestFrame,
        _ c: BallTrackingCandidateDebug,
        pd: (bytes: [UInt8], width: Int, height: Int),
        debug: BallTrackingFrameDebug
    ) -> BallTrackingTestObservation {

        let candidateD = c.diameter
        let center     = CGPoint(x: c.centerX, y: c.centerY)

        // Mask-based diameter refinement
        let maskOut: MaskRefineOutput = cfg.diameterRefinement.enabled
            ? maskRefineDiameter(pd, center: center, candidateDiameter: candidateD,
                                 config: cfg.diameterRefinement)
            : MaskRefineOutput(diameter: nil, boundsRect: nil, whitePixelCount: 0,
                               reason: "refinement_disabled", previewImage: nil,
                               cropNormRect: nil, candidateDiamInCrop: nil, refinedDiamInCrop: nil)

        let baseD = maskOut.diameter ?? candidateD

        // Temporal median smoothing
        recentDiameters.append(baseD)
        let windowSize = max(2, cfg.diameterRefinement.smoothingWindowSize)
        if recentDiameters.count > windowSize { recentDiameters.removeFirst() }

        let smoothedD: CGFloat?
        if cfg.diameterRefinement.smoothingEnabled && recentDiameters.count >= 2 {
            var sorted = recentDiameters; sorted.sort()
            smoothedD = sorted[sorted.count / 2]
        } else {
            smoothedD = nil
        }

        let finalD = smoothedD ?? maskOut.diameter ?? candidateD

        let diameterReason: String
        if smoothedD != nil {
            diameterReason = "smoothed"
        } else if maskOut.diameter != nil {
            diameterReason = maskOut.reason
        } else {
            diameterReason = cfg.diameterRefinement.enabled
                ? "mask_failed_fallback_candidate"
                : "candidate_no_refinement"
        }

        return BallTrackingTestObservation(
            frameIndex:               frame.frameIndex,
            centerX:                  c.centerX, centerY: c.centerY,
            diameter:                 finalD,
            candidateDiameter:        candidateD,
            maskRefinedDiameter:      maskOut.diameter,
            smoothedDiameter:         smoothedD,
            maskBoundsRect:           maskOut.boundsRect,
            maskWhitePixelCount:      maskOut.whitePixelCount,
            diameterDebugReason:      diameterReason,
            maskPreviewImage:         maskOut.previewImage,
            maskCropNormRect:         maskOut.cropNormRect,
            maskCandidateDiamInCrop:  maskOut.candidateDiamInCrop,
            maskRefinedDiamInCrop:    maskOut.refinedDiamInCrop,
            confidence:               c.confidence,
            debugReason:              "ok",
            frameDebug:               debug)
    }

    // MARK: - Mask-based diameter refinement

    private func maskRefineDiameter(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        center: CGPoint,
        candidateDiameter: CGFloat,
        config: DiameterRefinementConfig
    ) -> MaskRefineOutput {

        let (bytes, width, height) = pd
        let cx = Int((center.x * CGFloat(width)).rounded())
        let cy = Int((center.y * CGFloat(height)).rounded())
        guard cx >= 0, cx < width, cy >= 0, cy < height else {
            return MaskRefineOutput(diameter: nil, boundsRect: nil, whitePixelCount: 0,
                                    reason: "mask_failed_center_oob", previewImage: nil,
                                    cropNormRect: nil, candidateDiamInCrop: nil, refinedDiamInCrop: nil)
        }

        // Local mask crop radius: scale x candidate half-diameter in pixels.
        // The mask itself is intentionally only brightness-thresholded.
        let radiusPx  = max(4, Int((config.localMaskWindowScale * candidateDiameter * CGFloat(width) / 2).rounded()))
        let cropSize  = radiusPx * 2 + 1

        let cropOriginX = cx - radiusPx     // may be negative; used for crop-coord math
        let cropOriginY = cy - radiusPx

        let x0 = max(0, cx - radiusPx); let x1 = min(width  - 1, cx + radiusPx)
        let y0 = max(0, cy - radiusPx); let y1 = min(height - 1, cy + radiusPx)

        let maskBrightnessThreshold = 30

        // B&W preview: white = selected connected mask component, black = everything else.
        var thresholdMask = [Bool](repeating: false, count: cropSize * cropSize)
        var previewBytes = [UInt8](repeating: 0, count: cropSize * cropSize * 4)

        for py in y0...y1 {
            for px in x0...x1 {
                let crow = py - cropOriginY
                let ccol = px - cropOriginX
                guard crow >= 0, crow < cropSize, ccol >= 0, ccol < cropSize else { continue }
                let maskIndex = crow * cropSize + ccol

                let si = py * width * 4 + px * 4
                let r  = Int(bytes[si]), g = Int(bytes[si+1]), b = Int(bytes[si+2])
                let br = (r + g + b) / 3
                thresholdMask[maskIndex] = br >= maskBrightnessThreshold
            }
        }

        for i in 0..<(cropSize * cropSize) {
            previewBytes[i * 4 + 3] = 255
        }

        let componentSelection = mainMaskComponent(
            in: thresholdMask,
            cropSize: cropSize,
            targetCol: cx - cropOriginX,
            targetRow: cy - cropOriginY,
            maxCenterDriftPx: max(2, candidateDiameter * CGFloat(width) * 0.55)
        )
        let selectedComponent = componentSelection.component

        if let selectedComponent {
            for index in selectedComponent.indices {
                let di = index * 4
                previewBytes[di] = 255
                previewBytes[di + 1] = 255
                previewBytes[di + 2] = 255
                previewBytes[di + 3] = 255
            }
        }

        let cropNormRect = CGRect(x: CGFloat(cropOriginX) / CGFloat(width),
                                  y: CGFloat(cropOriginY) / CGFloat(height),
                                  width: CGFloat(cropSize) / CGFloat(width),
                                  height: CGFloat(cropSize) / CGFloat(height))
        let candidateDiamInCrop = candidateDiameter * CGFloat(width) / CGFloat(cropSize)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var previewImage: UIImage? = nil
        previewBytes.withUnsafeMutableBytes { ptr in
            if let ctx = CGContext(data: ptr.baseAddress, width: cropSize, height: cropSize,
                                   bitsPerComponent: 8, bytesPerRow: cropSize * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
               let cgImg = ctx.makeImage() {
                previewImage = UIImage(cgImage: cgImg)
            }
        }

        guard let component = selectedComponent else {
            return MaskRefineOutput(diameter: nil, boundsRect: nil, whitePixelCount: 0,
                                    reason: componentSelection.failureReason,
                                    previewImage: previewImage, cropNormRect: cropNormRect,
                                    candidateDiamInCrop: candidateDiamInCrop, refinedDiamInCrop: nil)
        }

        let count = component.count
        let minX = cropOriginX + component.minCol
        let maxX = cropOriginX + component.maxCol
        let minY = cropOriginY + component.minRow
        let maxY = cropOriginY + component.maxRow

        let bboxWidthPx = maxX - minX + 1
        let bboxHeightPx = maxY - minY + 1
        let bboxW = CGFloat(bboxWidthPx) / CGFloat(width)
        let bboxH = CGFloat(bboxHeightPx) / CGFloat(height)
        let boundsRect = CGRect(x: CGFloat(minX) / CGFloat(width),
                                y: CGFloat(minY) / CGFloat(height),
                                width: bboxW, height: bboxH)

        let diameterPx = max(bboxWidthPx, bboxHeightPx)
        let rawDiameter = CGFloat(diameterPx) / CGFloat(width)
        let refinedDiamInCrop = CGFloat(diameterPx) / CGFloat(cropSize)

        return MaskRefineOutput(diameter: rawDiameter, boundsRect: boundsRect,
                                whitePixelCount: count, reason: "mask_refined_threshold_\(maskBrightnessThreshold)_connected",
                                previewImage: previewImage, cropNormRect: cropNormRect,
                                candidateDiamInCrop: candidateDiamInCrop,
                                refinedDiamInCrop: refinedDiamInCrop)
    }

    private func mainMaskComponent(
        in mask: [Bool],
        cropSize: Int,
        targetCol: Int,
        targetRow: Int,
        maxCenterDriftPx: CGFloat
    ) -> (component: MaskComponent?, failureReason: String) {
        guard cropSize > 0, mask.count == cropSize * cropSize else {
            return (nil, "mask_failed_invalid_crop")
        }

        var visited = [Bool](repeating: false, count: mask.count)
        var components: [MaskComponent] = []

        for startIndex in mask.indices {
            guard mask[startIndex], !visited[startIndex] else { continue }

            var queue = [startIndex]
            var head = 0
            var indices: [Int] = []
            var minCol = Int.max
            var maxCol = 0
            var minRow = Int.max
            var maxRow = 0
            visited[startIndex] = true

            while head < queue.count {
                let index = queue[head]
                head += 1
                indices.append(index)

                let col = index % cropSize
                let row = index / cropSize
                if col < minCol { minCol = col }
                if col > maxCol { maxCol = col }
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }

                for (dc, dr) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nextCol = col + dc
                    let nextRow = row + dr
                    guard nextCol >= 0, nextCol < cropSize, nextRow >= 0, nextRow < cropSize else {
                        continue
                    }

                    let nextIndex = nextRow * cropSize + nextCol
                    if mask[nextIndex] && !visited[nextIndex] {
                        visited[nextIndex] = true
                        queue.append(nextIndex)
                    }
                }
            }

            let centerCol = CGFloat(minCol + maxCol) / 2
            let centerRow = CGFloat(minRow + maxRow) / 2
            let dx = centerCol - CGFloat(targetCol)
            let dy = centerRow - CGFloat(targetRow)
            let component = MaskComponent(
                indices: indices,
                minCol: minCol,
                maxCol: maxCol,
                minRow: minRow,
                maxRow: maxRow,
                distanceSquared: dx * dx + dy * dy
            )

            components.append(component)
        }

        guard !components.isEmpty else {
            return (nil, "mask_failed_no_white_pixels")
        }

        let substantial = components.filter { $0.count >= 3 }
        let usableComponents = substantial.isEmpty ? components : substantial

        guard let selected = usableComponents.min(by: {
            if $0.distanceSquared == $1.distanceSquared {
                return $0.count > $1.count
            }
            return $0.distanceSquared < $1.distanceSquared
        }) else {
            return (nil, "mask_failed_no_white_pixels")
        }

        guard sqrt(selected.distanceSquared) <= maxCenterDriftPx else {
            return (nil, "mask_failed_component_drift_fallback_candidate")
        }

        return (selected, "")
    }

    // MARK: - Connected-components blob finder

    private func findCandidates(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        roi: CGRect,
        config: ScanConfig,
        preferredCenter: CGPoint
    ) -> ([BallTrackingCandidateDebug], BallTrackingCandidateDebug?) {

        let (bytes, width, height) = pd
        let step = max(1, cfg.sampleStride)

        let xStart = max(0,      Int(roi.minX * CGFloat(width)))
        let xEnd   = min(width,  Int(roi.maxX * CGFloat(width)))
        let yStart = max(0,      Int(roi.minY * CGFloat(height)))
        let yEnd   = min(height, Int(roi.maxY * CGFloat(height)))
        guard xEnd > xStart, yEnd > yStart else { return ([], nil) }

        let cols = (xEnd - xStart + step - 1) / step
        let rows = (yEnd - yStart + step - 1) / step
        var bright  = [Bool](repeating: false, count: cols * rows)
        var visited = [Bool](repeating: false, count: cols * rows)

        for row in 0..<rows {
            let py      = yStart + row * step
            let baseRow = py * width * 4
            for col in 0..<cols {
                let px = xStart + col * step
                let i  = baseRow + px * 4
                let r  = Int(bytes[i]), g = Int(bytes[i+1]), b = Int(bytes[i+2])
                let br = (r + g + b) / 3
                let sp = max(r, max(g, b)) - min(r, min(g, b))
                bright[row * cols + col] = br >= config.brightnessThreshold && sp <= config.maxChannelSpread
            }
        }

        var blobs: [RawBlob] = []
        for startRow in 0..<rows {
            for startCol in 0..<cols {
                let si = startRow * cols + startCol
                guard bright[si], !visited[si] else { continue }
                var blob = RawBlob(minX: Int.max, maxX: 0, minY: Int.max, maxY: 0,
                                   sumX: 0, sumY: 0, count: 0)
                var queue = [si]; visited[si] = true; var head = 0
                while head < queue.count {
                    let idx = queue[head]; head += 1
                    let col = idx % cols, row = idx / cols
                    let px  = xStart + col * step, py = yStart + row * step
                    blob.count += 1; blob.sumX += px; blob.sumY += py
                    if px < blob.minX { blob.minX = px }; if px > blob.maxX { blob.maxX = px }
                    if py < blob.minY { blob.minY = py }; if py > blob.maxY { blob.maxY = py }
                    for (dc, dr) in [(-1,0),(1,0),(0,-1),(0,1)] {
                        let nc = col + dc, nr = row + dr
                        guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
                        let ni = nr * cols + nc
                        if bright[ni] && !visited[ni] { visited[ni] = true; queue.append(ni) }
                    }
                }
                blobs.append(blob)
            }
        }

        let candidates = blobs.map { evaluateBlob($0, step: step, width: width, height: height, config: config) }
        let chosen = candidates
            .filter { $0.accepted }
            .min(by: {
                hypot($0.centerX - preferredCenter.x, $0.centerY - preferredCenter.y) <
                hypot($1.centerX - preferredCenter.x, $1.centerY - preferredCenter.y)
            })
        return (candidates, chosen)
    }

    private func evaluateBlob(_ blob: RawBlob, step: Int, width: Int, height: Int,
                               config: ScanConfig) -> BallTrackingCandidateDebug {
        let cx  = CGFloat(blob.sumX) / CGFloat(blob.count) / CGFloat(width)
        let cy  = CGFloat(blob.sumY) / CGFloat(blob.count) / CGFloat(height)
        let bw  = CGFloat(blob.maxX - blob.minX + step)
        let bh  = CGFloat(blob.maxY - blob.minY + step)
        let nW  = bw / CGFloat(width), nH = bh / CGFloat(height)
        let asp = nW / max(nH, 1e-6)
        let dia = (nW + nH) / 2.0
        let conf = min(1.0, Double(blob.count) / Double(config.minimumBrightSamples * 4))
        let rect = CGRect(x: CGFloat(blob.minX)/CGFloat(width),
                          y: CGFloat(blob.minY)/CGFloat(height), width: nW, height: nH)

        guard blob.count >= config.minimumBrightSamples else {
            return BallTrackingCandidateDebug(rect: rect, centerX: cx, centerY: cy, diameter: dia,
                confidence: 0, accepted: false,
                rejectionReason: "too_few_pixels(\(blob.count)<\(config.minimumBrightSamples))",
                brightPixelCount: blob.count)
        }

        let reason: String?
        if      nW < config.minNormWidth  { reason = "w_small(\(String(format:"%.4f",nW)))" }
        else if nW > config.maxNormWidth  { reason = "w_large(\(String(format:"%.4f",nW)))" }
        else if nH < config.minNormHeight { reason = "h_small(\(String(format:"%.4f",nH)))" }
        else if nH > config.maxNormHeight { reason = "h_large(\(String(format:"%.4f",nH)))" }
        else if asp < config.minAspect    { reason = "asp_low(\(String(format:"%.2f",asp)))" }
        else if asp > config.maxAspect    { reason = "asp_high(\(String(format:"%.2f",asp)))" }
        else                              { reason = nil }

        return BallTrackingCandidateDebug(rect: rect, centerX: cx, centerY: cy, diameter: dia,
            confidence: conf, accepted: reason == nil, rejectionReason: reason,
            brightPixelCount: blob.count)
    }

    // MARK: - Summary

    private func printSummary(_ obs: [BallTrackingTestObservation], impact: Int,
                               impactResult: ImpactDetectionResult) {
        let preObs   = obs.filter { $0.frameIndex < impact }
        let postObs  = obs.filter { $0.frameIndex > impact }
        let preHit   = preObs.filter  { $0.centerX != nil }.count
        let postHit  = postObs.filter { $0.centerX != nil }.count
        let impactOk = obs.first { $0.frameIndex == impact }?.centerX != nil

        print("ExperimentalBallTracker results:")
        print("  Detected impact: \(impactResult.detectedImpactFrameIndex)  fallback: \(impactResult.fallbackImpactFrameIndex)  reason: \(impactResult.impactDetectionReason)")
        print("  Pre-impact:  \(preHit)/\(preObs.count)")
        print("  Impact:      \(impactOk ? "tracked" : "missed")")
        print("  Post-impact: \(postHit)/\(postObs.count)")

        let tracked = obs.filter { $0.centerX != nil }
        let maskDs  = tracked.compactMap { $0.maskRefinedDiameter }
        let candDs  = tracked.compactMap { $0.candidateDiameter }
        let sthDs   = tracked.compactMap { $0.smoothedDiameter }
        let fallbackCnt = tracked.filter { $0.diameterDebugReason.contains("fallback") }.count
        let clampedCnt  = tracked.filter { $0.diameterDebugReason.contains("clamped") }.count

        print("Diameter refinement summary")
        print("  Frames refined: \(maskDs.count)  mask_failed: \(tracked.count - maskDs.count)  clamped: \(clampedCnt)  fallback: \(fallbackCnt)")
        if !candDs.isEmpty {
            print(String(format: "  Avg candidate diameter: %.4f", candDs.reduce(0,+)/CGFloat(candDs.count)))
        }
        if !maskDs.isEmpty {
            let mean = maskDs.reduce(0,+)/CGFloat(maskDs.count)
            let std  = sqrt(maskDs.map { pow($0-mean,2) }.reduce(0,+)/CGFloat(maskDs.count))
            print(String(format: "  Avg refined diameter:  %.4f  min=%.4f  max=%.4f  std=%.4f",
                         mean, maskDs.min()!, maskDs.max()!, std))
        }
        if !sthDs.isEmpty {
            print(String(format: "  Avg smoothed diameter: %.4f", sthDs.reduce(0,+)/CGFloat(sthDs.count)))
        }

        print("--- Per-frame table ---")
        for o in obs {
            let marker = o.frameIndex == impact ? " ← impact" : ""
            if let cx = o.centerX, let cy = o.centerY, let d = o.diameter {
                let cD = o.candidateDiameter.map   { String(format:"%.4f",$0) } ?? "n/a"
                let mD = o.maskRefinedDiameter.map { String(format:"%.4f",$0) } ?? "n/a"
                let px = o.maskWhitePixelCount
                print(String(format: "frame=%02d x=%.4f y=%.4f d=%.4f(cand=%@ mask=%@ px=%d [%@]) conf=%.2f cands=%d%@",
                             o.frameIndex, cx, cy, d, cD, mD, px,
                             o.diameterDebugReason, o.confidence,
                             o.frameDebug?.candidates.count ?? 0, marker))
            } else {
                print(String(format: "frame=%02d miss reason=\(o.debugReason)%@", o.frameIndex, marker))
            }
        }
    }

    // MARK: - Config helpers

    private func makeScanConfig(pre: Bool) -> ScanConfig {
        pre ? ScanConfig(
            brightnessThreshold: cfg.preBrightnessThreshold,
            maxChannelSpread: cfg.preMaxChannelSpread, minimumBrightSamples: cfg.preMinBrightSamples,
            minNormWidth: cfg.preMinNormWidth, maxNormWidth: cfg.preMaxNormWidth,
            minNormHeight: cfg.preMinNormHeight, maxNormHeight: cfg.preMaxNormHeight,
            minAspect: cfg.preMinAspect, maxAspect: cfg.preMaxAspect)
        : ScanConfig(
            brightnessThreshold: cfg.postBrightnessThreshold,
            maxChannelSpread: cfg.postMaxChannelSpread, minimumBrightSamples: cfg.postMinBrightSamples,
            minNormWidth: cfg.postMinNormWidth, maxNormWidth: cfg.postMaxNormWidth,
            minNormHeight: cfg.postMinNormHeight, maxNormHeight: cfg.postMaxNormHeight,
            minAspect: cfg.postMinAspect, maxAspect: cfg.postMaxAspect)
    }

    // MARK: - Geometry

    private func expanded(_ rect: CGRect, scale: CGFloat) -> CGRect {
        expandedAround(rect.center, rect: rect, scale: scale)
    }

    private func expandedAround(_ center: CGPoint, rect: CGRect, scale: CGFloat) -> CGRect {
        let w = rect.width * scale, h = rect.height * scale
        return CGRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Pixel extraction

    private func pixelBytes(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let cs    = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return (bytes, w, h)
    }

    // MARK: - Helpers

    private func miss(_ frame: BallTrackingTestFrame, reason: String,
                      debug: BallTrackingFrameDebug) -> BallTrackingTestObservation {
        BallTrackingTestObservation(
            frameIndex: frame.frameIndex, centerX: nil, centerY: nil,
            diameter: nil, candidateDiameter: nil, maskRefinedDiameter: nil,
            smoothedDiameter: nil, maskBoundsRect: nil, maskWhitePixelCount: 0,
            diameterDebugReason: "",
            maskPreviewImage: nil, maskCropNormRect: nil,
            maskCandidateDiamInCrop: nil, maskRefinedDiamInCrop: nil,
            confidence: 0, debugReason: reason, frameDebug: debug)
    }

    private func firstRejectionReason(_ cands: [BallTrackingCandidateDebug]) -> String {
        cands.first(where: { !$0.accepted })?.rejectionReason
            ?? (cands.isEmpty ? "no_blobs" : "no_accepted_candidate")
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
