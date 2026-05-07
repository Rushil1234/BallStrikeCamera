#if DEBUG
import Foundation
import CoreGraphics
import simd

struct ExperimentalBall3DObservation {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    let imageX: CGFloat
    let imageY: CGFloat
    let diameterNorm: CGFloat
    let diameterPixels: Double
    let positionMeters: SIMD3<Double>
    let confidence: Double
}

struct ExperimentalBallLaunchMetrics {
    /// Image-space HLA relative to zeroDegreeReferenceAngleDegrees (primary HLA)
    let ballSpeedMph: Double?
    let hlaDegrees: Double?
    /// Formatted as "X.X° R" or "X.X° L"
    let hlaDisplay: String
    /// 3D raw atan2(vx, vz) — kept for reference/debugging
    let hla3DRawDegrees: Double?
    /// VLA clamped to ≥ 0 (Part E) — authoritative VLA used for all metrics
    var vlaDegrees: Double?
    /// Raw VLA before clamping (Part E) — nil if not clamped
    let vlaRawDegrees: Double?
    /// VLA estimated from ball diameter growth (Part D-new) — nil if not used
    var vlaDiameterEstDegrees: Double? = nil
    /// Raw diameter growth fraction used for VLA estimate (Part D-new)
    var diameterGrowthFraction: Double? = nil
    let hlaReferenceAngleDegrees: Double
    let ballMovementDx: Double?
    let ballMovementDy: Double?
    let hlaForwardComponent: Double?
    let hlaLateralComponent: Double?
    let pointsUsed: Int
    let quality: Double
    let method: String
    let warnings: [String]
    // VLA variants (all optional, filled based on mode)
    var vlaLegacyDegrees: Double? = nil
    var vlaPinhole2DSizeDegrees: Double? = nil
    var vlaTrainedModelDegrees: Double? = nil
    var vlaFinalDegrees: Double? = nil          // authoritative VLA used for all metrics
    var vlaModelUsed: String = "pinhole2DSize"
    var vlaModelFile: String? = nil
    var vlaModelFeaturesUsed: [String] = []
    var vlaModelFeatureValues: [String: Double] = [:]
    var vlaModelWarnings: [String] = []
    var vlaWasClamped: Bool = false
}

struct ExperimentalClubObservation {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    let centerX: CGFloat?
    let centerY: CGFloat?
    let leadingEdgeX: CGFloat?
    let leadingEdgeY: CGFloat?
    let clubBoundingBox: CGRect?
    let confidence: Double
    let searchROI: CGRect?
    let ballExclusionCenterX: CGFloat?
    let ballExclusionCenterY: CGFloat?
    let ballExclusionDiameter: CGFloat?
    let debugReason: String
    let detectionMode: String
    let ballExclusionWasApplied: Bool
    let frameDifferenceWasUsed: Bool

    var isDetected: Bool { centerX != nil || leadingEdgeX != nil }
}

struct ExperimentalClubMetrics {
    let clubSpeedMph: Double?
    let pointsUsed: Int
    let quality: Double
    let method: String
    let warnings: [String]
    let speedFrameIndices: [Int]
}

struct ExperimentalDistanceEstimate {
    let idealCarryYards: Double?
    let carryCorrectionFactor: Double
    let carryYards: Double?
    let rolloutYards: Double?
    let totalYards: Double?
    let rolloutFraction: Double?
    let vlaBucket: String
    let method: String
    let warnings: [String]
    var distanceVLAUsedSource: String = "unknown"
}

// MARK: - New estimated metrics

struct ExperimentalSpinEstimate {
    let estimatedBackspinRpm: Double?
    let estimatedSidespinRpmSigned: Double?
    /// "850 rpm R" / "450 rpm L" / "—"
    let estimatedSidespinDisplay: String
    let estimatedSpinAxisDegreesSigned: Double?
    /// "3.2° R" / "—"
    let estimatedSpinAxisDisplay: String
    let spinEstimateMethod: String
    let warnings: [String]
    var spinVLAUsedSource: String = "unknown"
}

struct ExperimentalClubPathEstimate {
    let clubPathDegreesSigned: Double?
    /// "4.2° R" / "—"
    let clubPathDisplay: String
    let confidence: Double
    let method: String
    let warnings: [String]
}

struct ExperimentalFaceAngleEstimate {
    let faceAngleDegreesSigned: Double?
    /// "1.8° R" / "—"
    let faceAngleDisplay: String
    let faceToPathDegreesSigned: Double?
    /// "2.4° L" / "—"
    let faceToPathDisplay: String
    /// "unavailable" | "low_bbox_heuristic" | "low_gradient"
    let confidence: String
    let method: String
    let warnings: [String]
}

// MARK: - Top-level result

struct ExperimentalShotMetricsResult {
    let detectedImpactFrameIndex: Int
    let fallbackImpactFrameIndex: Int
    let faceFrameIndex: Int
    let calibration: ExperimentalCameraCalibration
    let zeroDegreeReferenceAngleDegrees: Double
    let ballLaunch: ExperimentalBallLaunchMetrics
    let club: ExperimentalClubMetrics
    let smashFactor: Double?
    let rawSmashFactor: Double?
    let smashFactorClamped: Bool
    let distance: ExperimentalDistanceEstimate
    let spin: ExperimentalSpinEstimate
    let clubPath: ExperimentalClubPathEstimate
    let faceAngle: ExperimentalFaceAngleEstimate
    let ball3DObservations: [ExperimentalBall3DObservation]
    let clubObservations: [ExperimentalClubObservation]
    let warnings: [String]
}
#endif
