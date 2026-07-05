import Foundation
import UIKit

struct ShotBallObservation {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    // Nil when tracking failed for this frame.
    let centerX: CGFloat?
    let centerY: CGFloat?
    // Backward-compatible final diameter used by existing export/review code.
    let diameter: CGFloat?
    let candidateDiameter: CGFloat?
    let refinedDiameter: CGFloat?
    let smoothedDiameter: CGFloat?
    let finalDiameter: CGFloat?
    let confidence: Double
    let wasInterpolated: Bool
    let debugReason: String?
    let diameterDebugReason: String?
    let maskWhitePixelCount: Int
    /// Vertical extent of the detection bbox (fraction of frame height). Motion blur smears
    /// the blob ALONG the (mostly horizontal) travel direction, inflating width-based
    /// diameters; the vertical extent stays close to the true ball size, making it the right
    /// input for height-from-apparent-size VLA.
    let bboxHeightNorm: CGFloat?

    init(
        frameIndex: Int,
        timestamp: TimeInterval,
        relativeTime: TimeInterval,
        centerX: CGFloat?,
        centerY: CGFloat?,
        diameter: CGFloat?,
        candidateDiameter: CGFloat? = nil,
        refinedDiameter: CGFloat? = nil,
        smoothedDiameter: CGFloat? = nil,
        finalDiameter: CGFloat? = nil,
        confidence: Double,
        wasInterpolated: Bool,
        debugReason: String? = nil,
        diameterDebugReason: String? = nil,
        maskWhitePixelCount: Int = 0,
        bboxHeightNorm: CGFloat? = nil
    ) {
        self.frameIndex = frameIndex
        self.timestamp = timestamp
        self.relativeTime = relativeTime
        self.centerX = centerX
        self.centerY = centerY
        self.diameter = diameter
        self.candidateDiameter = candidateDiameter
        self.refinedDiameter = refinedDiameter
        self.smoothedDiameter = smoothedDiameter
        self.finalDiameter = finalDiameter ?? diameter
        self.confidence = confidence
        self.wasInterpolated = wasInterpolated
        self.debugReason = debugReason
        self.diameterDebugReason = diameterDebugReason
        self.maskWhitePixelCount = maskWhitePixelCount
        self.bboxHeightNorm = bboxHeightNorm
    }
}

struct ShotFrameDebugInfo {
    let frameIndex: Int
    let searchROI: CGRect?
    // Number of pixels that passed the brightness + spread filter.
    let candidateCount: Int
    // Nil when a candidate was accepted; populated with the rejection reason otherwise.
    let rejectionReason: String?
    let searchCenterSource: String?
    let searchScale: CGFloat?

    init(
        frameIndex: Int,
        searchROI: CGRect?,
        candidateCount: Int,
        rejectionReason: String?,
        searchCenterSource: String? = nil,
        searchScale: CGFloat? = nil
    ) {
        self.frameIndex = frameIndex
        self.searchROI = searchROI
        self.candidateCount = candidateCount
        self.rejectionReason = rejectionReason
        self.searchCenterSource = searchCenterSource
        self.searchScale = searchScale
    }
}

struct AnalyzedShotFrame {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    let originalFrame: CapturedFrame
    // Exposure-lifted copy — useful for visual review but too bright for tracking.
    let brightenedImage: UIImage?
    // Darker, higher-contrast copy — used by PostImpactBallTracker.
    let darkenedHighContrastImage: UIImage?
    // Nil until ball tracking runs.
    let ballObservation: ShotBallObservation?
    // Per-frame tracker diagnostics for the review UI.
    let debugInfo: ShotFrameDebugInfo?
}

struct ShotAnalysisResult {
    let frames: [AnalyzedShotFrame]
    // Effective impact frame used by review/composites. This is the detected frame
    // when movement detection succeeds, otherwise the capture fallback frame.
    let impactFrameIndex: Int
    let fallbackImpactFrameIndex: Int
    let detectedImpactFrameIndex: Int
    let impactDetectionReason: String
    let initialBallCenter: CGPoint?
    let movementThresholdNorm: CGFloat
    let lockedBallRect: CGRect?
    // 2.5× expansion of lockedBallRect used by the ImpactDetector.
    let lockedImpactROI: CGRect?
    let createdAt: Date
    let metrics: ShotMetricsResult?

    init(
        frames: [AnalyzedShotFrame],
        impactFrameIndex: Int,
        lockedBallRect: CGRect?,
        lockedImpactROI: CGRect?,
        createdAt: Date,
        fallbackImpactFrameIndex: Int? = nil,
        detectedImpactFrameIndex: Int? = nil,
        impactDetectionReason: String = "fallback_not_run",
        initialBallCenter: CGPoint? = nil,
        movementThresholdNorm: CGFloat = 0,
        metrics: ShotMetricsResult? = nil
    ) {
        self.frames = frames
        self.impactFrameIndex = impactFrameIndex
        self.fallbackImpactFrameIndex = fallbackImpactFrameIndex ?? impactFrameIndex
        self.detectedImpactFrameIndex = detectedImpactFrameIndex ?? impactFrameIndex
        self.impactDetectionReason = impactDetectionReason
        self.initialBallCenter = initialBallCenter
        self.movementThresholdNorm = movementThresholdNorm
        self.lockedBallRect = lockedBallRect
        self.lockedImpactROI = lockedImpactROI
        self.createdAt = createdAt
        self.metrics = metrics
    }
}
