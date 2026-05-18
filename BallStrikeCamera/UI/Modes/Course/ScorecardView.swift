import SwiftUI

struct ScorecardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showRoundSummary = false

    let round: CourseRound
    let course: GolfCourse?

    // MARK: - Computed

    private var frontNine: [RoundHole] { round.holes.filter { $0.holeNumber <= 9 } }
    private var backNine:  [RoundHole] { round.holes.filter { $0.holeNumber > 9  } }

    private var scoreDiff: Int { round.scoreSummary.totalScore - round.scoreSummary.totalPar }

    private var matchedTeeBox: TeeBox? {
        course?.teeBoxes.first(where: { $0.name == round.teeBoxName })
    }

    private func frontTotal(_ holes: [RoundHole]) -> Int {
        holes.reduce(0) { $0 + ($1.score ?? $1.par) }
    }

    private var totalScore: Int {
        let s = round.scoreSummary.totalScore
        return s > 0 ? s : round.holes.reduce(0) { $0 + ($1.score ?? $1.par) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                // Header bar
                headerBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: TCTheme.sectionGap) {
                        // Course summary card
                        courseCard
                            .padding(.horizontal, TCTheme.hPad)

                        // Scorecard grid
                        scorecardGrid
                            .padding(.horizontal, TCTheme.hPad)

                        // Legend
                        legendRow
                            .padding(.horizontal, TCTheme.hPad)

                        // Summary strip
                        summaryStrip
                            .padding(.horizontal, TCTheme.hPad)

                        // Stats card
                        statsCard
                            .padding(.horizontal, TCTheme.hPad)

                        // Action buttons
                        VStack(spacing: 10) {
                            TCPrimaryGoldButton(title: "Back to Hole", icon: "arrow.left") {
                                dismiss()
                            }
                            TCOutlineButton(title: "Round Summary", color: TCTheme.sage) {
                                showRoundSummary = true
                            }
                        }
                        .padding(.horizontal, TCTheme.hPad)

                        Spacer(minLength: 40)
                    }
                    .padding(.top, TCTheme.sectionGap)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Round Summary", isPresented: $showRoundSummary) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(roundSummaryText)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(TCTheme.textMuted)
            }
            .buttonStyle(.plain)

            Spacer()
            TrueCarryLogo(size: 16)
            Spacer()

            ShareLink(item: roundSummaryText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 12)
        .background(TCTheme.panel)
        .overlay(Rectangle().fill(TCTheme.border).frame(height: 1), alignment: .bottom)
    }

    private var roundSummaryText: String {
        let diff = scoreDiff == 0 ? "E" : scoreDiff > 0 ? "+\(scoreDiff)" : "\(scoreDiff)"
        return "\(round.courseName)\nScore: \(totalScore) (\(diff))\nFairways: \(round.scoreSummary.fairwaysHit)\nGIR: \(round.scoreSummary.greensInReg)\nPutts: \(round.scoreSummary.totalPutts)"
    }

    // MARK: - Course Card

    private var courseCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "flag")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(TCTheme.textMuted)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(round.courseName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                Text("\(round.teeBoxName) Tees  ·  \(formattedDate(round.startedAt))")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
                if let r = matchedTeeBox?.rating, let s = matchedTeeBox?.slope {
                    Text(String(format: "Rating %.1f  /  Slope %d", r, s))
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(scoreDiff == 0 ? "E" : scoreDiff > 0 ? "+\(scoreDiff)" : "\(scoreDiff)")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(scoreDiff < 0 ? TCTheme.sage : scoreDiff == 0 ? TCTheme.cyan : TCTheme.textPrimary)
                Text("Total")
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textMuted)
            }
        }
        .tcCard()
    }

    // MARK: - Scorecard Grid

    private var scorecardGrid: some View {
        VStack(spacing: 0) {
            // Header row
            scorecardHeaderRow

            Divider().background(Color(white: 0.75))

            // Hole rows
            ForEach(Array(round.holes.enumerated()), id: \.element.id) { idx, hole in
                scorecardHoleRow(hole: hole)
                if idx < round.holes.count - 1 {
                    Divider().background(Color(white: 0.80))
                }
            }

            // OUT subtotal
            if frontNine.count == 9 {
                Divider().background(Color(white: 0.70))
                scorecardTotalRow(label: "OUT", holes: frontNine)
            }

            // IN subtotal
            if backNine.count == 9 {
                Divider().background(Color(white: 0.70))
                scorecardTotalRow(label: "IN", holes: backNine)
            }

            // TOTAL
            Divider().background(Color(white: 0.60))
            scorecardTotalRow(label: "TOTAL", holes: round.holes)
        }
        .background(Color(red: 0.96, green: 0.94, blue: 0.90))
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
    }

    private var scorecardHeaderRow: some View {
        HStack(spacing: 0) {
            Text("HOLE")
                .frame(width: 44, alignment: .leading)
            Text("PAR")
                .frame(width: 36, alignment: .center)
            Spacer()
            Text("SCORE")
                .frame(width: 54, alignment: .center)
            Text("PUTTS")
                .frame(width: 44, alignment: .center)
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(Color(red: 0.94, green: 0.90, blue: 0.80))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            // Top corners rounded, bottom corners square to join the rows below
            Color(red: 0.10, green: 0.23, blue: 0.13)
                .clipShape(
                    RoundedTopCornersShape(radius: TCTheme.cardRadius)
                )
        )
    }

    private func scorecardHoleRow(hole: RoundHole) -> some View {
        HStack(spacing: 0) {
            Text("\(hole.holeNumber)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(white: 0.15))
                .frame(width: 44, alignment: .leading)

            Text("\(hole.par)")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.40))
                .frame(width: 36, alignment: .center)

            Spacer()

            // Score cell with colored background
            if let s = hole.score {
                let diff = s - hole.par
                Text("\(s)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(diff < 0 ? .white : diff == 0 ? Color(white: 0.20) : .white)
                    .frame(width: 28, height: 28)
                    .background(scoreCellBackground(diff: diff))
                    .clipShape(diff > 0
                               ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                               : AnyShape(Circle()))
                    .frame(width: 54, alignment: .center)
            } else {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 54, alignment: .center)
            }

            // Putts
            if let p = hole.putts {
                Text("\(p)")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.35))
                    .frame(width: 44, alignment: .center)
            } else {
                Text("—")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 44, alignment: .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func scoreCellBackground(diff: Int) -> Color {
        if diff < 0  { return Color(red: 0.20, green: 0.65, blue: 0.30).opacity(0.85) }
        if diff == 0 { return Color(white: 0.82) }
        return Color(red: 0.85, green: 0.65, blue: 0.20).opacity(0.85)
    }

    private func scorecardTotalRow(label: String, holes: [RoundHole]) -> some View {
        let totalPar   = holes.reduce(0) { $0 + $1.par }
        let totalScore = holes.reduce(0) { $0 + ($1.score ?? $1.par) }
        let totalPutts = holes.compactMap { $0.putts }.reduce(0, +)

        return HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .black))
                .foregroundColor(Color(white: 0.20))
                .frame(width: 44, alignment: .leading)
            Text("\(totalPar)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(white: 0.40))
                .frame(width: 36, alignment: .center)
            Spacer()
            Text("\(totalScore)")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(Color(white: 0.15))
                .frame(width: 54, alignment: .center)
            Text(totalPutts > 0 ? "\(totalPutts)" : "—")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(white: 0.40))
                .frame(width: 44, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(white: 0.88))
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 14) {
            legendItem(isCircle: true,  color: Color(red: 0.20, green: 0.65, blue: 0.30).opacity(0.85), label: "Birdie or Better")
            legendItem(isCircle: true,  color: Color(white: 0.82),                                       label: "Par")
            legendItem(isCircle: false, color: Color(red: 0.85, green: 0.65, blue: 0.20).opacity(0.85), label: "Bogey or Worse")
        }
        .tcCard()
    }

    private func legendItem(isCircle: Bool, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            if isCircle {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary Strip

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryCell(label: "OUT",
                        value: frontNine.reduce(0) { $0 + ($1.score ?? $1.par) },
                        isScore: false)
            Rectangle().fill(TCTheme.border).frame(width: 1, height: 44)
            summaryCell(label: "IN",
                        value: backNine.reduce(0) { $0 + ($1.score ?? $1.par) },
                        isScore: false)
            Rectangle().fill(TCTheme.border).frame(width: 1, height: 44)
            summaryCell(label: "TOTAL", value: totalScore, isScore: false)
            Rectangle().fill(TCTheme.border).frame(width: 1, height: 44)
            summaryCell(label: "+/-",   value: scoreDiff,  isScore: true)
            Rectangle().fill(TCTheme.border).frame(width: 1, height: 44)
            summaryCell(label: "PUTTS",
                        value: round.scoreSummary.totalPutts,
                        isScore: false)
        }
        .tcCard(padding: 0)
        .padding(.vertical, 0)
    }

    private func summaryCell(label: String, value: Int, isScore: Bool) -> some View {
        VStack(spacing: 3) {
            let color: Color = isScore
                ? (value < 0 ? TCTheme.sage : value == 0 ? TCTheme.cyan : TCTheme.textPrimary)
                : TCTheme.textPrimary
            let display: String = isScore
                ? (value == 0 ? "E" : value > 0 ? "+\(value)" : "\(value)")
                : "\(value)"

            Text(display)
                .font(.system(size: 18, weight: .black))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        let s = round.scoreSummary
        return VStack(spacing: 12) {
            TCSectionHeader(title: "Round Stats")
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()),
                          GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                TCMetricTile(label: "FIR",   value: "\(s.fairwaysHit)", accent: TCTheme.sage)
                TCMetricTile(label: "GIR",   value: "\(s.greensInReg)", accent: TCTheme.cyan)
                TCMetricTile(label: "Putts", value: "\(s.totalPutts)",  accent: TCTheme.gold)
                TCMetricTile(label: "Score", value: "\(s.totalScore)",  accent: TCTheme.textPrimary)
            }
        }
        .tcCard()
    }

    // MARK: - Date Helper

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - AnyShape helper (iOS 16 polyfill)

private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
    }
    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

// MARK: - Rounded top corners only

private struct RoundedTopCornersShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
