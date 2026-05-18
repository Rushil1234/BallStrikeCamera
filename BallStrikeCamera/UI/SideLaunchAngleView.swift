import SwiftUI

struct SideLaunchAngleView: View {
    var vlaDegrees: Double?
    var ballSpeedMph: Double?
    var carryYards: Double?

    @State private var progress: CGFloat = 0

    private static let pathColor = Color(red: 1.0, green: 0.65, blue: 0.10)  // warm orange/gold
    private var displayVLA: Double { min(max(vlaDegrees ?? 22, 0), 65) }

    var body: some View {
        ZStack {
            Color(white: 0.06)
            Canvas { ctx, size in
                drawScene(ctx: ctx, size: size, progress: progress)
            }
            labels
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18)
                .padding(.top, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
        .onAppear { animateIn() }
    }

    // MARK: - Canvas scene

    private func drawScene(ctx: GraphicsContext, size: CGSize, progress: CGFloat) {
        let origin = CGPoint(x: size.width * 0.12, y: size.height * 0.80)
        let arcLen = min(size.width * 0.78, size.height * 1.20)
        let vlaRad = CGFloat(displayVLA * .pi / 180)

        let endX = origin.x + arcLen * cos(vlaRad)
        let endY = origin.y - arcLen * sin(vlaRad)
        let endPt = CGPoint(x: endX, y: endY)

        // Control point for the ball-flight arc (slight upward bulge relative to pure line)
        let ctrlX = origin.x + arcLen * 0.50 * cos(vlaRad) - arcLen * 0.04 * sin(vlaRad)
        let ctrlY = origin.y - arcLen * 0.50 * sin(vlaRad) - arcLen * 0.06 * cos(vlaRad)
        let ctrl = CGPoint(x: ctrlX, y: ctrlY)

        drawGround(ctx: ctx, origin: origin, size: size)
        drawTee(ctx: ctx, origin: origin)
        drawVLAAngleArc(ctx: ctx, origin: origin, radius: 58)
        drawGuideLine(ctx: ctx, origin: origin, end: endPt)
        drawAnimatedPath(ctx: ctx, origin: origin, ctrl: ctrl, end: endPt, progress: progress)
        drawBallDot(ctx: ctx, origin: origin, ctrl: ctrl, end: endPt, progress: progress)
    }

    private func drawGround(ctx: GraphicsContext, origin: CGPoint, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: origin.y))
        path.addLine(to: CGPoint(x: size.width, y: origin.y))
        ctx.stroke(path, with: .color(Color.white.opacity(0.30)),
                   style: StrokeStyle(lineWidth: 2))

