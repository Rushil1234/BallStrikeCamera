import Foundation
import UIKit
import CoreGraphics

// MARK: - Putt engine
// Putts get their own physics because the general pipeline's assumptions are exactly wrong
// for them: the ball never leaves the ground, so the measured 58×32in footprint mapping
// (norm coords → inches) is EXACT for every tracked point — no flight model, no trained
// model, no depth ambiguity. That turns the observed roll into measured speed, start line,
// and curvature, and a green-speed (stimp) assumption turns speed into roll-out distance.
//
// The putter head gets a dedicated slow-motion pass: full-swing club tracking is skipped
// for putts (EBFS is tuned for blurred 80mph heads), but a putter at 2–8 mph is a clean,
// unblurred moving blob — simple frame differencing against an early pre-impact frame
// tracks it well enough for head speed, path, and a silhouette-based face-angle estimate.

/// Everything the putt engine measured. Sign convention matches HLA everywhere:
/// positive = +y in image space; displays convert to L/R.
struct PuttReadout {
    // Ball roll (ground-plane measured)
    var ballSpeedMph: Double?
    var rollDistanceFeet: Double?          // projected to stop at `stimp` green speed
    var rollDistanceMeasured: Bool = false // true if the ball visibly stopped in frame
    var stimp: Double
    var observedBreakInches: Double?       // lateral bend across the observed window (signed)
    var projectedBreakInches: Double?      // extrapolated over the full roll (signed)
    var breakMeasured: Bool = false        // false → curvature indistinguishable from noise
    var observedTravelInches: Double = 0

    // Putter head (frame-diff tracked)
    var putterSpeedMph: Double?
    var putterPathDegreesSigned: Double?
    var faceAngleDegreesSigned: Double?    // from head silhouette orientation — estimate

    /// Observed post-impact ball path in normalized frame coords, for the overhead trace.
    var observedPathNorm: [CGPoint] = []
    var warnings: [String] = []

    var breakDisplay: String {
        guard breakMeasured, let b = projectedBreakInches ?? observedBreakInches else { return "--" }
        if abs(b) < 0.75 { return "straight" }
        return String(format: "%.0f in %@", abs(b), b < 0 ? "L" : "R")
    }
    var faceDisplay: String {
        guard let f = faceAngleDegreesSigned else { return "--" }
        if abs(f) < 0.5 { return "square" }
        return String(format: "%.1f° %@", abs(f), f < 0 ? "L" : "R")
    }
}

struct PuttAnalyzer {

    struct Config {
        var groundLengthInches: CGFloat = 58.0   // frame's long (X) axis on the ground
        var groundWidthInches: CGFloat  = 32.0   // frame's short (Y) axis
        var edgeExclusionNorm: CGFloat  = 0.03
        var speedFitPoints: Int         = 10
        /// Green speed used to project roll-out (stimp feet). Overridable via UserDefaults.
        var defaultStimp: Double        = 10.0
        static let stimpDefaultsKey     = "tc_green_stimp"

        // Putter-head pass
        var headFramesTracked: Int      = 14     // pre-impact frames the head is tracked over
        var headDiffThreshold: Int      = 28     // |Δgray| that counts as "moved"
        var headMinPixels: Int          = 25     // below this the frame is ignored
        var downscaleWidth: Int         = 384
        var minCentroids: Int           = 5
        var faceMinAspect: Double       = 2.2    // major/minor axis ratio to trust orientation
    }

    let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    func analyze(analysis: ShotAnalysisResult) -> PuttReadout {
        let stimp = UserDefaults.standard.double(forKey: Config.stimpDefaultsKey)
        var out = PuttReadout(stimp: stimp > 0 ? stimp : config.defaultStimp)

        analyzeRoll(analysis: analysis, into: &out)
        analyzePutterHead(analysis: analysis, into: &out)

        print(String(format: "[Putt] speed=%@ roll=%@ break(obs/proj)=%@/%@ putter=%@ face=%@ path=%@ travel=%.0fin",
                     out.ballSpeedMph.map { String(format: "%.1fmph", $0) } ?? "--",
                     out.rollDistanceFeet.map { String(format: "%.1fft@stimp%.0f", $0, out.stimp) } ?? "--",
                     out.observedBreakInches.map { String(format: "%.1fin", $0) } ?? "--",
                     out.projectedBreakInches.map { String(format: "%.1fin", $0) } ?? "--",
                     out.putterSpeedMph.map { String(format: "%.1fmph", $0) } ?? "--",
                     out.faceAngleDegreesSigned.map { String(format: "%.1f°", $0) } ?? "--",
                     out.putterPathDegreesSigned.map { String(format: "%.1f°", $0) } ?? "--",
                     out.observedTravelInches))
        return out
    }

