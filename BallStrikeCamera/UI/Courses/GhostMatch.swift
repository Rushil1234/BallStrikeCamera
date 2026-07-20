import SwiftUI

// MARK: - Ghost match: race a past round on the same course

/// Match-play scoring between the live round and a "ghost" (a completed past
/// round on the same course). Pure math — holes are compared by holeNumber,
/// and only holes where BOTH rounds have a score count.
enum GhostMatchScorer {

    struct Status: Equatable {
        let holesUp: Int       // positive = you're up, negative = down
        let thru: Int          // holes compared so far
        let decided: Bool      // lead exceeds holes remaining — match closed out
        let roundLength: Int

        /// "1 UP thru 5", "ALL SQUARE thru 3", or a final "WON 3&2" / "LOST 2 DN".
        var text: String {
            guard thru > 0 else { return "Match starts on your first scored hole" }
            if decided {
                let remaining = roundLength - thru
                if holesUp > 0 {
                    return remaining > 0 ? "WON \(holesUp)&\(remaining)" : "WON \(holesUp) UP"
                } else {
                    return remaining > 0 ? "LOST \(-holesUp)&\(remaining)" : "LOST \(-holesUp) DN"
                }
            }
            if thru == roundLength {   // all holes played, no closeout margin
                if holesUp == 0 { return "HALVED" }
                return holesUp > 0 ? "WON \(holesUp) UP" : "LOST \(-holesUp) DN"
            }
            if holesUp == 0 { return "ALL SQUARE thru \(thru)" }
            return holesUp > 0 ? "\(holesUp) UP thru \(thru)" : "\(-holesUp) DN thru \(thru)"
        }
    }

    static func status(current: [RoundHole], ghost: [RoundHole]) -> Status {
        let ghostByNumber = Dictionary(uniqueKeysWithValues: ghost.map { ($0.holeNumber, $0) })
        var up = 0, thru = 0
        for hole in current.sorted(by: { $0.holeNumber < $1.holeNumber }) {
            guard let mine = hole.score,
                  let theirs = ghostByNumber[hole.holeNumber]?.score else { continue }
            thru += 1
            if mine < theirs { up += 1 } else if mine > theirs { up -= 1 }
        }
        let length = max(ghost.count, current.count)
        let decided = thru > 0 && abs(up) > (length - thru)
        return Status(holesUp: up, thru: thru, decided: decided, roundLength: length)
    }

    /// The ghost's score on a given hole, if it has one.
    static func ghostScore(onHole holeNumber: Int, ghost: [RoundHole]) -> Int? {
        ghost.first(where: { $0.holeNumber == holeNumber })?.score
    }

    /// Past rounds eligible to be a ghost: same course, actually scored, and not
    /// the round being played. Best (lowest) score first.
    static func candidates(from rounds: [CourseRound], courseId: String, excluding currentId: UUID?) -> [CourseRound] {
        rounds
            .filter { $0.courseId == courseId && $0.id != currentId && $0.scoreSummary.totalScore > 0 }
            .sorted { $0.scoreSummary.totalScore < $1.scoreSummary.totalScore }
    }
}

// MARK: - Persistence (survive app restart mid-round)

/// Remembers which ghost is being raced in the active round so resuming a
/// round after an app restart restores the match. One key, self-overwriting —
/// there's only ever one live round, so no per-round key buildup.
enum GhostPersistence {
    private static let key = "tc.ghost.active"

    static func save(roundId: UUID, ghostId: UUID) {
        UserDefaults.standard.set("\(roundId.uuidString)|\(ghostId.uuidString)", forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// The saved ghost id, but only if it was saved for this round.
    static func ghostId(forRound roundId: UUID) -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = raw.split(separator: "|").map(String.init)
        guard parts.count == 2, parts[0] == roundId.uuidString else { return nil }
        return UUID(uuidString: parts[1])
    }
}

// MARK: - HUD strip (live match state)

/// The in-round ghost readout, styled like the other HUD pills. Shows the
/// ghost's score on the current hole plus the running match status.
struct GhostStrip: View {
    let ghost: CourseRound
    let currentHoles: [RoundHole]
    let currentHoleNumber: Int
    let onEnd: () -> Void

    private var status: GhostMatchScorer.Status {
        GhostMatchScorer.status(current: currentHoles, ghost: ghost.holes)
    }

    private var statusColor: Color {
        if status.thru == 0 { return .white.opacity(0.85) }
        if status.holesUp > 0 { return TCTheme.captureGold }
        if status.holesUp < 0 { return TCTheme.captureSilver }
        return .white.opacity(0.9)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
            if let ghostScore = GhostMatchScorer.ghostScore(onHole: currentHoleNumber, ghost: ghost.holes) {
                Text("Ghost: \(ghostScore) here")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("·")
                    .foregroundColor(.white.opacity(0.5))
            }
            Text(status.text)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(statusColor)
            Button(action: onEnd) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 7).hudGlass(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ghost match: \(status.text)")
    }
}

// MARK: - Offer chip (ghost available, not yet racing)

struct GhostOfferChip: View {
    let bestScore: Int
    let onPick: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPick) {
                HStack(spacing: 7) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .bold))
                    Text("Race your ghost — best here: \(bestScore)")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 7).hudGlass(14)
    }
}

// MARK: - Ghost picker sheet

/// Lists the golfer's past scored rounds on this course, best first.
struct GhostPickerSheet: View {
    let candidates: [CourseRound]
    let onSelect: (CourseRound) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    var body: some View {
        ZStack {
            TCTheme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Race a Ghost")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Play match-play against one of your past rounds here. Win holes by beating the score you shot that day.")
                        .font(.system(size: 13))
                        .foregroundColor(TCTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, round in
                            Button {
                                onSelect(round)
                                dismiss()
                            } label: {
                                candidateRow(round, isBest: index == 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private func candidateRow(_ round: CourseRound, isBest: Bool) -> some View {
        let s = round.scoreSummary
        let toPar = s.totalScore - s.totalPar
        let toParStr = s.totalPar > 0 ? (toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")) : ""
        return HStack(spacing: 12) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isBest ? TCTheme.gold : TCTheme.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: round.startedAt))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    if isBest {
                        TCPill(text: "Best", color: TCTheme.gold)
                    }
                }
                Text("\(round.teeBoxName) tees")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer(minLength: 8)
            Text(toParStr.isEmpty ? "\(s.totalScore)" : "\(s.totalScore) (\(toParStr))")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(TCTheme.textPrimary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TCTheme.border, lineWidth: 1))
    }
}
