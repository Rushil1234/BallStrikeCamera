import SwiftUI

// MARK: - Coach diagrams
// Live, animated physics diagrams for the Ball Flight Lab — no videos, everything is
// drawn in Canvas and driven by sliders so the cause→effect is felt, not watched.
// Conventions: right-handed golfer, top-down views look downrange (up = target),
// positive angles point right of the target line.

// MARK: Face & Path (top-down)

/// Top-down view of the D-plane basics: the ball STARTS mostly where the face points
/// and CURVES away from the path. Face and path are slider-driven; the ball loops
/// its flight continuously.
struct FaceToPathDiagram: View {
    @Binding var faceDeg: Double    // face angle vs target line (+ = open/right)
    @Binding var pathDeg: Double    // swing path vs target line (+ = in-to-out/right)

    private var startDeg: Double { 0.85 * faceDeg + 0.15 * pathDeg }
    private var curveDeg: Double { faceDeg - pathDeg }   // + = curves right (fade/slice)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t: Double = timeline.date.timeIntervalSinceReferenceDate
                let phase: Double = (t.truncatingRemainder(dividingBy: 2.4)) / 2.4   // 0→1 flight loop
                let ball = CGPoint(x: size.width / 2, y: size.height - 34)
                let range: CGFloat = size.height - 70