        // Grass hatch lines for texture
        let hatchColor = Color.white.opacity(0.06)
        for i in stride(from: 0, through: Int(size.width), by: 18) {
            var h = Path()
            let x = CGFloat(i)
            h.move(to: CGPoint(x: x, y: origin.y))
            h.addLine(to: CGPoint(x: x - 10, y: origin.y + 14))
            ctx.stroke(h, with: .color(hatchColor), style: StrokeStyle(lineWidth: 1))
        }
    }

    private func drawTee(ctx: GraphicsContext, origin: CGPoint) {
        // Tee peg
        var tee = Path()
        tee.move(to: CGPoint(x: origin.x - 6, y: origin.y - 7))
        tee.addLine(to: CGPoint(x: origin.x + 6, y: origin.y - 7))
        tee.move(to: CGPoint(x: origin.x, y: origin.y - 7))
        tee.addLine(to: CGPoint(x: origin.x, y: origin.y))
        ctx.stroke(tee, with: .color(Color.white.opacity(0.70)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Ball at tee (small, visible before animation)
        if progress < 0.05 {
            ctx.fill(Path(ellipseIn: CGRect(x: origin.x - 7, y: origin.y - 21, width: 14, height: 14)),
                     with: .color(Color.white.opacity(0.60)))
        }
    }

    private func drawVLAAngleArc(ctx: GraphicsContext, origin: CGPoint, radius: CGFloat) {
        // Arc from 0° (ground right) up to VLA
        let arcPath = Path { p in
            p.addArc(center: origin, radius: radius,
                     startAngle: .degrees(0), endAngle: .degrees(-displayVLA), clockwise: true)
        }
        ctx.stroke(arcPath, with: .color(Self.pathColor.opacity(0.60)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

        // Angle label inside the arc
        let midRad = CGFloat(displayVLA / 2 * .pi / 180)
        let labelPt = CGPoint(
            x: origin.x + (radius + 18) * cos(midRad),
            y: origin.y - (radius + 18) * sin(midRad)
        )
        let vla = vlaDegrees.map { String(format: "%.1f°", $0) } ?? "?°"
        let lbl = Text(vla)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(Self.pathColor.opacity(0.85))
        ctx.draw(lbl, at: labelPt, anchor: .center)
    }

    private func drawGuideLine(ctx: GraphicsContext, origin: CGPoint, end: CGPoint) {
        var path = Path()
        path.move(to: origin)
        path.addLine(to: end)
        ctx.stroke(path, with: .color(Color.white.opacity(0.08)),
                   style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
    }

    private func drawAnimatedPath(ctx: GraphicsContext, origin: CGPoint, ctrl: CGPoint, end: CGPoint, progress: CGFloat) {
        guard progress > 0 else { return }

        // Draw the path up to current progress by sampling the quadratic
        let steps = 80
        let cap   = Int(CGFloat(steps) * progress)
        guard cap >= 1 else { return }

        var path = Path()
        path.move(to: origin)
        for i in 1...cap {
            let t = CGFloat(i) / CGFloat(steps)
            let pt = quadBezier(t: t, p0: origin, ctrl: ctrl, p1: end)
            path.addLine(to: pt)
        }
        ctx.stroke(path, with: .color(Self.pathColor),
                   style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
    }

    private func drawBallDot(ctx: GraphicsContext, origin: CGPoint, ctrl: CGPoint, end: CGPoint, progress: CGFloat) {
        guard progress > 0.01 else { return }
        let t   = min(progress, 0.995)
        let pos = quadBezier(t: t, p0: origin, ctrl: ctrl, p1: end)
        let r: CGFloat = 10

        // Glow ring
        ctx.fill(Path(ellipseIn: CGRect(x: pos.x - r*1.9, y: pos.y - r*1.9, width: r*3.8, height: r*3.8)),
                 with: .color(Self.pathColor.opacity(0.20)))
        // Ball
        ctx.fill(Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r*2, height: r*2)),
                 with: .color(Color.white))
        // Bright core
        ctx.fill(Path(ellipseIn: CGRect(x: pos.x - r*0.45, y: pos.y - r*0.45, width: r*0.9, height: r*0.9)),
                 with: .color(Self.pathColor))
    }

    // MARK: - Labels

    private var labels: some View {
        VStack(alignment: .leading, spacing: 6) {
            // VLA big label
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("VLA")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Self.pathColor.opacity(0.70))
                Text(vlaDegrees.map { String(format: "%.1f°", $0) } ?? "--")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Self.pathColor)
            }

            if let spd = ballSpeedMph {
                Text(String(format: "%.0f mph", spd))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }
            if let carry = carryYards {
                Text(String(format: "Carry %.0f yd", carry))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.50))
            }
        }
    }

    // MARK: - Math

    private func quadBezier(t: CGFloat, p0: CGPoint, ctrl: CGPoint, p1: CGPoint) -> CGPoint {
        let mt = 1 - t
        return CGPoint(x: mt*mt*p0.x + 2*mt*t*ctrl.x + t*t*p1.x,
                       y: mt*mt*p0.y + 2*mt*t*ctrl.y + t*t*p1.y)
    }

    // MARK: - Animation

    func animateIn() {
        progress = 0
        withAnimation(.easeOut(duration: 1.4)) { progress = 1 }
    }
}
