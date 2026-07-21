import SwiftUI

/// The full breakdown behind a feed post — opened by tapping the post body. Shows
/// every available stat (not just averages), and for the current user's own rounds
/// a hole-by-hole scorecard loaded from the linked round.
struct FeedActivityDetailView: View {
    let post: FeedPost
    let currentUserId: UUID
    let backend: AppBackend

    @Environment(\.dismiss) private var dismiss
    @State private var round: CourseRound?
    @State private var loading = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    private var stats: [(String, String)] {
        guard let m = post.activityMetadata else { return post.stats.map { ($0.label, $0.value) } }
        switch m.kind {
        case .round:
            return [
                ("Score", m.totalScore.map { "\($0)" } ?? "--"),
                ("To Par", m.scoreToPar.map { $0 == 0 ? "E" : ($0 > 0 ? "+\($0)" : "\($0)") } ?? "--"),
                ("Fairways", m.fairwaysHit.map { "\($0)" } ?? "--"),
                ("GIR", m.greensInRegulation.map { "\($0)" } ?? "--"),
                ("Putts", m.putts.map { "\($0)" } ?? "--"),
            ]
        case .range:
            return [
                ("Shots", m.shotCount.map { "\($0)" } ?? "--"),
                ("Avg Carry", m.averageCarryYards.map { "\($0) yd" } ?? "--"),
                ("Best Carry", m.bestCarryYards.map { "\($0) yd" } ?? "--"),
                ("Ball Speed", m.averageBallSpeedMph.map { "\($0) mph" } ?? "--"),
            ]
        case .sim:
            return [
                ("Shots", m.shotCount.map { "\($0)" } ?? "--"),
                ("Source", m.providerName ?? "Simulator"),
            ]
        case .manual:
            return post.stats.map { ($0.label, $0.value) }
        }
    }

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statsCard
                    if let round, !round.holes.isEmpty {
                        scorecard(round)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .task { await loadRoundIfOwn() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 32, height: 32)
                        .background(TCTheme.panel)
                        .clipShape(Circle())
                }
            }
            Text(post.title)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                AvatarCircle(name: post.authorName, size: 26)
                Text("\(post.authorName) · \(Self.dateFormatter.string(from: post.timestamp))")
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textMuted)
            }
        }
    }

    private var statsCard: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(spacing: 4) {
                    Text(s.1)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(s.0.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(TCTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
    }

    private func scorecard(_ round: CourseRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scorecard")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            VStack(spacing: 0) {
                scoreHeaderRow
                ForEach(round.holes) { hole in
                    scoreRow(hole)
                }
            }
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        }
    }

    private var scoreHeaderRow: some View {
        HStack {
            Text("HOLE").frame(width: 44, alignment: .leading)
            Text("PAR").frame(maxWidth: .infinity)
            Text("SCORE").frame(maxWidth: .infinity)
            Text("PUTTS").frame(maxWidth: .infinity)
        }
        .font(.system(size: 10, weight: .bold))
        .tracking(0.6)
        .foregroundColor(TCTheme.textMuted)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func scoreRow(_ hole: RoundHole) -> some View {
        let diff = (hole.score ?? hole.par) - hole.par
        let tint: Color = hole.score == nil ? TCTheme.textMuted
            : diff < 0 ? TCTheme.sage : diff == 0 ? TCTheme.textPrimary : TCTheme.gold
        return HStack {
            Text("\(hole.holeNumber)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
                .frame(width: 44, alignment: .leading)
            Text("\(hole.par)").frame(maxWidth: .infinity).foregroundColor(TCTheme.textMuted)
            Text(hole.score.map { "\($0)" } ?? "–").frame(maxWidth: .infinity).foregroundColor(tint).fontWeight(.bold)
            Text(hole.putts.map { "\($0)" } ?? "–").frame(maxWidth: .infinity).foregroundColor(TCTheme.textMuted)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(Rectangle().fill(TCTheme.border).frame(height: 1), alignment: .top)
    }

    private func loadRoundIfOwn() async {
        guard post.type == .round, let rid = post.linkedRoundId,
              post.userId == currentUserId, round == nil, !loading else { return }
        loading = true
        defer { loading = false }
        let all = (try? await backend.loadCourseRounds(userId: currentUserId)) ?? []
        round = all.first { $0.id == rid }
    }
}