                drawTargetLine(ctx, ball: ball, range: range)
                drawPathArrow(ctx, ball: ball)
                drawFaceBar(ctx, ball: ball)
                drawFlight(ctx, ball: ball, range: range, phase: phase)
            }
        }
    }

    private func drawTargetLine(_ ctx: GraphicsContext, ball: CGPoint, range: CGFloat) {
        var target = Path()
        target.move(to: ball)
        target.addLine(to: CGPoint(x: ball.x, y: ball.y - range))
        ctx.stroke(target, with: .color(TCTheme.textUltraMuted.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        ctx.draw(Text("TARGET").font(.system(size: 8, weight: .black)).foregroundColor(TCTheme.textUltraMuted),
                 at: CGPoint(x: ball.x, y: ball.y - range - 8))
    }

    private func drawPathArrow(_ ctx: GraphicsContext, ball: CGPoint) {
        let pr = Double.pi / 180
        let dx = CGFloat(sin(pathDeg * pr))
        let dy = CGFloat(-cos(pathDeg * pr))
        var pathLine = Path()
        pathLine.move(to: CGPoint(x: ball.x - dx * 46, y: ball.y - dy * 46))
        pathLine.addLine(to: CGPoint(x: ball.x + dx * 60, y: ball.y + dy * 60))
        ctx.stroke(pathLine, with: .color(TCTheme.sage), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        let tip = CGPoint(x: ball.x + dx * 60, y: ball.y + dy * 60)
        let px = -dy, py = dx     // perpendicular
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x - dx * 9 + px * 5, y: tip.y - dy * 9 + py * 5))
        arrow.addLine(to: CGPoint(x: tip.x - dx * 9 - px * 5, y: tip.y - dy * 9 - py * 5))
        arrow.closeSubpath()
        ctx.fill(arrow, with: .color(TCTheme.sage))
        ctx.draw(Text("PATH").font(.system(size: 8, weight: .black)).foregroundColor(TCTheme.sage),
                 at: CGPoint(x: tip.x + px * 16, y: tip.y + py * 16))
    }

    private func drawFaceBar(_ ctx: GraphicsContext, ball: CGPoint) {
        let pr = Double.pi / 180
        let fx = CGFloat(cos(faceDeg * pr))
        let fy = CGFloat(sin(faceDeg * pr))
        var face = Path()
        face.move(to: CGPoint(x: ball.x - fx * 22, y: ball.y + 10 - fy * 22))
        face.addLine(to: CGPoint(x: ball.x + fx * 22, y: ball.y + 10 + fy * 22))
        ctx.stroke(face, with: .color(TCTheme.goldLight), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        ctx.draw(Text("FACE").font(.system(size: 8, weight: .black)).foregroundColor(TCTheme.goldLight),
                 at: CGPoint(x: ball.x + fx * 34, y: ball.y + 10 + fy * 34))
    }

    /// Quadratic Bezier point for flight fraction u.
    private func flightPoint(_ u: CGFloat, ball: CGPoint, ctrl: CGPoint, end: CGPoint) -> CGPoint {
        let o = 1 - u
        let x = o * o * ball.x + 2 * o * u * ctrl.x + u * u * end.x
        let y = o * o * ball.y + 2 * o * u * ctrl.y + u * u * end.y
        return CGPoint(x: x, y: y)
    }

    private func drawFlight(_ ctx: GraphicsContext, ball: CGPoint, range: CGFloat, phase: Double) {
        // Launches on the start line, bends toward (face − path).
        let sr = startDeg * Double.pi / 180
        let sinS = CGFloat(sin(sr)), cosS = CGFloat(cos(sr))
        let ctrl = CGPoint(x: ball.x + 0.5 * range * sinS, y: ball.y - 0.5 * range * cosS)
        let end = CGPoint(x: ball.x + range * sinS + CGFloat(curveDeg) * 7.5, y: ball.y - range * cosS)

        var flight = Path()
        flight.move(to: ball)
        flight.addQuadCurve(to: end, control: ctrl)
        ctx.stroke(flight, with: .color(TCTheme.textPrimary.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 2, dash: [3, 4]))

        // Animated ball + fading trail
        let u = CGFloat(phase)
        var trail = Path()
        trail.move(to: flightPoint(max(0, u - 0.25), ball: ball, ctrl: ctrl, end: end))
        for i in stride(from: max(0, u - 0.25), through: u, by: 0.02) {
            trail.addLine(to: flightPoint(i, ball: ball, ctrl: ctrl, end: end))
        }
        ctx.stroke(trail, with: .color(TCTheme.textPrimary.opacity(0.65)),
                   style: StrokeStyle(lineWidth: 3, lineCap: .round))

        let bp = flightPoint(u, ball: ball, ctrl: ctrl, end: end)
        ctx.fill(Path(ellipseIn: CGRect(x: bp.x - 5, y: bp.y - 5, width: 10, height: 10)),
                 with: .color(TCTheme.textPrimary))
        ctx.fill(Path(ellipseIn: CGRect(x: ball.x - 5, y: ball.y - 5, width: 10, height: 10)),
                 with: .color(TCTheme.textPrimary.opacity(0.9)))
    }

    /// Plain-language name for the current face/path combination ("Push draw", "Slice"…).
    static func shotName(face: Double, path: Double) -> String {
        let start = 0.85 * face + 0.15 * path
        let curve = face - path
        let startWord: String = start < -1.5 ? "Pull" : (start > 1.5 ? "Push" : "")
        let curveWord: String
        switch curve {
        case ..<(-4.5): curveWord = "hook"
        case -4.5 ..< -1.5: curveWord = "draw"
        case -1.5 ... 1.5: curveWord = "straight ball"
        case 1.5 ... 4.5: curveWord = "fade"
        default: curveWord = "slice"
        }
        if startWord.isEmpty { return curveWord.capitalized }
        return "\(startWord) \(curveWord == "straight ball" ? "— dead straight" : curveWord)"
    }

    /// One-sentence physics explanation of the current setting.
    static func explanation(face: Double, path: Double) -> String {
        let curve = face - path
        if abs(curve) <= 1.5 && abs(face) <= 1.5 {
            return "Face and path match and both point at the target — the ball starts on line and stays there. This is the move everything else is measured against."
        }
        if abs(curve) <= 1.5 {
            return "Face and path match, so there's no curve — but both point \(face > 0 ? "right" : "left"), so the ball flies dead straight on the wrong line. Aim, not swing, is the fix."
        }
        let dir = curve > 0 ? "right" : "left"
        let feel = curve > 0 ? "face open to the path (or path too far left — over the top)" : "face closed to the path (or path too far in-to-out)"
        return "The face is \(String(format: "%.0f", abs(curve)))° \(curve > 0 ? "open" : "closed") to the path, so spin tilts the flight \(dir). The ball starts near the face line, then curves \(dir) — \(feel)."
    }
}

// MARK: Launch & Spin (side view)

/// Side-on trajectory: launch angle and spin rate drive a tiny flight sim, so the
/// height/carry trade-off (and the ballooning wedge / diving bullet) is visible live.
struct LaunchSpinDiagram: View {
    @Binding var launchDeg: Double     // 6…40
    @Binding var spinRPM: Double       // 1500…10000

    /// Simple flight integration — qualitative, tuned to look right, not a launch model.
    static func trajectory(launchDeg: Double, spinRPM: Double) -> [CGPoint] {
        var pts: [CGPoint] = []
        let v0 = 62.0                                   // m/s, fixed "7-iron-ish" speed
        var vx = v0 * cos(launchDeg * .pi / 180)
        var vy = v0 * sin(launchDeg * .pi / 180)
        var x = 0.0, y = 0.0
        let dt = 0.04
        var steps = 0
        while y >= 0 && steps < 500 {
            pts.append(CGPoint(x: x, y: y))
            let v = max(1.0, (vx * vx + vy * vy).squareRoot())
            let lift = min(14.0, 9.8 * (spinRPM / 6500.0) * (v / v0))   // Magnus, capped
            let drag = 0.055 * v                                        // linear-ish drag
            vx -= (drag * vx / v) * dt
            vy += (lift - 9.8 - drag * vy / v) * dt
            x += vx * dt
            y += vy * dt
            steps += 1
        }
        return pts
    }

    private struct Scale {
        let ground: CGFloat
        let sx: CGFloat
        let sy: CGFloat
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: 15 + p.x * sx, y: ground - p.y * sy)
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t: Double = timeline.date.timeIntervalSinceReferenceDate
                let phase: Double = (t.truncatingRemainder(dividingBy: 2.6)) / 2.6
                let pts = Self.trajectory(launchDeg: launchDeg, spinRPM: spinRPM)
                guard pts.count > 2 else { return }
                // Fixed world scale (220 "yards" × 80 up) so carry differences SHOW.
                let scale = Scale(ground: size.height - 22,
                                  sx: (size.width - 30) / 220,
                                  sy: (size.height - 40) / 80)

                drawGround(ctx, size: size, scale: scale)
                drawTrajectory(ctx, pts: pts, scale: scale, phase: phase)
            }
        }
    }

    private func drawGround(_ ctx: GraphicsContext, size: CGSize, scale: Scale) {
        var g = Path()
        g.move(to: CGPoint(x: 0, y: scale.ground))
        g.addLine(to: CGPoint(x: size.width, y: scale.ground))
        ctx.stroke(g, with: .color(TCTheme.sage.opacity(0.6)), lineWidth: 1.5)

        for d: CGFloat in [50, 100, 150, 200] {
            let x = 15 + d * scale.sx
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: scale.ground))
            tick.addLine(to: CGPoint(x: x, y: scale.ground + 5))
            ctx.stroke(tick, with: .color(TCTheme.textUltraMuted), lineWidth: 1)
            ctx.draw(Text("\(Int(d))").font(.system(size: 8, weight: .semibold)).foregroundColor(TCTheme.textUltraMuted),
                     at: CGPoint(x: x, y: scale.ground + 12))
        }

        // Launch-angle wedge at origin
        let o = scale.map(.zero)
        let a = launchDeg * Double.pi / 180
        var wedge = Path()
        wedge.move(to: o)
        wedge.addLine(to: CGPoint(x: o.x + 42, y: o.y))
        wedge.move(to: o)
        wedge.addLine(to: CGPoint(x: o.x + 42 * CGFloat(cos(a)),
                                  y: o.y - 42 * CGFloat(sin(a)) * (scale.sy / scale.sx)))
        ctx.stroke(wedge, with: .color(TCTheme.goldLight.opacity(0.8)), lineWidth: 1.5)
    }

    private func drawTrajectory(_ ctx: GraphicsContext, pts: [CGPoint], scale: Scale, phase: Double) {
        var traj = Path()
        traj.move(to: scale.map(pts[0]))
        for p in pts.dropFirst() { traj.addLine(to: scale.map(p)) }
        ctx.stroke(traj, with: .color(TCTheme.textPrimary.opacity(0.4)),
                   style: StrokeStyle(lineWidth: 2, dash: [3, 4]))

        // Carry marker on the ground
        if let last = pts.last {
            let lp = scale.map(last)
            ctx.fill(Path(ellipseIn: CGRect(x: lp.x - 3, y: scale.ground - 3, width: 6, height: 6)),
                     with: .color(TCTheme.gold))
        }

        // Animated ball + trail
        let idx = min(pts.count - 1, Int(Double(pts.count - 1) * phase))
        let back = max(0, idx - 10)
        var trail = Path()
        trail.move(to: scale.map(pts[back]))
        for i in back...idx { trail.addLine(to: scale.map(pts[i])) }
        ctx.stroke(trail, with: .color(TCTheme.textPrimary.opacity(0.65)),
                   style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let bp = scale.map(pts[idx])
        ctx.fill(Path(ellipseIn: CGRect(x: bp.x - 5, y: bp.y - 5, width: 10, height: 10)),
                 with: .color(TCTheme.textPrimary))
    }

    static func explanation(launchDeg: Double, spinRPM: Double) -> String {
        switch (launchDeg, spinRPM) {
        case (..<14, ..<2800):
            return "Low launch with low spin — the ball can't stay airborne and dives. Long rollout, but carry collapses; this is the thin strike or the de-lofted driver."
        case (..<14, _):
            return "Low launch, high spin — the ball takes off like a bullet then climbs late as spin lifts it. Penetrating but the spin bleeds distance up high."
        case (26..., 6000...):
            return "High launch AND high spin — the ballooning wedge. It climbs steeply, stalls against the wind, and drops almost vertically. Great for stopping power, terrible for distance."
        case (26..., _):
            return "High launch with modest spin — a tall, efficient flight. This is the modern driver recipe: launch it high, spin it low, let gravity do the landing."
        default:
            return "Mid launch and mid spin — the classic iron window. Enough spin to hold its line and the green, enough launch to carry trouble."
        }
    }
}

