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
            panel(label: "WHERE IT LIES · LEAD HAND") {
                GripHandIllustration()
                    .frame(height: 250)
            }
            Text("The grip runs diagonally through the fingers — from under the heel pad to the middle of the index finger. The palm never wraps first.")
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

/// Open lead hand (palm to camera, fingers down) with the grip crossing the fingers —
/// the "palm-and-fingers" money shot every grip lesson is built on.
private struct GripHandIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 320, size.height / 250)
            ctx.translateBy(x: (size.width - 320 * s) / 2, y: (size.height - 250 * s) / 2)
            ctx.scaleBy(x: s, y: s)

            let ink = TCTheme.textPrimary
            let handFill = ink.opacity(0.10)
            let outline = ink.opacity(0.72)

            // Forearm + glove cuff coming in from the top.
            var forearm = Path()
            forearm.move(to: CGPoint(x: 124, y: -4))
            forearm.addCurve(to: CGPoint(x: 131, y: 62), control1: CGPoint(x: 124, y: 22), control2: CGPoint(x: 128, y: 44))
            forearm.addLine(to: CGPoint(x: 167, y: 62))
            forearm.addCurve(to: CGPoint(x: 172, y: -4), control1: CGPoint(x: 170, y: 44), control2: CGPoint(x: 172, y: 22))
            forearm.closeSubpath()
            ctx.fill(forearm, with: .color(handFill))
            ctx.stroke(forearm, with: .color(outline), lineWidth: 1.5)

            let cuff = Path(roundedRect: CGRect(x: 126, y: 56, width: 46, height: 15), cornerRadius: 6)
            ctx.fill(cuff, with: .color(handFill))
            ctx.stroke(cuff, with: .color(outline), lineWidth: 1.5)
            for i in 1...5 {
                var knit = Path()
                knit.move(to: CGPoint(x: 126 + CGFloat(i) * 7.5, y: 59))
                knit.addLine(to: CGPoint(x: 126 + CGFloat(i) * 7.5, y: 68))
                ctx.stroke(knit, with: .color(outline.opacity(0.35)), lineWidth: 1)
            }

            // Palm (left hand, palm facing camera → pinky left, thumb right).
            var palm = Path()
            palm.move(to: CGPoint(x: 131, y: 70))
            palm.addCurve(to: CGPoint(x: 110, y: 122), control1: CGPoint(x: 119, y: 84), control2: CGPoint(x: 111, y: 102))
            palm.addCurve(to: CGPoint(x: 118, y: 168), control1: CGPoint(x: 109, y: 140), control2: CGPoint(x: 111, y: 156))
            palm.addCurve(to: CGPoint(x: 180, y: 166), control1: CGPoint(x: 138, y: 176), control2: CGPoint(x: 162, y: 176))
            palm.addCurve(to: CGPoint(x: 192, y: 126), control1: CGPoint(x: 189, y: 158), control2: CGPoint(x: 192, y: 142))
            palm.addCurve(to: CGPoint(x: 167, y: 70), control1: CGPoint(x: 192, y: 104), control2: CGPoint(x: 181, y: 82))
            palm.closeSubpath()
            ctx.fill(palm, with: .color(handFill))
            ctx.stroke(palm, with: .color(outline), lineWidth: 1.6)

            // Heel-pad + lifeline creases.
            var crease = Path()
            crease.move(to: CGPoint(x: 122, y: 118))
            crease.addQuadCurve(to: CGPoint(x: 130, y: 158), control: CGPoint(x: 118, y: 140))
            ctx.stroke(crease, with: .color(outline.opacity(0.35)), lineWidth: 1.2)
            var lifeline = Path()
            lifeline.move(to: CGPoint(x: 178, y: 92))
            lifeline.addQuadCurve(to: CGPoint(x: 152, y: 156), control: CGPoint(x: 154, y: 116))
            ctx.stroke(lifeline, with: .color(outline.opacity(0.35)), lineWidth: 1.2)

            // Fingers, pointing down, slight natural fan. (pinky → index, left → right)
            let fingers: [(base: CGPoint, angle: Double, len: CGFloat, w: CGFloat)] = [
                (CGPoint(x: 126, y: 168), -10, 46, 14.5),
                (CGPoint(x: 143, y: 172),  -4, 60, 15.5),
                (CGPoint(x: 161, y: 172),   2, 64, 16.0),
                (CGPoint(x: 178, y: 166),   8, 56, 15.5),
            ]
            for f in fingers {
                let path = fingerCapsule(from: f.base, angleDeg: f.angle, length: f.len, width: f.w)
                ctx.fill(path, with: .color(handFill))
                ctx.stroke(path, with: .color(outline), lineWidth: 1.5)
                // Middle-joint crease.
                let a = f.angle * .pi / 180
                let mid = CGPoint(x: f.base.x + CGFloat(sin(a)) * f.len * 0.55,
                                  y: f.base.y + CGFloat(cos(a)) * f.len * 0.55)
                var joint = Path()
                joint.move(to: CGPoint(x: mid.x - f.w * 0.32, y: mid.y))
                joint.addQuadCurve(to: CGPoint(x: mid.x + f.w * 0.32, y: mid.y),
                                   control: CGPoint(x: mid.x, y: mid.y + 3))
                ctx.stroke(joint, with: .color(outline.opacity(0.3)), lineWidth: 1)
            }

            // Thumb, off to the lower right.
            let thumb = fingerCapsule(from: CGPoint(x: 190, y: 124), angleDeg: 55, length: 58, width: 17)
            ctx.fill(thumb, with: .color(handFill))
            ctx.stroke(thumb, with: .color(outline), lineWidth: 1.5)

            // The grip, laid diagonally ACROSS the fingers (in front of the hand):
            // under the heel pad on the pinky side, across the index's middle segment.
            let gripA = CGPoint(x: 84, y: 142)
            let gripB = CGPoint(x: 252, y: 208)
            let grip = fingerCapsule(from: gripA, to: gripB, width: 30)
            ctx.fill(grip, with: .color(ink.opacity(0.22)))
            ctx.stroke(grip, with: .color(outline.opacity(0.9)), lineWidth: 1.6)
            // Butt cap poking out past the heel pad.
            let butt = CGPoint(x: 78, y: 139.6)
            ctx.fill(Path(ellipseIn: CGRect(x: butt.x - 16, y: butt.y - 16, width: 32, height: 32)),
                     with: .color(ink.opacity(0.28)))
            ctx.stroke(Path(ellipseIn: CGRect(x: butt.x - 16, y: butt.y - 16, width: 32, height: 32)),
                       with: .color(outline), lineWidth: 1.6)
            ctx.stroke(Path(ellipseIn: CGRect(x: butt.x - 7, y: butt.y - 7, width: 14, height: 14)),
                       with: .color(outline.opacity(0.5)), lineWidth: 1.2)
            // Grip texture dots.
            let dir = CGVector(dx: gripB.x - gripA.x, dy: gripB.y - gripA.y)
            let len = hypot(dir.dx, dir.dy)
            let u = CGVector(dx: dir.dx / len, dy: dir.dy / len)
            let n = CGVector(dx: -u.dy, dy: u.dx)
            for row in [-1, 0, 1] {
                for i in stride(from: CGFloat(28), through: len - 14, by: 13) {
                    let p = CGPoint(x: gripA.x + u.dx * i + n.dx * CGFloat(row) * 8,
                                    y: gripA.y + u.dy * i + n.dy * CGFloat(row) * 8)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)),
                             with: .color(ink.opacity(0.28)))
                }
            }
            // Gold guide line along the grip's core — the line to feel.
            var guide = Path()
            guide.move(to: gripA)
            guide.addLine(to: gripB)
            ctx.stroke(guide, with: .color(TCTheme.gold.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 7]))

            // Annotations.
            annotate(ctx, text: "UNDER THE HEEL PAD", at: CGPoint(x: 92, y: 100),
                     arrowFrom: CGPoint(x: 96, y: 108), to: CGPoint(x: 106, y: 132))
            annotate(ctx, text: "ACROSS THE FINGERS", at: CGPoint(x: 236, y: 240),
                     arrowFrom: CGPoint(x: 230, y: 232), to: CGPoint(x: 212, y: 204))
        }
    }

    private func annotate(_ ctx: GraphicsContext, text: String, at point: CGPoint,
                          arrowFrom: CGPoint, to tip: CGPoint) {
        ctx.draw(Text(text).font(.system(size: 8.5, weight: .black)).foregroundColor(TCTheme.gold),
                 at: point)
        var arrow = Path()
        arrow.move(to: arrowFrom)
        arrow.addLine(to: tip)
        ctx.stroke(arrow, with: .color(TCTheme.gold.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 2, y: tip.y - 2, width: 4, height: 4)),
                 with: .color(TCTheme.gold))
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
            for (i, k) in knuckles.enumerated() {
                let r: CGFloat = 4.5
                let dot = Path(ellipseIn: CGRect(x: k.x - r, y: k.y - r, width: r * 2, height: r * 2))
                if i < visible {
                    ctx.fill(dot, with: .color(TCTheme.gold))
                } else {
                    ctx.stroke(dot, with: .color(outline.opacity(0.4)), lineWidth: 1.2)
                }
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

/// Capsule from a base point at an angle (0° = straight down, + tilts right).
private func fingerCapsule(from base: CGPoint, angleDeg: Double, length: CGFloat, width: CGFloat) -> Path {
    let a = angleDeg * .pi / 180
    let end = CGPoint(x: base.x + CGFloat(sin(a)) * length, y: base.y + CGFloat(cos(a)) * length)
    return fingerCapsule(from: base, to: end, width: width)
}
