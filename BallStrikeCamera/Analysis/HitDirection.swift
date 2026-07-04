import CoreGraphics

/// Global hit-direction convention for the whole capture + tracking + metrics pipeline.
///
/// The phone is now mounted the opposite way, so the ball travels **right→left** across the
/// (upright) frame instead of left→right. Every horizontal directional assumption — where the
/// club is relative to the ball, which way the frontier advances, the aim fan, and the L/R metric
/// signs — is expressed in terms of `sign` so the whole thing flips from one switch.
///
/// `sign` is the image-x direction multiplier:
///   •  +1  → ball travels left→right (original convention)
///   •  −1  → ball travels right→left (reversed / current mount)
///
/// To restore the original convention, set `reversed = false`.
enum HitDirection {
    static let reversed = true

    static var sign: Double { reversed ? -1 : 1 }
    static var signCG: CGFloat { CGFloat(sign) }
}
