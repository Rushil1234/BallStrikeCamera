import SwiftUI

// MARK: - Spinning Golf Ball

/// A rendered, dimpled golf ball that rotates continuously for the Home feed
/// empty state. Dimples are projected with spherical coordinates so the ball
/// reads as dimensional rather than as a flat pattern.
struct SpinningGolfBallView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Diameter of the ball in points.
    var size: CGFloat = 150
    /// Seconds for one full rotation.
    var period: Double = 6

    var body: some View {
        if reduceMotion {
            GolfBallCanvas(phase: 0.12, size: size)
                .frame(width: size, height: size * 1.16) // extra room for shadow
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: period)) / period
                GolfBallCanvas(phase: phase, size: size)
                    .frame(width: size, height: size * 1.16)
            }
        }
    }
}

private struct GolfBallCanvas: View {
    /// 0...1 progress of one full spin.
    var phase: Double
    var size: CGFloat

    // Brand palette
    private let bone   = Color(red: 0.945, green: 0.929, blue: 0.902) // Range Bone-ish body
    private let shade  = Color(red: 0.78,  green: 0.77,  blue: 0.74)  // terminator
    private let deep   = Color(red: 0.58,  green: 0.58,  blue: 0.56)  // far shadow

    var body: some View {
        Canvas { ctx, canvasSize in
            let r = size / 2
            let center = CGPoint(x: canvasSize.width / 2, y: r + 4)

            // Contact shadow
            let shY = center.y + r * 1.06
            let shRect = CGRect(x: center.x - r * 0.78, y: shY - r * 0.12,
                                width: r * 1.56, height: r * 0.24)
            ctx.fill(
                Path(ellipseIn: shRect),
                with: .radialGradient(
                    Gradient(colors: [Color.black.opacity(0.30), .clear]),
                    center: CGPoint(x: center.x, y: shY),
                    startRadius: 0, endRadius: r * 0.82
                )
            )

            let ballRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let ballPath = Path(ellipseIn: ballRect)

            // Body shading, light from upper-left.
            let lightCenter = CGPoint(x: center.x - r * 0.34, y: center.y - r * 0.40)
            ctx.fill(
                ballPath,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color.white,        location: 0.0),
                        .init(color: bone,               location: 0.45),
                        .init(color: shade,              location: 0.80),
                        .init(color: deep,               location: 1.0)
                    ]),
                    center: lightCenter,
                    startRadius: 0, endRadius: r * 1.65
                )
            )

            // Dimples projected onto the sphere.
            // Clip everything that follows to the ball.
            ctx.clip(to: ballPath)
            drawDimples(ctx: &ctx, center: center, radius: r)

            // Ambient occlusion at the rim.
            ctx.fill(
                ballPath,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .clear,                  location: 0.62),
                        .init(color: Color.black.opacity(0.0), location: 0.78),
                        .init(color: Color.black.opacity(0.22), location: 1.0)
                    ]),
                    center: center,
                    startRadius: 0, endRadius: r
                )
            )

            // Specular highlight.
            let hi = CGPoint(x: center.x - r * 0.36, y: center.y - r * 0.42)
            ctx.fill(
                Path(ellipseIn: CGRect(x: hi.x - r * 0.30, y: hi.y - r * 0.30,
                                       width: r * 0.60, height: r * 0.60)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.95), .clear]),
                    center: hi, startRadius: 0, endRadius: r * 0.34
                )
            )
            // Tight glint
            ctx.fill(
                Path(ellipseIn: CGRect(x: hi.x - r * 0.07, y: hi.y - r * 0.07,
                                       width: r * 0.14, height: r * 0.14)),
                with: .color(Color.white)
            )
        }
    }

    /// Lay dimples on a lat/long grid, rotate longitude by `phase`, project to the
    /// visible hemisphere. Front-facing dimples (z > 0) are drawn, scaled by depth.
    private func drawDimples(ctx: inout GraphicsContext, center: CGPoint, radius r: CGFloat) {
        let spin = phase * 2 * .pi
        // Tilt the spin axis slightly for a more natural tumble.
        let tilt = 0.32

        let latBands = 9
        for i in 0..<latBands {
            // Latitude from -80 to +80 degrees.
            let lat = (Double(i) / Double(latBands - 1) - 0.5) * (.pi * 0.92)
            let cosLat = cos(lat)
            // Fewer dimples near the poles, more around the equator.
            let count = max(4, Int((Double(latBands) * 2.4) * cosLat))
            for j in 0..<count {
                let lon = (Double(j) / Double(count)) * 2 * .pi + spin
                // Unit sphere coords (apply axis tilt around X).
                let x0 = cosLat * sin(lon)
                let y0 = sin(lat)
                let z0 = cosLat * cos(lon)
                let y = y0 * cos(tilt) - z0 * sin(tilt)
                let z = y0 * sin(tilt) + z0 * cos(tilt)
                let x = x0
                guard z > 0.04 else { continue } // only the front hemisphere

                let px = center.x + CGFloat(x) * r
                let py = center.y + CGFloat(y) * r
                // Perspective: dimples shrink and fade toward the rim.
                let depth = CGFloat(z)
                let dimR = r * 0.052 * (0.45 + 0.55 * depth)

                // Shade dimple by position relative to the light (upper-left).
                let lightDot = CGFloat(x) * -0.5 + CGFloat(y) * -0.55 + depth * 0.4
                let shadeAmt = min(max(0.10 + (1 - lightDot) * 0.10, 0.06), 0.26) * Double(depth)

                let dRect = CGRect(x: px - dimR, y: py - dimR, width: dimR * 2, height: dimR * 2)
                // Concave look: dark crescent lower-right, light crescent upper-left.
                ctx.fill(
                    Path(ellipseIn: dRect),
                    with: .radialGradient(
                        Gradient(colors: [Color.black.opacity(shadeAmt), .clear]),
                        center: CGPoint(x: px + dimR * 0.28, y: py + dimR * 0.28),
                        startRadius: 0, endRadius: dimR * 1.25
                    )
                )
                ctx.fill(
                    Path(ellipseIn: dRect),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(0.22 * Double(depth)), .clear]),
                        center: CGPoint(x: px - dimR * 0.3, y: py - dimR * 0.3),
                        startRadius: 0, endRadius: dimR * 0.9
                    )
                )
            }
        }
    }
}

