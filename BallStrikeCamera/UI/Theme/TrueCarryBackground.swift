import SwiftUI

// MARK: - True Carry Background

/// Brand texture options for the app background (Brand pattern 06.00).
enum BackgroundPattern {
    case plain     // brand wash without surface pattern
    case contour   // moving green-side radius rings
    case dimple    // static golf-ball dimple grid
}

struct TrueCarryBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pattern: BackgroundPattern = .plain

    var body: some View {
        ZStack {
            TCTheme.background
            RadialGradient(
                colors: [TCTheme.cream.opacity(0.025), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
            RadialGradient(
                colors: [TCTheme.gold.opacity(0.040), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 460
            )
            RadialGradient(
                colors: [TCTheme.sage.opacity(0.030), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 420
            )
            switch pattern {
            case .plain:
                EmptyView()
            case .dimple:
                DimpleGridCanvas()
            case .contour:
                if reduceMotion {
                    ContourRingsCanvas(phase: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        ContourRingsCanvas(phase: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Contour Rings (animated brand pattern)

struct ContourRingsCanvas: View {
    var phase: TimeInterval = 0
    /// Distance between rings and how long one ring takes to drift outward (seconds).
    private let spacing: CGFloat = 48
    private let period: Double = 7

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width * 0.66, y: size.height * 0.72)
            // Farthest corner sets how many rings we need to cover the screen.
            let maxR: CGFloat = hypot(max(center.x, size.width - center.x),
                                      max(center.y, size.height - center.y)) + spacing
            // Drift one full ring-spacing over `period` seconds, then loop seamlessly.
            let t: Double = (phase.truncatingRemainder(dividingBy: period)) / period
            let drift: CGFloat = CGFloat(t) * spacing

            var r: CGFloat = drift + 6
            while r < maxR {
                // Fade rings gently as they reach the edges.
                let fade: Double = 1 - Double(r / maxR) * 0.55
                let shading = GraphicsContext.Shading.color(TCTheme.cream.opacity(0.07 * fade))
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                ctx.stroke(Path(ellipseIn: rect), with: shading, lineWidth: 1)
                r += spacing
            }
        }
        .drawingGroup()
    }
}

// MARK: - Dimple Grid (static brand pattern)

struct DimpleGridCanvas: View {
    /// Tile size and dot radius mirror the brand spec: 22 px repeat, two offset dots.
    private let tile: CGFloat = 22
    private let dotRadius: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, size in
            let color = GraphicsContext.Shading.color(TCTheme.cream.opacity(0.06))
            let cols: Int = Int(size.width / tile) + 2
            let rows: Int = Int(size.height / tile) + 2
            // Two dots per tile (30%/30% and 70%/70%) → offset dimple lattice.
            let offsets: [(CGFloat, CGFloat)] = [(0.30, 0.30), (0.70, 0.70)]
            for row in 0..<rows {
                for col in 0..<cols {
                    let ox: CGFloat = CGFloat(col) * tile
                    let oy: CGFloat = CGFloat(row) * tile
                    for offset in offsets {
                        let cx: CGFloat = ox + tile * offset.0
                        let cy: CGFloat = oy + tile * offset.1
                        let rect = CGRect(x: cx - dotRadius, y: cy - dotRadius,
                                          width: dotRadius * 2, height: dotRadius * 2)
                        ctx.fill(Path(ellipseIn: rect), with: color)
                    }
                }
            }
        }
        .drawingGroup()
    }
}

// MARK: - Topographic Canvas

struct TopoLinesCanvas: View {
    var phase: TimeInterval = 0

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let flow = CGFloat(phase.truncatingRemainder(dividingBy: 8)) / 8
            var path = Path()
            let groups: [(y: CGFloat, n: Int, amp: CGFloat)] = [
                (h * 0.15, 7, h * 0.048),
                (h * 0.43, 9, h * 0.058),
                (h * 0.73, 8, h * 0.042),
            ]
            for g in groups {
                for i in 0..<g.n {
                    let wave = sin((flow * .pi * 2) + CGFloat(i) * 0.45)
                    let y = g.y + CGFloat(i) * 22 + wave * 5
                    let amp = g.amp * (1 - CGFloat(i) * 0.07)
                    let drift = (flow * 44) - 22
                    path.move(to: CGPoint(x: -64 + drift, y: y))
                    path.addCurve(
                        to: CGPoint(x: w + 64 + drift, y: y + amp * 0.3),
                        control1: CGPoint(x: w * 0.25 + drift, y: y - amp),
                        control2: CGPoint(x: w * 0.75 + drift, y: y + amp * 0.8)
                    )
                }
            }
            ctx.stroke(path, with: .color(TCTheme.cream),
                       style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
        }
    }
}

// MARK: - True Carry Logo

struct TrueCarryLogo: View {
    var size: CGFloat = 24

    var body: some View {
        Text("True Carry")
            .font(.system(size: size, weight: .medium, design: .serif))
            .tracking(-0.25)
            .foregroundColor(TCTheme.cream)
    }
}

// MARK: - Universal Tab Header Bar

struct TCHeaderBar<RightContent: View>: View {
    let initials: String
    @ViewBuilder let rightContent: () -> RightContent
    private let sideWidth: CGFloat = 80

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Color.clear
                .frame(width: sideWidth, height: 44)
            TrueCarryLogo(size: 20)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) { rightContent() }
                .frame(width: sideWidth, height: 44, alignment: .trailing)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Profile Avatar Button (top-right header tap → profile sheet)

struct TCProfileAvatarButton: View {
    let initials: String
    var devMode: Bool = false
    var action: () -> Void = {}

    private let devOrange = Color(red: 1, green: 0.6, blue: 0)

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(TCTheme.panelRaised)
                    Circle()
                        .strokeBorder(devMode ? devOrange.opacity(0.85) : TCTheme.gold.opacity(0.55), lineWidth: 1.5)
                    Text(String(initials.prefix(2)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(devMode ? devOrange : TCTheme.gold)
                }
                .frame(width: 32, height: 32)

                if devMode {
                    Circle()
                        .fill(devOrange)
                        .frame(width: 8, height: 8)
                        .offset(x: 1, y: -1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header Icon Buttons

struct TCBellButton: View {
    var badgeCount: Int = 0
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(TCTheme.textSecondary)
                if badgeCount > 0 {
                    Text("\(min(badgeCount, 9))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                        .offset(x: 6, y: -5)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}

struct TCIconButton: View {
    let icon: String
    var color: Color = TCTheme.textSecondary
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Generated Fairway View (course-map illustration in SwiftUI Canvas)

struct GeneratedFairwayView: View {
    var landingFraction: CGFloat = 0.55
    var dispersionOffline: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let w = size.width; let h = size.height; let midX = w / 2
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(red:0.02,green:0.08,blue:0.14),
                                                              Color(red:0.04,green:0.14,blue:0.10)]),
                                           startPoint:.zero, endPoint:CGPoint(x:0,y:h)))
            let fw = w * 0.36
            let roughPath = Path { p in
                p.addRoundedRect(in: CGRect(x:midX-fw, y:h*0.04, width:fw*2, height:h*0.92),
                                 cornerSize: CGSize(width:fw*0.44, height:fw*0.44))
            }
            ctx.fill(roughPath, with: .color(Color(red:0.12,green:0.24,blue:0.14)))
            let fwPath = Path { p in
                p.addRoundedRect(in: CGRect(x:midX-fw*0.55, y:h*0.13, width:fw*1.10, height:h*0.73),
                                 cornerSize: CGSize(width:fw*0.28, height:fw*0.28))
            }
            ctx.fill(fwPath, with: .color(Color(red:0.16,green:0.35,blue:0.18)))
            let gR = w * 0.11; let gCY = h * 0.11
            ctx.fill(Path(ellipseIn: CGRect(x:midX-gR,y:gCY-gR*0.65,width:gR*2,height:gR*1.3)),
                     with: .color(Color(red:0.20,green:0.48,blue:0.22)))
            ctx.fill(Path(CGRect(x:midX-1,y:gCY-gR*0.45,width:2,height:gR*0.8)), with:.color(.white.opacity(0.9)))
            ctx.fill(Path(CGRect(x:midX+1,y:gCY-gR*0.45,width:gR*0.4,height:gR*0.28)), with:.color(TCTheme.gold))
            let teeCY = h * 0.89
            let lx = midX + dispersionOffline*(w/200)
            let ly = h*(1-landingFraction)*0.77+h*0.11
            var sp = Path()
            sp.move(to: CGPoint(x:midX,y:teeCY-4))
            sp.addQuadCurve(to: CGPoint(x:lx,y:ly),
                            control: CGPoint(x:(midX+lx)/2, y:teeCY-(teeCY-ly)*1.32))
            ctx.stroke(sp, with:.color(TCTheme.gold.opacity(0.72)),
                       style:StrokeStyle(lineWidth:1.8,lineCap:.round,dash:[4,3]))
            ctx.fill(Path(ellipseIn: CGRect(x:lx-4,y:ly-4,width:8,height:8)), with:.color(TCTheme.gold))
            ctx.stroke(Path(ellipseIn: CGRect(x:lx-11,y:ly-11,width:22,height:22)),
                       with:.color(TCTheme.gold.opacity(0.28)), lineWidth:1)
        }
    }
}

// MARK: - Dispersion Chart

struct DispersionChartView: View {
    var dots: [(x: CGFloat, y: CGFloat)] = []
    static let sampleDots: [(x: CGFloat, y: CGFloat)] = [
        (0.49,0.54),(0.51,0.48),(0.53,0.52),(0.47,0.55),(0.50,0.46),
        (0.54,0.50),(0.46,0.52),(0.52,0.57),(0.48,0.49),(0.55,0.53),
        (0.45,0.58),(0.51,0.44),(0.56,0.48),(0.50,0.61),(0.44,0.50),(0.53,0.44)
    ]
    var body: some View {
        let useDots = dots.isEmpty ? Self.sampleDots : dots
        Canvas { ctx, size in
            let w = size.width; let h = size.height; let mx = w/2
            let fw = w*0.30
            ctx.fill(Path(CGRect(x:mx-fw,y:h*0.05,width:fw*2,height:h*0.90)),
                     with:.color(Color(red:0.10,green:0.22,blue:0.12)))
            ctx.fill(Path(CGRect(x:mx-fw*0.55,y:h*0.05,width:fw*1.10,height:h*0.90)),
                     with:.color(Color(red:0.14,green:0.30,blue:0.16)))
            for r in [0.20,0.35,0.50] as [Double] {
                let rv = CGFloat(r)*w
                ctx.stroke(Path(ellipseIn: CGRect(x:mx-rv,y:h*0.55-rv*0.4,width:rv*2,height:rv*0.8)),
                           with:.color(Color.white.opacity(0.08)),lineWidth:1)
            }
            var cl = Path(); cl.move(to:CGPoint(x:mx,y:h*0.05)); cl.addLine(to:CGPoint(x:mx,y:h*0.95))
            ctx.stroke(cl, with:.color(TCTheme.sage.opacity(0.18)),
                       style:StrokeStyle(lineWidth:1,dash:[4,4]))
            for d in useDots {
                ctx.fill(Path(ellipseIn: CGRect(x:d.x*w-4,y:d.y*h-4,width:8,height:8)),
                         with:.color(TCTheme.gold.opacity(0.78)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x:mx-5.5,y:h*0.52-5.5,width:11,height:11)),
                     with:.color(TCTheme.sage))
        }
    }
}

// MARK: - Range Hero Background (dark fairway scene for hero cards)

struct RangeHeroBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width; let h = size.height
            ctx.fill(Path(CGRect(origin:.zero, size:size)),
                     with:.linearGradient(Gradient(colors:[Color(red:0.03,green:0.12,blue:0.06),
                                                           Color(red:0.01,green:0.06,blue:0.03)]),
                                          startPoint:.zero,endPoint:CGPoint(x:0,y:h)))
            let gw = w*0.55
            ctx.fill(Path(CGRect(x:w*0.22,y:h*0.30,width:gw,height:h*0.70)),
                     with:.color(Color(red:0.14,green:0.30,blue:0.16).opacity(0.7)))
            var arc = Path()
            arc.move(to:CGPoint(x:w*0.08,y:h*0.78))
            arc.addCurve(to:CGPoint(x:w*0.72,y:h*0.35),
                         control1:CGPoint(x:w*0.18,y:h*0.15),
                         control2:CGPoint(x:w*0.55,y:h*0.08))
            ctx.stroke(arc,with:.color(TCTheme.gold.opacity(0.55)),
                       style:StrokeStyle(lineWidth:1.5,lineCap:.round,dash:[5,4]))
            ctx.fill(Path(ellipseIn:CGRect(x:w*0.69,y:h*0.33,width:8,height:8)),
                     with:.color(TCTheme.gold))
            // Device silhouette (range monitor)
            let dx=w*0.72; let dy=h*0.45
            ctx.fill(Path(CGRect(x:dx,y:dy,width:w*0.22,height:h*0.28)),
                     with:.color(Color(red:0.08,green:0.14,blue:0.10).opacity(0.8)))
            ctx.stroke(Path(CGRect(x:dx,y:dy,width:w*0.22,height:h*0.28)),
                       with:.color(TCTheme.sage.opacity(0.20)),lineWidth:1)
            ctx.fill(Path(CGRect(x:dx+w*0.04,y:dy+h*0.04,width:w*0.14,height:h*0.12)),
                     with:.color(TCTheme.sage.opacity(0.15)))
            // Ball
            ctx.fill(Path(ellipseIn:CGRect(x:w*0.12,y:h*0.74,width:10,height:10)),
                     with:.color(.white.opacity(0.85)))
            ctx.stroke(Path(ellipseIn:CGRect(x:w*0.12,y:h*0.74,width:10,height:10)),
                       with:.color(TCTheme.gold.opacity(0.40)),lineWidth:1)
        }
    }
}
