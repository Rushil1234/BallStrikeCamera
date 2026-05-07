#if DEBUG
import CoreGraphics

// MARK: - Impact Detection Settings

struct ImpactDetectionSettings {
    var movementThresholdNorm: Double = 0.006
    var confirmFrames:         Double = 2
    var stableWindowCount:     Double = 10
    // Part A: diameter change detection
    var useDiameterChange:    Bool   = true
    var diameterChangeRatio:  Double = 1.35
    var diameterShrinkRatio:  Double = 0.80
    var returnOneFrameBefore: Bool   = true
    var minimumStableFrames:  Double = 6

    func toConfig() -> ImpactDetectionConfig {
        ImpactDetectionConfig(
            movementThresholdNorm: CGFloat(movementThresholdNorm),
            confirmFrames:         Int(confirmFrames.rounded()),
            stableWindowCount:     Int(stableWindowCount.rounded()),
            useDiameterChange:    useDiameterChange,
            diameterChangeRatio:  CGFloat(diameterChangeRatio),
            diameterShrinkRatio:  CGFloat(diameterShrinkRatio),
            returnOneFrameBefore: returnOneFrameBefore,
            minimumStableFrames:  Int(minimumStableFrames.rounded())
        )
    }
}

// MARK: - Diameter / Mask Refinement Settings

struct DiameterRefinementSettings {
    var enabled:              Bool   = true
    var localMaskWindowScale: Double = 1.8
    var maskBrightness:       Double = 30
    var maskMaxSpread:        Double = 65
    var minDiameterNorm:      Double = 0.004
    var maxDiameterNorm:      Double = 0.120
    var combineModeIsMax:     Bool   = false
    var smoothingEnabled:     Bool   = true
    var smoothingWindowSize:  Double = 5
    // Part A — percentile-based mask threshold
    var usePercentileMaskThreshold:     Bool   = true
    var maskWhitenessPercentile:        Double = 85.0
    var maskPercentileMinBrightness:    Double = 80
    var maskPercentileMaxBrightness:    Double = 245
    var maskBackgroundSuppressionDelta: Double = 15
    // Part B — diameter growth / pre-impact median gates
    var maxDiameterGrowthRatioPerFrame: Double = 1.35
    var maxDiameterRatioToPreImpactMedian: Double = 4.0
    var hardClampDiameter:              Bool   = true
    // Part C-new — diameter shrink constraint
    var minDiameterShrinkRatioPerFrame: Double = 0.70
    var hardClampDiameterShrink:        Bool   = true
    // Part D: line-like mask rejection
    var rejectLineLikeMask:            Bool   = true
    var maxMaskAspectForBall:          Double = 2.2
    var minMaskAspectForBall:          Double = 0.45
    var lineLikeAspectThreshold:       Double = 3.0
    var lineLikeFillMax:               Double = 0.18
    var minMaskComponentPixelsForBall: Double = 10

    func toConfig() -> ExperimentalBallTracker.DiameterRefinementConfig {
        ExperimentalBallTracker.DiameterRefinementConfig(
            enabled:              enabled,
            localMaskWindowScale: CGFloat(localMaskWindowScale),
            maskBrightness:       Int(maskBrightness.rounded()),
            maskMaxSpread:        Int(maskMaxSpread.rounded()),
            minDiameterNorm:      CGFloat(minDiameterNorm),
            maxDiameterNorm:      CGFloat(maxDiameterNorm),
            combineMode:          combineModeIsMax ? .max : .average,
            smoothingEnabled:     smoothingEnabled,
            smoothingWindowSize:  Int(smoothingWindowSize.rounded()),
            usePercentileMaskThreshold:     usePercentileMaskThreshold,
            maskWhitenessPercentile:        maskWhitenessPercentile,
            maskPercentileMinBrightness:    Int(maskPercentileMinBrightness.rounded()),
            maskPercentileMaxBrightness:    Int(maskPercentileMaxBrightness.rounded()),
            maskBackgroundSuppressionDelta: Int(maskBackgroundSuppressionDelta.rounded()),
            maxDiameterGrowthRatioPerFrame:    CGFloat(maxDiameterGrowthRatioPerFrame),
            maxDiameterRatioToPreImpactMedian: CGFloat(maxDiameterRatioToPreImpactMedian),
            hardClampDiameter:              hardClampDiameter,
            minDiameterShrinkRatioPerFrame: CGFloat(minDiameterShrinkRatioPerFrame),
            hardClampDiameterShrink:        hardClampDiameterShrink,
            rejectLineLikeMask:            rejectLineLikeMask,
            maxMaskAspectForBall:          CGFloat(maxMaskAspectForBall),
            minMaskAspectForBall:          CGFloat(minMaskAspectForBall),
            lineLikeAspectThreshold:       CGFloat(lineLikeAspectThreshold),
            lineLikeFillMax:               CGFloat(lineLikeFillMax),
            minMaskComponentPixelsForBall: Int(minMaskComponentPixelsForBall.rounded())
        )
    }
}

