import SwiftUI

/// The leaderboards hub, opened from the trophy button on the feed. Three boards:
/// Friends (from feed activity), Home course (best saved rounds), and Global (the
/// camera-verified carry board). Replaces the old inline feed sections.
struct LeaderboardView: View {
    let userId: UUID
    let backend: AppBackend

    @EnvironmentObject private var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    enum Board: String, CaseIterable, Identifiable {
        case friends = "Friends"
        case homeCourse = "Home Course"
        case global = "Global"
        var id: String { rawValue }
    }

    @State private var board: Board = .friends
    @State private var friends: [FeedLeaderboardEntry] = []
    @State private var homeCourse: [HomeCourseLeaderboardEntry] = []
    @State private var loading = false
    @State private var challengeRefresh = 0
    @State private var profileTarget: ProfileTarget?

    private var homeCourseName: String {
        (session.userProfile?.homeCourseName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain)
            VStack(spacing: 0) {
                header
                boardPicker
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        switch board {
                        case .friends:    friendsBoard
                        case .homeCourse: homeCourseBoard
                        case .global:     globalBoard
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 16)
                }
            }
        }
        .navigationBarHidden(true)
        .task(id: board) { await load() }
        .refreshable { await load(force: true) }
        .sheet(item: $profileTarget) { t in
            NavigationStack {
                PublicProfileView(userId: t.id, seedName: t.name, seedHomeCourse: t.homeCourse,
                                  seedPosts: t.seedPosts, backend: backend)
            }
            .tcAppearance()
        }
    }

    // MARK: Header + picker

    private var header: some View {
        HStack {
            Text("Leaderboards")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
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
        .padding(.horizontal, TCTheme.hPad)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var boardPicker: some View {
        HStack(spacing: 8) {
            ForEach(Board.allCases) { b in
                Button { board = b } label: {
                    Text(b.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(board == b ? TCTheme.onPrimary : TCTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(board == b ? AnyView(TCTheme.goldGradient) : AnyView(TCTheme.panel))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TCTheme.hPad)
    }

    // MARK: Boards

    @ViewBuilder private var friendsBoard: some View {
        if loading && friends.isEmpty {
            loadingRow
        } else if friends.isEmpty {
            emptyRow("Add friends or finish activities to light up the board.",
                     system: "person.2.fill")
        } else {
            ForEach(Array(friends.enumerated()), id: \.element.id) { i, entry in
                Button {
                    profileTarget = ProfileTarget(id: entry.userId, name: entry.displayName, homeCourse: nil, seedPosts: [])
                } label: {
                    LeaderboardRow(
                        rank: i + 1,
                        name: entry.displayName,
                        subtitle: entry.metric.title,
                        value: "\(entry.value)",
                        unit: entry.metric.unit,
                        caption: entry.subtitle,
                        highlight: entry.userId == userId
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var homeCourseBoard: some View {
        if homeCourseName.isEmpty {
            emptyRow("Set your home course in your profile to see how you stack up.",
                     system: "flag.fill")
        } else if loading && homeCourse.isEmpty {
            loadingRow
        } else if homeCourse.isEmpty {
            emptyRow("No saved scores at \(baseCourse(homeCourseName)) yet. Post a round to start the board.",
                     system: "flag.fill")
        } else {
            Text(baseCourse(homeCourseName).uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(TCTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(homeCourse.enumerated()), id: \.element.id) { i, entry in
                Button {
                    profileTarget = ProfileTarget(id: entry.userId, name: entry.displayName,
                                                  homeCourse: homeCourseName, seedPosts: [])
                } label: {
                    LeaderboardRow(
                        rank: i + 1,
                        name: entry.displayName,
                        subtitle: "\(entry.roundsPlayed) round\(entry.roundsPlayed == 1 ? "" : "s")",
                        value: "\(entry.bestScore)",
                        unit: "",
                        caption: entry.toParString + " to par",
                        highlight: entry.userId == userId
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var globalBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera-verified longest carry, worldwide.")
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            VerifiedChallengeCard(refreshToken: challengeRefresh)
        }
    }

    // MARK: Pieces

    private var loadingRow: some View {
        ProgressView().tint(TCTheme.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }

    private func emptyRow(_ message: String, system: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: system)
                .font(.system(size: 26))
                .foregroundColor(TCTheme.textUltraMuted)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Data

    private func load(force: Bool = false) async {
        if board == .global { challengeRefresh += 1; return }
        loading = true
        defer { loading = false }
        switch board {
        case .friends:
            friends = (try? await backend.loadFriendLeaderboard(userId: userId, period: .week)) ?? friends
        case .homeCourse:
            if !homeCourseName.isEmpty {
                homeCourse = (try? await backend.loadHomeCourseLeaderboard(course: homeCourseName)) ?? homeCourse
            }
        case .global:
            break
        }
    }

    private func baseCourse(_ s: String) -> String {
        s.components(separatedBy: " ~ ").first ?? s
    }
}

/// One leaderboard row — rank medallion, avatar, name/subtitle, value/caption.
private struct LeaderboardRow: View {
    let rank: Int
    let name: String
    let subtitle: String
    let value: String
    let unit: String
    let caption: String
    var highlight: Bool = false

    private var rankTint: Color {
        switch rank {
        case 1:  return TCTheme.gold
        case 2:  return TCTheme.silver
        case 3:  return Color(red: 0.72, green: 0.49, blue: 0.32)
        default: return TCTheme.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(rankTint)
                .frame(width: 26, height: 26)
                .background(rankTint.opacity(0.14))
                .clipShape(Circle())
            AvatarCircle(name: name, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundColor(TCTheme.textPrimary)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(TCTheme.textMuted)
                    }
                }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(highlight ? TCTheme.panelRaised : TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                .strokeBorder(highlight ? TCTheme.gold.opacity(0.5) : TCTheme.border, lineWidth: 1)
        )
    }
}