// MARK: - Empty-state field

/// The Home feed's empty state: a spinning golf ball on a deep Carry Forest
/// field, echoing the brand's "equipment on ink" treatment.
struct GolfBallEmptyField: View {
    var title: String = "No activity yet"
    var message: String = "Start a round or range session to see your stats here."
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    // Carry Forest gradient, independent of light/dark so the ball always reads.
    private let forestTop = Color(red: 0.137, green: 0.196, blue: 0.157)
    private let forestBot = Color(red: 0.067, green: 0.106, blue: 0.086)

    var body: some View {
        VStack(spacing: 22) {
            SpinningGolfBallView(size: 132, period: 6)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(red: 0.925, green: 0.894, blue: 0.824))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.682, green: 0.690, blue: 0.635))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(forestBot)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.925, green: 0.894, blue: 0.824))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            ZStack {
                LinearGradient(colors: [forestTop, forestBot],
                               startPoint: .top, endPoint: .bottom)
                // Soft glow behind the ball, like the brand "on ink" vignette.
                RadialGradient(
                    colors: [Color(red: 0.925, green: 0.894, blue: 0.824).opacity(0.10), .clear],
                    center: .init(x: 0.5, y: 0.34),
                    startRadius: 10, endRadius: 220
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                .strokeBorder(TCTheme.gold.opacity(0.18), lineWidth: 1)
        )
    }
}