// MARK: - Experimental Calibration Settings

struct CalibrationTuningSettings {
    var horizontalFOVDegrees: Double = 70
    var verticalFOVDegrees:   Double = 45
    var realBallDiameterMeters: Double = 0.04267
    var useCameraHeight: Bool = false
    var cameraHeightMeters: Double = 1.0
    var useCameraTilt: Bool = false
    var cameraTiltDegrees: Double = 0

    mutating func resetDefaults() {
        self = CalibrationTuningSettings()
    }
}

// MARK: - Experimental Club Tracking Settings

struct ClubTrackingTuningSettings {
    var enabled: Bool = true
    var searchBehindBallEnabled: Bool = true
    var ballExclusionRadiusScale: Double = 1.8
    var clubSearchROIScaleX: Double = 8.0
    var clubSearchROIScaleY: Double = 6.0
    var useFrameDifference: Bool = true
    var frameDifferenceThreshold: Double = 34
    var minClubBlobArea: Double = 5
    var maxClubBlobArea: Double = 6000
    var minClubConfidence: Double = 0.20
    var minClubDarknessOrEdgeThreshold: Double = 85
    var debugLoggingEnabled: Bool = true

    var showClubTracker: Bool = true
    var showClubSearchROI: Bool = true
    var showClubPath: Bool = true
    var showBallExclusionZone: Bool = true

    mutating func resetDefaults() {
        self = ClubTrackingTuningSettings()
    }

    func toConfig(trackingMode: FrameNormalizationMode, sampleStride: Double) -> ExperimentalClubTracker.Configuration {
        ExperimentalClubTracker.Configuration(
            enabled: enabled,
            searchBehindBallEnabled: searchBehindBallEnabled,
            ballExclusionRadiusScale: CGFloat(ballExclusionRadiusScale),
            clubSearchROIScaleX: CGFloat(clubSearchROIScaleX),
            clubSearchROIScaleY: CGFloat(clubSearchROIScaleY),
            minClubDarknessOrEdgeThreshold: Int(minClubDarknessOrEdgeThreshold.rounded()),
            useFrameDifference: useFrameDifference,
            frameDifferenceThreshold: Int(frameDifferenceThreshold.rounded()),
            minClubBlobArea: Int(minClubBlobArea.rounded()),
            maxClubBlobArea: Int(maxClubBlobArea.rounded()),
            minClubConfidence: minClubConfidence,
            sampleStride: Int(sampleStride.rounded()),
            debugLoggingEnabled: debugLoggingEnabled,
            normalizationMode: trackingMode
        )
    }
}

// MARK: - Ball Candidate Scoring Settings (Parts A-H)

struct BallCandidateScoringSettings {
    // Score weights
    var brightnessScoreWeight:  Double = 0.5
    var sizeScoreWeight:        Double = 4.0
    var distanceScoreWeight:    Double = 2.5
    var motionScoreWeight:      Double = 1.5
    var directionScoreWeight:   Double = 1.0
    var shapeScoreWeight:       Double = 0.5

    // Motion prediction (Part B)
    var useMotionPrediction:                Bool   = true
    var predictionLookbackFrames:           Double = 3
    var maxJumpDistanceNorm:                Double = 0.10
    var maxJumpDistanceMultiplierByDiameter: Double = 4.0
    var jumpPenaltyWeight:                  Double = 3.0
    var allowReacquireAfterMisses:          Bool   = true
    var reacquireMissFrameLimit:            Double = 3

    // Direction constraint (Part C)
    var useDirectionConstraint:             Bool   = true
    var directionPenaltyWeight:             Double = 1.5
    var minForwardProgressNorm:             Double = -0.005
    var expectedDirectionSmoothingAlpha:    Double = 0.35