// MARK: Strike point / gear effect (face view + resulting curve)

/// Face-on impact location with the resulting gear-effect curve: toe strikes close the
/// spin axis (draw), heel strikes open it (fade) — the reason a miss curves even with a
/// square face and path.
struct GearEffectDiagram: View {
    @Binding var strike: Double     // −1 heel … +1 toe

    var body: some View {
        HStack(spacing: 18) {
            // Clubface, face-on, with the impact mark
            Canvas { ctx, size in
                let faceRect = CGRect(x: 8, y: size.height * 0.25, width: size.width - 16, height: size.height * 0.5)
                let face = Path(roundedRect: faceRect, cornerRadius: 10)
                ctx.stroke(face, with: .color(TCTheme.textMuted), lineWidth: 2)
                // grooves
                for i in 1...4 {
                    let y = faceRect.minY + faceRect.height * CGFloat(i) / 5
                    var line = Path()
                    line.move(to: CGPoint(x: faceRect.minX + 10, y: y))
                    line.addLine(to: CGPoint(x: faceRect.maxX - 10, y: y))
                    ctx.stroke(line, with: .color(TCTheme.textMuted.opacity(0.3)), lineWidth: 1)
                }
                ctx.draw(Text("HEEL").font(.system(size: 8, weight: .black)).foregroundColor(TCTheme.textUltraMuted),
                         at: CGPoint(x: faceRect.minX + 14, y: faceRect.maxY + 12))
                ctx.draw(Text("TOE").font(.system(size: 8, weight: .black)).foregroundColor(TCTheme.textUltraMuted),
                         at: CGPoint(x: faceRect.maxX - 14, y: faceRect.maxY + 12))
                // sweet spot
                let cx = faceRect.midX
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - 3, y: faceRect.midY - 3, width: 6, height: 6)),
                           with: .color(TCTheme.textUltraMuted), lineWidth: 1)
                // impact mark
                let ix = cx + CGFloat(strike) * (faceRect.width / 2 - 18)
                ctx.fill(Path(ellipseIn: CGRect(x: ix - 7, y: faceRect.midY - 7, width: 14, height: 14)),
                         with: .color(TCTheme.gold.opacity(0.85)))
            }
            .frame(maxWidth: .infinity)

            // Resulting curve, reusing the top-down flight (square face & path, gear-effect tilt)
            FaceToPathDiagram(faceDeg: .constant(0), pathDeg: .constant(strike * 5.5))
                .frame(maxWidth: .infinity)
        }
    }

    static func explanation(strike: Double) -> String {
        if abs(strike) < 0.2 {
            return "Center strike — no gear effect, all the energy goes into the ball (best smash factor), and the face/path numbers tell the whole story."
        }
        if strike > 0 {
            return "Toe strike — at impact the head twists open around its center of gravity and the ball 'gears' the other way, tilting spin into a draw/hook. Also costs ball speed: the classic toe-hook that flies short and left."
        }
        return "Heel strike — the head twists closed, the ball gears toward fade/slice spin, and speed drops. On a driver this is the weak slice that starts okay and leaks right."
    }
}