    // MARK: - Ball roll (post-impact, on the ground plane)

    private func analyzeRoll(analysis: ShotAnalysisResult, into out: inout PuttReadout) {
        // Post-impact tracked points, stopping at the first miss or edge clip — same policy
        // as GroundPlaneMetricsCalculator: extrapolating across a gap fakes a slower exit.
        var pts: [(t: Double, x: CGFloat, y: CGFloat)] = []   // inches
        var norm: [CGPoint] = []
        let m = config.edgeExclusionNorm
        for frame in analysis.frames where frame.frameIndex > analysis.detectedImpactFrameIndex {
            guard let obs = frame.ballObservation,
                  let xN = obs.centerX, let yN = obs.centerY else { break }
            if xN < m || xN > 1 - m || yN < m || yN > 1 - m { break }
            pts.append((t: obs.relativeTime,
                        x: xN * config.groundLengthInches,
                        y: yN * config.groundWidthInches))
            norm.append(CGPoint(x: xN, y: yN))
        }
        out.observedPathNorm = norm

        guard pts.count >= 3 else {
            out.warnings.append("Putt roll: only \(pts.count) tracked points — speed/break unavailable.")
            return
        }

        // Initial speed: least-squares over the first points (launch conditions, noise-robust).
        let head = Array(pts.prefix(config.speedFitPoints))
        let vx = Self.lsqVelocity(head.map { ($0.t, $0.x) })
        let vy = Self.lsqVelocity(head.map { ($0.t, $0.y) })
        let vInPerSec = Double(hypot(vx, vy))
        guard vInPerSec > 3 else {
            out.warnings.append("Putt roll: ball barely moved — no speed fit.")
            return
        }
        out.ballSpeedMph = vInPerSec / 17.6

        // Rotate all points into (s = along start line, l = lateral) coordinates.
        let inv = 1.0 / CGFloat(hypot(vx, vy))
        let ux = vx * inv, uy = vy * inv        // start-line direction
        let nx = -uy, ny = ux                   // lateral (left-hand normal)
        let p0 = pts[0]
        var sl: [(s: CGFloat, l: CGFloat)] = pts.map {
            let dx = $0.x - p0.x, dy = $0.y - p0.y
            return (s: dx * ux + dy * uy, l: dx * nx + dy * ny)
        }
        sl = sl.filter { $0.s >= 0 }
        let sEnd = sl.map(\.s).max() ?? 0
        out.observedTravelInches = Double(sEnd)

        // Roll-out from stimp physics: the stimpmeter releases at 6.00 ft/s and rolls S feet,
        // so deceleration a = 18/S ft/s² (stimp 10 → 1.8). Distance = v²/2a.
        let aFtPerS2 = 18.0 / out.stimp
        let vFtPerS = vInPerSec / 12.0
        let rollFeet = (vFtPerS * vFtPerS) / (2.0 * aFtPerS2)
        out.rollDistanceFeet = rollFeet
        out.warnings.append(String(format:
            "Putt distance projected at green speed (stimp %.0f) — set your green speed in settings for better numbers.", out.stimp))

        // Break: fit l(s) = b·s + c·s² — b absorbs start-line error, c is the bend. Only
        // report when the bend clears the fit noise; 0.4s of roll is a short window and an
        // honest "straight" beats a fabricated break.
        guard sl.count >= 8, sEnd > 12 else {
            out.warnings.append("Putt break: observed window too short to measure curvature.")
            return
        }
        guard let (b, c, rms) = Self.fitQuadratic(sl) else { return }
        let observedBend = Double(c * sEnd * sEnd)
        // Lateral sign in image y: n = (nx, ny); positive break should mean +y (matches HLA).
        let ySign: Double = ny >= 0 ? 1.0 : -1.0
        out.observedBreakInches = observedBend * ySign
        _ = b

        let noiseFloor = max(0.3, 2.5 * Double(rms))
        if abs(observedBend) > noiseFloor {
            out.breakMeasured = true
            // Constant lateral acceleration (side slope) + linear decel ⇒ total break over a
            // roll of length S is 4·c·S² (closed form; break grows quadratically in time while
            // the ball spends disproportionate time slowing near the hole).
            let sRollIn = rollFeet * 12.0
            var projected = 4.0 * Double(c) * sRollIn * sRollIn * ySign
            // Sanity: a break beyond ~40% of the putt length means the quadratic fit blew up.
            if abs(projected) > sRollIn * 0.4 {
                out.warnings.append("Putt break: projection unstable — reporting observed bend only.")
                projected = observedBend * ySign
            }
            out.projectedBreakInches = projected
        } else {
            out.breakMeasured = abs(observedBend) <= noiseFloor && rms < 0.6
            out.observedBreakInches = out.breakMeasured ? 0 : out.observedBreakInches
            out.projectedBreakInches = out.breakMeasured ? 0 : nil
            if !out.breakMeasured {
                out.warnings.append("Putt break: track too noisy to separate bend from jitter.")
            }
        }
    }

