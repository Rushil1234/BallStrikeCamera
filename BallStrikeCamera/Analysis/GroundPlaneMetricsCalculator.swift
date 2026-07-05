import Foundation
import CoreGraphics

/// Experimental physically-calibrated metrics from the measured ground footprint of the camera.
///
/// The user measured the area the camera sees on the ground: 58" along the image's long
/// (horizontal) axis and 32" along the short (vertical) axis, with the phone on a 41" tripod.
/// That turns normalized image coordinates directly into inches for anything on the ground
/// plane, and per-frame timestamps (240fps) turn displacement into speed with no trained model.
///
/// Runs ALONGSIDE the existing ShotMetricsCalculator — output is console-only for now, so
/// nothing user-facing changes until this is validated against a Garmin R10. Once validated,
/// per-shot (frames → R10 ground truth) pairs can train the real replacement model.
///
/// Physics notes:
/// - While the ball is on/near the ground, the footprint mapping is exact — ideal for putts.
/// - As the ball rises toward the camera its apparent diameter grows: d ∝ 1/(cameraHeight - z),
///   so height z = h·(1 − d₀/d) where d₀ is the pre-impact (on-ground) diameter. VLA comes from
///   the fitted vertical velocity vs the fitted ground velocity — no model needed.
/// - A rising ball's ground-plane (x,y) also projects outward from the camera axis, inflating
///   apparent horizontal travel by ~1/(1 − z/h). We report both raw and height-corrected speed.
struct GroundPlaneMetricsCalculator {

    struct Config {
        /// Inches spanned by the full frame along normalized X (the long axis in landscape).
        var groundLengthInches: CGFloat = 58.0
        /// Inches spanned by the full frame along normalized Y.
        var groundWidthInches: CGFloat = 32.0
        /// Camera lens height above the ground plane, inches.
        var cameraHeightInches: CGFloat = 41.0
        /// Points whose center is within this normalized margin of any frame edge are dropped —
        /// a partially clipped blob biases its centroid inward and corrupts the last sample.
        var edgeExclusionNorm: CGFloat = 0.03
        /// Minimum tracked post-impact points required to fit velocity.
        var minPoints: Int = 2
        /// Max post-impact points used for the launch fit. Early points dominate launch
        /// conditions; late points mix in flight curvature and projection error.
        var maxPoints: Int = 8
    }

    struct Result {
        let ballSpeedMph: Double?
        /// Height-corrected speed (accounts for ground-projection inflation as the ball rises).
        let correctedBallSpeedMph: Double?
        let hlaDegrees: Double?            // signed; positive = +y in image space (toward bottom)
        let vlaDegrees: Double?
        let pointsUsed: Int
        let usedDiameterVLA: Bool
        let warnings: [String]
        let perPointLog: [String]
    }