// MARK: - Grip (illustrated, replaces the old procedural 3D grip scene)

/// Instructional grip illustration in the house diagram style: an open lead hand with the
/// grip running diagonally through the fingers, then the golfer's own view looking down
/// (knuckle count + V direction). The live camera step does the "with you" half.
struct GripDiagram: View {
    enum Variant {
        case neutral, strong

        init?(asset: String?) {
            switch asset {
            case "grip_interlock": self = .neutral
            case "grip_strong":    self = .strong
            default: return nil
            }
        }
    }

    let variant: Variant

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GripHologramDemo()
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("TAKE THE GRIP")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.1)
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.08)))
                        .padding(8)
                }
            Text("Fingers wrap the back of the grip first, thumb pads stack on top, and the trail pinky interlocks the lead index — one unit, 5/10 pressure.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(TCTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            panel(label: "YOUR VIEW AT ADDRESS") {
                GripKnuckleIllustration(strong: variant == .strong)
                    .frame(height: 170)
            }
            Text(variant == .strong
                 ? "Rotate the lead hand until a third knuckle shows and the V points outside your trail shoulder — same fingers, same pressure. That's the slice-fixing strong grip."
                 : "Close your hands and look down: two knuckles on the lead hand, and the thumb-and-index V points at your trail shoulder.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(TCTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func panel<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TCTheme.panelDeep.opacity(0.6))
            )
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.1)
                    .foregroundColor(TCTheme.textUltraMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(TCTheme.panelRaised))
                    .padding(8)
            }
    }
}

// MARK: - Ghost hand artwork (visionOS-style translucent hands, parametric)

/// Shared translucent-hand renderer: an OPEN floating pose (back of hand, fingers up)
/// and a GRIP pose (hand wrapped on a vertical shaft, thumb down it). Geometry is
/// parametric — tapered fingers along bending centerlines — with gradient fill,
/// blurred rim light, tendon hints. Drawn in a local frame the caller transforms.
enum GhostHandArt {

    struct Finger {
        let base: CGPoint
        let angleDeg: Double      // 0° = straight up, + tilts right
        let bendDeg: Double       // direction change base→tip
        let length: CGFloat
        let baseW: CGFloat
        let tipW: CGFloat
    }

    enum Pose { case open, grip }

    struct Style {
        let gradient: Gradient
        let rim: Color
        let rimOpacity: Double
        let detail: Bool          // tendon + knuckle sheen passes

        static let realistic = Style(
            gradient: Gradient(colors: [Color(red: 0.29, green: 0.32, blue: 0.38),
                                        Color(red: 0.21, green: 0.24, blue: 0.28),
                                        Color(red: 0.14, green: 0.15, blue: 0.18)]),
            rim: Color(red: 0.87, green: 0.90, blue: 0.95), rimOpacity: 0.5, detail: true)

        static func tinted(_ c: Color) -> Style {
            Style(gradient: Gradient(colors: [c.opacity(0.95), c.opacity(0.68)]),
                  rim: .white, rimOpacity: 0.65, detail: false)
        }
    }

    // Open pose: left hand, back view, fingers up, thumb merged into the palm outline.
    static let openFingers: [Finger] = [
        Finger(base: CGPoint(x: -44, y: -24), angleDeg: -17, bendDeg: -5, length: 76, baseW: 20, tipW: 14),
        Finger(base: CGPoint(x: -23, y: -37), angleDeg: -7, bendDeg: -3, length: 98, baseW: 21.5, tipW: 15),
        Finger(base: CGPoint(x: 3, y: -41), angleDeg: 1, bendDeg: -2, length: 106, baseW: 22, tipW: 15.5),
        Finger(base: CGPoint(x: 28, y: -33), angleDeg: 10, bendDeg: 3, length: 94, baseW: 21, tipW: 15),
    ]

    // Grip pose: shaft runs vertically through local x ≈ +12; back of hand to its left,
    // four curled finger stubs folding over it, thumb running down the near side.
    static let gripFingers: [Finger] = [
        Finger(base: CGPoint(x: 4, y: -30), angleDeg: 92, bendDeg: 72, length: 34, baseW: 19, tipW: 13),
        Finger(base: CGPoint(x: 8, y: -12), angleDeg: 90, bendDeg: 76, length: 38, baseW: 20, tipW: 13.5),
        Finger(base: CGPoint(x: 8, y: 6), angleDeg: 90, bendDeg: 76, length: 36, baseW: 20, tipW: 13),
        Finger(base: CGPoint(x: 4, y: 24), angleDeg: 94, bendDeg: 70, length: 30, baseW: 18, tipW: 12.5),
        Finger(base: CGPoint(x: 0, y: -30), angleDeg: 176, bendDeg: -8, length: 56, baseW: 22, tipW: 15),
    ]

