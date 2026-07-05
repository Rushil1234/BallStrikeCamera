import CoreGraphics

struct BallObservation {
    /// Normalized rect in camera-buffer coordinates: x/y/width/height from 0...1.
    let normalizedRect: CGRect
    let confidence: Double
    /// Fraction of the cluster's bounding-box grid cells that were bright. A solid ball disc
    /// fills ~0.45-0.7; ball-sized glare slivers on a shoe/clubhead fill far less. Defaults to
    /// 1 (pass) for detectors that don't measure it.
    let fillRatio: Double

    init(normalizedRect: CGRect, confidence: Double, fillRatio: Double = 1.0) {
        self.normalizedRect = normalizedRect
        self.confidence = confidence
        self.fillRatio = fillRatio
    }

    var center: CGPoint {
        CGPoint(x: normalizedRect.midX, y: normalizedRect.midY)
    }
}