    // MARK: - Putter head (pre-impact frame differencing)

    private func analyzePutterHead(analysis: ShotAnalysisResult, into out: inout PuttReadout) {
        guard let ballRect = analysis.lockedBallRect else {
            out.warnings.append("Putter head: no locked ball rect — head pass skipped.")
            return
        }
        let preFrames = analysis.frames.filter { $0.frameIndex < analysis.detectedImpactFrameIndex }
        guard preFrames.count >= config.headFramesTracked + 6,
              let baseFrame = preFrames.first,
              let base = Self.grayscale(baseFrame.originalFrame.image, width: config.downscaleWidth) else {
            out.warnings.append("Putter head: not enough pre-impact frames for the diff pass.")
            return
        }
        let tracked = Array(preFrames.suffix(config.headFramesTracked))

        // ROI around the ball, wide along the target line (the head approaches along it).
        let r = max(ballRect.width, ballRect.height) / 2
        let bx = ballRect.midX, by = ballRect.midY
        let x0 = max(0, bx - 14 * r), x1 = min(1, bx + 14 * r)
        let y0 = max(0, by - 8 * r),  y1 = min(1, by + 8 * r)

        var centroids: [(t: Double, x: CGFloat, y: CGFloat)] = []   // inches
        var bestPixels: [(x: CGFloat, y: CGFloat)] = []              // inches, densest frame
        for frame in tracked {
            guard let cur = Self.grayscale(frame.originalFrame.image, width: config.downscaleWidth),
                  cur.h == base.h else { continue }
            var sx: Double = 0, sy: Double = 0, count = 0
            var px: [(CGFloat, CGFloat)] = []
            let pxX0 = Int(x0 * CGFloat(cur.w)), pxX1 = Int(x1 * CGFloat(cur.w))
            let pxY0 = Int(y0 * CGFloat(cur.h)), pxY1 = Int(y1 * CGFloat(cur.h))
            for yy in stride(from: pxY0, to: min(pxY1, cur.h), by: 1) {
                let row = yy * cur.w
                for xx in stride(from: pxX0, to: min(pxX1, cur.w), by: 1) {
                    let d = Int(cur.data[row + xx]) - Int(base.data[row + xx])
                    if abs(d) > config.headDiffThreshold {
                        let xN = CGFloat(xx) / CGFloat(cur.w)
                        let yN = CGFloat(yy) / CGFloat(cur.h)
                        // Ignore the ball's own disk — pre-impact jitter isn't the head.
                        let ddx = xN - bx, ddy = yN - by
                        if ddx * ddx + ddy * ddy < (2 * r) * (2 * r) { continue }
                        let xIn = xN * config.groundLengthInches
                        let yIn = yN * config.groundWidthInches
                        sx += Double(xIn); sy += Double(yIn); count += 1
                        px.append((xIn, yIn))
                    }
                }
            }
            guard count >= config.headMinPixels else { continue }
            // One-step trim: recompute the centroid from pixels near the first centroid so a
            // stray shadow at the ROI edge can't drag it.
            let cx0 = CGFloat(sx / Double(count)), cy0 = CGFloat(sy / Double(count))
            let trimRadius: CGFloat = 6.0   // inches
            let near = px.filter { hypot($0.0 - cx0, $0.1 - cy0) < trimRadius }
            guard near.count >= config.headMinPixels / 2 else { continue }
            let cx = near.map(\.0).reduce(0, +) / CGFloat(near.count)
            let cy = near.map(\.1).reduce(0, +) / CGFloat(near.count)
            centroids.append((t: frame.relativeTime, x: cx, y: cy))
            if near.count > bestPixels.count { bestPixels = near }
        }

        guard centroids.count >= config.minCentroids else {
            out.warnings.append("Putter head: too few clean frames (\(centroids.count)) — head metrics unavailable.")
            return
        }

        // Head speed + path from the centroid track.
        let vx = Self.lsqVelocity(centroids.map { ($0.t, $0.x) })
        let vy = Self.lsqVelocity(centroids.map { ($0.t, $0.y) })
        let speedMph = Double(hypot(vx, vy)) / 17.6
        if (0.5...15).contains(speedMph) {
            out.putterSpeedMph = speedMph
            // Path vs the target line (X axis), sign = +y to match HLA convention.
            out.putterPathDegreesSigned = Double(atan2(vy, abs(vx))) * 180 / .pi
        } else {
            out.warnings.append(String(format: "Putter head: fitted speed %.1f mph outside plausible range — withheld.", speedMph))
        }

        // Face angle from the head silhouette: viewed from the tripod's high angle the head is
        // elongated heel-to-toe, i.e. along the FACE line (square = perpendicular to the target
        // line). The silhouette's major axis orientation is therefore the face orientation.
        if bestPixels.count >= config.headMinPixels {
            let n = CGFloat(bestPixels.count)
            let mx = bestPixels.map(\.x).reduce(0, +) / n
            let my = bestPixels.map(\.y).reduce(0, +) / n
            var cxx: Double = 0, cyy: Double = 0, cxy: Double = 0
            for p in bestPixels {
                let dx = Double(p.x - mx), dy = Double(p.y - my)
                cxx += dx * dx; cyy += dy * dy; cxy += dx * dy
            }
            cxx /= Double(n); cyy /= Double(n); cxy /= Double(n)
            let tr = cxx + cyy
            let det = cxx * cyy - cxy * cxy
            let disc = max(0, tr * tr / 4 - det)
            let l1 = tr / 2 + disc.squareRoot()
            let l2 = max(tr / 2 - disc.squareRoot(), 1e-6)
            if l1 / l2 >= config.faceMinAspect {
                // Major-axis angle vs the Y axis (square face) — small signed tilt = face angle.
                let theta = 0.5 * atan2(2 * cxy, cxx - cyy)          // vs X axis
                var face = theta * 180 / .pi
                face += face < 0 ? 90 : -90                           // vs Y axis (square = 0)
                if abs(face) <= 25 {
                    out.faceAngleDegreesSigned = face
                    out.warnings.append("Putter face is estimated from the head silhouette orientation — treat direction as more trustworthy than magnitude.")
                } else {
                    out.warnings.append("Putter face: silhouette tilt implausible — withheld.")
                }
            } else {
                out.warnings.append("Putter face: head silhouette too round to read orientation.")
            }
        }
    }