    // Diameter constraint (Part D)
    var useExpectedDiameterConstraint:      Bool   = true
    var minDiameterRatioToExpected:         Double = 0.35
    var maxDiameterRatioToExpected:         Double = 2.25
    var diameterScoreWeight:                Double = 2.0
    var hardRejectExtremeDiameter:          Bool   = true
    var extremeMaxDiameterRatio:            Double = 4.0

    // Club-like rejection (Part F)
    var rejectClubLikeCandidates:           Bool   = true
    var clubLikeMaxAspect:                  Double = 4.0

    // Launch direction / backward rejection / termination (Parts A–C)
    var useMonotonicProgressConstraint:       Bool   = true
    var minLaunchProgressToLockDirection:     Double = 0.02
    var allowedBackwardProgressNorm:          Double = 0.005
    var backwardPenaltyWeight:                Double = 3.0
    var hardRejectBackwardAfterLaunch:        Bool   = true
    var enableLostBallTermination:            Bool   = true
    var lostBallMissFrameLimit:               Double = 3
    var lostBallMinProgressBeforeTermination: Double = 0.05
    var allowReacquireAfterTermination:       Bool   = false

    // Part A-new — pre-launch reference direction rejection
    var hardRejectBehindStart:            Bool   = true
    var useReferenceProgressBeforeLaunch: Bool   = true
    var minAllowedProgressBeforeLaunch:   Double = -0.003

    // Part H — HLA closeness scoring (raised to 3.0)
    var hlaClosenessWeight:     Double = 3.0
    var maxCandidateHLADegrees: Double = 35.0

    // New session Part C: prediction cross boost
    var enablePredictionBoost:       Bool   = true
    var predictionInsideBonus:       Double = 4.0
    var predictionNearBonus:         Double = 2.0
    var predictionBoostRadiusNorm:   Double = 0.045
    var predictionDistPenaltyWeight: Double = 3.0

    // New session Part E: off-path hard rejection
    var hardRejectFarOffPath: Bool   = true
    var maxOffPathDistNorm:   Double = 0.060

    // New session Part F: prediction miss limit
    var disablePredictionAfterMiss: Bool   = true
    var predictionMissLimit:        Double = 3

    // New session Part B: merged club-ball rejection
    var enableMergedClubBallReject:      Bool   = true
    var maxFirstPostImpactDiameterRatio: Double = 1.85
    var mergedCandidateFrameWindow:      Double = 3

    // Part A: Face prior from ball HLA
    var useBallHLAFacePrior:             Bool   = true
    var facePriorBallHLAWeight:          Double = 0.85
    var facePriorClubPathWeight:         Double = 0.15
    var maxFacePriorDeviationDegrees:    Double = 25.0
    var facePriorScoreWeight:            Double = 5.0
    var suppressFaceIfFarFromBallHLA:    Bool   = true
    var maxFaceBallHLADifferenceDegrees: Double = 30.0

    // Part B: Enhanced early merged shape stopper
    var enableEarlyMergedShapeStopper:   Bool   = true
    var mergedShapeFrameWindowAfterImpact: Int   = 3
    var maxEarlyDiameterSpikeRatio:      Double = 1.60
    var maxEarlyAreaSpikeRatio:          Double = 2.50
    var maxEarlyMaskBoundsSpikeRatio:    Double = 2.00
    var requireSpikeThenDropCheck:       Bool   = true
    var spikeDropLookaheadFrames:        Int    = 2
    var spikeDropRatioThreshold:         Double = 0.75
    var allowGradualDiameterGrowth:      Bool   = true
    var maxGradualGrowthRatioPerFrame:   Double = 1.35

    // Part A: Impact frame merged spike (separate from post-impact)
    var maxImpactDiameterSpikeRatio: Double = 1.75

    // Strict impact frame diameter gate
    var enableStrictImpactDiameterGate:    Bool   = true
    var impactFrameMaxDiameterGrowthRatio: Double = 1.25

    // Part C: Cone search
    var useConeSearchRegion:                 Bool   = true
    var coneHalfAngleDegrees:               Double = 18.0
    var coneInitialLengthNorm:              Double = 0.12
    var coneLengthGrowthPerFrameNorm:       Double = 0.035
    var coneMaxLengthNorm:                  Double = 0.75
    var coneBackwardAllowanceNorm:          Double = 0.015
    var coneUseLaunchDirectionWhenAvailable: Bool  = true

    // Part D: Full-frame recovery after cone miss
    var enableFullFrameRecoveryAfterConeMiss: Bool   = true
    var recoveryMinMaskWhitePixels:           Int    = 25
    var recoveryMinMaskFillRatio:             Double = 0.12
    var recoveryMaxLineResidualNorm:          Double = 0.035