    /// Open-pose outline: wrist-left → pinky edge → knuckle arc → web dip → out the
    /// thumb → thenar → wrist-right. One continuous silhouette so nothing seams.
    /// Left UNCLOSED: fill implicitly closes across the wrist, stroke stays open.
    static let openPalm: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -28, y: 62))
        p.addCurve(to: CGPoint(x: -45, y: -26), control1: CGPoint(x: -46, y: 40), control2: CGPoint(x: -52, y: 2))
        p.addCurve(to: CGPoint(x: -27, y: -42), control1: CGPoint(x: -41, y: -32), control2: CGPoint(x: -35, y: -38))
        p.addCurve(to: CGPoint(x: 29, y: -38), control1: CGPoint(x: -9, y: -50), control2: CGPoint(x: 14, y: -49))
        p.addCurve(to: CGPoint(x: 37, y: -16), control1: CGPoint(x: 33, y: -32), control2: CGPoint(x: 35, y: -24))
        p.addCurve(to: CGPoint(x: 94, y: -52), control1: CGPoint(x: 54, y: -26), control2: CGPoint(x: 76, y: -40))
        p.addCurve(to: CGPoint(x: 101, y: -37), control1: CGPoint(x: 103, y: -57), control2: CGPoint(x: 111, y: -45))
        p.addCurve(to: CGPoint(x: 56, y: 8), control1: CGPoint(x: 88, y: -28), control2: CGPoint(x: 70, y: -8))
        p.addCurve(to: CGPoint(x: 28, y: 62), control1: CGPoint(x: 50, y: 22), control2: CGPoint(x: 42, y: 42))
        return p
    }()

    static let gripPalm: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -52, y: -30))
        p.addCurve(to: CGPoint(x: 14, y: -34), control1: CGPoint(x: -30, y: -42), control2: CGPoint(x: 6, y: -42))
        p.addCurve(to: CGPoint(x: 20, y: 6), control1: CGPoint(x: 20, y: -24), control2: CGPoint(x: 22, y: -8))
        p.addCurve(to: CGPoint(x: 4, y: 38), control1: CGPoint(x: 18, y: 22), control2: CGPoint(x: 14, y: 32))
        p.addCurve(to: CGPoint(x: -50, y: 28), control1: CGPoint(x: -14, y: 44), control2: CGPoint(x: -40, y: 40))
        p.addCurve(to: CGPoint(x: -52, y: -30), control1: CGPoint(x: -56, y: 8), control2: CGPoint(x: -56, y: -14))
        return p
    }()

    static let openFingerPaths: [(fill: Path, stroke: Path)] = openFingers.map(fingerPaths)
    static let gripFingerPaths: [(fill: Path, stroke: Path)] = gripFingers.map(fingerPaths)

    /// Tapered finger along a quadratic-bend centerline. The stroke path skips the
    /// first samples so finger edges fade out inside the palm instead of seaming.
    static func fingerPaths(_ f: Finger) -> (fill: Path, stroke: Path) {
        let samples = 14
        var centers: [CGPoint] = []
        var dirs: [Double] = []
        var x = f.base.x, y = f.base.y
        let a0 = f.angleDeg * .pi / 180
        let bend = f.bendDeg * .pi / 180
        for i in 0...samples {
            let a = a0 + bend * Double(i) / Double(samples)
            dirs.append(a)
            if i > 0 {
                let step = f.length / CGFloat(samples)
                x += CGFloat(sin(a)) * step
                y -= CGFloat(cos(a)) * step
            }
            centers.append(CGPoint(x: x, y: y))
        }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let w = (f.baseW + (f.tipW - f.baseW) * t) / 2
            let n = CGPoint(x: CGFloat(cos(dirs[i])), y: CGFloat(sin(dirs[i])))
            left.append(CGPoint(x: centers[i].x - n.x * w, y: centers[i].y - n.y * w))
            right.append(CGPoint(x: centers[i].x + n.x * w, y: centers[i].y + n.y * w))
        }
        let aTip = dirs[samples]
        let tip = centers[samples]
        let r = f.tipW / 2
        let u = CGPoint(x: CGFloat(sin(aTip)), y: CGFloat(-cos(aTip)))
        let n = CGPoint(x: CGFloat(cos(aTip)), y: CGFloat(sin(aTip)))
        var arc: [CGPoint] = []
        for i in 0...10 {
            let th = Double(i) / 10 * .pi
            arc.append(CGPoint(x: tip.x + n.x * CGFloat(-cos(th)) * r + u.x * CGFloat(sin(th)) * r,
                               y: tip.y + n.y * CGFloat(-cos(th)) * r + u.y * CGFloat(sin(th)) * r))
        }
        var fill = Path()
        fill.addLines(left + arc + right.reversed())
        fill.closeSubpath()
        var stroke = Path()
        stroke.addLines(Array(left.dropFirst(3)) + arc + Array(right.reversed().dropLast(3)))
        return (fill, stroke)
    }

    /// Draw one hand in its local frame (caller applies translate/rotate/scale first).
    static func draw(_ ctx: GraphicsContext, pose: Pose, style: Style, alpha: Double = 1) {
        guard alpha > 0.01 else { return }
        let palm = pose == .open ? openPalm : gripPalm
        let fingers = pose == .open ? openFingerPaths : gripFingerPaths
        let shadeSpan: (CGPoint, CGPoint) = pose == .open
            ? (CGPoint(x: 0, y: -150), CGPoint(x: 0, y: 110))
            : (CGPoint(x: 0, y: -64), CGPoint(x: 0, y: 64))
        let shading = GraphicsContext.Shading.linearGradient(
            style.gradient, startPoint: shadeSpan.0, endPoint: shadeSpan.1)

        var base = ctx
        base.opacity = alpha

        // Forearm stub fading out (down for open pose, out to the left for grip pose).
        var stub = base
        let stubColor = style.gradient.stops.last?.color ?? .black
        if pose == .open {
            stub.fill(Path(roundedRect: CGRect(x: -28, y: 54, width: 56, height: 52), cornerRadius: 16),
                      with: .linearGradient(Gradient(colors: [stubColor, stubColor.opacity(0)]),
                                            startPoint: CGPoint(x: 0, y: 54), endPoint: CGPoint(x: 0, y: 106)))
        } else {
            stub.fill(Path(roundedRect: CGRect(x: -104, y: -24, width: 66, height: 52), cornerRadius: 17),
                      with: .linearGradient(Gradient(colors: [stubColor.opacity(0), stubColor]),
                                            startPoint: CGPoint(x: -104, y: 0), endPoint: CGPoint(x: -38, y: 0)))
        }

        // Fill pass: palm + fingers share one gradient → reads as a single mass.
        var fillCtx = base
        fillCtx.addFilter(.blur(radius: 0.6))
        fillCtx.fill(palm, with: shading)
        for f in fingers { fillCtx.fill(f.fill, with: shading) }

        // Detail pass: tendons + knuckle sheen.
        if style.detail {
            var detail = base
            detail.addFilter(.blur(radius: 3))
            if pose == .open {
                detail.opacity = alpha * 0.07
                for f in openFingers {
                    var tendon = Path()
                    tendon.move(to: CGPoint(x: 2, y: 52))
                    tendon.addQuadCurve(to: f.base,
                                        control: CGPoint(x: f.base.x * 0.55, y: f.base.y * 0.4 + 20))
                    detail.stroke(tendon, with: .color(style.rim), lineWidth: 5)
                }
                detail.opacity = alpha * 0.10
                for f in openFingers {
                    detail.fill(Path(ellipseIn: CGRect(x: f.base.x - 8, y: f.base.y - 7, width: 16, height: 10)),
                                with: .color(style.rim))
                }
            } else {
                detail.opacity = alpha * 0.12
                for k in [CGPoint(x: 8, y: -28), CGPoint(x: 12, y: -10),
                          CGPoint(x: 12, y: 8), CGPoint(x: 8, y: 26)] {
                    detail.fill(Path(ellipseIn: CGRect(x: k.x - 7, y: k.y - 5, width: 14, height: 10)),
                                with: .color(style.rim))
                }
            }
        }

        // Rim-light pass: blurred bright edges (open paths, so no hard seams).
        var rim = base
        rim.opacity = alpha * style.rimOpacity
        rim.addFilter(.blur(radius: 1.4))
        rim.stroke(palm, with: .color(style.rim), lineWidth: 1.6)
        for f in fingers { rim.stroke(f.stroke, with: .color(style.rim), lineWidth: 1.4) }
    }
}

