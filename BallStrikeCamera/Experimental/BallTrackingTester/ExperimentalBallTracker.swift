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
        // Part A — percentile-based mask threshold
        var usePercentileMaskThreshold:     Bool   = true
        var maskWhitenessPercentile:        Double = 85.0
        var maskPercentileMinBrightness:    Int    = 80
        var maskPercentileMaxBrightness:    Int    = 245
        var maskBackgroundSuppressionDelta: Int    = 15
        // Part B — diameter growth / pre-impact median gates
        var maxDiameterGrowthRatioPerFrame:    CGFloat = 1.35
        var maxDiameterRatioToPreImpactMedian: CGFloat = 4.0
        var hardClampDiameter:                 Bool    = true
        // Part C-new — diameter shrink constraint
        var minDiameterShrinkRatioPerFrame:    CGFloat = 0.70
        var hardClampDiameterShrink:           Bool    = true
        // Part D: line-like mask rejection
        var rejectLineLikeMask:            Bool    = true
        var maxMaskAspectForBall:          CGFloat = 2.2
        var minMaskAspectForBall:          CGFloat = 0.45
        var lineLikeAspectThreshold:       CGFloat = 3.0
        var lineLikeFillMax:               CGFloat = 0.18
        var minMaskComponentPixelsForBall: Int     = 10
    }

    // MARK: - Candidate Scoring Configuration (Parts A–H)

    struct CandidateScoringConfig {
        var brightnessScoreWeight:         Double  = 0.5
        var sizeScoreWeight:               Double  = 4.0
        var distanceScoreWeight:           Double  = 2.5
        var motionScoreWeight:             Double  = 1.5
        var directionScoreWeight:          Double  = 1.0
        var shapeScoreWeight:              Double  = 0.5

        var useMotionPrediction:           Bool    = true
        var predictionLookbackFrames:      Int     = 3
        var maxJumpDistanceNorm:           CGFloat = 0.10
        var maxJumpDistByDiameter:         CGFloat = 4.0
        var jumpPenaltyWeight:             Double  = 3.0
        var allowReacquireAfterMisses:     Bool    = true
        var reacquireMissFrameLimit:       Int     = 3

        var useDirectionConstraint:        Bool    = true
        var directionPenaltyWeight:        Double  = 1.5
        var minForwardProgressNorm:        CGFloat = -0.005
        var directionSmoothingAlpha:       CGFloat = 0.35

        var useExpectedDiameterConstraint: Bool    = true
        var minDiameterRatioToExpected:    CGFloat = 0.35
        var maxDiameterRatioToExpected:    CGFloat = 2.25
        var diameterScoreWeight:           Double  = 2.0
        var hardRejectExtremeDiameter:     Bool    = true
        var extremeMaxDiameterRatio:       CGFloat = 4.0

        var rejectClubLikeCandidates:      Bool    = true
        var clubLikeMaxAspect:             CGFloat = 4.0

        // Launch direction / backward rejection / termination (Parts A–C)
        var useMonotonicProgressConstraint:       Bool    = true
        var minLaunchProgressToLockDirection:     CGFloat = 0.02
        var allowedBackwardProgressNorm:          CGFloat = 0.005
        var backwardPenaltyWeight:                Double  = 3.0
        var hardRejectBackwardAfterLaunch:        Bool    = true
        var enableLostBallTermination:            Bool    = true
        var lostBallMissFrameLimit:               Int     = 3
        var lostBallMinProgressBeforeTermination: CGFloat = 0.05
        var allowReacquireAfterTermination:       Bool    = false

        var exclusionZones:                [CGRect] = []
        var hardRejectInsideExclusion:     Bool    = true
        var exclusionPenaltyWeight:        Double  = 5.0

        // Part A-new — pre-launch reference direction rejection
        var hardRejectBehindStart:              Bool    = true
        var useReferenceProgressBeforeLaunch:   Bool    = true
        var minAllowedProgressBeforeLaunch:     CGFloat = -0.003

        // Part H — HLA closeness scoring (raised to 3.0 for stronger on-line preference)
        var hlaClosenessWeight:     Double  = 3.0
        var maxCandidateHLADegrees: Double  = 35.0

        // New session Part C: prediction cross boost
        var enablePredictionBoost:       Bool    = true
        var predictionInsideBonus:       Double  = 4.0
        var predictionNearBonus:         Double  = 2.0
        var predictionBoostRadiusNorm:   CGFloat = 0.045
        var predictionDistPenaltyWeight: Double  = 3.0

        // New session Part E: off-path hard rejection after launch
        var hardRejectFarOffPath:  Bool    = true
        var maxOffPathDistNorm:    CGFloat = 0.060

        // New session Part F: prediction miss limit (disable cross after N misses)
        var disablePredictionAfterMiss: Bool = true
        var predictionMissLimit:        Int  = 3

        // New session Part B: merged club-ball rejection (early post-impact)
        var enableMergedClubBallReject:      Bool    = true
        var maxFirstPostImpactDiameterRatio: CGFloat = 1.85
        var mergedCandidateFrameWindow:      Int     = 3

        // Part A: Face prior from ball HLA
        var useBallHLAFacePrior:             Bool    = true
        var facePriorBallHLAWeight:          Double  = 0.85
        var facePriorClubPathWeight:         Double  = 0.15
        var maxFacePriorDeviationDegrees:    Double  = 25.0
        var facePriorScoreWeight:            Double  = 5.0
        var suppressFaceIfFarFromBallHLA:    Bool    = true
        var maxFaceBallHLADifferenceDegrees: Double  = 30.0

        // Part B: Enhanced early merged shape stopper
        var enableEarlyMergedShapeStopper:   Bool    = true
        var mergedShapeFrameWindowAfterImpact: Int    = 3
        var maxEarlyDiameterSpikeRatio:      Double  = 1.60
        var maxEarlyAreaSpikeRatio:          Double  = 2.50
        var maxEarlyMaskBoundsSpikeRatio:    Double  = 2.00
        var requireSpikeThenDropCheck:       Bool    = true
        var spikeDropLookaheadFrames:        Int     = 2
        var spikeDropRatioThreshold:         Double  = 0.75
        var allowGradualDiameterGrowth:      Bool    = true
        var maxGradualGrowthRatioPerFrame:   Double  = 1.35

        // Part A: Impact frame merged spike (separate from post-impact)
        var maxImpactDiameterSpikeRatio:     CGFloat = 1.75

        // Strict impact frame diameter gate
        var enableStrictImpactDiameterGate:    Bool    = true
        var impactFrameMaxDiameterGrowthRatio: CGFloat = 1.25

        // Part C: Cone search
        var useConeSearchRegion:                  Bool    = true
        var coneHalfAngleDegrees:                 CGFloat = 18.0
        var coneInitialLengthNorm:                CGFloat = 0.12
        var coneLengthGrowthPerFrameNorm:         CGFloat = 0.035
        var coneMaxLengthNorm:                    CGFloat = 0.75
        var coneBackwardAllowanceNorm:            CGFloat = 0.015
        var coneUseLaunchDirectionWhenAvailable:  Bool    = true

        // Part D: Full-frame recovery after cone miss
        var enableFullFrameRecoveryAfterConeMiss: Bool    = true
        var recoveryMinMaskWhitePixels:           Int     = 25
        var recoveryMinMaskFillRatio:             CGFloat = 0.12
        var recoveryMaxLineResidualNorm:          CGFloat = 0.035

        // Part F: Vertical jump rejection
        var hardRejectLargeDownwardJumpAfterLaunch: Bool    = true
        var maxDownwardJumpPerFrameNorm:            CGFloat = 0.040
        var maxVerticalJumpFromPathNorm:            CGFloat = 0.050
        var verticalJumpPenaltyWeight:              Double  = 4.0
        var useFittedPathForVerticalGate:           Bool    = true

        // Prediction cross rescue (updated defaults per Part F)
        var enablePredictionCrossRescue:        Bool    = true
        var predictionRescueWindowAfterLaunch:  Int     = 16
        var predictionRescueMaxConsecMisses:    Int     = 2
        var predictionRescueRadiusNorm:         CGFloat = 0.065
        var predictionRescueInsideBonus:        Double  = 12.0
        var predictionRescueNearBonus:          Double  = 7.0
        var predictionRescueMaxLineResidual:    CGFloat = 0.025
        var predictionRescueInsideCircleScale:  CGFloat = 1.25
        var predictionRescueAllowBorderlineMask: Bool   = true
        var predictionRescueMinMaskPixels:      Int     = 8
        var predictionRescueMinFillRatio:       CGFloat = 0.045
        var predictionRescueMinDiamRatio:       CGFloat = 0.35
        var predictionRescueRequireFwdProgress: Bool    = true
        var predictionRescueDisableAfterTerm:   Bool    = true
        // Part C: offscreen/edge ball rejection
        var rejectEdgePartialBall: Bool    = true
        var minBallMarginNorm:     CGFloat = 0.012
        // Final edge ball filter (post-rescue gate)
        var enableFinalEdgeBallFilter:       Bool    = true
        var finalEdgeMarginNorm:             CGFloat = 0.012
        var finalEdgeRadiusMarginScale:      CGFloat = 1.00
        var excludeEdgeBallFromMetrics:      Bool    = true
        // Part E: single-point prediction
        var enableSinglePointPrediction:   Bool    = true
        var singlePointPredictionMaxStep:  CGFloat = 0.12
        var singlePointPredictionMinStep:  CGFloat = 0.006
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

        var postBrightnessThreshold: Int     = 92
        var postMaxChannelSpread:    Int     = 110
        var postMinBrightSamples:    Int     = 4
        var postMinNormWidth:        CGFloat = 0.018
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

        var normalizationMode:   FrameNormalizationMode    = .darkenedHighContrast
        var diameterRefinement:  DiameterRefinementConfig  = DiameterRefinementConfig()
        var impactDetection:     ImpactDetectionConfig     = ImpactDetectionConfig()
        var candidateScoring:    CandidateScoringConfig    = CandidateScoringConfig()

        // Part F — asymmetric pre-impact ROI with vertical expansion
        var zeroDegreeAngleDegrees:            Double  = 0.0
        var useAsymmetricPreImpactROI:         Bool    = true
        var preImpactForwardExpansionScale:    CGFloat = 5.5
        var preImpactBackwardExpansionScale:   CGFloat = 1.8
        var preImpactVerticalExpansionScale:   CGFloat = 1.4
        var nearImpactForwardExpansionScale:   CGFloat = 10.0
        var nearImpactBackwardExpansionScale:  CGFloat = 2.5
        var nearImpactVerticalExpansionScale:  CGFloat = 2.0
        var nearImpactWindowFrames:            Int     = 4

        // Part A (new) — asymmetric post-impact ROI
        var postImpactForwardExpansionScale:              CGFloat = 10.0
        var postImpactBackwardExpansionScale:             CGFloat = 1.2
        var postImpactVerticalExpansionScaleUntracked:    CGFloat = 1.5
        var postImpactVerticalExpansionScaleTracked:      CGFloat = 2.5
        var reliableTrackMinPostImpactPoints:             Int     = 2

        // Part C (new) — near-impact diameter jump guard
        var enableNearImpactDiameterJumpGuard:           Bool    = true
        var nearImpactDiameterGuardWindowAfterImpact:    Int     = 2
        var maxNearImpactDiameterGrowthFrameToFrame:     CGFloat = 1.50
        var minNearImpactDiameterShrinkFrameToFrame:     CGFloat = 0.80
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
        var normWidth: CGFloat = 0; var normHeight: CGFloat = 0
    }

    private struct MaskComponent {
        var indices: [Int]
        var minCol: Int; var maxCol: Int
        var minRow: Int; var maxRow: Int
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
        // Part A — threshold debug
        let percentileThreshold: Int?
        let localMedianBrightness: Int?
        let effectiveBrightnessThreshold: Int
        let maskThresholdMode: String
    }

    // Selection context passed into findCandidates for scoring
    private struct SelectionContext {
        var preferredCenter: CGPoint
        var predictedPosition: CGPoint?    // from velocity extrapolation
        var expectedDiameter: CGFloat?     // median pre-impact diameter
        var expectedDirection: CGPoint?    // normalized unit vector of launch
        var initialBallCenter: CGPoint?    // original ball position for direction scoring
        var missCount: Int                 // consecutive misses (for reacquire threshold)
        var isPostImpact: Bool
        // Launch direction / backward rejection (Parts A–C)
        var launchDirectionVector: CGPoint?  // locked launch direction
        var previousProgress: CGFloat?       // progress of last selected candidate
        var maxProgress: CGFloat?            // max progress ever seen
        var ballHasLaunched: Bool            // whether launch direction is locked
        // Parts A-new / E-new — reference direction & HLA closeness
        var zeroDegreeAngleDegrees: Double = 0.0
        var imageWidth:  Int = 1
        var imageHeight: Int = 1
    }

    // Lightweight timestamped position for velocity computation
    private struct TrackedPoint {
        let frameIndex: Int
        let center: CGPoint
        let relativeTime: TimeInterval
    }

    // Result bundle returned by runTrackingPass (Parts A–C + new session)
    private struct TrackingPassResult {
        let observations:               [BallTrackingTestObservation]
        let launchDirectionVector:      CGPoint?
        let ballLaunchedAtFrameIndex:   Int?
        let ballTrackTerminated:        Bool
        let ballTerminatedAtFrameIndex: Int?
        let predictionDisabledAtFrame:  Int?
    }

    private let cfg:        Configuration
    private let normalizer: FrameNormalizer

    private var recentDiameters: [CGFloat] = []

    init(configuration: Configuration = Configuration()) {
        self.cfg        = configuration
        self.normalizer = FrameNormalizer()
    }

    // MARK: - Public entry point

    func run(on sequence: BallTrackingTestSequence) -> BallTrackingTestResult {
        print("ExperimentalBallTracker: starting on \(sequence.sourceName)")
        print("ExperimentalBallTracker: \(sequence.frames.count) frames, fallbackImpact=\(sequence.impactFrameIndex), mode=\(cfg.normalizationMode)")
        print("ExperimentalBallTracker: maskRefinement=\(cfg.diameterRefinement.enabled) useScoring=true")

        let normalized: [(bytes: [UInt8], width: Int, height: Int)?] = sequence.frames.map { frame in
            let img = cfg.normalizationMode == .original
                ? frame.image
                : normalizer.normalizedImage(from: frame.image, mode: cfg.normalizationMode)
            return pixelBytes(from: img)
        }

        let lockedRect = sequence.lockedBallRect ?? CGRect(x: 0.45, y: 0.45, width: 0.10, height: 0.10)
        let preConfig  = makeScanConfig(pre: true)
        let postConfig = makeScanConfig(pre: false)

        let pass1 = runTrackingPass(frames: sequence.frames, normalized: normalized,
                                    impact: sequence.impactFrameIndex,
                                    lockedRect: lockedRect,
                                    preConfig: preConfig, postConfig: postConfig)

        let detector     = ExperimentalImpactFrameDetector(config: cfg.impactDetection)
        let impactResult = detector.detect(observations: pass1.observations,
                                           fallbackImpactIndex: sequence.impactFrameIndex)
        let effectiveImpact = impactResult.detectedImpactFrameIndex

        let finalPass: TrackingPassResult
        if effectiveImpact != sequence.impactFrameIndex {
            print("ExperimentalBallTracker: re-tracking with detectedImpact=\(effectiveImpact)")
            finalPass = runTrackingPass(frames: sequence.frames, normalized: normalized,
                                        impact: effectiveImpact,
                                        lockedRect: lockedRect,
                                        preConfig: preConfig, postConfig: postConfig)
        } else {
            print("ExperimentalBallTracker: detected impact matches fallback — reusing pass-1")
            finalPass = pass1
        }

        printSummary(finalPass.observations, impact: effectiveImpact, impactResult: impactResult)
        if let launchDir = finalPass.launchDirectionVector {
            print(String(format: "ExperimentalBallTracker: launchDir=(%.3f,%.3f) launchedAtFrame=%@  terminated=%@ terminatedAtFrame=%@",
                launchDir.x, launchDir.y,
                finalPass.ballLaunchedAtFrameIndex.map { "\($0)" } ?? "nil",
                finalPass.ballTrackTerminated ? "yes" : "no",
                finalPass.ballTerminatedAtFrameIndex.map { "\($0)" } ?? "nil"))
        }

        let tracked = finalPass.observations.filter { $0.centerX != nil }
        let avgConf = tracked.isEmpty ? 0.0
            : tracked.reduce(0.0) { $0 + $1.confidence } / Double(tracked.count)

        return BallTrackingTestResult(
            observations:               finalPass.observations,
            trackedCount:               tracked.count,
            missingCount:               finalPass.observations.count - tracked.count,
            averageConfidence:          avgConf,
            detectedImpactFrameIndex:   impactResult.detectedImpactFrameIndex,
            fallbackImpactFrameIndex:   impactResult.fallbackImpactFrameIndex,
            impactDetectionReason:      impactResult.impactDetectionReason,
            initialBallCenter:          impactResult.initialBallCenter,
            movementThresholdNorm:      impactResult.movementThresholdNorm,
            launchDirectionVector:      finalPass.launchDirectionVector,
            ballLaunchedAtFrameIndex:   finalPass.ballLaunchedAtFrameIndex,
            ballTrackTerminated:        finalPass.ballTrackTerminated,
            ballTerminatedAtFrameIndex: finalPass.ballTerminatedAtFrameIndex)
    }

    // MARK: - Tracking pass

    private func runTrackingPass(
        frames: [BallTrackingTestFrame],
        normalized: [(bytes: [UInt8], width: Int, height: Int)?],
        impact: Int,
        lockedRect: CGRect,
        preConfig: ScanConfig,
        postConfig: ScanConfig
    ) -> TrackingPassResult {

        recentDiameters = []
        let sc = cfg.candidateScoring

        var observations: [BallTrackingTestObservation] = []
        var lastPreCenter  = lockedRect.center
        var lastPostCenter: CGPoint? = nil

        // Scoring state (Parts B–D)
        var recentPostPoints: [TrackedPoint] = []
        var expectedDiameter: CGFloat?
        var expectedDirection: CGPoint?
        var postMissCount: Int = 0
        var preTrackedDiameters: [CGFloat] = []

        // Part B: diameter gate state
        var previousValidDiameter: CGFloat? = nil
        var preImpactMedianDiameter: CGFloat? = nil

        // Launch direction / termination state (Parts A–C)
        var launchDirectionVector: CGPoint? = nil
        var ballHasLaunched = false
        var ballLaunchedAtFrameIndex: Int? = nil
        var maxProgress: CGFloat = 0
        var previousProgress: CGFloat? = nil
        var consecutiveMissesAfterLaunch = 0
        var ballTrackTerminated = false
        var ballTerminatedAtFrameIndex: Int? = nil
        // New session Part F: prediction disable state
        var predictionMissCount = 0
        var predictionDisabled = false
        var predictionDisabledAtFrame: Int? = nil

        for (i, frame) in frames.enumerated() {
            let idx = frame.frameIndex
            guard let pd = normalized[i] else {
                let dbg = BallTrackingFrameDebug(frameIndex: idx, searchROI: nil,
                    searchCenterSource: "none", searchScale: 0,
                    candidates: [], selectedCandidate: nil, reason: "no_pixel_data",
                    ballHasLaunched: ballHasLaunched, launchDirectionVector: launchDirectionVector,
                    maxProgress: maxProgress > 0 ? maxProgress : nil, previousProgress: previousProgress,
                    ballTrackTerminated: ballTrackTerminated)
                observations.append(miss(frame, reason: "no_pixel_data", debug: dbg))
                continue
            }

            // Part C: all post-termination frames output as miss
            if ballTrackTerminated && sc.enableLostBallTermination && idx > impact {
                let dbg = BallTrackingFrameDebug(frameIndex: idx, searchROI: nil,
                    searchCenterSource: "terminated", searchScale: 0,
                    candidates: [], selectedCandidate: nil, reason: "ball_track_terminated",
                    ballHasLaunched: ballHasLaunched, launchDirectionVector: launchDirectionVector,
                    maxProgress: maxProgress > 0 ? maxProgress : nil, previousProgress: previousProgress,
                    ballTrackTerminated: true)
                observations.append(miss(frame, reason: "ball_track_terminated", debug: dbg))
                continue
            }

            let obs: BallTrackingTestObservation

            if idx < impact {
                // PRE-IMPACT: proximity selection, with optional asymmetric forward-biased ROI
                let roi: CGRect
                if cfg.useAsymmetricPreImpactROI {
                    roi = asymmetricPreImpactROI(center: lockedRect.center, lockedRect: lockedRect,
                                                 frameIdx: idx, impactIdx: impact)
                } else {
                    roi = expanded(lockedRect, scale: cfg.preImpactSearchScale)
                }
                let ctx = SelectionContext(preferredCenter: lastPreCenter, predictedPosition: nil,
                                          expectedDiameter: nil, expectedDirection: nil,
                                          initialBallCenter: nil, missCount: 0, isPostImpact: false,
                                          launchDirectionVector: nil, previousProgress: nil,
                                          maxProgress: nil, ballHasLaunched: false)
                let (cands, chosen, _) = findCandidates(pd, roi: roi, config: preConfig, context: ctx)
                let dbg = BallTrackingFrameDebug(
                    frameIndex: idx, searchROI: roi,
                    searchCenterSource: "lockedBall", searchScale: cfg.preImpactSearchScale,
                    candidates: cands, selectedCandidate: chosen,
                    reason: chosen == nil ? firstRejectionReason(cands) : nil)
                if let c = chosen {
                    obs = makeHit(frame, c, pd: pd, debug: dbg)
                    lastPreCenter = CGPoint(x: c.centerX, y: c.centerY)
                    if let d = obs.diameter {
                        preTrackedDiameters.append(d)
                        previousValidDiameter = d
                    }
                } else {
                    obs = miss(frame, reason: dbg.reason ?? "no_candidate", debug: dbg)
                }

            } else if idx == impact {
                // IMPACT: compute expectedDiameter and preImpactMedianDiameter from pre-impact frames
                if !preTrackedDiameters.isEmpty {
                    var sorted = preTrackedDiameters; sorted.sort()
                    expectedDiameter = sorted[sorted.count / 2]
                    preImpactMedianDiameter = expectedDiameter
                    print("ExperimentalBallTracker: expectedDiameter=\(String(format:"%.4f", expectedDiameter!))")
                }

                let roi = expanded(lockedRect, scale: cfg.impactSearchScale)
                let ctx = SelectionContext(preferredCenter: lastPreCenter, predictedPosition: nil,
                                          expectedDiameter: expectedDiameter, expectedDirection: nil,
                                          initialBallCenter: lockedRect.center, missCount: 0, isPostImpact: false,
                                          launchDirectionVector: nil, previousProgress: nil,
                                          maxProgress: nil, ballHasLaunched: false)
                let (cands, _chosenRaw, _) = findCandidates(pd, roi: roi, config: preConfig, context: ctx)
                // Strict impact diameter gate
                var chosen = _chosenRaw
                if sc.enableStrictImpactDiameterGate, let c = chosen,
                   let refDiam = preImpactMedianDiameter, refDiam > 1e-6 {
                    let ratio = c.diameter / refDiam
                    if ratio > sc.impactFrameMaxDiameterGrowthRatio {
                        print("[ExperimentalBallTracker] Strict impact diameter gate: frame=\(idx) diameterRatio=\(String(format:"%.2f",ratio)) > \(sc.impactFrameMaxDiameterGrowthRatio), rejecting likely club+ball merged candidate")
                        chosen = nil
                    }
                }
                let dbg = BallTrackingFrameDebug(
                    frameIndex: idx, searchROI: roi,
                    searchCenterSource: "lockedBall", searchScale: cfg.impactSearchScale,
                    candidates: cands, selectedCandidate: chosen,
                    reason: chosen == nil ? firstRejectionReason(cands) : nil,
                    expectedDiameter: expectedDiameter)
                if let c = chosen {
                    obs = makeHit(frame, c, pd: pd, debug: dbg)
                    lastPreCenter = CGPoint(x: c.centerX, y: c.centerY)
                    if let d = obs.diameter { previousValidDiameter = d }
                    recentPostPoints.append(TrackedPoint(frameIndex: idx,
                        center: CGPoint(x: c.centerX, y: c.centerY),
                        relativeTime: frame.relativeTime))
                } else {
                    obs = miss(frame, reason: dbg.reason ?? "no_candidate", debug: dbg)
                }

            } else {
                // POST-IMPACT: full scoring with motion prediction + direction + diameter + backward rejection
                let postOffset = idx - impact
                // Keep scale computation for potential future use (terminated-frame ROI)
                let maxScale   = min(cfg.postImpactMaxScale,
                                     cfg.postImpactBaseScale + CGFloat(postOffset) * cfg.postImpactScaleGrowth)
                let roiCenter    = lastPostCenter ?? lockedRect.center
                let centerSource = lastPostCenter != nil ? "previousDetection" : "lockedBall_fallback"

                var predicted = computePredicted(from: recentPostPoints,
                                                 currentTime: frame.relativeTime,
                                                 lookback: sc.predictionLookbackFrames,
                                                 initialBallCenter: lockedRect.center)
                // New session Part F: disable prediction cross after N consecutive misses
                if predictionDisabled && sc.disablePredictionAfterMiss {
                    predicted = nil
                }
                let effectivePreferred = predicted ?? roiCenter

                let ctx = SelectionContext(
                    preferredCenter: effectivePreferred,
                    predictedPosition: predicted,
                    expectedDiameter: expectedDiameter,
                    expectedDirection: expectedDirection,
                    initialBallCenter: lockedRect.center,
                    missCount: postMissCount,
                    isPostImpact: true,
                    launchDirectionVector: launchDirectionVector,
                    previousProgress: previousProgress,
                    maxProgress: maxProgress > 0 ? maxProgress : nil,
                    ballHasLaunched: ballHasLaunched,
                    zeroDegreeAngleDegrees: cfg.zeroDegreeAngleDegrees,
                    imageWidth: pd.width,
                    imageHeight: pd.height
                )

                // Part A (new): asymmetric post-impact ROI — wide forward, narrow vertical
                let _nCleanPost = recentPostPoints.count
                let _reliableTrack = _nCleanPost >= cfg.reliableTrackMinPostImpactPoints
                let _launchDirForROI = launchDirectionVector
                let _asymPostROI = asymmetricPostImpactROI(center: roiCenter,
                                                           lockedRect: lockedRect,
                                                           launchDirection: _launchDirForROI,
                                                           reliableTrack: _reliableTrack)

                var allCands: [BallTrackingCandidateDebug] = []
                var chosen:    BallTrackingCandidateDebug? = nil
                var finalROI   = _asymPostROI
                var usedScale  = maxScale
                var jumpDist:   Double? = nil

                // Single pass using asymmetric ROI (Part A)
                let (postCands, postFound, postJump) = findCandidates(pd, roi: _asymPostROI, config: postConfig, context: ctx)
                allCands = postCands
                jumpDist = postJump
                if let found = postFound {
                    // New session Part B: merged club-ball rejection in early post-impact frames
                    let isMergedTooBig: Bool = sc.enableMergedClubBallReject &&
                        postOffset <= sc.mergedCandidateFrameWindow &&
                        (expectedDiameter.map { found.diameter > $0 * sc.maxFirstPostImpactDiameterRatio } ?? false)
                    if !isMergedTooBig {
                        // Part C (new): near-impact diameter jump guard
                        var passedDiamGuard = true
                        if cfg.enableNearImpactDiameterJumpGuard &&
                           postOffset <= cfg.nearImpactDiameterGuardWindowAfterImpact {
                            let refDiam = preImpactMedianDiameter ?? previousValidDiameter
                            if let ref = refDiam, ref > 1e-6 {
                                let ratio = found.diameter / ref
                                if ratio > cfg.maxNearImpactDiameterGrowthFrameToFrame {
                                    passedDiamGuard = false
                                } else if ratio < cfg.minNearImpactDiameterShrinkFrameToFrame,
                                          previousValidDiameter != nil {
                                    passedDiamGuard = false
                                }
                            }
                        }
                        if passedDiamGuard {
                            chosen = found
                        }
                    }
                }

                let dbg = BallTrackingFrameDebug(
                    frameIndex: idx, searchROI: finalROI,
                    searchCenterSource: centerSource, searchScale: usedScale,
                    candidates: allCands, selectedCandidate: chosen,
                    reason: chosen == nil ? firstRejectionReason(allCands) : nil,
                    predictedPosition: predicted, jumpDistance: jumpDist,
                    expectedDiameter: expectedDiameter,
                    ballHasLaunched: ballHasLaunched,
                    launchDirectionVector: launchDirectionVector,
                    maxProgress: maxProgress > 0 ? maxProgress : nil,
                    previousProgress: previousProgress,
                    ballTrackTerminated: ballTrackTerminated)

                // Final edge safety gate — after all rescue, before state updates
                if sc.enableFinalEdgeBallFilter, let c = chosen {
                    let efm    = sc.finalEdgeMarginNorm
                    let efrs   = sc.finalEdgeRadiusMarginScale
                    let eradius = (c.diameter / 2.0) * efrs
                    let eleft   = c.centerX - eradius
                    let eright  = c.centerX + eradius
                    let etop    = c.centerY - eradius
                    let ebottom = c.centerY + eradius
                    let edgeFail = eleft < efm || eright > 1.0 - efm ||
                                   etop < efm  || ebottom > 1.0 - efm
                    if edgeFail {
                        chosen = nil  // prevent state updates; candidate preserved in debug
                    }
                }

                if let c = chosen {
                    obs = makeHit(frame, c, pd: pd, debug: dbg,
                                  previousValidDiameter: previousValidDiameter,
                                  preImpactMedianDiameter: preImpactMedianDiameter)
                    if let d = obs.diameter { previousValidDiameter = d }
                    let newPt = CGPoint(x: c.centerX, y: c.centerY)
                    lastPostCenter = newPt
                    postMissCount = 0
                    consecutiveMissesAfterLaunch = 0
                    predictionMissCount = 0  // reset prediction miss counter on hit

                    let tp = TrackedPoint(frameIndex: idx, center: newPt,
                                         relativeTime: frame.relativeTime)
                    recentPostPoints.append(tp)
                    let maxLookback = max(sc.predictionLookbackFrames, 3)
                    if recentPostPoints.count > maxLookback + 1 {
                        recentPostPoints.removeFirst()
                    }

                    // Update expected direction (Part C)
                    if recentPostPoints.count >= 2 {
                        let a = recentPostPoints[recentPostPoints.count - 2].center
                        let b = newPt
                        let dx = b.x - a.x; let dy = b.y - a.y
                        let len = sqrt(dx * dx + dy * dy)
                        if len > 1e-6 {
                            let newDir = CGPoint(x: dx / len, y: dy / len)
                            if let existing = expectedDirection {
                                let alpha = sc.directionSmoothingAlpha
                                expectedDirection = CGPoint(
                                    x: alpha * newDir.x + (1 - alpha) * existing.x,
                                    y: alpha * newDir.y + (1 - alpha) * existing.y)
                            } else {
                                expectedDirection = newDir
                            }
                        }
                    }

                    // Update progress tracking (Part A)
                    if let prog = c.progress {
                        if prog > maxProgress { maxProgress = prog }
                        previousProgress = prog
                    }

                    // Lock launch direction once ball has traveled far enough (Part A)
                    if !ballHasLaunched {
                        let init0 = lockedRect.center
                        let dx = newPt.x - init0.x
                        let dy = newPt.y - init0.y
                        let dist = sqrt(dx * dx + dy * dy)
                        if dist >= sc.minLaunchProgressToLockDirection {
                            launchDirectionVector = CGPoint(x: dx / dist, y: dy / dist)
                            ballHasLaunched = true
                            ballLaunchedAtFrameIndex = idx
                            print(String(format: "ExperimentalBallTracker: ball launched at frame %d dir=(%.3f,%.3f)",
                                idx, dx / dist, dy / dist))
                        }
                    }
                } else {
                    obs = miss(frame, reason: dbg.reason ?? "no_candidate", debug: dbg)
                    postMissCount += 1

                    // New session Part F: track prediction misses, disable cross after limit
                    if ballHasLaunched {
                        predictionMissCount += 1
                        if sc.disablePredictionAfterMiss &&
                           predictionMissCount >= sc.predictionMissLimit &&
                           !predictionDisabled {
                            predictionDisabled = true
                            predictionDisabledAtFrame = idx
                            print("ExperimentalBallTracker: prediction disabled at frame \(idx) after \(predictionMissCount) misses")
                        }
                    }

                    // Part C: check for lost-ball termination
                    if ballHasLaunched {
                        consecutiveMissesAfterLaunch += 1
                        if sc.enableLostBallTermination &&
                           consecutiveMissesAfterLaunch >= sc.lostBallMissFrameLimit &&
                           maxProgress >= sc.lostBallMinProgressBeforeTermination &&
                           !ballTrackTerminated {
                            ballTrackTerminated = true
                            ballTerminatedAtFrameIndex = idx - (sc.lostBallMissFrameLimit - 1)
                            print(String(format: "ExperimentalBallTracker: ball track terminated at frame %d after %d consecutive misses maxProgress=%.4f",
                                idx, consecutiveMissesAfterLaunch, maxProgress))
                        }
                    }
                }
            }
            observations.append(obs)
        }

        return TrackingPassResult(
            observations:               observations,
            launchDirectionVector:      launchDirectionVector,
            ballLaunchedAtFrameIndex:   ballLaunchedAtFrameIndex,
            ballTrackTerminated:        ballTrackTerminated,
            ballTerminatedAtFrameIndex: ballTerminatedAtFrameIndex,
            predictionDisabledAtFrame:  predictionDisabledAtFrame)
    }

    // MARK: - Velocity prediction (Part B)

    private func computePredicted(from points: [TrackedPoint],
                                   currentTime: TimeInterval,
                                   lookback: Int,
                                   initialBallCenter: CGPoint? = nil) -> CGPoint? {
        guard cfg.candidateScoring.useMotionPrediction else { return nil }
        let sc = cfg.candidateScoring
        let usable = Array(points.suffix(lookback))
        if usable.count >= 2 {
            let a = usable[usable.count - 2]
            let b = usable[usable.count - 1]
            let dt = b.relativeTime - a.relativeTime
            guard dt > 1e-9 else { return nil }
            let vx = (b.center.x - a.center.x) / CGFloat(dt)
            let vy = (b.center.y - a.center.y) / CGFloat(dt)
            let stepDt = currentTime - b.relativeTime
            guard stepDt > 0 else { return b.center }
            return CGPoint(x: b.center.x + vx * CGFloat(stepDt),
                           y: b.center.y + vy * CGFloat(stepDt))
        } else if usable.count == 1, sc.enableSinglePointPrediction,
                  let init0 = initialBallCenter {
            // Part E: single-point prediction — project from init_center through first post point
            let pt = usable[0].center
            let dx = pt.x - init0.x
            let dy = pt.y - init0.y
            let dist = hypot(dx, dy)
            guard dist > 1e-6 else { return nil }
            let step = min(max(dist, sc.singlePointPredictionMinStep), sc.singlePointPredictionMaxStep)
            return CGPoint(x: pt.x + dx / dist * step,
                           y: pt.y + dy / dist * step)
        }
        return nil
    }

    // MARK: - Hit builder

    private func makeHit(
        _ frame: BallTrackingTestFrame,
        _ c: BallTrackingCandidateDebug,
        pd: (bytes: [UInt8], width: Int, height: Int),
        debug: BallTrackingFrameDebug,
        previousValidDiameter: CGFloat? = nil,
        preImpactMedianDiameter: CGFloat? = nil
    ) -> BallTrackingTestObservation {

        let candidateD = c.diameter
        let center     = CGPoint(x: c.centerX, y: c.centerY)
        let dr = cfg.diameterRefinement

        let maskOut: MaskRefineOutput = dr.enabled
            ? maskRefineDiameter(pd, center: center, candidateDiameter: candidateD, config: dr)
            : MaskRefineOutput(diameter: nil, boundsRect: nil, whitePixelCount: 0,
                               reason: "refinement_disabled", previewImage: nil,
                               cropNormRect: nil, candidateDiamInCrop: nil, refinedDiamInCrop: nil,
                               percentileThreshold: nil, localMedianBrightness: nil,
                               effectiveBrightnessThreshold: dr.maskBrightness,
                               maskThresholdMode: "disabled")

        // Part B: clamp base diameter before smoothing — growth gate
        var baseD = maskOut.diameter ?? candidateD
        var clampReason: String? = nil
        if dr.hardClampDiameter {
            if let prev = previousValidDiameter {
                let maxFromPrev = prev * dr.maxDiameterGrowthRatioPerFrame
                if baseD > maxFromPrev {
                    baseD = maxFromPrev
                    clampReason = "diameter_clamped_growth"
                }
            }
            if let median = preImpactMedianDiameter {
                let maxFromMedian = median * dr.maxDiameterRatioToPreImpactMedian
                if baseD > maxFromMedian {
                    baseD = maxFromMedian
                    clampReason = clampReason.map { $0 + "+median" } ?? "diameter_clamped_median"
                }
            }
        }
        // Part C-new: shrink clamp — diameter cannot drop more than minDiameterShrinkRatioPerFrame per frame
        if dr.hardClampDiameterShrink, let prev = previousValidDiameter {
            let minFromPrev = prev * dr.minDiameterShrinkRatioPerFrame
            if baseD < minFromPrev {
                baseD = minFromPrev
                clampReason = clampReason.map { $0 + "+shrink" } ?? "diameter_clamped_shrink"
            }
        }

        recentDiameters.append(baseD)
        let windowSize = max(2, dr.smoothingWindowSize)
        if recentDiameters.count > windowSize { recentDiameters.removeFirst() }

        let smoothedD: CGFloat?
        if dr.smoothingEnabled && recentDiameters.count >= 2 {
            var sorted = recentDiameters; sorted.sort()
            smoothedD = sorted[sorted.count / 2]
        } else {
            smoothedD = nil
        }

        let finalD = smoothedD ?? baseD

        let diameterReason: String
        if let cr = clampReason      { diameterReason = cr }
        else if smoothedD != nil     { diameterReason = "smoothed" }
        else if maskOut.diameter != nil { diameterReason = maskOut.reason }
        else { diameterReason = dr.enabled ? "mask_failed_fallback_candidate" : "candidate_no_refinement" }

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
            frameDebug:               debug,
            maskPercentileThreshold:   maskOut.percentileThreshold,
            maskLocalMedianBrightness: maskOut.localMedianBrightness,
            maskEffectiveThreshold:    maskOut.effectiveBrightnessThreshold,
            maskThresholdMode:         maskOut.maskThresholdMode)
    }

    // MARK: - Mask refinement (Part A: percentile threshold)

    private func maskRefineDiameter(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        center: CGPoint,
        candidateDiameter: CGFloat,
        config: DiameterRefinementConfig
    ) -> MaskRefineOutput {
        let (bytes, width, height) = pd
        let cx = Int((center.x * CGFloat(width)).rounded())
        let cy = Int((center.y * CGFloat(height)).rounded())

        func failOutput(_ reason: String, threshold: Int, mode: String) -> MaskRefineOutput {
            MaskRefineOutput(diameter: nil, boundsRect: nil, whitePixelCount: 0,
                             reason: reason, previewImage: nil,
                             cropNormRect: nil, candidateDiamInCrop: nil, refinedDiamInCrop: nil,
                             percentileThreshold: nil, localMedianBrightness: nil,
                             effectiveBrightnessThreshold: threshold, maskThresholdMode: mode)
        }

        guard cx >= 0, cx < width, cy >= 0, cy < height else {
            return failOutput("mask_failed_center_oob", threshold: config.maskBrightness, mode: "absolute")
        }

        let radiusPx  = max(4, Int((config.localMaskWindowScale * candidateDiameter * CGFloat(width) / 2).rounded()))
        let cropSize  = radiusPx * 2 + 1
        let cropOriginX = cx - radiusPx; let cropOriginY = cy - radiusPx
        let x0 = max(0, cx - radiusPx); let x1 = min(width  - 1, cx + radiusPx)
        let y0 = max(0, cy - radiusPx); let y1 = min(height - 1, cy + radiusPx)

        // Part A: collect all brightness values in the crop for adaptive thresholding
        var allBrightness: [Int] = []
        for py in y0...y1 {
            for px in x0...x1 {
                let si = py * width * 4 + px * 4
                let r = Int(bytes[si]), g = Int(bytes[si+1]), b = Int(bytes[si+2])
                allBrightness.append((r + g + b) / 3)
            }
        }
        allBrightness.sort()
        let localMedian = allBrightness.isEmpty ? config.maskBrightness : allBrightness[allBrightness.count / 2]

        let effectiveThreshold: Int
        let maskThresholdMode: String
        var percentileThresholdValue: Int? = nil

        if config.usePercentileMaskThreshold && !allBrightness.isEmpty {
            let pIdx = max(0, min(allBrightness.count - 1,
                Int(Double(allBrightness.count - 1) * config.maskWhitenessPercentile / 100.0)))
            let pVal = allBrightness[pIdx]
            percentileThresholdValue = pVal
            let deltaThresh = localMedian + config.maskBackgroundSuppressionDelta
            let rawThresh = max(config.maskBrightness, max(pVal, deltaThresh))
            effectiveThreshold = max(config.maskPercentileMinBrightness,
                                     min(config.maskPercentileMaxBrightness, rawThresh))
            maskThresholdMode = "percentile_\(Int(config.maskWhitenessPercentile.rounded()))"
        } else {
            effectiveThreshold = config.maskBrightness
            maskThresholdMode = "absolute"
        }

        var thresholdMask = [Bool](repeating: false, count: cropSize * cropSize)
        var previewBytes  = [UInt8](repeating: 0,   count: cropSize * cropSize * 4)

        for py in y0...y1 {
            for px in x0...x1 {
                let crow = py - cropOriginY; let ccol = px - cropOriginX
                guard crow >= 0, crow < cropSize, ccol >= 0, ccol < cropSize else { continue }
                let si = py * width * 4 + px * 4
                let r = Int(bytes[si]), g = Int(bytes[si+1]), b = Int(bytes[si+2])
                thresholdMask[crow * cropSize + ccol] = (r + g + b) / 3 >= effectiveThreshold
            }
        }
        for i in 0..<(cropSize * cropSize) { previewBytes[i * 4 + 3] = 255 }

        let componentSelection = mainMaskComponent(
            in: thresholdMask, cropSize: cropSize,
            targetCol: cx - cropOriginX, targetRow: cy - cropOriginY,
            maxCenterDriftPx: max(2, candidateDiameter * CGFloat(width) * 0.55))
        let selectedComponent = componentSelection.component

        if let sel = selectedComponent {
            for index in sel.indices {
                let di = index * 4
                previewBytes[di] = 255; previewBytes[di+1] = 255
                previewBytes[di+2] = 255; previewBytes[di+3] = 255
            }
        }

        let cropNormRect = CGRect(x: CGFloat(cropOriginX)/CGFloat(width),
                                  y: CGFloat(cropOriginY)/CGFloat(height),
                                  width: CGFloat(cropSize)/CGFloat(width),
                                  height: CGFloat(cropSize)/CGFloat(height))
        let candidateDiamInCrop = candidateDiameter * CGFloat(width) / CGFloat(cropSize)

        var previewImage: UIImage? = nil
        previewBytes.withUnsafeMutableBytes { ptr in
            if let ctx = CGContext(data: ptr.baseAddress, width: cropSize, height: cropSize,
                                   bitsPerComponent: 8, bytesPerRow: cropSize * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
               let cgImg = ctx.makeImage() {
                previewImage = UIImage(cgImage: cgImg)
            }
        }

        guard let component = selectedComponent else {
            return MaskRefineOutput(diameter: nil, boundsRect: nil, whitePixelCount: 0,
                                    reason: componentSelection.failureReason,
                                    previewImage: previewImage, cropNormRect: cropNormRect,
                                    candidateDiamInCrop: candidateDiamInCrop, refinedDiamInCrop: nil,
                                    percentileThreshold: percentileThresholdValue,
                                    localMedianBrightness: localMedian,
                                    effectiveBrightnessThreshold: effectiveThreshold,
                                    maskThresholdMode: maskThresholdMode)
        }

        let minX = cropOriginX + component.minCol; let maxX = cropOriginX + component.maxCol
        let minY = cropOriginY + component.minRow; let maxY = cropOriginY + component.maxRow
        let bboxW = CGFloat(maxX - minX + 1)/CGFloat(width)
        let bboxH = CGFloat(maxY - minY + 1)/CGFloat(height)
        let boundsRect = CGRect(x: CGFloat(minX)/CGFloat(width), y: CGFloat(minY)/CGFloat(height),
                                width: bboxW, height: bboxH)
        let diameterPx = max(maxX - minX + 1, maxY - minY + 1)
        let rawDiameter = CGFloat(diameterPx)/CGFloat(width)
        let refinedDiamInCrop = CGFloat(diameterPx)/CGFloat(cropSize)

        return MaskRefineOutput(diameter: rawDiameter, boundsRect: boundsRect,
                                whitePixelCount: component.count,
                                reason: "mask_refined_\(maskThresholdMode)_thresh\(effectiveThreshold)_connected",
                                previewImage: previewImage, cropNormRect: cropNormRect,
                                candidateDiamInCrop: candidateDiamInCrop,
                                refinedDiamInCrop: refinedDiamInCrop,
                                percentileThreshold: percentileThresholdValue,
                                localMedianBrightness: localMedian,
                                effectiveBrightnessThreshold: effectiveThreshold,
                                maskThresholdMode: maskThresholdMode)
    }

    private func mainMaskComponent(
        in mask: [Bool], cropSize: Int, targetCol: Int, targetRow: Int,
        maxCenterDriftPx: CGFloat
    ) -> (component: MaskComponent?, failureReason: String) {
        guard cropSize > 0, mask.count == cropSize * cropSize else {
            return (nil, "mask_failed_invalid_crop")
        }
        var visited = [Bool](repeating: false, count: mask.count)
        var components: [MaskComponent] = []

        for startIndex in mask.indices {
            guard mask[startIndex], !visited[startIndex] else { continue }
            var queue = [startIndex]; var head = 0
            var indices: [Int] = []
            var minCol = Int.max; var maxCol = 0; var minRow = Int.max; var maxRow = 0
            visited[startIndex] = true
            while head < queue.count {
                let index = queue[head]; head += 1; indices.append(index)
                let col = index % cropSize; let row = index / cropSize
                if col < minCol { minCol = col }; if col > maxCol { maxCol = col }
                if row < minRow { minRow = row }; if row > maxRow { maxRow = row }
                for (dc, dr) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nc = col+dc; let nr = row+dr
                    guard nc >= 0, nc < cropSize, nr >= 0, nr < cropSize else { continue }
                    let ni = nr * cropSize + nc
                    if mask[ni] && !visited[ni] { visited[ni] = true; queue.append(ni) }
                }
            }
            let cx2 = CGFloat(minCol+maxCol)/2; let cy2 = CGFloat(minRow+maxRow)/2
            let dx = cx2 - CGFloat(targetCol); let dy = cy2 - CGFloat(targetRow)
            components.append(MaskComponent(indices: indices, minCol: minCol, maxCol: maxCol,
                                            minRow: minRow, maxRow: maxRow,
                                            distanceSquared: dx*dx+dy*dy))
        }

        guard !components.isEmpty else { return (nil, "mask_failed_no_white_pixels") }
        let substantial = components.filter { $0.count >= 3 }
        let usable = substantial.isEmpty ? components : substantial
        guard let selected = usable.min(by: {
            $0.distanceSquared == $1.distanceSquared ? $0.count > $1.count : $0.distanceSquared < $1.distanceSquared
        }) else { return (nil, "mask_failed_no_white_pixels") }
        guard sqrt(selected.distanceSquared) <= maxCenterDriftPx else {
            return (nil, "mask_failed_component_drift_fallback_candidate")
        }
        return (selected, "")
    }

    // MARK: - Candidate finding with scoring (Parts A–F)

    private func findCandidates(
        _ pd: (bytes: [UInt8], width: Int, height: Int),
        roi: CGRect,
        config: ScanConfig,
        context: SelectionContext
    ) -> ([BallTrackingCandidateDebug], BallTrackingCandidateDebug?, Double?) {

        let (bytes, width, height) = pd
        let step = max(1, cfg.sampleStride)

        let xStart = max(0,      Int(roi.minX * CGFloat(width)))
        let xEnd   = min(width,  Int(roi.maxX * CGFloat(width)))
        let yStart = max(0,      Int(roi.minY * CGFloat(height)))
        let yEnd   = min(height, Int(roi.maxY * CGFloat(height)))
        guard xEnd > xStart, yEnd > yStart else { return ([], nil, nil) }

        let cols = (xEnd - xStart + step - 1) / step
        let rows = (yEnd - yStart + step - 1) / step
        var bright  = [Bool](repeating: false, count: cols * rows)
        var visited = [Bool](repeating: false, count: cols * rows)

        for row in 0..<rows {
            let py      = yStart + row * step; let baseRow = py * width * 4
            for col in 0..<cols {
                let px = xStart + col * step; let i = baseRow + px * 4
                let r = Int(bytes[i]), g = Int(bytes[i+1]), b = Int(bytes[i+2])
                let br = (r+g+b)/3; let sp = max(r, max(g, b)) - min(r, min(g, b))
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
                    let col = idx % cols; let row = idx / cols
                    let px = xStart + col * step; let py = yStart + row * step
                    blob.count += 1; blob.sumX += px; blob.sumY += py
                    if px < blob.minX { blob.minX = px }; if px > blob.maxX { blob.maxX = px }
                    if py < blob.minY { blob.minY = py }; if py > blob.maxY { blob.maxY = py }
                    for (dc, dr) in [(-1,0),(1,0),(0,-1),(0,1)] {
                        let nc = col+dc; let nr = row+dr
                        guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
                        let ni = nr * cols + nc
                        if bright[ni] && !visited[ni] { visited[ni] = true; queue.append(ni) }
                    }
                }
                blob.normWidth  = CGFloat(blob.maxX - blob.minX + step) / CGFloat(width)
                blob.normHeight = CGFloat(blob.maxY - blob.minY + step) / CGFloat(height)
                blobs.append(blob)
            }
        }

        // Evaluate blobs → candidates with scoring
        let sc = cfg.candidateScoring
        var rawCandidates = blobs.map { evaluateBlob($0, step: step, width: width, height: height, config: config) }

        // Score each accepted candidate
        rawCandidates = rawCandidates.map { cand in
            guard cand.accepted else { return cand }
            return scoreCandidate(cand, context: context, scoring: sc)
        }

        // Select highest-scoring accepted candidate that is not hard-rejected by new constraints
        let eligible = rawCandidates.filter { $0.accepted }
        let chosen = eligible.max(by: { $0.totalScore < $1.totalScore })

        // Mark selected
        let finalCandidates = rawCandidates.map { cand -> BallTrackingCandidateDebug in
            let sel = chosen != nil && cand.centerX == chosen!.centerX && cand.centerY == chosen!.centerY
            guard sel else { return cand }
            return BallTrackingCandidateDebug(
                rect: cand.rect, centerX: cand.centerX, centerY: cand.centerY,
                diameter: cand.diameter, confidence: cand.confidence,
                accepted: cand.accepted, rejectionReason: cand.rejectionReason,
                brightPixelCount: cand.brightPixelCount,
                totalScore: cand.totalScore, brightnessScore: cand.brightnessScore,
                sizeScore: cand.sizeScore, distanceScore: cand.distanceScore,
                motionScore: cand.motionScore, directionScore: cand.directionScore,
                shapeScore: cand.shapeScore, penaltyScore: cand.penaltyScore,
                isSelected: true,
                progress: cand.progress, backwardRejected: cand.backwardRejected)
        }

        // Jump distance for debug
        let jumpDist: Double? = chosen.map { c in
            let ref = context.predictedPosition ?? context.preferredCenter
            return Double(hypot(c.centerX - ref.x, c.centerY - ref.y))
        }

        // Console debug
        if let c = chosen {
            let top3 = eligible.sorted { $0.totalScore > $1.totalScore }.prefix(3)
            var line = String(format: "frame=? cands=%d sel=(%.3f,%.3f) total=%.2f size=%.2f dist=%.2f motion=%.2f dir=%.2f penalty=%.2f",
                eligible.count, c.centerX, c.centerY,
                c.totalScore, c.sizeScore, c.distanceScore,
                c.motionScore, c.directionScore, c.penaltyScore)
            for (j, t) in top3.enumerated() {
                line += String(format: " | #%d(%.2f)", j+1, t.totalScore)
            }
            print(line)
        } else if !rawCandidates.isEmpty {
            print("frame=? cands=\(rawCandidates.count) acc=\(eligible.count) no_selection reason=\(firstRejectionReason(rawCandidates))")
        }

        return (finalCandidates, chosen, jumpDist)
    }

    // MARK: - Candidate scoring engine (Parts A–F)

    private func scoreCandidate(
        _ cand: BallTrackingCandidateDebug,
        context: SelectionContext,
        scoring sc: CandidateScoringConfig
    ) -> BallTrackingCandidateDebug {

        var penalty = 0.0
        var rejectionReason: String? = cand.rejectionReason
        var accepted = cand.accepted

        // Part F — club-like shape hard reject
        let nW = cand.rect.width; let nH = cand.rect.height
        let asp = max(nW, nH) / max(min(nW, nH), 1e-6)
        if sc.rejectClubLikeCandidates && asp > sc.clubLikeMaxAspect {
            accepted = false
            rejectionReason = "club_like_aspect(\(String(format:"%.1f",asp)))"
        }

        // Part D — hard reject by extreme diameter ratio
        var sizeScore = 0.5  // neutral when no expected diameter
        if let expD = context.expectedDiameter, expD > 1e-6 {
            let ratio = cand.diameter / expD
            if sc.hardRejectExtremeDiameter && (ratio > sc.extremeMaxDiameterRatio || ratio < sc.minDiameterRatioToExpected) {
                accepted = false
                rejectionReason = "extreme_diameter_ratio(\(String(format:"%.2f",ratio)))"
            }
            if sc.useExpectedDiameterConstraint {
                sizeScore = max(0, 1.0 - abs(Double(ratio) - 1.0))
            }
        }

        guard accepted else {
            return BallTrackingCandidateDebug(
                rect: cand.rect, centerX: cand.centerX, centerY: cand.centerY,
                diameter: cand.diameter, confidence: cand.confidence,
                accepted: false, rejectionReason: rejectionReason,
                brightPixelCount: cand.brightPixelCount,
                totalScore: -999, isSelected: false)
        }

        // Part E — exclusion zones
        let inZone = sc.exclusionZones.contains { $0.contains(CGPoint(x: cand.centerX, y: cand.centerY)) }
        if inZone {
            if sc.hardRejectInsideExclusion {
                return BallTrackingCandidateDebug(
                    rect: cand.rect, centerX: cand.centerX, centerY: cand.centerY,
                    diameter: cand.diameter, confidence: cand.confidence,
                    accepted: false, rejectionReason: "exclusion_zone",
                    brightPixelCount: cand.brightPixelCount,
                    totalScore: -999, isSelected: false)
            }
            penalty += sc.exclusionPenaltyWeight
        }

        // Distance / motion scores (Part B)
        let preferred = context.predictedPosition ?? context.preferredCenter
        let dist = Double(hypot(cand.centerX - preferred.x, cand.centerY - preferred.y))
        let maxJump = Double(sc.maxJumpDistanceNorm)
        let distanceScore = max(0.0, 1.0 - dist / maxJump)

        // Jump penalty
        if dist > maxJump {
            let excess = dist - maxJump
            penalty += sc.jumpPenaltyWeight * (excess / maxJump)
        }

        // If diameter-based jump threshold is tighter, use it
        if let expD = context.expectedDiameter {
            let diamJump = Double(expD * sc.maxJumpDistByDiameter)
            if dist > diamJump { penalty += sc.jumpPenaltyWeight * 0.5 }
        }

        // Motion score from predicted vs fallback preferred
        let motionScore: Double
        if let pred = context.predictedPosition {
            let mDist = Double(hypot(cand.centerX - pred.x, cand.centerY - pred.y))
            motionScore = max(0.0, 1.0 - mDist / maxJump)
        } else {
            motionScore = distanceScore
        }

        // Direction score (Part C)
        var directionScore = 0.5  // neutral until we have a direction
        if sc.useDirectionConstraint, context.isPostImpact,
           let dir = context.expectedDirection,
           let init0 = context.initialBallCenter {
            let dx = Double(cand.centerX - init0.x)
            let dy = Double(cand.centerY - init0.y)
            let len = sqrt(dx*dx + dy*dy)
            if len > 1e-6 {
                let dot = (dx/len) * Double(dir.x) + (dy/len) * Double(dir.y)
                directionScore = max(0.0, dot)
                if dot < Double(sc.minForwardProgressNorm) {
                    penalty += sc.directionPenaltyWeight
                }
            }
        }

        // Part A-new: pre-launch reference direction rejection (before launch is locked)
        if sc.hardRejectBehindStart && sc.useReferenceProgressBeforeLaunch &&
           !context.ballHasLaunched && context.isPostImpact,
           let init0 = context.initialBallCenter {
            let theta = CGFloat(context.zeroDegreeAngleDegrees * .pi / 180.0)
            let refDx = cos(theta); let refDy = -sin(theta)
            let dxNorm = cand.centerX - init0.x
            let dyNorm = cand.centerY - init0.y
            let progressRef = dxNorm * refDx + dyNorm * refDy
            if progressRef < sc.minAllowedProgressBeforeLaunch {
                return BallTrackingCandidateDebug(
                    rect: cand.rect, centerX: cand.centerX, centerY: cand.centerY,
                    diameter: cand.diameter, confidence: cand.confidence,
                    accepted: false,
                    rejectionReason: "rejected_behind_start(\(String(format:"%.4f",progressRef)))",
                    brightPixelCount: cand.brightPixelCount,
                    totalScore: -999, isSelected: false,
                    progress: progressRef, backwardRejected: true)
            }
        }

        // Backward rejection (Parts A–B) — only after launch direction is locked
        var progress: CGFloat? = nil
        var backwardRejected = false
        if sc.useMonotonicProgressConstraint, context.ballHasLaunched,
           let launchDir = context.launchDirectionVector,
           let init0 = context.initialBallCenter {
            let dx = cand.centerX - init0.x
            let dy = cand.centerY - init0.y
            let p = dx * launchDir.x + dy * launchDir.y
            progress = p

            let behindInitial = p < -sc.allowedBackwardProgressNorm
            let backwardFromPrev = context.previousProgress.map { p < $0 - sc.allowedBackwardProgressNorm } ?? false

            if behindInitial || backwardFromPrev {
                backwardRejected = true
                let reason = behindInitial
                    ? "rejected_behind_initial_ball(\(String(format:"%.4f",p)))"
                    : "rejected_backward_after_launch(\(String(format:"%.4f",p)))"
                if sc.hardRejectBackwardAfterLaunch {
                    return BallTrackingCandidateDebug(
                        rect: cand.rect, centerX: cand.centerX, centerY: cand.centerY,
                        diameter: cand.diameter, confidence: cand.confidence,
                        accepted: false, rejectionReason: reason,
                        brightPixelCount: cand.brightPixelCount,
                        totalScore: -999, isSelected: false,
                        progress: progress, backwardRejected: true)
                } else {
                    penalty += sc.backwardPenaltyWeight
                }
            }
        }

        // Brightness score
        let brightnessScore = cand.confidence

        // Shape score (circularity)
        let shapeScore = Double(min(nW, nH) / max(max(nW, nH), 1e-6))

        // Part E-new: HLA closeness scoring — prefer candidates closer to 0° after launch
        var hlaClosenessScore = 0.0
        if context.isPostImpact && context.ballHasLaunched,
           let init0 = context.initialBallCenter,
           context.imageWidth > 1, context.imageHeight > 1 {
            let theta = CGFloat(context.zeroDegreeAngleDegrees * .pi / 180.0)
            let refX = cos(theta); let refY = -sin(theta)
            let perpX = sin(theta); let perpY = cos(theta)
            let dxPx = (cand.centerX - init0.x) * CGFloat(context.imageWidth)
            let dyPx = (cand.centerY - init0.y) * CGFloat(context.imageHeight)
            let movLen = sqrt(dxPx * dxPx + dyPx * dyPx)
            if movLen > 1e-6 {
                let fwd = dxPx * refX + dyPx * refY
                let lat = dxPx * perpX + dyPx * perpY
                let candHLADeg = Double(atan2(lat, fwd)) * 180.0 / .pi
                let maxHLARef = max(sc.maxCandidateHLADegrees, 1e-6)
                hlaClosenessScore = max(0.0, 1.0 - abs(candHLADeg) / maxHLARef)
            }
        }

        // New session Part E: off-path hard rejection after launch
        if sc.hardRejectFarOffPath && context.ballHasLaunched && context.isPostImpact,
           let ld = context.launchDirectionVector,
           let init0 = context.initialBallCenter {
            let ddx = cand.centerX - init0.x
            let ddy = cand.centerY - init0.y
            let perp = abs(ddx * ld.y - ddy * ld.x)
            if perp > sc.maxOffPathDistNorm {
                return BallTrackingCandidateDebug(
                    rect: cand.rect, centerX: cand.centerX, centerY: cand.centerY,
                    diameter: cand.diameter, confidence: cand.confidence,
                    accepted: false,
                    rejectionReason: "rejected_far_right_off_path(\(String(format:"%.4f",perp)))",
                    brightPixelCount: cand.brightPixelCount,
                    totalScore: -999, isSelected: false,
                    progress: progress, backwardRejected: backwardRejected)
            }
        }

        // New session Part C: prediction cross boost — nearby prediction earns bonus
        var predBoostScore = 0.0
        if sc.enablePredictionBoost && context.isPostImpact,
           let pred = context.predictedPosition {
            let bx = Double(cand.rect.minX); let by = Double(cand.rect.minY)
            let bw = Double(cand.rect.width); let bh = Double(cand.rect.height)
            let px = Double(pred.x); let py = Double(pred.y)
            let insideRect = px >= bx && px <= bx + bw && py >= by && py <= by + bh
            if insideRect {
                predBoostScore = sc.predictionInsideBonus
            } else {
                let boostR = Double(sc.predictionBoostRadiusNorm)
                let pd2 = hypot(Double(cand.centerX) - px, Double(cand.centerY) - py)
                if pd2 <= boostR {
                    predBoostScore = sc.predictionNearBonus * (1.0 - pd2 / max(boostR, 1e-9))
                } else if pd2 > boostR * 2 {
                    penalty += sc.predictionDistPenaltyWeight * min(1.0, (pd2 - boostR * 2) / max(boostR, 1e-9))
                }
            }
        }

        // Part C: offscreen/edge ball rejection
        if sc.rejectEdgePartialBall && context.isPostImpact {
            let margin = sc.minBallMarginNorm
            let radius = cand.diameter / 2.0
            let edgeFail = (cand.centerX - radius < margin ||
                            cand.centerX + radius > 1.0 - margin ||
                            cand.centerY - radius < margin ||
                            cand.centerY + radius > 1.0 - margin)
            if edgeFail {
                return BallTrackingCandidateDebug(
                    rect: cand.rect, centerX: cand.centerX, centerY: cand.centerY,
                    diameter: cand.diameter, confidence: cand.confidence,
                    accepted: false, rejectionReason: "rejected_partial_offscreen_ball",
                    brightPixelCount: cand.brightPixelCount,
                    totalScore: -999, isSelected: false,
                    progress: progress, backwardRejected: backwardRejected)
            }
        }

        // Total score
        let total = sc.brightnessScoreWeight  * brightnessScore
                  + sc.sizeScoreWeight        * sizeScore
                  + sc.distanceScoreWeight    * distanceScore
                  + sc.motionScoreWeight      * motionScore
                  + sc.directionScoreWeight   * directionScore
                  + sc.shapeScoreWeight       * shapeScore
                  + sc.hlaClosenessWeight     * hlaClosenessScore
                  + predBoostScore
                  - penalty

        return BallTrackingCandidateDebug(
            rect: cand.rect, centerX: cand.centerX, centerY: cand.centerY,
            diameter: cand.diameter, confidence: cand.confidence,
            accepted: true, rejectionReason: nil,
            brightPixelCount: cand.brightPixelCount,
            totalScore: total, brightnessScore: brightnessScore,
            sizeScore: sizeScore, distanceScore: distanceScore,
            motionScore: motionScore, directionScore: directionScore,
            shapeScore: shapeScore, penaltyScore: penalty,
            isSelected: false,
            progress: progress, backwardRejected: backwardRejected)
    }

    // MARK: - Blob evaluator (hard shape/size filters only)

    private func evaluateBlob(_ blob: RawBlob, step: Int, width: Int, height: Int,
                               config: ScanConfig) -> BallTrackingCandidateDebug {
        let cx  = CGFloat(blob.sumX) / CGFloat(blob.count) / CGFloat(width)
        let cy  = CGFloat(blob.sumY) / CGFloat(blob.count) / CGFloat(height)
        let bw  = CGFloat(blob.maxX - blob.minX + step)
        let bh  = CGFloat(blob.maxY - blob.minY + step)
        let nW  = bw / CGFloat(width); let nH = bh / CGFloat(height)
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
        let preObs  = obs.filter { $0.frameIndex < impact }
        let postObs = obs.filter { $0.frameIndex > impact }
        let preHit  = preObs.filter  { $0.centerX != nil }.count
        let postHit = postObs.filter { $0.centerX != nil }.count
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

        print("Diameter refinement summary")
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
                let dbg = o.frameDebug
                let selScore = dbg?.selectedCandidate.map { String(format:" score=%.2f", $0.totalScore) } ?? ""
                print(String(format: "frame=%02d x=%.4f y=%.4f d=%.4f(cand=%@ mask=%@) cands=%d acc=%d conf=%.2f%@%@",
                             o.frameIndex, cx, cy, d, cD, mD,
                             dbg?.candidates.count ?? 0,
                             dbg?.candidates.filter { $0.accepted }.count ?? 0,
                             o.confidence, selScore, marker))
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

    private func expanded(_ rect: CGRect, scale: CGFloat) -> CGRect {
        expandedAround(rect.center, rect: rect, scale: scale)
    }

    private func asymmetricPreImpactROI(center: CGPoint, lockedRect: CGRect,
                                         frameIdx: Int, impactIdx: Int) -> CGRect {
        let isNear  = abs(frameIdx - impactIdx) <= cfg.nearImpactWindowFrames
        let fwdMul  = isNear ? cfg.nearImpactForwardExpansionScale   : cfg.preImpactForwardExpansionScale
        let bwdMul  = isNear ? cfg.nearImpactBackwardExpansionScale  : cfg.preImpactBackwardExpansionScale
        let vertMul = isNear ? cfg.nearImpactVerticalExpansionScale  : cfg.preImpactVerticalExpansionScale
        let theta = CGFloat(cfg.zeroDegreeAngleDegrees * .pi / 180.0)
        let fx = cos(theta); let fy = -sin(theta)   // forward unit vector
        let px = -fy;        let py =  fx            // perpendicular (up/left)
        let base = lockedRect.width
        // Separate vertical (perpendicular) expansion from forward/backward expansion
        let cornersX = [
            center.x - bwdMul * base * fx - vertMul * base * px,
            center.x + fwdMul * base * fx - vertMul * base * px,
            center.x + fwdMul * base * fx + vertMul * base * px,
            center.x - bwdMul * base * fx + vertMul * base * px
        ]
        let cornersY = [
            center.y - bwdMul * base * fy - vertMul * base * py,
            center.y + fwdMul * base * fy - vertMul * base * py,
            center.y + fwdMul * base * fy + vertMul * base * py,
            center.y - bwdMul * base * fy + vertMul * base * py
        ]
        let x0 = max(0.0, cornersX.min()!); let x1 = min(1.0, cornersX.max()!)
        let y0 = max(0.0, cornersY.min()!); let y1 = min(1.0, cornersY.max()!)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    private func asymmetricPostImpactROI(center: CGPoint, lockedRect: CGRect,
                                          launchDirection: CGPoint?,
                                          reliableTrack: Bool) -> CGRect {
        let fwdMul  = cfg.postImpactForwardExpansionScale
        let bwdMul  = cfg.postImpactBackwardExpansionScale
        let vertMul = reliableTrack ? cfg.postImpactVerticalExpansionScaleTracked
                                    : cfg.postImpactVerticalExpansionScaleUntracked
        let theta: CGFloat
        if let ld = launchDirection, ld.x * ld.x + ld.y * ld.y > 1e-12 {
            theta = atan2(-ld.y, ld.x)
        } else {
            theta = CGFloat(cfg.zeroDegreeAngleDegrees * .pi / 180.0)
        }
        let fx = cos(theta); let fy = -sin(theta)
        let px = -fy;        let py =  fx
        let base = lockedRect.width
        let cornersX = [
            center.x - bwdMul * base * fx - vertMul * base * px,
            center.x + fwdMul * base * fx - vertMul * base * px,
            center.x + fwdMul * base * fx + vertMul * base * px,
            center.x - bwdMul * base * fx + vertMul * base * px
        ]
        let cornersY = [
            center.y - bwdMul * base * fy - vertMul * base * py,
            center.y + fwdMul * base * fy - vertMul * base * py,
            center.y + fwdMul * base * fy + vertMul * base * py,
            center.y - bwdMul * base * fy + vertMul * base * py
        ]
        let x0 = max(0.0, cornersX.min()!); let x1 = min(1.0, cornersX.max()!)
        let y0 = max(0.0, cornersY.min()!); let y1 = min(1.0, cornersY.max()!)
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    private func expandedAround(_ center: CGPoint, rect: CGRect, scale: CGFloat) -> CGRect {
        let w = rect.width * scale, h = rect.height * scale
        return CGRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func pixelBytes(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return (bytes, w, h)
    }

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
