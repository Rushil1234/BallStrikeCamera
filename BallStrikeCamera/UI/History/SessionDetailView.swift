import SwiftUI

// MARK: - Session type wrapper (Identifiable for sheet/NavigationLink use)

enum SessionItem: Identifiable {
    case range(PracticeSession)
    case sim(SimSession)
    case course(CourseRound)

    var id: UUID {
        switch self {
        case .range(let s):  return s.id
        case .sim(let s):    return s.id
        case .course(let r): return r.id
        }
    }

    var shotIds: [UUID] {
        switch self {
        case .range(let s):  return s.shotIds
        case .sim(let s):    return s.shotIds
        case .course(let r): return r.shotIds
        }
    }

    var displayName: String {
        switch self {
        case .range(let s):  return s.name.isEmpty ? "Range Session" : s.name
        case .sim(let s):    return s.name.isEmpty ? "Sim Session" : s.name
        case .course(let r): return r.name.isEmpty ? r.courseName : r.name
        }
    }

    var icon: String {
        switch self {
        case .range:  return "scope"
        case .sim:    return "display"
        case .course: return "flag.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .range:  return TCTheme.sage
        case .sim:    return TCTheme.gold
        case .course: return TCTheme.sage
        }
    }

    var startedAt: Date {
        switch self {
        case .range(let s):  return s.startedAt
        case .sim(let s):    return s.startedAt
        case .course(let r): return r.startedAt
        }
    }

    var subtitle: String {
        switch self {
        case .range(let s):  return s.selectedClubName.map { "Club: \($0)" } ?? "All Clubs"
        case .sim(let s):    return s.provider.rawValue + (s.usedOpenGolfSim ? " · OGS" : "")
        case .course(let r): return "\(r.courseName) · \(r.teeBoxName) Tees"
        }
    }
}

// MARK: - SessionDetailView

struct SessionDetailView: View {
    @EnvironmentObject var session: AuthSessionStore
    let item: SessionItem

    @State private var shots: [SavedShot] = []
    @State private var isLoading = true

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView()
                        .tint(TCTheme.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: TCTheme.sectionGap) {
                            headerCard
                            if case .range(let rs) = item { rangeStatsCard(rs) }
                            if case .course(let r) = item { courseStatsCard(r) }
                            shotsSection
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, TCTheme.hPad)
                        .padding(.top, 12)
                    }
                }
            }
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .task { await loadShots() }
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(item.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(item.accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(item.shotIds.count)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("SHOTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }
            TCDivider()
            Text(Self.dateFormatter.string(from: item.startedAt))
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
        }
        .tcCard()
    }

    // MARK: Range Stats

    private func rangeStatsCard(_ rs: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Session Stats")
            HStack(spacing: 0) {
                statItem("Avg Carry", rs.summary.avgCarry > 0 ? "\(Int(rs.summary.avgCarry)) yd" : "—")
                statItem("Best Carry", rs.summary.bestCarry > 0 ? "\(Int(rs.summary.bestCarry)) yd" : "—")
                statItem("Avg Ball Spd", rs.summary.avgBallSpeed > 0 ? "\(Int(rs.summary.avgBallSpeed)) mph" : "—")
            }
        }
        .tcCard()
    }

    // MARK: Course Stats

    private func courseStatsCard(_ r: CourseRound) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Round Summary")
            HStack(spacing: 0) {
                let diff = r.scoreSummary.totalScore - r.scoreSummary.totalPar
                statItem("Score", r.scoreSummary.totalPar == 0 ? "—" : (diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)"))
                statItem("Fairways", "\(r.scoreSummary.fairwaysHit)")
                statItem("Putts", "\(r.scoreSummary.totalPutts)")
            }
        }
        .tcCard()
    }

    // MARK: Shots List

    private var shotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Shots")
            if shots.isEmpty {
                Text("No shots recorded.")
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(shots.enumerated()), id: \.element.id) { idx, shot in
                        NavigationLink(destination: ShotDetailView(shot: shot)) {
                            shotRow(shot, number: idx + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func shotRow(_ shot: SavedShot, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("#\(number)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(TCTheme.textMuted)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(shot.clubName ?? "Unknown")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(shot.source == .simulated ? "Simulated" : "Live")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }

            Spacer()

            HStack(spacing: 16) {
                if shot.metrics.carryYards > 0 {
                    metricPair("\(Int(shot.metrics.carryYards))", "yd", "carry")
                }
                if shot.metrics.ballSpeedMph > 0 {
                    metricPair("\(Int(shot.metrics.ballSpeedMph))", "mph", "ball spd")
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TCTheme.textUltraMuted)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TCTheme.border, lineWidth: 1))
    }

    // MARK: Helpers

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.5)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricPair(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.textPrimary)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textMuted)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(TCTheme.textMuted)
        }
    }

    private func loadShots() async {
        guard let uid = session.currentUser?.id else { isLoading = false; return }
        let ids = item.shotIds
        let all = (try? await session.backend.loadShots(userId: uid)) ?? []
        let ordered = ids.compactMap { id in all.first(where: { $0.id == id }) }
        shots = ordered
        isLoading = false
    }
}