    let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    /// `groundCalibration` corrects for position-dependent apparent size: the ball looks
    /// smaller toward the frame edges (off-axis distance + lens) even at constant height, so
    /// raw diameter growth under-reads or cancels the true rise. The calibration provides the
    /// expected ON-GROUND size at any image position; we use it as a unit-free ratio against
    /// the lock position so the blur-immune vertical-extent measure stays the size input.
    func calculate(observations: [ShotBallObservation],
                   impactFrameIndex: Int,
                   groundCalibration: GroundCalibration? = nil) -> Result {
        var warnings: [String] = []
        var perPoint: [String] = []

        // Pre-impact on-ground size baseline (median) — the reference for height-from-size.
        // Uses the VERTICAL bbox extent, not the blur-averaged diameter: motion blur smears the
        // blob along the (mostly horizontal) travel direction and inflated width-based
        // diameters by ~35% at full-swing speeds, which the z = h·(1 − d₀/d) formula read as
        // the ball rising steeply (observed: 52° VLA on a ~10° shot). The vertical extent only
        // blurs with vertical velocity — small at real launch angles — so it stays honest.
        let sizeOf: (ShotBallObservation) -> CGFloat? = { $0.bboxHeightNorm ?? $0.finalDiameter ?? $0.diameter }
        let preDiameters = observations
            .filter { $0.frameIndex < impactFrameIndex }
            .compactMap(sizeOf)
            .sorted()
        let groundDiameter: CGFloat? = preDiameters.isEmpty ? nil : preDiameters[preDiameters.count / 2]
        if groundDiameter == nil {
            warnings.append("no pre-impact sizes — VLA-from-size unavailable")
        }

        // Post-impact tracked points, stopping at the FIRST miss: a gap means the ball left the
        // frame (or was lost) between samples — extrapolating across it would fake a slower exit.
        var pts: [(t: Double, xIn: CGFloat, yIn: CGFloat, xN: CGFloat, yN: CGFloat, dia: CGFloat?)] = []
        for obs in observations.sorted(by: { $0.frameIndex < $1.frameIndex }) {
            guard obs.frameIndex > impactFrameIndex else { continue }
            guard let xN = obs.centerX, let yN = obs.centerY else { break }   // stop at first miss
            // Drop edge-clipped samples (and everything after — the ball is leaving).
            let m = config.edgeExclusionNorm
            if xN < m || xN > 1 - m || yN < m || yN > 1 - m {
                perPoint.append(String(format: "frame=%02d SKIPPED edge-clipped (x=%.3f y=%.3f)", obs.frameIndex, xN, yN))
                break
            }
            pts.append((
                t: obs.relativeTime,
                xIn: xN * config.groundLengthInches,
                yIn: yN * config.groundWidthInches,
                xN: xN, yN: yN,
                dia: sizeOf(obs)
            ))
            if pts.count >= config.maxPoints { break }
        }

        guard pts.count >= config.minPoints else {
            warnings.append("only \(pts.count) usable post-impact points (need \(config.minPoints))")
            return Result(ballSpeedMph: nil, correctedBallSpeedMph: nil, hlaDegrees: nil,
                          vlaDegrees: nil, pointsUsed: pts.count, usedDiameterVLA: false,
                          warnings: warnings, perPointLog: perPoint)
        }

        // Least-squares linear fit of position vs time — noise-robust vs first/last differencing.
        let vx = Self.fitVelocity(pts.map { ($0.t, $0.xIn) })
        let vy = Self.fitVelocity(pts.map { ($0.t, $0.yIn) })
        let groundSpeedInPerSec = Double(hypot(vx, vy))
        let mph = groundSpeedInPerSec / 17.6     // 1 mph = 17.6 in/s

        // HLA: lateral angle of the ground-plane velocity relative to the long (x) axis.
        let hla = Double(atan2(vy, abs(vx))) * 180.0 / .pi

        // Height per point from size growth: z = h · (1 − d₀ᵉᶠᶠ/d). The naive fixed-d₀ version
        // was blind to POSITION: apparent size shrinks as the ball moves away from directly
        // under the camera (off-axis distance + lens), so a rising ball moving outward reads
        // as "same size" and VLA collapses to 0. GroundCalibration measured the on-ground size
        // at 985 image positions; using it as a ratio field, the expected ground size at the
        // flight position is d₀ · cal(pos)/cal(lock) — only size ABOVE that curve is height.
        var vla: Double? = nil
        var usedDiaVLA = false
        var correctedMph: Double? = nil
        // Median pre-impact center = the lock position (reference for the calibration ratio).
        let preXs = observations.filter { $0.frameIndex < impactFrameIndex }.compactMap { $0.centerX }.sorted()
        let preYs = observations.filter { $0.frameIndex < impactFrameIndex }.compactMap { $0.centerY }.sorted()
        let lockU = preXs.isEmpty ? nil : preXs[preXs.count / 2]
        let lockV = preYs.isEmpty ? nil : preYs[preYs.count / 2]
        var calAtLock: Double? = nil
        if let cal = groundCalibration, let u = lockU, let v = lockV {
            let (dia, conf) = cal.expectedDiameter(u: Double(u), v: Double(v))
            if let dia, dia > 1e-6, conf >= 0.15 { calAtLock = dia }
        }
        if let d0 = groundDiameter, d0 > 1e-6 {
            var heights: [(t: Double, zIn: CGFloat)] = []
            var corrections: [Double] = []
            for p in pts {
                guard let d = p.dia, d > 1e-6 else { continue }
                // Position correction: expected on-ground size at this spot relative to lock.
                var correction: CGFloat = 1.0
                if let cal = groundCalibration, let refCal = calAtLock {
                    let (dia, conf) = cal.expectedDiameter(u: Double(p.xN), v: Double(p.yN))
                    if let dia, dia > 1e-6, conf >= 0.15 {
                        correction = CGFloat(dia / refCal)
                    }
                }
                corrections.append(Double(correction))
                let ratio = max((d0 * correction) / d, 0.05)  // d above ground-expected → ratio < 1
                let z = config.cameraHeightInches * (1 - ratio)
                heights.append((t: p.t, zIn: z))
            }
            if !corrections.isEmpty, calAtLock != nil {
                perPoint.append("cal corrections: " + corrections.map { String(format: "%.3f", $0) }.joined(separator: " "))
            } else if groundCalibration != nil {
                warnings.append("ground calibration has no coverage at lock/flight positions — uncorrected sizes used")
            }
            // Height samples are a quantized staircase (one size quantum ≈ several inches of
            // inferred height). A Theil–Sen MEDIAN slope collapses to exactly 0 whenever most
            // sample pairs share a quantum — which pinned VLA to 0 on every real low-launch
            // shot. Least squares averages THROUGH the staircase and recovers sub-quantum
            // slopes, so use it here (ground speed keeps the robust Theil–Sen fit — it has
            // plenty of signal per frame).
            if heights.count >= 2 {
                let vz = Self.fitVelocityLeastSquares(heights.map { ($0.t, $0.zIn) })
                // Projection correction: apparent ground travel is inflated by h/(h−z) at height z.
                // Use mean height over the fit window for a first-order correction.
                let meanZ = heights.map { $0.zIn }.reduce(0, +) / CGFloat(heights.count)
                let shrink = max(0.2, (config.cameraHeightInches - meanZ) / config.cameraHeightInches)
                let correctedGround = groundSpeedInPerSec * Double(shrink)
                correctedMph = hypot(correctedGround, Double(vz)) / 17.6
                vla = Double(atan2(vz, CGFloat(correctedGround))) * 180.0 / .pi
                usedDiaVLA = true
                perPoint.append(String(format: "heights: %@  vz=%.1f in/s  meanZ=%.1f in  shrink=%.3f",
                                       heights.map { String(format: "%.2f", $0.zIn) }.joined(separator: " "),
                                       Double(vz), Double(meanZ), Double(shrink)))
            } else {
                warnings.append("too few diameter samples post-impact for VLA-from-size")
            }
        }

        for p in pts {
            perPoint.append(String(format: "t=%+.4fs pos=(%.1f, %.1f)in norm=(%.3f, %.3f) dia=%@",
                                   p.t, p.xIn, p.yIn, p.xN, p.yN,
                                   p.dia.map { String(format: "%.4f", $0) } ?? "n/a"))
        }

        return Result(ballSpeedMph: mph, correctedBallSpeedMph: correctedMph, hlaDegrees: hla,
                      vlaDegrees: vla, pointsUsed: pts.count, usedDiameterVLA: usedDiaVLA,
                      warnings: warnings, perPointLog: perPoint)
    }