    // MARK: - Fits & helpers

    /// Least-squares velocity (units/second) of position samples vs time.
    private static func lsqVelocity(_ samples: [(Double, CGFloat)]) -> CGFloat {
        let nD = Double(samples.count)
        guard nD >= 2 else { return 0 }
        let mt = samples.map(\.0).reduce(0, +) / nD
        let mv = samples.map { Double($0.1) }.reduce(0, +) / nD
        var num = 0.0, den = 0.0
        for (t, v) in samples {
            num += (t - mt) * (Double(v) - mv)
            den += (t - mt) * (t - mt)
        }
        return den > 0 ? CGFloat(num / den) : 0
    }

    /// LSQ fit of l = b·s + c·s²; returns (b, c, rmsResidual).
    private static func fitQuadratic(_ sl: [(s: CGFloat, l: CGFloat)]) -> (CGFloat, CGFloat, CGFloat)? {
        var s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0, sl1 = 0.0, sl2 = 0.0
        for p in sl {
            let s = Double(p.s), l = Double(p.l)
            s1 += s; s2 += s * s; s3 += s * s * s; s4 += s * s * s * s
            sl1 += s * l; sl2 += s * s * l
        }
        _ = s1
        let det = s2 * s4 - s3 * s3
        guard abs(det) > 1e-9 else { return nil }
        let b = (sl1 * s4 - sl2 * s3) / det
        let c = (sl2 * s2 - sl1 * s3) / det
        var ss = 0.0
        for p in sl {
            let e = Double(p.l) - (b * Double(p.s) + c * Double(p.s) * Double(p.s))
            ss += e * e
        }
        let rms = (ss / Double(sl.count)).squareRoot()
        return (CGFloat(b), CGFloat(c), CGFloat(rms))
    }

    /// Downscaled grayscale copy; respects UIImage orientation.
    private static func grayscale(_ image: UIImage, width: Int) -> (data: [UInt8], w: Int, h: Int)? {
        guard image.size.width > 0 else { return nil }
        let h = max(1, Int(CGFloat(width) * image.size.height / image.size.width))
        guard let ctx = CGContext(data: nil, width: width, height: h, bitsPerComponent: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(h)))
        UIGraphicsPopContext()
        guard let raw = ctx.data else { return nil }
        let data = [UInt8](Data(bytes: raw, count: width * h))
        return (data, width, h)
    }
}
