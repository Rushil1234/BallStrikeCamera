import Foundation
import UIKit

struct ShotBallObservation {
    let frameIndex: Int
    let timestamp: TimeInterval
    let relativeTime: TimeInterval
    // Nil when tracking failed for this frame.
    let centerX: CGFloat?
    let centerY: CGFloat?
    let diameter: CGFloat?
    let confidence: Double
    let wasInterpolated: Bool
}

struct ShotFrameDebugInfo {
    let frameIndex: Int
    let searchROI: CGRect?
    // Number of pixels that passed the brightness + spread filter.
    let candidateCount: Int
    // Nil when a candidate was accepted; populated with the rejection reason otherwise.
    let rejectionReason: String?
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
    let impactFrameIndex: Int
    let lockedBallRect: CGRect?
    // 2.5× expansion of lockedBallRect used by the ImpactDetector.
    let lockedImpactROI: CGRect?
    let createdAt: Date
}