    // Part F: Vertical jump rejection
    var hardRejectLargeDownwardJumpAfterLaunch: Bool   = true
    var maxDownwardJumpPerFrameNorm:            Double = 0.040
    var maxVerticalJumpFromPathNorm:            Double = 0.050
    var verticalJumpPenaltyWeight:              Double = 4.0
    var useFittedPathForVerticalGate:           Bool   = true

    // Prediction cross rescue (updated defaults per Part F)
    var enablePredictionCrossRescue:        Bool   = true
    var predictionRescueWindowAfterLaunch:  Double = 16
    var predictionRescueMaxConsecMisses:    Double = 2
    var predictionRescueRadiusNorm:         Double = 0.065
    var predictionRescueInsideBonus:        Double = 12.0
    var predictionRescueNearBonus:          Double = 7.0
    var predictionRescueMaxLineResidual:    Double = 0.025
    var predictionRescueInsideCircleScale:  Double = 1.25
    var predictionRescueAllowBorderlineMask: Bool  = true
    var predictionRescueMinMaskPixels:      Double = 8
    var predictionRescueMinFillRatio:       Double = 0.045
    var predictionRescueMinDiamRatio:       Double = 0.35
    var predictionRescueRequireFwdProgress: Bool   = true
    var predictionRescueDisableAfterTerm:   Bool   = true
    // Part C: offscreen/edge ball rejection
    var rejectEdgePartialBall: Bool   = true
    var minBallMarginNorm:     Double = 0.012
    // Final edge ball filter (post-rescue gate)
    var enableFinalEdgeBallFilter:       Bool   = true
    var finalEdgeMarginNorm:             Double = 0.012
    var finalEdgeRadiusMarginScale:      Double = 1.00
    var excludeEdgeBallFromMetrics:      Bool   = true
    // Part E: single-point prediction
    var enableSinglePointPrediction:   Bool   = true
    var singlePointPredictionMaxStep:  Double = 0.12
    var singlePointPredictionMinStep:  Double = 0.006

    // Exclusion zones (Part E)
    var useExclusionZones:                  Bool   = false
    var exclusionZone1Enabled:              Bool   = false
    var exclusionZone1X:                    Double = 0.0
    var exclusionZone1Y:                    Double = 0.7
    var exclusionZone1W:                    Double = 1.0
    var exclusionZone1H:                    Double = 0.3
    var exclusionZone2Enabled:              Bool   = false
    var exclusionZone2X:                    Double = 0.0
    var exclusionZone2Y:                    Double = 0.0
    var exclusionZone2W:                    Double = 0.15
    var exclusionZone2H:                    Double = 1.0
    var hardRejectInsideExclusion:          Bool   = true
    var exclusionPenaltyWeight:             Double = 5.0

    var exclusionZones: [CGRect] {
        var zones: [CGRect] = []
        if useExclusionZones && exclusionZone1Enabled {
            zones.append(CGRect(x: exclusionZone1X, y: exclusionZone1Y,
                                width: exclusionZone1W, height: exclusionZone1H))
        }
        if useExclusionZones && exclusionZone2Enabled {
            zones.append(CGRect(x: exclusionZone2X, y: exclusionZone2Y,
                                width: exclusionZone2W, height: exclusionZone2H))
        }
        return zones
    }

