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

struct BallTrackingTestObservation {
    let frameIndex: Int
    let centerX: CGFloat?
    let centerY: CGFloat?
    let diameter: CGFloat?
    let confidence: Double
    let debugReason: String
}

struct BallTrackingTestResult {
    let observations: [BallTrackingTestObservation]
    let trackedCount: Int
    let missingCount: Int
    let averageConfidence: Double
}
