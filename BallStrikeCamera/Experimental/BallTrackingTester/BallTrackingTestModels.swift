import Foundation
import UIKit

struct BallTrackingTestFrame {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    let image: UIImage
}

struct BallTrackingTestSequence {
    let frames: [BallTrackingTestFrame]
    let impactFrameIndex: Int
    let sourceName: String
    let sourceURL: URL?
    let lockedBallRect: CGRect?
    // The live ImpactDetector's 2.5×-expanded ROI, when the export recorded it — used by the
    // live-parity replay's reposition gate. Nil for older exports (derived from the lock).
    var lockedImpactROI: CGRect? = nil
}

struct BallTrackingCandidateDebug {
    let rect: CGRect
    let centerX: CGFloat
    let centerY: CGFloat
    let diameter: CGFloat
    let confidence: Double
    let accepted: Bool
    let rejectionReason: String?
    let brightPixelCount: Int
    // Scoring breakdown (Parts A–H)
    let totalScore: Double
    let brightnessScore: Double
    let sizeScore: Double
    let distanceScore: Double
    let motionScore: Double
    let directionScore: Double
    let shapeScore: Double
    let penaltyScore: Double
    let isSelected: Bool
    // Launch direction / backward rejection (Parts A–C)
    let progress: CGFloat?       // forward progress along launch direction
    let backwardRejected: Bool   // hard-rejected for backward motion after launch

    init(rect: CGRect, centerX: CGFloat, centerY: CGFloat, diameter: CGFloat,
         confidence: Double, accepted: Bool, rejectionReason: String?,
         brightPixelCount: Int,
         totalScore: Double = 0, brightnessScore: Double = 0,
         sizeScore: Double = 0, distanceScore: Double = 0,
         motionScore: Double = 0, directionScore: Double = 0,
         shapeScore: Double = 0, penaltyScore: Double = 0,
         isSelected: Bool = false,
         progress: CGFloat? = nil, backwardRejected: Bool = false) {
        self.rect = rect; self.centerX = centerX; self.centerY = centerY
        self.diameter = diameter; self.confidence = confidence
        self.accepted = accepted; self.rejectionReason = rejectionReason
        self.brightPixelCount = brightPixelCount
        self.totalScore = totalScore; self.brightnessScore = brightnessScore
        self.sizeScore = sizeScore; self.distanceScore = distanceScore
        self.motionScore = motionScore; self.directionScore = directionScore
        self.shapeScore = shapeScore; self.penaltyScore = penaltyScore
        self.isSelected = isSelected
        self.progress = progress; self.backwardRejected = backwardRejected
    }
}

struct BallTrackingFrameDebug {
    let frameIndex: Int
    let searchROI: CGRect?
    let searchCenterSource: String
    let searchScale: CGFloat
    let candidates: [BallTrackingCandidateDebug]
    let selectedCandidate: BallTrackingCandidateDebug?
    let reason: String?
    // Motion prediction debug (Part B)
    let predictedPosition: CGPoint?
    let jumpDistance: Double?
    let expectedDiameter: CGFloat?
    // Launch direction / termination state (Parts A–C)
    let ballHasLaunched: Bool
    let launchDirectionVector: CGPoint?
    let maxProgress: CGFloat?
    let previousProgress: CGFloat?
    let ballTrackTerminated: Bool

    init(frameIndex: Int, searchROI: CGRect?, searchCenterSource: String,
         searchScale: CGFloat, candidates: [BallTrackingCandidateDebug],
         selectedCandidate: BallTrackingCandidateDebug?, reason: String?,
         predictedPosition: CGPoint? = nil, jumpDistance: Double? = nil,
         expectedDiameter: CGFloat? = nil,
         ballHasLaunched: Bool = false, launchDirectionVector: CGPoint? = nil,
         maxProgress: CGFloat? = nil, previousProgress: CGFloat? = nil,
         ballTrackTerminated: Bool = false) {
        self.frameIndex = frameIndex; self.searchROI = searchROI
        self.searchCenterSource = searchCenterSource; self.searchScale = searchScale
        self.candidates = candidates; self.selectedCandidate = selectedCandidate
        self.reason = reason; self.predictedPosition = predictedPosition
        self.jumpDistance = jumpDistance; self.expectedDiameter = expectedDiameter
        self.ballHasLaunched = ballHasLaunched
        self.launchDirectionVector = launchDirectionVector
        self.maxProgress = maxProgress; self.previousProgress = previousProgress
        self.ballTrackTerminated = ballTrackTerminated
    }
}