    func toConfig() -> ExperimentalBallTracker.CandidateScoringConfig {
        ExperimentalBallTracker.CandidateScoringConfig(
            brightnessScoreWeight:            brightnessScoreWeight,
            sizeScoreWeight:                  sizeScoreWeight,
            distanceScoreWeight:              distanceScoreWeight,
            motionScoreWeight:                motionScoreWeight,
            directionScoreWeight:             directionScoreWeight,
            shapeScoreWeight:                 shapeScoreWeight,
            useMotionPrediction:              useMotionPrediction,
            predictionLookbackFrames:         Int(predictionLookbackFrames.rounded()),
            maxJumpDistanceNorm:              CGFloat(maxJumpDistanceNorm),
            maxJumpDistByDiameter:            CGFloat(maxJumpDistanceMultiplierByDiameter),
            jumpPenaltyWeight:                jumpPenaltyWeight,
            allowReacquireAfterMisses:        allowReacquireAfterMisses,
            reacquireMissFrameLimit:          Int(reacquireMissFrameLimit.rounded()),
            useDirectionConstraint:           useDirectionConstraint,
            directionPenaltyWeight:           directionPenaltyWeight,
            minForwardProgressNorm:           CGFloat(minForwardProgressNorm),
            directionSmoothingAlpha:          CGFloat(expectedDirectionSmoothingAlpha),
            useExpectedDiameterConstraint:    useExpectedDiameterConstraint,
            minDiameterRatioToExpected:       CGFloat(minDiameterRatioToExpected),
            maxDiameterRatioToExpected:       CGFloat(maxDiameterRatioToExpected),
            diameterScoreWeight:              diameterScoreWeight,
            hardRejectExtremeDiameter:        hardRejectExtremeDiameter,
            extremeMaxDiameterRatio:          CGFloat(extremeMaxDiameterRatio),
            rejectClubLikeCandidates:         rejectClubLikeCandidates,
            clubLikeMaxAspect:                CGFloat(clubLikeMaxAspect),
            useMonotonicProgressConstraint:       useMonotonicProgressConstraint,
            minLaunchProgressToLockDirection:     CGFloat(minLaunchProgressToLockDirection),
            allowedBackwardProgressNorm:          CGFloat(allowedBackwardProgressNorm),
            backwardPenaltyWeight:                backwardPenaltyWeight,
            hardRejectBackwardAfterLaunch:        hardRejectBackwardAfterLaunch,
            enableLostBallTermination:            enableLostBallTermination,
            lostBallMissFrameLimit:               Int(lostBallMissFrameLimit.rounded()),
            lostBallMinProgressBeforeTermination: CGFloat(lostBallMinProgressBeforeTermination),
            allowReacquireAfterTermination:       allowReacquireAfterTermination,
            exclusionZones:                   exclusionZones,
            hardRejectInsideExclusion:        hardRejectInsideExclusion,
            exclusionPenaltyWeight:           exclusionPenaltyWeight,
            hardRejectBehindStart:            hardRejectBehindStart,
            useReferenceProgressBeforeLaunch: useReferenceProgressBeforeLaunch,
            minAllowedProgressBeforeLaunch:   CGFloat(minAllowedProgressBeforeLaunch),
            hlaClosenessWeight:               hlaClosenessWeight,
            maxCandidateHLADegrees:           maxCandidateHLADegrees,
            enablePredictionBoost:            enablePredictionBoost,
            predictionInsideBonus:            predictionInsideBonus,
            predictionNearBonus:              predictionNearBonus,
            predictionBoostRadiusNorm:        CGFloat(predictionBoostRadiusNorm),
            predictionDistPenaltyWeight:      predictionDistPenaltyWeight,
            hardRejectFarOffPath:             hardRejectFarOffPath,
            maxOffPathDistNorm:               CGFloat(maxOffPathDistNorm),
            disablePredictionAfterMiss:       disablePredictionAfterMiss,
            predictionMissLimit:              Int(predictionMissLimit.rounded()),
            enableMergedClubBallReject:       enableMergedClubBallReject,
            maxFirstPostImpactDiameterRatio:  CGFloat(maxFirstPostImpactDiameterRatio),
            mergedCandidateFrameWindow:       Int(mergedCandidateFrameWindow.rounded()),
            maxImpactDiameterSpikeRatio:      CGFloat(maxImpactDiameterSpikeRatio),
            enableStrictImpactDiameterGate:    enableStrictImpactDiameterGate,
            impactFrameMaxDiameterGrowthRatio: CGFloat(impactFrameMaxDiameterGrowthRatio),
            useConeSearchRegion:              useConeSearchRegion,
            coneHalfAngleDegrees:            coneHalfAngleDegrees,
            coneInitialLengthNorm:            CGFloat(coneInitialLengthNorm),
            coneLengthGrowthPerFrameNorm:     CGFloat(coneLengthGrowthPerFrameNorm),
            coneMaxLengthNorm:               CGFloat(coneMaxLengthNorm),
            coneBackwardAllowanceNorm:        CGFloat(coneBackwardAllowanceNorm),
            coneUseLaunchDirectionWhenAvailable: coneUseLaunchDirectionWhenAvailable,
            enableFullFrameRecoveryAfterConeMiss: enableFullFrameRecoveryAfterConeMiss,
            recoveryMinMaskWhitePixels:       recoveryMinMaskWhitePixels,
            recoveryMinMaskFillRatio:         CGFloat(recoveryMinMaskFillRatio),
            recoveryMaxLineResidualNorm:      CGFloat(recoveryMaxLineResidualNorm),
            hardRejectLargeDownwardJumpAfterLaunch: hardRejectLargeDownwardJumpAfterLaunch,
            maxDownwardJumpPerFrameNorm:      CGFloat(maxDownwardJumpPerFrameNorm),
            maxVerticalJumpFromPathNorm:      CGFloat(maxVerticalJumpFromPathNorm),
            verticalJumpPenaltyWeight:        verticalJumpPenaltyWeight,
            useFittedPathForVerticalGate:     useFittedPathForVerticalGate,
            enablePredictionCrossRescue:      enablePredictionCrossRescue,
            predictionRescueWindowAfterLaunch: Int(predictionRescueWindowAfterLaunch.rounded()),
            predictionRescueMaxConsecMisses:  Int(predictionRescueMaxConsecMisses.rounded()),
            predictionRescueRadiusNorm:       CGFloat(predictionRescueRadiusNorm),
            predictionRescueInsideBonus:      predictionRescueInsideBonus,
            predictionRescueNearBonus:        predictionRescueNearBonus,
            predictionRescueMaxLineResidual:  CGFloat(predictionRescueMaxLineResidual),
            predictionRescueInsideCircleScale: CGFloat(predictionRescueInsideCircleScale),
            predictionRescueAllowBorderlineMask: predictionRescueAllowBorderlineMask,
            predictionRescueMinMaskPixels:    Int(predictionRescueMinMaskPixels.rounded()),
            predictionRescueMinFillRatio:     CGFloat(predictionRescueMinFillRatio),
            predictionRescueMinDiamRatio:     CGFloat(predictionRescueMinDiamRatio),
            predictionRescueRequireFwdProgress: predictionRescueRequireFwdProgress,
            predictionRescueDisableAfterTerm: predictionRescueDisableAfterTerm,
            rejectEdgePartialBall: rejectEdgePartialBall,
            minBallMarginNorm:     CGFloat(minBallMarginNorm),
            enableFinalEdgeBallFilter:    enableFinalEdgeBallFilter,
            finalEdgeMarginNorm:          CGFloat(finalEdgeMarginNorm),
            finalEdgeRadiusMarginScale:   CGFloat(finalEdgeRadiusMarginScale),
            excludeEdgeBallFromMetrics:   excludeEdgeBallFromMetrics,
            enableSinglePointPrediction:   enableSinglePointPrediction,
            singlePointPredictionMaxStep:  CGFloat(singlePointPredictionMaxStep),
            singlePointPredictionMinStep:  CGFloat(singlePointPredictionMinStep)
        )
    }