// MARK: - Grip demo stage (the "hands take the grip" loop for the lesson page)

/// Dark-stage animation: two translucent hands float in open — visionOS style — then
/// travel onto the club and close around the grip, lead hand first, trail hand stacking
/// underneath. Loops forever; caption chip narrates each beat.
struct GripHandsDemo: View {
    // Stage design space 480×420; the club runs butt → head at address angle.
    private let butt = CGPoint(x: 118, y: 36)
    private let head = CGPoint(x: 400, y: 330)

    private func along(_ t: CGFloat) -> CGPoint {
        CGPoint(x: butt.x + (head.x - butt.x) * t, y: butt.y + (head.y - butt.y) * t)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let s = min(size.width / 480, size.height / 420)
                ctx.translateBy(x: (size.width - 480 * s) / 2, y: (size.height - 420 * s) / 2)
                ctx.scaleBy(x: s, y: s)

                let t = timeline.date.timeIntervalSinceReferenceDate
                let p = (t / 6.0).truncatingRemainder(dividingBy: 1)
                let fadeAll = p > 0.93 ? max(0, (1 - p) / 0.07) : min(1, p / 0.06)

                drawClub(ctx)

                let shaftDeg = Double(atan2(head.y - butt.y, head.x - butt.x)) * 180 / .pi
                // Lead hand: floats at the left, travels to the top of the grip.
                drawHand(ctx, t: t, p: p, fadeAll: fadeAll,
                         travel: (0.10, 0.32),
                         from: (CGPoint(x: 128, y: 228), -10, 0.44),
                         to: (along(0.15), shaftDeg - 90, 0.62),
                         mirrored: false, bobPhase: 0)
                // Trail hand: floats at the right, stacks snug underneath.
                drawHand(ctx, t: t, p: p, fadeAll: fadeAll,
                         travel: (0.36, 0.58),
                         from: (CGPoint(x: 368, y: 212), 12, 0.44),
                         to: (along(0.29), shaftDeg - 90, 0.62),
                         mirrored: true, bobPhase: 1.9)

                // Settle beat: gold "no gap" tick between the stacked hands.
                if p > 0.62 && p < 0.93 {
                    let a = min(1, (p - 0.62) / 0.05) * fadeAll
                    let mid = along(0.22)
                    var tick = Path()
                    tick.move(to: CGPoint(x: mid.x + 34, y: mid.y - 26))
                    tick.addLine(to: CGPoint(x: mid.x + 42, y: mid.y - 18))
                    tick.addLine(to: CGPoint(x: mid.x + 56, y: mid.y - 36))
                    ctx.stroke(tick, with: .color(TCTheme.gold.opacity(a)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                drawCaption(ctx, p: p, fadeAll: fadeAll)
            }
        }
        .background(Color(red: 0.078, green: 0.094, blue: 0.122))
    }

    private func drawClub(_ ctx: GraphicsContext) {
        // Ground spotlight.
        ctx.fill(Path(ellipseIn: CGRect(x: 70, y: 334, width: 380, height: 68)),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.22).opacity(0.9),
                                                         Color.clear]),
                                       center: CGPoint(x: 260, y: 368), startRadius: 0, endRadius: 190))
        // Shaft (below the grip) with a metallic sheen.
        var shaft = Path()
        shaft.move(to: along(0.5))
        shaft.addLine(to: head)
        ctx.stroke(shaft, with: .linearGradient(Gradient(colors: [Color(red: 0.54, green: 0.58, blue: 0.64),
                                                                  Color(red: 0.29, green: 0.31, blue: 0.36)]),
                                                startPoint: along(0.5), endPoint: head),
                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
        // Iron blade at the bottom.
        let deg = Double(atan2(head.y - butt.y, head.x - butt.x)) * 180 / .pi
        var blade = Path()
        blade.move(to: CGPoint(x: -4, y: -7))
        blade.addCurve(to: CGPoint(x: 22, y: 4), control1: CGPoint(x: 10, y: -9), control2: CGPoint(x: 20, y: -4))
        blade.addCurve(to: CGPoint(x: 6, y: 11), control1: CGPoint(x: 23, y: 9), control2: CGPoint(x: 16, y: 12))
        blade.addLine(to: CGPoint(x: -4, y: 7))
        blade.closeSubpath()
        blade = blade.applying(CGAffineTransform(translationX: head.x, y: head.y)
            .rotated(by: CGFloat(deg * .pi / 180)))
        ctx.fill(blade, with: .color(Color(red: 0.23, green: 0.25, blue: 0.31)))
        // Grip section: dark rubber with texture rows, butt cap above the hands.
        var grip = Path()
        grip.move(to: butt)
        grip.addLine(to: along(0.5))
        ctx.stroke(grip, with: .color(Color(red: 0.11, green: 0.12, blue: 0.15)),
                   style: StrokeStyle(lineWidth: 15, lineCap: .round))
        ctx.stroke(grip, with: .color(Color(red: 0.23, green: 0.26, blue: 0.31).opacity(0.7)),
                   style: StrokeStyle(lineWidth: 15, lineCap: .round, dash: [1.5, 6]))
        ctx.stroke(Path(ellipseIn: CGRect(x: butt.x - 9, y: butt.y - 9, width: 18, height: 18)),
                   with: .color(Color(red: 0.29, green: 0.32, blue: 0.38)), lineWidth: 2.5)
    }

    /// One hand across the whole loop: float (bobbing, open) → travel (open, turning
    /// to the shaft) → crossfade to the grip pose as it lands → hold.
    private func drawHand(_ ctx: GraphicsContext, t: TimeInterval, p: Double, fadeAll: Double,
                          travel: (Double, Double),
                          from: (CGPoint, Double, CGFloat),
                          to: (CGPoint, Double, CGFloat),
                          mirrored: Bool, bobPhase: Double) {
        let progress = min(max((p - travel.0) / (travel.1 - travel.0), 0), 1)
        let eased = progress * progress * (3 - 2 * progress)   // smoothstep
        let gripFrac = min(max((progress - 0.7) / 0.3, 0), 1)

        let bob = (1 - eased) * 4 * sin(t * 1.3 + bobPhase)
        let pos = CGPoint(x: from.0.x + (to.0.x - from.0.x) * CGFloat(eased),
                          y: from.0.y + (to.0.y - from.0.y) * CGFloat(eased) + CGFloat(bob))
        let rot = from.1 + (to.1 - from.1) * eased
        // Settle pulse just after both hands land.
        let pulse: CGFloat = (0.60...0.68).contains(p) ? 1 + 0.04 * CGFloat(sin(.pi * (p - 0.60) / 0.08)) : 1

        var c = ctx
        c.translateBy(x: pos.x, y: pos.y)
        c.rotate(by: .degrees(rot))
        // The two artworks live at different local sizes (open hand ≈ 256 units tall,
        // wrapped hand ≈ 90) — the open hand shrinks toward matching VISUAL size while it
        // travels, and the crossfade dips through transparency so the pose (and the trail
        // hand's mirror) switches while nearly invisible instead of popping.
        let openLand = to.2 * (90.0 / 256.0) * 1.2   // slightly larger than the fist it becomes
        let openScale = (from.2 + (openLand - from.2) * CGFloat(eased)) * pulse
        let gripScale = to.2 * pulse
        let openAlpha = (1 - min(1, gripFrac / 0.6)) * fadeAll
        let gripAlpha = max(0, (gripFrac - 0.4) / 0.6) * fadeAll
        if openAlpha > 0.01 {
            var open = c
            open.scaleBy(x: mirrored ? -openScale : openScale, y: openScale)
            GhostHandArt.draw(open, pose: .open, style: .realistic, alpha: openAlpha)
        }
        if gripAlpha > 0.01 {
            var grip = c
            grip.scaleBy(x: gripScale, y: gripScale)
            grip.translateBy(x: -14, y: 0)   // center the wrapped hand on the shaft line
            GhostHandArt.draw(grip, pose: .grip, style: .realistic, alpha: gripAlpha)
        }
    }

    private func drawCaption(_ ctx: GraphicsContext, p: Double, fadeAll: Double) {
        let caption: String
        switch p {
        case ..<0.34:  caption = "Lead hand first — fingers wrap, thumb pad on top"
        case ..<0.60:  caption = "Trail hand — thumb covers the lead thumbnail"
        default:       caption = "Interlock pinky + index — 5/10 pressure"
        }
        let text = ctx.resolve(Text(caption).font(.system(size: 15, weight: .bold))
            .foregroundColor(.white.opacity(0.92)))
        let sz = text.measure(in: CGSize(width: 440, height: 60))
        let rect = CGRect(x: 240 - sz.width / 2 - 14, y: 384 - sz.height / 2 - 8,
                          width: sz.width + 28, height: sz.height + 16)
        var c = ctx
        c.opacity = fadeAll
        c.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2),
               with: .color(.black.opacity(0.45)))
        c.draw(text, at: CGPoint(x: 240, y: 384))
    }
}

