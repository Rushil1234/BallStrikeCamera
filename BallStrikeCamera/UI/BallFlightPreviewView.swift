import SwiftUI

struct BallFlightPreviewView: View {
    var carryYards: Double?
    var totalYards: Double?
    var hlaDegrees: Double?
    var vlaDegrees: Double?
    // When launch conditions are provided, the airborne path is integrated with
    // FlightArcModel (shared aerodynamics with the web sim) so draws/fades curve.
    var ballSpeedMph: Double?
    var backspinRpm: Double?
    var sidespinRpm: Double?

    private var arcSamples: [FlightArcModel.Sample] {
        guard let speed = ballSpeedMph, let vla = vlaDegrees else { return [] }
        return FlightArcModel.trajectory(
            ballSpeedMph: speed,
            vlaDeg: vla,
            hlaDeg: hlaDegrees ?? 0,
            backspinRpm: backspinRpm ?? 0,
            sidespinRpm: sidespinRpm ?? 0
        )
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                drawGrid(ctx: ctx, size: size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Layout Constants

    private struct Layout {
        let size: CGSize
        // Margins: tight top, generous bottom for labels
        let padTop: CGFloat = 24
        let padBottom: CGFloat = 38
        let padH: CGFloat = 40

        var plotW: CGFloat { size.width - padH * 2 }
        var plotH: CGFloat { size.height - padTop - padBottom }
        var originX: CGFloat { size.width / 2 }
        var originY: CGFloat { size.height - padBottom }
    }

    // MARK: - Scale Calculation

    private struct Scale {
        let maxDownrangeYd: Double   // vertical axis max
        let maxOfflineYd: Double     // horizontal half-axis max (symmetric)
    }

    private func computeScale(totalYd: Double?, offlineYd: Double?) -> Scale {
        let td = totalYd ?? 0
        let od = abs(offlineYd ?? 0)

        let downrangeSteps: [Double] = [50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300, 350, 400]
        let maxDown = downrangeSteps.first(where: { $0 >= td }) ?? 400

        let offlineSteps: [Double] = [25, 30, 40, 50, 60, 75, 100]
        let maxOff = offlineSteps.first(where: { $0 >= od * 1.25 }) ?? 100

        return Scale(maxDownrangeYd: maxDown, maxOfflineYd: maxOff)
    }

    // MARK: - Coordinate Mapping

    private func toPoint(offlineYd: Double, downrangeYd: Double, scale: Scale, layout: Layout) -> CGPoint {
        let xFrac = CGFloat(offlineYd / scale.maxOfflineYd)  // -1…1
        let yFrac = CGFloat(downrangeYd / scale.maxDownrangeYd) // 0…1
        return CGPoint(
            x: layout.originX + xFrac * (layout.plotW / 2),
            y: layout.originY - yFrac * layout.plotH
        )
    }

    // MARK: - Main Draw

    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        let layout = Layout(size: size)

        // Background
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                 with: .color(Color(white: 0.07)))

        // --- Offline: physics arc landing when available, else HLA projection ---
        let arcPts = scaledArcPoints()
        let offlineYd: Double
        if let land = arcPts.last {
            let carryYd = carryYards ?? land.down
            let totalYd = totalYards ?? carryYd
            offlineYd = land.off + arcRolloutSlope(arcPts) * max(0, totalYd - carryYd)
        } else {
            let hlaRad = (hlaDegrees ?? 0) * .pi / 180.0
            let refDist = totalYards ?? carryYards ?? 0
            offlineYd = tan(hlaRad) * refDist   // positive = right, negative = left
        }

        let scale = computeScale(totalYd: totalYards ?? carryYards, offlineYd: offlineYd)

        drawGridLines(ctx: ctx, layout: layout, scale: scale)
        drawTargetLine(ctx: ctx, layout: layout, scale: scale)
        drawShotPath(ctx: ctx, layout: layout, scale: scale, offlineYd: offlineYd, arcPts: arcPts)
        drawLabels(ctx: ctx, layout: layout, scale: scale, offlineYd: offlineYd)
    }