    mutating func resetDefaults() { self = BallCandidateScoringSettings() }
}

// MARK: - Main Tuning Settings

struct BallTrackingTuningSettings {
    var sampleStride: Double = 2

    var preBrightnessThreshold:  Double = 90
    var preMaxChannelSpread:     Double = 90
    var preMinBrightSamples:     Double = 6
    var preMinNormWidth:         Double = 0.008
    var preMaxNormWidth:         Double = 0.090
    var preMinNormHeight:        Double = 0.012
    var preMaxNormHeight:        Double = 0.130
    var preMinAspect:            Double = 0.30
    var preMaxAspect:            Double = 2.00

    var postBrightnessThreshold: Double = 92
    var postMaxChannelSpread:    Double = 110
    var postMinBrightSamples:    Double = 4
    var postMinNormWidth:        Double = 0.018
    var postMaxNormWidth:        Double = 0.120
    var postMinNormHeight:       Double = 0.005
    var postMaxNormHeight:       Double = 0.150
    var postMinAspect:           Double = 0.12
    var postMaxAspect:           Double = 5.00

    var preImpactSearchScale:    Double = 5.67
    var impactSearchScale:       Double = 8.66
    var postImpactBaseScale:     Double = 5.03
    var postImpactScaleGrowth:   Double = 5.00
    var postImpactMaxScale:      Double = 30.0

