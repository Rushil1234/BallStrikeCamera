import SwiftUI

struct ScorecardView: View {
    @Environment(\.dismiss) private var dismiss
    let round: CourseRound
    let course: GolfCourse?

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BSTheme.sectionGap) {
                        summaryCard
                        if !frontNine.isEmpty { nineCard(title: "Front 9", holes: frontNine) }
                        if !backNine.isEmpty  { nineCard(title: "Back 9",  holes: backNine)  }
                        statsCard
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, BSTheme.hPad)
                    .padding(.top, 4)
                }
            }
            .navigationTitle("Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundColor(BSTheme.textMuted)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(round.courseName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(BSTheme.textPrimary)
                Text("\(round.teeBoxName) Tees · \(formattedDate)")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                let diff = round.scoreSummary.totalScore - round.scoreSummary.totalPar
                Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(diff < 0 ? BSTheme.fairwayGreen : (diff == 0 ? BSTheme.electricCyan : BSTheme.textPrimary))
                Text("\(round.scoreSummary.totalScore) / \(round.scoreSummary.totalPar)")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
        }
        .premiumCard()
    }

    // MARK: - Nine Card

    private func nineCard(title: String, holes: [RoundHole]) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                columnHeader("Hole", width: 40)
                columnHeader("Par",  width: 36)
                columnHeader("Yds",  width: 50)
                Spacer()
                columnHeader("Score", width: 52)
                columnHeader("Putts", width: 44)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))

            BSDivider()

            // Hole rows
            ForEach(holes) { hole in
                ScorecardRow(hole: hole, golfHole: golfHole(for: hole), teeBox: nil)
                BSDivider()
            }

            // Sub-total
            let subtotalScore = holes.compactMap { $0.score }.reduce(0, +)
            let subtotalPar   = holes.map { $0.par }.reduce(0, +)
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(BSTheme.textMuted)
                    .frame(width: 40, alignment: .leading)
                Spacer()
                Text("\(subtotalPar)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BSTheme.textMuted)
                    .frame(width: 52, alignment: .center)
                Text(holes.allSatisfy { $0.score != nil } ? "\(subtotalScore)" : "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BSTheme.textPrimary)
                    .frame(width: 44, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
        }
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
            .strokeBorder(BSTheme.border, lineWidth: 1))
    }

    // MARK: - Stats

    private var statsCard: some View {
        VStack(spacing: 12) {
            BSectionHeader(title: "Round Stats")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 10) {
                let s = round.scoreSummary
                StatTile(label: "FIR",    value: "\(s.fairwaysHit)",  accent: BSTheme.fairwayGreen)
                StatTile(label: "GIR",    value: "\(s.greensInReg)",  accent: BSTheme.electricCyan)
                StatTile(label: "Putts",  value: "\(s.totalPutts)",   accent: BSTheme.gold)
                StatTile(label: "Score",  value: "\(s.totalScore)",   accent: BSTheme.textPrimary)
            }
        }
    }

    // MARK: - Helpers

    private var frontNine: [RoundHole] { round.holes.filter { $0.holeNumber <= 9  } }
    private var backNine:  [RoundHole] { round.holes.filter { $0.holeNumber >= 10 } }

    private func golfHole(for rh: RoundHole) -> GolfHole? {
        course?.holes.first { $0.number == rh.holeNumber }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: round.startedAt)
    }

    private func columnHeader(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(BSTheme.textMuted)
            .frame(width: width, alignment: .center)
    }
}

// MARK: - Scorecard Row

private struct ScorecardRow: View {
    let hole: RoundHole
    let golfHole: GolfHole?
    let teeBox: TeeBox?

    var body: some View {
        HStack(spacing: 0) {
            Text("\(hole.holeNumber)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSTheme.textPrimary)
                .frame(width: 40, alignment: .leading)
            Text("\(hole.par)")
                .font(.system(size: 14))
                .foregroundColor(BSTheme.textMuted)
                .frame(width: 36, alignment: .center)
            if let yards = yardage {
                Text("\(yards)")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
                    .frame(width: 50, alignment: .center)
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
                    .frame(width: 50, alignment: .center)
            }
            Spacer()
            // Score box
            if let s = hole.score {
                Text("\(s)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(scoreColor(s))
                    .frame(width: 52, alignment: .center)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(BSTheme.textMuted)
                    .frame(width: 52, alignment: .center)
            }
            if let p = hole.putts {
                Text("\(p)")
                    .font(.system(size: 14))
                    .foregroundColor(BSTheme.textMuted)
                    .frame(width: 44, alignment: .center)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(BSTheme.textMuted)
                    .frame(width: 44, alignment: .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var yardage: Int? {
        guard let gh = golfHole, let tee = teeBox else { return nil }
        return gh.teeYardsByTeeBox[tee.id]
    }

    private func scoreColor(_ s: Int) -> Color {
        let diff = s - hole.par
        if diff < -1 { return BSTheme.gold }
        if diff == -1 { return BSTheme.fairwayGreen }
        if diff == 0 { return BSTheme.textPrimary }
        if diff == 1 { return BSTheme.gold }
        return BSTheme.dangerRed
    }
}