    // MARK: - Physics arc helpers

    /// Integrated samples scaled so the airborne landing matches the measured carry.
    private func scaledArcPoints() -> [(off: Double, down: Double)] {
        let arc = arcSamples
        guard let last = arc.last, last.downrangeYd > 5 else { return [] }
        let k = (carryYards ?? last.downrangeYd) / last.downrangeYd
        return arc.map { (off: $0.offlineYd * k, down: $0.downrangeYd * k) }
    }

    /// Horizontal direction of the final flight segment (offline yd per downrange yd).
    private func arcRolloutSlope(_ pts: [(off: Double, down: Double)]) -> Double {
        guard pts.count >= 2 else { return 0 }
        let a = pts[pts.count - 2], b = pts[pts.count - 1]
        let dd = b.down - a.down
        guard dd > 0.01 else { return 0 }
        return (b.off - a.off) / dd
    }

    // MARK: - Grid Lines

    private func drawGridLines(ctx: GraphicsContext, layout: Layout, scale: Scale) {
        let gridColor = Color.white.opacity(0.07)
        let lineStyle = StrokeStyle(lineWidth: 0.5, dash: [3, 5])
        let labelColor = Color.white.opacity(0.25)

        // Horizontal lines (downrange distance markers)
        let downrangeStepYd: Double = scale.maxDownrangeYd <= 100 ? 25 : (scale.maxDownrangeYd <= 200 ? 50 : 100)
        var yd: Double = downrangeStepYd
        while yd <= scale.maxDownrangeYd {
            let pt = toPoint(offlineYd: 0, downrangeYd: yd, scale: scale, layout: layout)
            var path = Path()
            path.move(to: CGPoint(x: layout.padH * 0.4, y: pt.y))
            path.addLine(to: CGPoint(x: layout.size.width - layout.padH * 0.4, y: pt.y))
            ctx.stroke(path, with: .color(gridColor), style: lineStyle)

            // Label
            let label = Text("\(Int(yd))yd")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundColor(labelColor)
            ctx.draw(label, at: CGPoint(x: layout.padH * 0.2 + 6, y: pt.y), anchor: .leading)
            yd += downrangeStepYd
        }

        // Vertical lines (offline distance markers)
        let offlineStepYd: Double = scale.maxOfflineYd <= 30 ? 10 : (scale.maxOfflineYd <= 60 ? 20 : 25)
        var off: Double = offlineStepYd
        while off < scale.maxOfflineYd {
            for sign in [-1.0, 1.0] {
                let pt = toPoint(offlineYd: off * sign, downrangeYd: 0, scale: scale, layout: layout)
                var path = Path()
                path.move(to: CGPoint(x: pt.x, y: layout.padTop))
                path.addLine(to: CGPoint(x: pt.x, y: layout.originY))
                ctx.stroke(path, with: .color(gridColor), style: lineStyle)

                let label = Text("\(Int(off))")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundColor(labelColor)
                let anchor: UnitPoint = sign > 0 ? .trailing : .leading
                ctx.draw(label, at: CGPoint(x: pt.x + CGFloat(sign) * 2, y: layout.originY + 10), anchor: anchor)
            }
            off += offlineStepYd
        }
    }

    // MARK: - Target Line

    private func drawTargetLine(ctx: GraphicsContext, layout: Layout, scale: Scale) {
        let origin = toPoint(offlineYd: 0, downrangeYd: 0, scale: scale, layout: layout)
        let top = CGPoint(x: origin.x, y: layout.padTop)

        var path = Path()
        path.move(to: origin)
        path.addLine(to: top)
        ctx.stroke(path, with: .color(Color.white.opacity(0.18)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

        let label = Text("Target")
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.30))
        ctx.draw(label, at: CGPoint(x: origin.x + 4, y: layout.padTop + 6), anchor: .leading)
    }

