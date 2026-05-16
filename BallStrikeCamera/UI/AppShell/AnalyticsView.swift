import SwiftUI

private struct ClubAvg: Identifiable {
    let id = UUID()
    let name: String
    let abbrev: String
    let carry: Int
    let ballSpeed: Int
    let smash: Double
    let barFraction: CGFloat
}

private struct InsightMock: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let accent: Color
}

struct AnalyticsView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var selectedClub = "All"
    private let clubs = ["All", "Driver", "3W", "5I", "6I", "7I", "8I", "9I", "PW"]

    private let clubAverages: [ClubAvg] = [
        ClubAvg(name: "Driver",   abbrev: "Dr",  carry: 241, ballSpeed: 148, smash: 1.42, barFraction: 1.00),
        ClubAvg(name: "3 Wood",   abbrev: "3W",  carry: 218, ballSpeed: 140, smash: 1.44, barFraction: 0.90),
        ClubAvg(name: "5 Iron",   abbrev: "5I",  carry: 191, ballSpeed: 127, smash: 1.43, barFraction: 0.79),
        ClubAvg(name: "6 Iron",   abbrev: "6I",  carry: 178, ballSpeed: 119, smash: 1.43, barFraction: 0.74),
        ClubAvg(name: "7 Iron",   abbrev: "7I",  carry: 162, ballSpeed: 112, smash: 1.44, barFraction: 0.67),
        ClubAvg(name: "8 Iron",   abbrev: "8I",  carry: 148, ballSpeed: 103, smash: 1.43, barFraction: 0.61),
        ClubAvg(name: "9 Iron",   abbrev: "9I",  carry: 132, ballSpeed: 94,  smash: 1.42, barFraction: 0.55),
        ClubAvg(name: "PW",       abbrev: "PW",  carry: 112, ballSpeed: 82,  smash: 1.41, barFraction: 0.46),
    ]

    private let insights: [InsightMock] = [
        InsightMock(icon: "arrow.up.right.circle.fill", text: "Your Driver carry is up 4 yd this week. Smash factor trending better.", accent: BSTheme.fairwayGreen),
        InsightMock(icon: "scope",                      text: "Typical dispersion is ±9 yd. Narrowing down from ±13 yd last month.",   accent: BSTheme.electricCyan),
        InsightMock(icon: "exclamationmark.triangle.fill", text: "Club path is averaging 2.1° in-to-out. May promote a slight draw.",   accent: BSTheme.gold),
    ]

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: BSTheme.sectionGap) {
                    clubPicker
                    heroStats
                    clubAveragesCard
                    dispersionCard
                    distanceTrendCard
                    aiInsightsCard
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, BSTheme.hPad)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .task {
            // Analytics data is derived from saved shots — hook up AnalyticsViewModel here
        }
    }

    // MARK: Club Picker

    private var clubPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(clubs, id: \.self) { c in
                    Button { selectedClub = c } label: {
                        Text(c)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedClub == c ? .black : BSTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedClub == c
                                    ? AnyView(Capsule().fill(BSTheme.rangeGradient))
                                    : AnyView(Capsule().fill(BSTheme.panel))
                            )
                            .overlay(Capsule().strokeBorder(BSTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Hero Stats

    private var heroStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: selectedClub == "All" ? "Overall" : selectedClub)
            HStack(spacing: 10) {
                StatTile(label: "Avg Driver Carry", value: "241", unit: "yd", icon: "arrow.up.right", accent: BSTheme.electricCyan)
                StatTile(label: "Best Shot",        value: "284", unit: "yd", icon: "star.fill",      accent: BSTheme.gold)
            }
            HStack(spacing: 10) {
                StatTile(label: "Typical Miss",    value: "6",  unit: "yd R", icon: "scope",          accent: BSTheme.simPurple)
                StatTile(label: "Consistency",     value: "78", unit: "%",    icon: "chart.line.uptrend.xyaxis", accent: BSTheme.fairwayGreen)
            }
        }
    }

    // MARK: Club Averages Card

    private var clubAveragesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BSectionHeader(title: "Club Averages")
            VStack(spacing: 0) {
                // Column header
                HStack {
                    Text("Club").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Carry").frame(width: 60, alignment: .trailing)
                    Text("Ball Spd").frame(width: 70, alignment: .trailing)
                    Text("Smash").frame(width: 56, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BSTheme.panelRaised)

                ForEach(clubAverages) { club in
                    clubAverageRow(club)
                    if club.id != clubAverages.last?.id {
                        BSDivider()
                    }
                }
            }
            .background(BSTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                    .strokeBorder(BSTheme.border, lineWidth: 1)
            )
        }
    }

    private func clubAverageRow(_ club: ClubAvg) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(club.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                // Mini progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BSTheme.panelRaised).frame(height: 4)
                        Capsule()
                            .fill(BSTheme.rangeGradient)
                            .frame(width: geo.size.width * club.barFraction, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(club.carry)")
                .frame(width: 60, alignment: .trailing)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(BSTheme.textPrimary)
            Text("\(club.ballSpeed)")
                .frame(width: 70, alignment: .trailing)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(BSTheme.textSecondary)
            Text(String(format: "%.2f", club.smash))
                .frame(width: 56, alignment: .trailing)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(BSTheme.electricCyan)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Dispersion Card

    private var dispersionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BSectionHeader(title: "Dispersion")
            ZStack {
                // Dispersion visualization
                Canvas { ctx, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let dots: [(CGFloat, CGFloat, Double)] = [
                        (0.50, 0.45, 0.9), (0.48, 0.42, 0.8), (0.52, 0.48, 0.9),
                        (0.46, 0.44, 0.7), (0.54, 0.46, 0.8), (0.51, 0.40, 0.7),
                        (0.53, 0.50, 0.6), (0.44, 0.47, 0.5), (0.56, 0.43, 0.5),
                        (0.42, 0.52, 0.4), (0.58, 0.54, 0.4),
                    ]
                    // Rings
                    for r in [0.18, 0.30, 0.42].map({ $0 * size.width }) {
                        var p = Path()
                        p.addEllipse(in: CGRect(x: cx - r, y: cy - r * 0.55, width: r * 2, height: r * 1.1))
                        ctx.stroke(p, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
                    }
                    // Target line
                    var line = Path()
                    line.move(to: CGPoint(x: cx, y: cy - size.height * 0.42))
                    line.addLine(to: CGPoint(x: cx, y: cy - size.height * 0.05))
                    ctx.stroke(line, with: .color(BSTheme.electricCyan.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    // Dots
                    for (nx, ny, alpha) in dots {
                        let x = nx * size.width
                        let y = ny * size.height
                        let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                        ctx.fill(Path(ellipseIn: rect), with: .color(BSTheme.electricCyan.opacity(alpha)))
                    }
                    // Center
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy * 0.90 - 5, width: 10, height: 10)),
                             with: .color(BSTheme.fairwayGreen))
                }
                .frame(height: 160)
            }
            HStack(spacing: 0) {
                dispersionStat(label: "Avg Left",  value: "3 yd")
                Divider().background(BSTheme.border).frame(height: 30)
                dispersionStat(label: "Avg Right", value: "9 yd")
                Divider().background(BSTheme.border).frame(height: 30)
                dispersionStat(label: "Long",      value: "4 yd")
                Divider().background(BSTheme.border).frame(height: 30)
                dispersionStat(label: "Short",     value: "7 yd")
            }
            .padding(.vertical, 8)
            .background(BSTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .premiumCard()
    }

    private func dispersionStat(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(BSTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(BSTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Distance Trend Card

    private var distanceTrendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BSectionHeader(title: "Carry Trend — Last 30 Days")
            let bars: [(String, CGFloat)] = [
                ("W1", 0.72), ("W2", 0.78), ("W3", 0.75), ("W4", 0.82),
                ("W5", 0.80), ("W6", 0.85), ("W7", 0.88), ("W8", 0.90),
            ]
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(bars, id: \.0) { label, frac in
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer()
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [BSTheme.electricCyan, BSTheme.fairwayGreen],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    .frame(height: geo.size.height * frac)
                            }
                        }
                        .frame(height: 80)
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(BSTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text("232 yd avg")
                    .font(.system(size: 11))
                    .foregroundColor(BSTheme.textMuted)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("+13 yd from baseline")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(BSTheme.fairwayGreen)
            }
        }
        .premiumCard()
    }

    // MARK: AI Insights Card

    private var aiInsightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                BSectionHeader(title: "Insights")
                Spacer()
                StatusPill(text: "AI", color: BSTheme.electricCyan, filled: true)
            }
            VStack(spacing: 10) {
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 16))
                            .foregroundColor(insight.accent)
                            .frame(width: 22)
                        Text(insight.text)
                            .font(.system(size: 13))
                            .foregroundColor(BSTheme.textSecondary)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(insight.accent.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(insight.accent.opacity(0.22), lineWidth: 1)
                    )
                }
            }
        }
        .premiumCard()
    }
}
