import SwiftUI

struct TrueCarryHomeView: View {
    @EnvironmentObject var session: AuthSessionStore

    @State private var shots: [SavedShot] = []
    @State private var rounds: [CourseRound] = []
    @State private var rangeSessions: [PracticeSession] = []
    @State private var showSessions = false
    @State private var showProfile = false

    // MARK: Derived helpers

    private var firstName: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "Golfer"
        return name.components(separatedBy: " ").first ?? name
    }

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2,
           let f = parts[0].first,
           let l = parts[1].first {
            return "\(f)\(l)"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var greetingPrefix: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        default: return "Good evening,"
        }
    }

    private var fairwayAccuracyStr: String {
        guard !rounds.isEmpty else { return "—" }
        let hit = rounds.reduce(0) { $0 + $1.scoreSummary.fairwaysHit }
        let total = rounds.count * 14
        guard total > 0 else { return "—" }
        return "\(Int(Double(hit) / Double(total) * 100))%"
    }

    // MARK: Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCProfileAvatarButton(initials: userInitials) { showProfile = true }
                    }
                    VStack(spacing: TCTheme.sectionGap) {
                        greetingCard
                        activitySection
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showSessions) {
            NavigationStack { PastSessionsView() }
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { TrueCarryProfileView() }
                .preferredColorScheme(.dark)
        }
        .task {
            if let uid = session.currentUser?.id {
                async let s = try? await session.backend.loadShots(userId: uid)
                async let r = try? await session.backend.loadCourseRounds(userId: uid)
                async let rs = try? await session.backend.loadRangeSessions(userId: uid)
                shots = await s ?? []
                rounds = await r ?? []
                rangeSessions = await rs ?? []
            }
        }
    }

    // MARK: Greeting Card

    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingPrefix)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(TCTheme.textMuted)
                Text(firstName)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
            }

            TCDivider()

            HStack(spacing: 0) {
                TCStatGroup(
                    icon: "chart.line.uptrend.xyaxis",
                    value: "—",
                    label: "HANDICAP",
                    color: TCTheme.gold
                )
                Spacer()
                TCStatGroup(
                    icon: "flag.fill",
                    value: "\(rounds.count)",
                    label: "ROUNDS YTD",
                    color: TCTheme.sage
                )
                Spacer()
                TCStatGroup(
                    icon: "scope",
                    value: fairwayAccuracyStr,
                    label: "ACCURACY",
                    color: TCTheme.cyan
                )
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Activity Feed

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity Feed")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Spacer()
                Button("View All") { showSessions = true }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
            }

            if rounds.isEmpty && rangeSessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "figure.golf")
                        .font(.system(size: 30))
                        .foregroundColor(TCTheme.textMuted)
                    Text("No activity yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textSecondary)
                    Text("Start a round or range session to see your stats here.")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                if let latestRound = rounds.first {
                    TCFeedCard(
                        avatarInitials: userInitials,
                        name: session.userProfile?.displayName ?? session.currentUser?.name ?? "You",
                        mode: "Round",
                        courseName: latestRound.courseName,
                        dateStr: formattedDate(latestRound.startedAt),
                        primaryStat: scoreStr(latestRound),
                        primaryLabel: "SCORE",
                        secondaryStat: "\(latestRound.scoreSummary.fairwaysHit)",
                        secondaryLabel: "FAIRWAYS",
                        tertiaryStat: "\(latestRound.scoreSummary.totalPutts)",
                        tertiaryLabel: "PUTTS"
                    )
                }

                if let latestRange = rangeSessions.first {
                    TCFeedCard(
                        avatarInitials: userInitials,
                        name: session.userProfile?.displayName ?? session.currentUser?.name ?? "You",
                        mode: "Practice",
                        courseName: latestRange.selectedClubName ?? "True Carry Range",
                        dateStr: formattedDate(latestRange.startedAt),
                        primaryStat: "\(Int(latestRange.summary.bestCarry)) yds",
                        primaryLabel: "BEST CARRY",
                        secondaryStat: "\(Int(latestRange.summary.avgBallSpeed)) mph",
                        secondaryLabel: "BALL SPEED",
                        tertiaryStat: "\(latestRange.summary.shotCount) shots",
                        tertiaryLabel: "SHOTS HIT"
                    )
                }
            }
        }
    }

    // MARK: Helpers

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }

    private func scoreStr(_ round: CourseRound) -> String {
        let diff = round.scoreSummary.totalScore - round.scoreSummary.totalPar
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }
}