    /// Least-squares slope of (t, value) — velocity in units/second. Used for the height fit,
    /// where the input is a quantized staircase: LS averages through the steps and recovers
    /// the true sub-quantum slope, where a median-based fit reads exactly 0.
    private static func fitVelocityLeastSquares(_ samples: [(Double, CGFloat)]) -> CGFloat {
        let n = CGFloat(samples.count)
        guard n >= 2 else { return 0 }
        let meanT = samples.map { CGFloat($0.0) }.reduce(0, +) / n
        let meanV = samples.map { $0.1 }.reduce(0, +) / n
        var num: CGFloat = 0, den: CGFloat = 0
        for (t, v) in samples {
            let dt = CGFloat(t) - meanT
            num += dt * (v - meanV)
            den += dt * dt
        }
        return den > 1e-12 ? num / den : 0
    }

    /// Velocity in units/second via Theil–Sen (median of all pairwise slopes). The per-frame
    /// sizes/positions are quantized to the sampling grid (~2px steps → ~13% size jumps on a
    /// 15px ball), and a least-squares fit lets one quantization spike drag the slope hard —
    /// which was inflating VLA (fit vz from noisy heights read 29° on a ~10-15° shot). The
    /// median of pairwise slopes ignores such outliers entirely. O(n²) with n ≤ 8 — trivial.
    private static func fitVelocity(_ samples: [(Double, CGFloat)]) -> CGFloat {
        guard samples.count >= 2 else { return 0 }
        var slopes: [CGFloat] = []
        slopes.reserveCapacity(samples.count * (samples.count - 1) / 2)
        for i in 0..<samples.count {
            for j in (i + 1)..<samples.count {
                let dt = CGFloat(samples[j].0 - samples[i].0)
                guard abs(dt) > 1e-9 else { continue }
                slopes.append((samples[j].1 - samples[i].1) / dt)
            }
        }
        guard !slopes.isEmpty else { return 0 }
        let sorted = slopes.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Formats the result as console lines, prefixed for easy filtering/export.
    static func logResult(_ r: Result, existingSpeedMph: Double?, existingHLA: Double?, existingVLA: Double?) {
        print("[GroundPlane] ===== experimental ground-plane metrics =====")
        print(String(format: "[GroundPlane] ball speed: %@ mph (height-corrected: %@)  [existing model: %@]",
                     r.ballSpeedMph.map { String(format: "%.1f", $0) } ?? "n/a",
                     r.correctedBallSpeedMph.map { String(format: "%.1f", $0) } ?? "n/a",
                     existingSpeedMph.map { String(format: "%.1f", $0) } ?? "n/a"))
        print(String(format: "[GroundPlane] HLA: %@°  [existing: %@]   VLA: %@°%@  [existing: %@]",
                     r.hlaDegrees.map { String(format: "%+.1f", $0) } ?? "n/a",
                     existingHLA.map { String(format: "%+.1f", $0) } ?? "n/a",
                     r.vlaDegrees.map { String(format: "%.1f", $0) } ?? "n/a",
                     r.usedDiameterVLA ? " (from diameter growth)" : "",
                     existingVLA.map { String(format: "%.1f", $0) } ?? "n/a"))
        print("[GroundPlane] points used: \(r.pointsUsed)")
        for line in r.perPointLog { print("[GroundPlane]   \(line)") }
        for w in r.warnings { print("[GroundPlane] warning: \(w)") }
        print("[GroundPlane] ============================================")
    }
}
