import SwiftUI

struct PastSessionsView: View {
    @EnvironmentObject var session: AuthSessionStore

    @State private var selectedFilter = "All"
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var shots:         [SavedShot]       = []
    @State private var rangeSessions: [PracticeSession] = []
    @State private var simSessions:   [SimSession]      = []
    @State private var rounds:        [CourseRound]     = []

    private let filters = ["All", "Range", "Sim", "Course", "Saved Shots"]

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    // Header
                    TCHeaderBar(initials: userInitials) {
                        TCIconButton(icon: "magnifyingglass") { showSearch.toggle() }
                        TCIconButton(icon: "slider.horizontal.3") { cycleFilter() }
                    }

                    // Section label
                    Text("PAST SESSIONS")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TCTheme.hPad)

                    // Filter tabs
                    if showSearch {
                        TextField("Search sessions", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundColor(TCTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(TCTheme.panelRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.horizontal, TCTheme.hPad)
                    }

                    // Filter tabs
                    TCFilterTabBar(tabs: filters, selected: $selectedFilter)
                        .padding(.horizontal, TCTheme.hPad)

                    // Summary strip
                    summaryStrip
                        .padding(.horizontal, TCTheme.hPad)

                    // Session cards
                    sessionCards
                        .padding(.horizontal, TCTheme.hPad)

                    // Export card
                    exportCard
                        .padding(.horizontal, TCTheme.hPad)

                    Spacer(minLength: 140)
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Past Sessions")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .task { await loadData() }
    }

    // MARK: - Summary Strip

    private var totalSessions: Int { rangeSessions.count + simSessions.count + rounds.count }

    private var avgBallSpeedStr: String {
        let vals = shots.map { $0.metrics.ballSpeedMph }.filter { $0 > 0 }
        guard !vals.isEmpty else { return "—" }
        return "\(Int(vals.reduce(0, +) / Double(vals.count)))"
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryItem("\(totalSessions)", "Total Sessions")

            Rectangle()
                .fill(TCTheme.border)
                .frame(width: 1, height: 24)

            summaryItem("\(shots.count)", "Saved Shots")

            Rectangle()
                .fill(TCTheme.border)
                .frame(width: 1, height: 24)

            summaryItem(avgBallSpeedStr, "Avg Ball Speed")
        }
        .tcCard(padding: 14)
    }

    private func summaryItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.5)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session Cards (filtered)

    @ViewBuilder
    private var sessionCards: some View {
        VStack(spacing: 14) {
            // Range sessions
            if selectedFilter == "All" || selectedFilter == "Range" {
                if filteredRangeSessions.isEmpty {
                    emptySessionCard(icon: "scope", message: "No range sessions yet.")
                } else {
                    ForEach(filteredRangeSessions) { rs in rangeSessionCard(rs) }
                }
            }

            // Sim sessions
            if selectedFilter == "All" || selectedFilter == "Sim" {
                if filteredSimSessions.isEmpty {
                    emptySessionCard(icon: "display", message: "No sim sessions yet.")
                } else {
                    ForEach(filteredSimSessions) { ss in simSessionCard(ss) }
                }
            }

            // Course rounds
            if selectedFilter == "All" || selectedFilter == "Course" {
                if filteredRounds.isEmpty {
                    emptySessionCard(icon: "flag.fill", message: "No rounds yet.")
                } else {
                    ForEach(filteredRounds) { r in courseRoundCard(r) }
                }
            }

            // Saved shots grid
            if selectedFilter == "Saved Shots" {
                savedShotsGrid
            }
        }
    }

    // MARK: - Empty Session Card

    private func emptySessionCard(icon: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(TCTheme.textMuted)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
            Spacer()
        }
        .padding(.vertical, 20)
        .tcCard()
    }

    // MARK: - Live Session Cards

    private func rangeSessionCard(_ rs: PracticeSession) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Range Session · \(shortDate(rs.startedAt))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(rs.selectedClubName ?? "All Clubs")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(rs.shotIds.count)")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("SHOTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }
            TCDivider()
            HStack(spacing: 0) {
                sessionStat("Avg Ball Speed", String(format: "%.0f mph", rs.summary.avgBallSpeed))
                sessionStat("Avg Carry",      String(format: "%.0f yds", rs.summary.avgCarry))
                sessionStat("Best Carry",     String(format: "%.0f yds", rs.summary.bestCarry))
            }
        }
        .tcCard()
    }

    private func simSessionCard(_ ss: SimSession) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "display")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sim Session · \(shortDate(ss.startedAt))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(ss.provider.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ss.shotIds.count)")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("SHOTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }
        }
        .tcCard()
    }

    private func courseRoundCard(_ r: CourseRound) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "flag")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Round · \(shortDate(r.startedAt))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(r.courseName)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
            }
            TCDivider()
            let diff = r.scoreSummary.totalScore - r.scoreSummary.totalPar
            HStack(spacing: 0) {
                sessionStat("Score",    diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                sessionStat("Fairways", "\(r.scoreSummary.fairwaysHit)")
                sessionStat("Putts",    "\(r.scoreSummary.totalPutts)")
            }
        }
        .tcCard()
    }

    // MARK: - Saved Shots Grid

    private var savedShotsGrid: some View {
        let displayShots = Array(filteredShots.prefix(9))
        return LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            if displayShots.isEmpty {
                Text("No shots saved yet.")
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(displayShots) { shot in
                    TCShotThumb(
                        clubName: shot.clubName ?? "Driver",
                        yards: Int(shot.metrics.carryYards)
                    )
                }
            }
        }
    }

    // MARK: - Export Card

    private var exportCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(TCTheme.textMuted)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("Export Session")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Export data or analyze offline.")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TCTheme.textUltraMuted)
        }
        .tcCard()
    }

    // MARK: - Helpers

    private func sessionStat(_ label: String, _ value: String) -> some View {
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
        }
        .frame(maxWidth: .infinity)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? "Player"
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "P")).uppercased()
                 + String((parts[1].first ?? "L")).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var filteredRangeSessions: [PracticeSession] {
        guard hasSearch else { return rangeSessions }
        return rangeSessions.filter {
            matches($0.selectedClubName) || matches(shortDate($0.startedAt)) || matches("Range Session")
        }
    }

    private var filteredSimSessions: [SimSession] {
        guard hasSearch else { return simSessions }
        return simSessions.filter { matches($0.provider.rawValue) || matches(shortDate($0.startedAt)) || matches("Sim Session") }
    }

    private var filteredRounds: [CourseRound] {
        guard hasSearch else { return rounds }
        return rounds.filter { matches($0.courseName) || matches($0.teeBoxName) || matches(shortDate($0.startedAt)) }
    }

    private var filteredShots: [SavedShot] {
        guard hasSearch else { return shots }
        return shots.filter { matches($0.clubName) || matches(shortDate($0.timestamp)) || matches("\(Int($0.metrics.carryYards))") }
    }

    private var hasSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func matches(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.localizedCaseInsensitiveContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func cycleFilter() {
        guard let index = filters.firstIndex(of: selectedFilter) else {
            selectedFilter = filters[0]
            return
        }
        selectedFilter = filters[(index + 1) % filters.count]
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let uid = session.currentUser?.id else { return }
        let backend = session.backend
        async let shotList      = backend.loadShots(userId: uid)
        async let rangeList     = backend.loadRangeSessions(userId: uid)
        async let simList       = backend.loadSimSessions(userId: uid)
        async let roundList     = backend.loadCourseRounds(userId: uid)
        shots         = (try? await shotList)   ?? []
        rangeSessions = (try? await rangeList)  ?? []
        simSessions   = (try? await simList)    ?? []
        rounds        = (try? await roundList)  ?? []
    }
}
