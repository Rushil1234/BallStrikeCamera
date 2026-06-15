import SwiftUI

struct TrueCarryLockerView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var showClubs    = false
    @State private var showSessions = false
    @State private var showProfile  = false
    @State private var clubs: [UserClub]     = []
    @State private var shots: [SavedShot]    = []
    @State private var rounds: [CourseRound] = []

    private var profile: UserProfile? { session.userProfile }
    private var user: AppUser?        { session.currentUser }

    // MARK: - Derived helpers

    private var userInitials: String {
        let name = profile?.displayName ?? user?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2, let f = parts[0].first, let l = parts[1].first {
            return "\(f)\(l)"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var displayName: String {
        profile?.displayName ?? user?.name ?? "Golfer"
    }

    private var homeCourseName: String {
        let name = profile?.homeCourseName ?? ""
        return name.isEmpty ? "No home course set" : name
    }

    private var avgScoreStr: String {
        let completed = rounds.filter { $0.scoreSummary.totalScore > 0 }
        guard !completed.isEmpty else { return "—" }
        let total = completed.reduce(0) { $0 + $1.scoreSummary.totalScore }
        return String(format: "%.1f", Double(total) / Double(completed.count))
    }

    private var subEightyCount: Int {
        rounds.filter { $0.scoreSummary.totalScore > 0 && $0.scoreSummary.totalScore < 80 }.count
    }

    private var bestRoundStr: String {
        let scores = rounds.compactMap { $0.scoreSummary.totalScore > 0 ? $0.scoreSummary.totalScore : nil }
        guard let best = scores.min() else { return "—" }
        let diff = best - 72
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCProfileAvatarButton(initials: userInitials, devMode: session.entitlementVM.isDeveloperMode) { showProfile = true }
                    }
                    VStack(spacing: TCTheme.sectionGap) {
                        profileCard
                        clubsInBagCard
                        milestonesCard
                        savedShotsCard
                        settingsRowCard
                        signOutButton
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showClubs) {
            if let uid = user?.id {
                NavigationStack {
                    ClubsInBagView(userId: uid, backend: session.backend)
                }
                .tcAppearance()
            }
        }
        .sheet(isPresented: $showSessions) {
            NavigationStack { PastSessionsView() }
                .tcAppearance()
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { TrueCarryProfileView() }
                .tcAppearance()
        }
        .task {
            if let uid = user?.id {
                async let c = try? await session.backend.loadClubs(userId: uid)
                async let s = try? await session.backend.loadShots(userId: uid)
                async let r = try? await session.backend.loadCourseRounds(userId: uid)
                clubs  = await c ?? []
                shots  = await s ?? []
                rounds = await r ?? []
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(TCTheme.panelRaised)
                    Circle()
                        .strokeBorder(TCTheme.gold.opacity(0.55), lineWidth: 1.5)
                    Text(String(userInitials.prefix(2)).uppercased())
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(TCTheme.sage)
                        Text(homeCourseName)
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                statBadge("HANDICAP", "—", "Index")
                statBadge("ROUNDS", "\(rounds.count)", "This Year")
                statBadge("AVG SCORE", avgScoreStr, "Last 20")
            }
        }
        .tcCard()
    }

    private func statBadge(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundColor(TCTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 9))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(TCTheme.panelRaised.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Clubs in Bag Card

    private var clubsInBagCard: some View {
        VStack(spacing: 0) {
            HStack {
                TCSectionHeader(title: "Clubs in Bag")
                Button {
                    showClubs = true
                } label: {
                    Text("Manage Bag ›")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            TCDivider()
                .padding(.top, 8)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    let driverName  = clubs.first(where: { $0.type == .driver })?.name ?? "Not set"
                    let fwName      = clubs.first(where: { $0.type == .fairwayWood })?.name ?? "Not set"
                    let ironName    = clubs.filter({ $0.type == .iron }).isEmpty ? "Not set" : "Irons"
                    let wedgeName   = clubs.first(where: { $0.type == .wedge })?.name ?? "Not set"
                    let putterName  = clubs.first(where: { $0.type == .putter })?.name ?? "Not set"

                    TCClubRow(category: "DRIVER", name: driverName)
                    TCClubRow(category: "3 WOOD",  name: fwName)
                    TCClubRow(category: "5-PW",    name: ironName)
                    TCClubRow(category: "WEDGES",  name: wedgeName)
                    TCClubRow(category: "PUTTER",  name: putterName)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
        }
        .tcCard()
    }

    // MARK: - Milestones Card

    private var milestonesCard: some View {
        VStack(spacing: 12) {
            TCSectionHeader(title: "Milestones")
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                TCMilestoneBadge(icon: "checkmark.seal.fill", value: "\(rounds.count)",  label: "Rounds\nCompleted", accent: TCTheme.sage)
                TCMilestoneBadge(icon: "flame.fill",          value: "\(subEightyCount)", label: "Sub-80\nRounds",    accent: TCTheme.gold)
                TCMilestoneBadge(icon: "star.fill",           value: bestRoundStr,        label: "Best\nRound",       accent: TCTheme.goldLight)
                TCMilestoneBadge(icon: "scope",               value: "\(shots.count)",    label: "Shots\nTracked",    accent: TCTheme.silver)
            }
        }
        .tcCard()
    }

    // MARK: - Saved Shots Card

    private var savedShotsCard: some View {
        VStack(spacing: 12) {
            TCSectionHeader(title: "Saved Shots", viewAllAction: { showSessions = true })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if shots.isEmpty {
                        Text("No shots saved yet. Start a session to track your shots.")
                            .font(.system(size: 13))
                            .foregroundColor(TCTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        let displayShots = Array(shots.prefix(3))
                        ForEach(Array(displayShots.enumerated()), id: \.offset) { index, shot in
                            TCShotThumb(
                                clubName: shot.clubName ?? "Club",
                                yards: Int(shot.metrics.carryYards),
                                isBest: index == 0
                            )
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .tcCard()
    }

    // MARK: - Settings Row Card

    private var settingsRowCard: some View {
        Button { showProfile = true } label: {
            TCSettingsRow(
                icon: "gearshape.fill",
                title: "Settings",
                value: "Preferences, units & privacy",
                accent: TCTheme.gold
            )
        }
        .buttonStyle(.plain)
        .tcCard(padding: 0)
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            Task { await session.signOut() }
        } label: {
            Text("Sign Out")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TCTheme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(Rectangle().fill(TCTheme.border).frame(height: 1), alignment: .bottom)
        }
        .buttonStyle(.plain)
    }
}