    var trackingMode:               FrameNormalizationMode    = .darkenedHighContrast
    var diameter:                   DiameterRefinementSettings = DiameterRefinementSettings()
    var impact:                     ImpactDetectionSettings    = ImpactDetectionSettings()
    var calibration:                CalibrationTuningSettings  = CalibrationTuningSettings()
    var club:                       ClubTrackingTuningSettings = ClubTrackingTuningSettings()
    var scoring:                    BallCandidateScoringSettings = BallCandidateScoringSettings()
    var showOriginalCandidateBounds: Bool = false
    var showMaskPreview:             Bool = true
    var showBallPath:                Bool = true
    var show0DegRef:                 Bool = true
    var showCandidateIDs:            Bool = false
    var showScoreTable:              Bool = true
    var showLaunchDirection:         Bool = true
    var zeroDegreeAngleDeg:          Double = 0
    var carryCorrectionFactor:       Double = 0.75

    // Part F — asymmetric pre-impact ROI with vertical expansion
    var useAsymmetricPreImpactROI:         Bool   = true
    var preImpactForwardExpansionScale:    Double = 5.5
    var preImpactBackwardExpansionScale:   Double = 1.8
    var preImpactVerticalExpansionScale:   Double = 1.4
    var nearImpactForwardExpansionScale:   Double = 10.0
    var nearImpactBackwardExpansionScale:  Double = 2.5
    var nearImpactVerticalExpansionScale:  Double = 2.0
    var nearImpactWindowFrames:            Double = 4.0

    // Part A (new) — asymmetric post-impact ROI
    var postImpactForwardExpansionScale:             Double = 10.0
    var postImpactBackwardExpansionScale:            Double = 1.2
    var postImpactVerticalScaleUntracked:            Double = 1.5
    var postImpactVerticalScaleTracked:              Double = 2.5
    var reliableTrackMinPostImpactPoints:            Double = 2.0

    // Part C (new) — near-impact diameter jump guard
    var enableNearImpactDiameterJumpGuard:           Bool   = true
    var nearImpactDiameterGuardWindow:               Double = 2.0
    var maxNearImpactDiameterGrowth:                 Double = 1.50
    var minNearImpactDiameterShrink:                 Double = 0.80

    // Part D (new) — preliminary mask scoring
    var enablePrelimMaskScoring:                     Bool   = true
    var prelimRoundnessWeight:                       Double = 5.0
    var prelimRejectLineLike:                        Bool   = true

    // Part E (new) — require clean first post-impact point for single-point prediction
    var requireCleanFirstPointForPrediction:         Bool   = true

    // Part A/D — VLA from diameter growth (metrics calculator, updated scale + weights)
    var useDiameterGrowthForVLA:    Bool   = true
    var diameterGrowthToVLAScale:   Double = 140.0
    var diameterGrowthVLAWeight:    Double = 0.75
    var imageYVLAWeight:            Double = 0.25

    // New VLA model (pinhole2DSize / trainedModel)
    var vlaEstimationMode: VLAEstimationMode = .trainedModel
    var vlaModelFilePath: String? = nil
    var vlaImageYWeight: Double = 0.45
    var vlaDiameterDepthWeight: Double = 0.55
    var vlaDepthSign: Double = 1.0
    var vlaDepthScale: Double = 1.0
    var useRightwardPerspectiveSizeCorrection: Bool = true
    var rightwardSizeCorrectionStrength: Double = 0.35
    var maxSizeCorrectionRatio: Double = 1.35
    var vlaGrowthBoostDiameterScale: Double = 140.0
    var vlaSignificantGrowthThreshold: Double = 0.10
    var vlaVeryHighGrowthThreshold: Double = 0.25
    var vlaMinFromVeryHighGrowth: Double = 30.0
    var maxVLAPinholeDegrees: Double = 70.0