    // MARK: - Shot Path

    private func drawShotPath(ctx: GraphicsContext, layout: Layout, scale: Scale, offlineYd: Double,
                              arcPts: [(off: Double, down: Double)] = []) {
        let origin = toPoint(offlineYd: 0, downrangeYd: 0, scale: scale, layout: layout)

        // Physics-integrated path: curved draw/fade shape from real launch data.
        if arcPts.count >= 2 {
            let land = arcPts[arcPts.count - 1]
            let carryYd = carryYards ?? land.down
            let totalYd = max(totalYards ?? carryYd, carryYd)
            let carryPt = toPoint(offlineYd: land.off, downrangeYd: land.down, scale: scale, layout: layout)
            let totalPt = toPoint(offlineYd: offlineYd, downrangeYd: totalYd, scale: scale, layout: layout)

            var flightPath = Path()
            flightPath.move(to: origin)
            for p in arcPts.dropFirst() {
                flightPath.addLine(to: toPoint(offlineYd: p.off, downrangeYd: p.down, scale: scale, layout: layout))
            }
            ctx.stroke(flightPath, with: .color(Color(red: 0.0, green: 0.85, blue: 1.0)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            let hasRollout = totalYd > carryYd + 1
            if hasRollout {
                var rollPath = Path()
                rollPath.move(to: carryPt)
                rollPath.addLine(to: totalPt)
                ctx.stroke(rollPath, with: .color(Color(red: 1.0, green: 0.60, blue: 0.0)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            filledDot(ctx: ctx, at: origin, r: 5, color: .white)
            if hasRollout {
                filledDot(ctx: ctx, at: carryPt, r: 4.5, color: Color(red: 0.0, green: 0.85, blue: 1.0))
            }
            filledDot(ctx: ctx, at: totalPt, r: 5.5, color: Color(red: 0.3, green: 0.9, blue: 0.4))

            var dropLine = Path()
            dropLine.move(to: totalPt)
            dropLine.addLine(to: CGPoint(x: totalPt.x, y: origin.y))
            ctx.stroke(dropLine, with: .color(Color.white.opacity(0.12)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            return
        }

        let hasRealData = (totalYards ?? carryYards) != nil

        if !hasRealData {
            // Placeholder path: a gentle straight line upward with a small bias
            let placeholderEnd = CGPoint(x: origin.x + 10, y: layout.padTop + 30)
            var arc = Path()
            arc.move(to: origin)
            arc.addLine(to: placeholderEnd)
            ctx.stroke(arc, with: .color(Color.white.opacity(0.30)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))

            // "Distance unavailable" label
            let label = Text("Distance unavailable")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.35))
            ctx.draw(label, at: CGPoint(x: layout.size.width / 2, y: layout.size.height / 2), anchor: .center)
            return
        }

        let totalYd = totalYards ?? carryYards ?? 0
        let carryYd = carryYards ?? totalYd

        let totalPt = toPoint(offlineYd: offlineYd, downrangeYd: totalYd, scale: scale, layout: layout)
        let carryOffline = offlineYd * (carryYd / max(totalYd, 1))
        let carryPt = toPoint(offlineYd: carryOffline, downrangeYd: carryYd, scale: scale, layout: layout)

        // Bezier control point: midpoint along the arc
        let midOffline   = offlineYd * 0.5
        let midDownrange = totalYd * 0.5
        let midPt  = toPoint(offlineYd: midOffline, downrangeYd: midDownrange, scale: scale, layout: layout)
        let ctrlPt = CGPoint(x: midPt.x, y: midPt.y)

        // Quadratic Bezier sampler
        func qBez(t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u*u*origin.x + 2*u*t*ctrlPt.x + t*t*totalPt.x,
                           y: u*u*origin.y + 2*u*t*ctrlPt.y + t*t*totalPt.y)
        }

        // Carry fraction along arc (0…1)
        let carryT = CGFloat(carryYd / max(totalYd, 0.001))
        let hasRollout = carryYards != nil && carryYd < totalYd * 0.97
        let splitT = hasRollout ? carryT : CGFloat(1.0)

        let steps = 60

        // Cyan airborne segment: tee → carry
        let carrySteps = max(1, Int(splitT * CGFloat(steps)))
        var flightPath = Path()
        flightPath.move(to: origin)
        for i in 1...carrySteps {
            flightPath.addLine(to: qBez(t: CGFloat(i) / CGFloat(steps)))
        }
        ctx.stroke(flightPath, with: .color(Color(red: 0.0, green: 0.85, blue: 1.0)),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

        // Orange rollout segment: carry → total
        if hasRollout && carrySteps < steps {
            var rollPath = Path()
            rollPath.move(to: qBez(t: CGFloat(carrySteps) / CGFloat(steps)))
            for i in (carrySteps + 1)...steps {
                rollPath.addLine(to: qBez(t: CGFloat(i) / CGFloat(steps)))
            }
            ctx.stroke(rollPath, with: .color(Color(red: 1.0, green: 0.60, blue: 0.0)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }

        // Tee dot (white)
        filledDot(ctx: ctx, at: origin, r: 5, color: .white)

        // Carry dot (cyan) when there is a rollout
        if hasRollout {
            filledDot(ctx: ctx, at: carryPt, r: 4.5, color: Color(red: 0.0, green: 0.85, blue: 1.0))
        }

        // Total dot (green)
        filledDot(ctx: ctx, at: totalPt, r: 5.5, color: Color(red: 0.3, green: 0.9, blue: 0.4))

        // Offline drop line
        var dropLine = Path()
        dropLine.move(to: totalPt)
        dropLine.addLine(to: CGPoint(x: totalPt.x, y: origin.y))
        ctx.stroke(dropLine, with: .color(Color.white.opacity(0.12)),
                   style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
    }

    // MARK: - Labels

    private func drawLabels(ctx: GraphicsContext, layout: Layout, scale: Scale, offlineYd: Double) {
        let hasData = (totalYards ?? carryYards) != nil
        guard hasData else { return }

        let totalYd = totalYards ?? carryYards!
        let carryYd = carryYards ?? totalYd

        // Build label array: [left column, right column]
        var leftParts: [String] = []
        var rightParts: [String] = []

        leftParts.append(String(format: "Total  %.0f yd", totalYd))
        if carryYards != nil && carryYd < totalYd * 0.98 {
            leftParts.append(String(format: "Carry  %.0f yd", carryYd))
        }

        let absOff = abs(offlineYd)
        if absOff >= 0.5 {
            let side = offlineYd > 0 ? "R" : "L"
            rightParts.append(String(format: "Offline  %.0f yd %@", absOff, side))
        }
        if let hla = hlaDegrees, abs(hla) >= 0.1 {
            let side = hla > 0 ? "R" : "L"
            rightParts.append(String(format: "HLA  %.1f° %@", abs(hla), side))
        }

        let x0: CGFloat = layout.padH * 0.35
        let x1: CGFloat = layout.size.width / 2 + 6
        let y0: CGFloat = layout.size.height - layout.padBottom + 8

        for (i, text) in leftParts.enumerated() {
            let label = Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.60))
            ctx.draw(label, at: CGPoint(x: x0, y: y0 + CGFloat(i) * 12), anchor: .leading)
        }
        for (i, text) in rightParts.enumerated() {
            let label = Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.60))
            ctx.draw(label, at: CGPoint(x: x1, y: y0 + CGFloat(i) * 12), anchor: .leading)
        }
    }

    // MARK: - Helpers

    private func filledDot(ctx: GraphicsContext, at pt: CGPoint, r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                 with: .color(color))
    }
}
