import SwiftUI

// History tab — reuses PastSessionsView which already supports
// Range / Course / Sim / Saved Shots with filter tabs and search.
struct TrueCarryHistoryView: View {
    var body: some View {
        PastSessionsView()
            .navigationBarHidden(true)
    }
}

// MARK: - Handicap (World Handicap System–style estimate)

/// Computes an estimated Handicap Index from the user's recent course rounds, following the WHS
/// "best N of last 20" method. Differentials use the played tee's course/slope rating when the
/// round captured them, otherwise fall back to strokes-over-par (neutral slope).
enum HandicapService {

    struct RoundDifferential: Identifiable {
        let round: CourseRound
        let differential: Double
        var counted: Bool          // among the lowest-K differentials used for the index
        var id: UUID { round.id }
    }

    struct Result {
        let index: Double?                       // nil until there are 3+ scored rounds
        let differentials: [RoundDifferential]   // most recent 20, newest first
        let usedCount: Int                       // K differentials averaged
        let totalScored: Int                     // total scored rounds available
    }

    /// Score differential for one round: (113 / slope) × (gross − course rating).
    static func differential(for round: CourseRound) -> Double? {
        let s = round.scoreSummary
        guard s.totalScore > 0, s.totalPar > 0 else { return nil }
        if let rating = round.courseRating, let slope = round.slopeRating, slope > 0 {
            return (113.0 / Double(slope)) * (Double(s.totalScore) - rating)
        }
        // No rating/slope captured → neutral course (rating = par, slope = 113) = strokes over par.
        return Double(s.totalScore - s.totalPar)
    }

    /// WHS table: how many of the lowest differentials to average, plus an adjustment, for a given
    /// number of available rounds.
    private static func selection(for n: Int) -> (use: Int, adjustment: Double)? {
        switch n {
        case ..<3:    return nil
        case 3:       return (1, -2.0)
        case 4:       return (1, -1.0)
        case 5:       return (1,  0.0)
        case 6:       return (2, -1.0)
        case 7...8:   return (2,  0.0)
        case 9...11:  return (3,  0.0)
        case 12...14: return (4,  0.0)
        case 15...16: return (5,  0.0)
        case 17...18: return (6,  0.0)
        case 19:      return (7,  0.0)
        default:      return (8,  0.0)   // 20
        }
    }

    static func compute(from rounds: [CourseRound]) -> Result {
        let scored = rounds
            .filter { differential(for: $0) != nil }
            .sorted { $0.startedAt > $1.startedAt }
        let recent = Array(scored.prefix(20))
        var diffs = recent.map {
            RoundDifferential(round: $0, differential: differential(for: $0)!, counted: false)
        }
        guard let sel = selection(for: diffs.count) else {
            return Result(index: nil, differentials: diffs, usedCount: 0, totalScored: scored.count)
        }
        let lowest = diffs.indices.sorted { diffs[$0].differential < diffs[$1].differential }.prefix(sel.use)
        for i in lowest { diffs[i].counted = true }
        let avg = lowest.map { diffs[$0].differential }.reduce(0, +) / Double(sel.use)
        let index = ((avg + sel.adjustment) * 10).rounded() / 10
        return Result(index: index, differentials: diffs, usedCount: sel.use, totalScored: scored.count)
    }

    static func indexString(_ index: Double?) -> String {
        guard let index else { return "—" }
        return index < 0 ? String(format: "+%.1f", -index) : String(format: "%.1f", index)
    }
}

// MARK: - Handicap / Scores page

struct HandicapView: View {
    let rounds: [CourseRound]

    private var result: HandicapService.Result { HandicapService.compute(from: rounds) }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    indexCard
                    if result.differentials.isEmpty {
                        emptyState
                    } else {
                        roundsSection
                    }
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Handicap")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
    }

    private var indexCard: some View {
        VStack(spacing: 6) {
            Text("HANDICAP INDEX")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(1.4)
            Text(HandicapService.indexString(result.index))
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .tcCard()
    }

    private var subtitle: String {
        if result.index == nil {
            return "Play \(max(0, 3 - result.totalScored)) more scored round\(3 - result.totalScored == 1 ? "" : "s") to get an estimated index."
        }
        return "Estimated from the best \(result.usedCount) of your last \(result.differentials.count) round\(result.differentials.count == 1 ? "" : "s")."
    }

    private var roundsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Last \(result.differentials.count) Round\(result.differentials.count == 1 ? "" : "s")")
            VStack(spacing: 8) {
                ForEach(result.differentials) { d in roundRow(d) }
            }
            Text("Dots mark the rounds counted toward your index. Differentials use each tee's course & slope rating when available, otherwise score relative to par.")
                .font(.system(size: 11))
                .foregroundColor(TCTheme.textUltraMuted)
                .padding(.top, 2)
        }
    }

    private func roundRow(_ d: HandicapService.RoundDifferential) -> some View {
        let r = d.round
        let s = r.scoreSummary
        let toPar = s.totalScore - s.totalPar
        let toParStr = toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")
        return HStack(spacing: 12) {
            Circle()
                .fill(d.counted ? TCTheme.sage : TCTheme.textUltraMuted.opacity(0.35))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.courseName.isEmpty ? (r.name.isEmpty ? "Round" : r.name) : r.courseName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                Text("\(Self.dateFormatter.string(from: r.startedAt)) · \(r.teeBoxName) tees")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(s.totalScore) (\(toParStr))")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Diff \(String(format: "%.1f", d.differential))")
                    .font(.system(size: 10))
                    .foregroundColor(d.counted ? TCTheme.sage : TCTheme.textMuted)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TCTheme.border, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.fill")
                .font(.system(size: 28))
                .foregroundColor(TCTheme.sage)
            Text("No scored rounds yet")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Text("Play and score a course round to start tracking your handicap.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .tcCard()
    }
}