/// Looking-down view: closed lead hand on the grip with the knuckle count (2 = neutral,
/// 3 = strong) and the thumb-index V pointing at the trail shoulder.
private struct GripKnuckleIllustration: View {
    let strong: Bool

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 320, size.height / 170)
            ctx.translateBy(x: (size.width - 320 * s) / 2, y: (size.height - 170 * s) / 2)
            ctx.scaleBy(x: s, y: s)

            let ink = TCTheme.textPrimary
            let handFill = ink.opacity(0.10)
            let outline = ink.opacity(0.72)

            // Shaft running away, down-right, to a small clubhead.
            let shaft = fingerCapsule(from: CGPoint(x: 172, y: 96), to: CGPoint(x: 262, y: 156), width: 5)
            ctx.fill(shaft, with: .color(ink.opacity(0.35)))
            var head = Path(ellipseIn: CGRect(x: -15, y: -7, width: 30, height: 14))
            head = head.applying(CGAffineTransform(translationX: 268, y: 159).rotated(by: 0.6))
            ctx.fill(head, with: .color(ink.opacity(0.4)))

            // Grip section under the hands.
            let grip = fingerCapsule(from: CGPoint(x: 136, y: 62), to: CGPoint(x: 176, y: 100), width: 17)
            ctx.fill(grip, with: .color(ink.opacity(0.25)))
            ctx.stroke(grip, with: .color(outline.opacity(0.7)), lineWidth: 1.3)
            // Butt cap, nearly end-on.
            ctx.fill(Path(ellipseIn: CGRect(x: 126, y: 51, width: 19, height: 19)), with: .color(ink.opacity(0.3)))
            ctx.stroke(Path(ellipseIn: CGRect(x: 126, y: 51, width: 19, height: 19)), with: .color(outline), lineWidth: 1.3)

            // Lead-hand fist wrapped on the grip (back of the glove toward you).
            var fist = Path(ellipseIn: CGRect(x: -34, y: -25, width: 68, height: 50))
            let fistTransform = CGAffineTransform(translationX: 158, y: 84).rotated(by: 0.68)
            fist = fist.applying(fistTransform)
            ctx.fill(fist, with: .color(handFill))
            ctx.stroke(fist, with: .color(outline), lineWidth: 1.6)

            // Thumb running down the shaft.
            let thumb = fingerCapsule(from: CGPoint(x: 166, y: 88), to: CGPoint(x: 186, y: 106), width: 11)
            ctx.fill(thumb, with: .color(handFill))
            ctx.stroke(thumb, with: .color(outline), lineWidth: 1.4)

            // Knuckle ridge — the dots you count. Gold = what you should see.
            let knuckles: [CGPoint] = [
                CGPoint(x: 138, y: 76),
                CGPoint(x: 148, y: 68),
                CGPoint(x: 160, y: 65),
                CGPoint(x: 171, y: 66),
            ]
            let visible = strong ? 3 : 2
            for k in knuckles.prefix(visible) {
                let r: CGFloat = 4.5
                ctx.fill(Path(ellipseIn: CGRect(x: k.x - r, y: k.y - r, width: r * 2, height: r * 2)),
                         with: .color(TCTheme.gold))
            }
            ctx.draw(Text("\(visible) KNUCKLES").font(.system(size: 9, weight: .black)).foregroundColor(TCTheme.gold),
                     at: CGPoint(x: 112, y: 40))
            var knuckleArrow = Path()
            knuckleArrow.move(to: CGPoint(x: 120, y: 48))
            knuckleArrow.addLine(to: CGPoint(x: 134, y: 70))
            ctx.stroke(knuckleArrow, with: .color(TCTheme.gold.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            // The V (thumb + index crease) and where it points.
            let vApex = CGPoint(x: 176, y: 84)
            var v = Path()
            v.move(to: CGPoint(x: 166, y: 72))
            v.addLine(to: vApex)
            v.addLine(to: CGPoint(x: 184, y: 76))
            ctx.stroke(v, with: .color(TCTheme.sage), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            let vTarget = strong ? CGPoint(x: 272, y: 48) : CGPoint(x: 246, y: 30)
            var pointer = Path()
            pointer.move(to: vApex)
            pointer.addLine(to: vTarget)
            ctx.stroke(pointer, with: .color(TCTheme.sage.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 5]))
            ctx.draw(Text(strong ? "V OUTSIDE TRAIL SHOULDER" : "V TO TRAIL SHOULDER")
                        .font(.system(size: 8.5, weight: .black)).foregroundColor(TCTheme.sage),
                     at: CGPoint(x: vTarget.x - 20, y: vTarget.y - 12))
        }
    }
}

/// Rounded capsule between two points (fingers, grip sections, shafts).
private func fingerCapsule(from p1: CGPoint, to p2: CGPoint, width: CGFloat) -> Path {
    let dx = p2.x - p1.x, dy = p2.y - p1.y
    let len = max(hypot(dx, dy), 0.001)
    var path = Path()
    path.addRoundedRect(in: CGRect(x: 0, y: -width / 2, width: len, height: width),
                        cornerSize: CGSize(width: width / 2, height: width / 2),
                        style: .continuous,
                        transform: CGAffineTransform(translationX: p1.x, y: p1.y).rotated(by: atan2(dy, dx)))
    return path
}