    func toConfiguration() -> ExperimentalBallTracker.Configuration {
        ExperimentalBallTracker.Configuration(
            sampleStride:             Int(sampleStride.rounded()),
            preBrightnessThreshold:   Int(preBrightnessThreshold.rounded()),
            preMaxChannelSpread:      Int(preMaxChannelSpread.rounded()),
            preMinBrightSamples:      Int(preMinBrightSamples.rounded()),
            preMinNormWidth:          CGFloat(preMinNormWidth),
            preMaxNormWidth:          CGFloat(preMaxNormWidth),
            preMinNormHeight:         CGFloat(preMinNormHeight),
            preMaxNormHeight:         CGFloat(preMaxNormHeight),
            preMinAspect:             CGFloat(preMinAspect),
            preMaxAspect:             CGFloat(preMaxAspect),
            postBrightnessThreshold:  Int(postBrightnessThreshold.rounded()),
            postMaxChannelSpread:     Int(postMaxChannelSpread.rounded()),
            postMinBrightSamples:     Int(postMinBrightSamples.rounded()),
            postMinNormWidth:         CGFloat(postMinNormWidth),
            postMaxNormWidth:         CGFloat(postMaxNormWidth),
            postMinNormHeight:        CGFloat(postMinNormHeight),
            postMaxNormHeight:        CGFloat(postMaxNormHeight),
            postMinAspect:            CGFloat(postMinAspect),
            postMaxAspect:            CGFloat(postMaxAspect),
            preImpactSearchScale:     CGFloat(preImpactSearchScale),
            impactSearchScale:        CGFloat(impactSearchScale),
            postImpactBaseScale:      CGFloat(postImpactBaseScale),
            postImpactScaleGrowth:    CGFloat(postImpactScaleGrowth),
            postImpactMaxScale:       CGFloat(postImpactMaxScale),
            normalizationMode:        trackingMode,
            diameterRefinement:       diameter.toConfig(),
            impactDetection:          impact.toConfig(),
            candidateScoring:         scoring.toConfig(),
            zeroDegreeAngleDegrees:            zeroDegreeAngleDeg,
            useAsymmetricPreImpactROI:         useAsymmetricPreImpactROI,
            preImpactForwardExpansionScale:    CGFloat(preImpactForwardExpansionScale),
            preImpactBackwardExpansionScale:   CGFloat(preImpactBackwardExpansionScale),
            preImpactVerticalExpansionScale:   CGFloat(preImpactVerticalExpansionScale),
            nearImpactForwardExpansionScale:   CGFloat(nearImpactForwardExpansionScale),
            nearImpactBackwardExpansionScale:  CGFloat(nearImpactBackwardExpansionScale),
            nearImpactVerticalExpansionScale:  CGFloat(nearImpactVerticalExpansionScale),
            nearImpactWindowFrames:            Int(nearImpactWindowFrames.rounded()),
            postImpactForwardExpansionScale:             CGFloat(postImpactForwardExpansionScale),
            postImpactBackwardExpansionScale:            CGFloat(postImpactBackwardExpansionScale),
            postImpactVerticalExpansionScaleUntracked:   CGFloat(postImpactVerticalScaleUntracked),
            postImpactVerticalExpansionScaleTracked:     CGFloat(postImpactVerticalScaleTracked),
            reliableTrackMinPostImpactPoints:            Int(reliableTrackMinPostImpactPoints.rounded()),
            enableNearImpactDiameterJumpGuard:           enableNearImpactDiameterJumpGuard,
            nearImpactDiameterGuardWindowAfterImpact:    Int(nearImpactDiameterGuardWindow.rounded()),
            maxNearImpactDiameterGrowthFrameToFrame:     CGFloat(maxNearImpactDiameterGrowth),
            minNearImpactDiameterShrinkFrameToFrame:     CGFloat(minNearImpactDiameterShrink)
        )
    }

    func toMetricsCalculatorConfig() -> ExperimentalShotMetricsCalculator.Configuration {
        var c = ExperimentalShotMetricsCalculator.Configuration()
        c.useDiameterGrowthForVLA  = useDiameterGrowthForVLA
        c.diameterGrowthToVLAScale = diameterGrowthToVLAScale
        c.diameterGrowthVLAWeight  = diameterGrowthVLAWeight
        c.imageYVLAWeight          = imageYVLAWeight
        c.vlaEstimationMode        = vlaEstimationMode
        c.vlaModelFilePath         = vlaModelFilePath
        c.vlaImageYWeight          = vlaImageYWeight
        c.vlaDiameterDepthWeight   = vlaDiameterDepthWeight
        c.vlaDepthSign             = vlaDepthSign
        c.vlaDepthScale            = vlaDepthScale
        c.useRightwardPerspectiveSizeCorrection = useRightwardPerspectiveSizeCorrection
        c.rightwardSizeCorrectionStrength = rightwardSizeCorrectionStrength
        c.maxSizeCorrectionRatio   = maxSizeCorrectionRatio
        c.vlaGrowthBoostDiameterScale = vlaGrowthBoostDiameterScale
        c.vlaSignificantGrowthThreshold = vlaSignificantGrowthThreshold
        c.vlaVeryHighGrowthThreshold = vlaVeryHighGrowthThreshold
        c.vlaMinFromVeryHighGrowth = vlaMinFromVeryHighGrowth
        c.maxVLAPinholeDegrees     = maxVLAPinholeDegrees
        return c
    }
}
#endif