struct BallTrackingTestObservation {
    let frameIndex: Int
    let centerX: CGFloat?
    let centerY: CGFloat?
    let diameter: CGFloat?
    let candidateDiameter: CGFloat?
    let maskRefinedDiameter: CGFloat?
    let smoothedDiameter: CGFloat?
    let maskBoundsRect: CGRect?
    let maskWhitePixelCount: Int
    let diameterDebugReason: String
    let maskPreviewImage: UIImage?
    let maskCropNormRect: CGRect?
    let maskCandidateDiamInCrop: CGFloat?
    let maskRefinedDiamInCrop: CGFloat?
    let confidence: Double
    let debugReason: String
    let frameDebug: BallTrackingFrameDebug?
    // Part A — mask threshold debug
    let maskPercentileThreshold: Int?
    let maskLocalMedianBrightness: Int?
    let maskEffectiveThreshold: Int?
    let maskThresholdMode: String?

    init(frameIndex: Int, centerX: CGFloat?, centerY: CGFloat?, diameter: CGFloat?,
         candidateDiameter: CGFloat?, maskRefinedDiameter: CGFloat?, smoothedDiameter: CGFloat?,
         maskBoundsRect: CGRect?, maskWhitePixelCount: Int, diameterDebugReason: String,
         maskPreviewImage: UIImage?, maskCropNormRect: CGRect?,
         maskCandidateDiamInCrop: CGFloat?, maskRefinedDiamInCrop: CGFloat?,
         confidence: Double, debugReason: String, frameDebug: BallTrackingFrameDebug?,
         maskPercentileThreshold: Int? = nil, maskLocalMedianBrightness: Int? = nil,
         maskEffectiveThreshold: Int? = nil, maskThresholdMode: String? = nil) {
        self.frameIndex = frameIndex; self.centerX = centerX; self.centerY = centerY
        self.diameter = diameter; self.candidateDiameter = candidateDiameter
        self.maskRefinedDiameter = maskRefinedDiameter; self.smoothedDiameter = smoothedDiameter
        self.maskBoundsRect = maskBoundsRect; self.maskWhitePixelCount = maskWhitePixelCount
        self.diameterDebugReason = diameterDebugReason; self.maskPreviewImage = maskPreviewImage
        self.maskCropNormRect = maskCropNormRect
        self.maskCandidateDiamInCrop = maskCandidateDiamInCrop
        self.maskRefinedDiamInCrop = maskRefinedDiamInCrop
        self.confidence = confidence; self.debugReason = debugReason; self.frameDebug = frameDebug
        self.maskPercentileThreshold = maskPercentileThreshold
        self.maskLocalMedianBrightness = maskLocalMedianBrightness
        self.maskEffectiveThreshold = maskEffectiveThreshold
        self.maskThresholdMode = maskThresholdMode
    }
}

struct BallTrackingTestResult {
    let observations: [BallTrackingTestObservation]
    let trackedCount: Int
    let missingCount: Int
    let averageConfidence: Double
    let detectedImpactFrameIndex: Int
    let fallbackImpactFrameIndex: Int
    let impactDetectionReason: String
    let initialBallCenter: CGPoint?
    let movementThresholdNorm: CGFloat
    let metrics: ExperimentalShotMetricsResult?
    // Launch direction / termination (Parts A–C)
    let launchDirectionVector: CGPoint?
    let ballLaunchedAtFrameIndex: Int?
    let ballTrackTerminated: Bool
    let ballTerminatedAtFrameIndex: Int?

    init(observations: [BallTrackingTestObservation],
         trackedCount: Int, missingCount: Int, averageConfidence: Double,
         detectedImpactFrameIndex: Int, fallbackImpactFrameIndex: Int,
         impactDetectionReason: String, initialBallCenter: CGPoint?,
         movementThresholdNorm: CGFloat, metrics: ExperimentalShotMetricsResult? = nil,
         launchDirectionVector: CGPoint? = nil, ballLaunchedAtFrameIndex: Int? = nil,
         ballTrackTerminated: Bool = false, ballTerminatedAtFrameIndex: Int? = nil) {
        self.observations = observations
        self.trackedCount = trackedCount; self.missingCount = missingCount
        self.averageConfidence = averageConfidence
        self.detectedImpactFrameIndex = detectedImpactFrameIndex
        self.fallbackImpactFrameIndex = fallbackImpactFrameIndex
        self.impactDetectionReason = impactDetectionReason
        self.initialBallCenter = initialBallCenter
        self.movementThresholdNorm = movementThresholdNorm
        self.metrics = metrics
        self.launchDirectionVector = launchDirectionVector
        self.ballLaunchedAtFrameIndex = ballLaunchedAtFrameIndex
        self.ballTrackTerminated = ballTrackTerminated
        self.ballTerminatedAtFrameIndex = ballTerminatedAtFrameIndex
    }
}
