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
    let lockedBallRect: CGRect?
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
}

struct BallTrackingFrameDebug {
    let frameIndex: Int
    let searchROI: CGRect?
    let searchCenterSource: String  // "lockedBall" | "previousDetection" | "lockedBall_fallback" | "none"
    let searchScale: CGFloat
    let candidates: [BallTrackingCandidateDebug]
    let selectedCandidate: BallTrackingCandidateDebug?
    let reason: String?
}

struct BallTrackingTestObservation {
    let frameIndex: Int
    let centerX: CGFloat?
    let centerY: CGFloat?
    // final diameter: smoothed → maskRefined → candidate fallback
    let diameter: CGFloat?
    let candidateDiameter: CGFloat?     // raw blob bounding-box diameter
    let maskRefinedDiameter: CGFloat?   // from local mask bounding-box scan
    let smoothedDiameter: CGFloat?      // temporally smoothed via median window
    let maskBoundsRect: CGRect?         // normalized bounding rect of mask white pixels
    let maskWhitePixelCount: Int        // white pixels found in local mask
    let diameterDebugReason: String     // "mask_refined" | "diameter_clamped_min/max" | "mask_failed_*" | "smoothed" | ""
    // Mask preview for top-right inset
    let maskPreviewImage: UIImage?          // B&W crop of the local search window
    let maskCropNormRect: CGRect?           // normalized crop bounds in full image
    let maskCandidateDiamInCrop: CGFloat?   // candidate diameter as fraction of crop width
    let maskRefinedDiamInCrop: CGFloat?     // raw mask-measured diameter as fraction of crop width
    let confidence: Double
    let debugReason: String
    let frameDebug: BallTrackingFrameDebug?
}

struct BallTrackingTestResult {
    let observations: [BallTrackingTestObservation]
    let trackedCount: Int
    let missingCount: Int
    let averageConfidence: Double
    // Impact detection
    let detectedImpactFrameIndex: Int
    let fallbackImpactFrameIndex: Int
    let impactDetectionReason: String
    let initialBallCenter: CGPoint?
    let movementThresholdNorm: CGFloat
}
