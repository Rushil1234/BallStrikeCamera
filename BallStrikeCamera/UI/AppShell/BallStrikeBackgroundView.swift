import SwiftUI

struct BallStrikeBackgroundView: View {
    var body: some View {
        ZStack {
            // Base gradient
            BSTheme.mainBackground
                .ignoresSafeArea()

            // Top-right cyan glow
            RadialGradient(
                colors: [BSTheme.electricCyan.opacity(0.18), Color.clear],
                center: .init(x: 1.1, y: -0.1),
                startRadius: 0,
                endRadius: 480
            )
            .ignoresSafeArea()

            // Bottom-left green glow
            RadialGradient(
                colors: [BSTheme.fairwayGreen.opacity(0.12), Color.clear],
                center: .init(x: -0.1, y: 1.15),
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()

            // Centre ambient
            RadialGradient(
                colors: [BSTheme.electricCyan.opacity(0.05), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()

            // Flowing arc lines
            FlowingArcsView()
                .ignoresSafeArea()
        }
    }
}

private struct FlowingArcsView: View {
    var body: some View {
        Canvas { ctx, size in
            let arcs: [(start: CGPoint, cp1: CGPoint, cp2: CGPoint, end: CGPoint, opacity: Double)] = [
                (
                    CGPoint(x: size.width * 0.0,  y: size.height * 0.35),
                    CGPoint(x: size.width * 0.35, y: size.height * 0.05),
                    CGPoint(x: size.width * 0.65, y: size.height * 0.45),
                    CGPoint(x: size.width * 1.0,  y: size.height * 0.15),
                    0.055
                ),
                (
                    CGPoint(x: size.width * 0.0,  y: size.height * 0.70),
                    CGPoint(x: size.width * 0.30, y: size.height * 0.40),
                    CGPoint(x: size.width * 0.70, y: size.height * 0.80),
                    CGPoint(x: size.width * 1.0,  y: size.height * 0.50),
                    0.040
                ),
                (
                    CGPoint(x: size.width * 0.15, y: size.height * 0.0),
                    CGPoint(x: size.width * 0.45, y: size.height * 0.60),
                    CGPoint(x: size.width * 0.55, y: size.height * 0.20),
                    CGPoint(x: size.width * 0.85, y: size.height * 1.0),
                    0.035
                ),
                (
                    CGPoint(x: size.width * 0.0,  y: size.height * 0.55),
                    CGPoint(x: size.width * 0.50, y: size.height * 0.25),
                    CGPoint(x: size.width * 0.60, y: size.height * 0.70),
                    CGPoint(x: size.width * 1.0,  y: size.height * 0.35),
                    0.028
                ),
            ]

            for arc in arcs {
                var path = Path()
                path.move(to: arc.start)
                path.addCurve(to: arc.end, control1: arc.cp1, control2: arc.cp2)
                ctx.stroke(
                    path,
                    with: .color(Color.white.opacity(arc.opacity)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
            }
        }
    }
}
