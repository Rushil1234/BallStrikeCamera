import SwiftUI

/// A golfer's profile — opened by tapping their name/avatar anywhere (feed,
/// friends, leaderboards). Loads their profile + activity itself given just a
/// userId (RLS scopes what's visible), so it works from any entry point.
/// Strava/Beli-style: hero header, a real stat strip, recent activity, and a
/// full "view all activities" list. Shareable as a link to this profile.
struct PublicProfileView: View {
    let userId: UUID
    var seedName: String
    var seedHomeCourse: String? = nil
    var seedPosts: [FeedPost] = []
    var currentUserId: UUID? = nil
    let backend: AppBackend

    @Environment(\.dismiss) private var dismiss
    @State private var posts: [FeedPost] = []
    @State private var profile: UserProfile?
    @State private var social: ProfileSocial = .empty
    @State private var loaded = false
    @State private var busyFollow = false
    @State private var showAllActivities = false
    @State private var shareURL: URL?
    @State private var showShare = false

    private var isSelf: Bool { currentUserId != nil && currentUserId == userId }
    private var canViewActivity: Bool { isSelf || social.canView }

    // MARK: Derived

    private var name: String {
        if let dn = profile?.displayName, !dn.isEmpty, !dn.contains("@") { return dn }
        return seedName
    }
    private var username: String? {
        guard let u = profile?.username, !u.isEmpty else { return nil }
        return u
    }
    private var homeCourse: String? {
        let hc = (profile?.homeCourseName ?? "").isEmpty ? (seedHomeCourse ?? "") : (profile?.homeCourseName ?? "")
        return hc.isEmpty ? nil : hc
    }
    private var activities: [FeedPost] {
        let base: [FeedPost] = posts.isEmpty ? seedPosts.filter { $0.userId == userId } : posts
        return base.sorted { $0.timestamp > $1.timestamp }
    }
    private var rounds: Int { activities.filter { $0.type == .round }.count }
    private var sessions: Int { activities.filter { $0.type == .session }.count }
    private var bestCarry: Int { activities.compactMap { $0.activityMetadata?.bestCarryYards }.max() ?? 0 }

    private var shareData: ProfileShareData {
        ProfileShareData(userId: userId, name: name, homeCourse: homeCourse, handicap: nil,
                         rounds: rounds, sessions: sessions, bestCarry: bestCarry)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    hero
                    followRow
                    if canViewActivity {
                        statStrip
                        achievements
                        activitySection
                    } else {
                        privateNotice
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .task { await load() }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url, ProfileLink.url(for: userId)]) }
        }
        .sheet(isPresented: $showAllActivities) {
            NavigationStack { AllActivitiesView(name: name, posts: activities) }
                .tcAppearance()
        }
    }

    // MARK: Hero header

    private var hero: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if let url = renderProfileShareCard(data: shareData) { shareURL = url; showShare = true }
                } label: { circleIcon("square.and.arrow.up") }
                Spacer()
                Button { dismiss() } label: { circleIcon("xmark") }
            }
            .padding(.horizontal, 16).padding(.top, 16)

            AvatarCircle(name: name, size: 92)
                .overlay(Circle().strokeBorder(TCTheme.gold.opacity(0.5), lineWidth: 2))
                .padding(.top, 6)

            Text(name)
                .font(.system(size: 25, weight: .bold, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
                .padding(.top, 12)
            if let username {
                Text("@\(username)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TCTheme.gold)
                    .padding(.top, 1)
            }
            if let hc = homeCourse {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill").font(.system(size: 11))
                    Text(hc.components(separatedBy: " ~ ").first ?? hc).font(.system(size: 13))
                }
                .foregroundColor(TCTheme.textMuted)
                .padding(.top, 6)
            }
            if !isSelf { followButton.padding(.top, 14) }
            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [TCTheme.gold.opacity(0.14), TCTheme.panel.opacity(0.0)],
                           startPoint: .top, endPoint: .bottom)
        )
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
    }

    private func circleIcon(_ system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(TCTheme.textMuted)
            .frame(width: 32, height: 32)
            .background(TCTheme.panelRaised)
            .clipShape(Circle())
    }

    // MARK: Stat strip

    private var statStrip: some View {
        HStack(spacing: 0) {
            stat("\(activities.count)", "Activities")
            divider
            stat("\(rounds)", "Rounds")
            divider
            stat("\(sessions)", "Sessions")
            divider
            stat(bestCarry > 0 ? "\(bestCarry)" : "--", "Best Carry", unit: bestCarry > 0 ? "yd" : "")
        }
        .padding(.vertical, 16)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, unit: String = "") -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10, weight: .semibold)).foregroundColor(TCTheme.textMuted)
                }
            }
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(TCTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(TCTheme.border).frame(width: 1, height: 30)
    }

    // MARK: Activity

    @ViewBuilder private var activitySection: some View {
        HStack {
            Text("Recent activity")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Spacer()
            if activities.count > 4 {
                Button { showAllActivities = true } label: {
                    Text("View all").font(.system(size: 13, weight: .semibold)).foregroundColor(TCTheme.gold)
                }
                .buttonStyle(.plain)
            }
        }
        if activities.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: loaded ? "figure.golf" : "hourglass").font(.system(size: 22)).foregroundColor(TCTheme.textUltraMuted)
                Text(loaded ? "No shared activities yet." : "Loading…")
                    .font(.system(size: 13)).foregroundColor(TCTheme.textMuted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 30)
        } else {
            ForEach(activities.prefix(4)) { post in
                ProfileActivityRow(post: post)
            }
            if activities.count > 4 {
                Button { showAllActivities = true } label: {
                    Text("View all \(activities.count) activities")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(TCTheme.gold.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Follow

    private var followButton: some View {
        Button { Task { await toggleFollow() } } label: {
            HStack(spacing: 6) {
                Image(systemName: followIcon).font(.system(size: 12, weight: .bold))
                Text(followLabel).font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(social.isFollowing || social.isPending ? TCTheme.textPrimary : TCTheme.onPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(social.isFollowing || social.isPending ? TCTheme.panelRaised : TCTheme.gold)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(TCTheme.gold.opacity(social.isFollowing || social.isPending ? 0.5 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busyFollow)
        .padding(.horizontal, 40)
    }

    private var followLabel: String {
        if social.isFollowing { return "Following" }
        if social.isPending { return "Requested" }
        return social.isPrivate ? "Request" : "Follow"
    }
    private var followIcon: String {
        if social.isFollowing { return "checkmark" }
        if social.isPending { return "clock" }
        return "plus"
    }

    private func toggleFollow() async {
        busyFollow = true; defer { busyFollow = false }
        if social.isFollowing || social.isPending {
            try? await backend.unfollowUser(target: userId)
        } else {
            _ = try? await backend.followUser(target: userId)
        }
        social = (try? await backend.profileSocial(target: userId)) ?? social
    }

    private var followRow: some View {
        HStack(spacing: 0) {
            countTile("\(social.followerCount)", "Followers")
            Rectangle().fill(TCTheme.border).frame(width: 1, height: 30)
            countTile("\(social.followingCount)", "Following")
        }
        .padding(.vertical, 14)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
    }

    private func countTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(TCTheme.textPrimary)
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Achievements (milestone badges, derived from activity)

    private var earnedMilestones: [Int] { [10, 25, 50, 100].filter { activities.count >= $0 } }

    @ViewBuilder private var achievements: some View {
        if !earnedMilestones.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Achievements")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                HStack(spacing: 12) {
                    ForEach(earnedMilestones, id: \.self) { m in
                        VStack(spacing: 6) {
                            ZStack {
                                Image(systemName: "hexagon.fill").font(.system(size: 46)).foregroundColor(TCTheme.gold.opacity(0.18))
                                Image(systemName: "hexagon").font(.system(size: 46)).foregroundColor(TCTheme.gold.opacity(0.6))
                                Text("\(m)").font(.system(size: 15, weight: .black, design: .rounded)).foregroundColor(TCTheme.gold)
                            }
                            Text("\(m) posts").font(.system(size: 9, weight: .semibold)).foregroundColor(TCTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        }
    }

    private var privateNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundColor(TCTheme.textUltraMuted)
            Text("This account is private")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(TCTheme.textPrimary)
            Text(social.isPending ? "Your follow request is pending approval."
                                  : "Follow \(name) to see their activity.")
                .font(.system(size: 13)).foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
    }

    private func load() async {
        async let p = try? await backend.loadUserPosts(userId: userId)
        async let pr = try? await backend.loadUserProfile(userId: userId)
        async let so = try? await backend.profileSocial(target: userId)
        posts = (await p ?? []).filter { $0.userId == userId }
        profile = await pr ?? nil
        social = await so ?? .empty
        loaded = true
    }
}

/// One activity row on a profile — icon, title/subtitle, headline metric.
private struct ProfileActivityRow: View {
    let post: FeedPost
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: post.type == .round ? "flag.fill" : post.type == .session ? "scope" : "sparkles")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.gold)
                .frame(width: 36, height: 36)
                .background(TCTheme.gold.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                Text(post.subtitle.isEmpty ? relativeTime(post.timestamp) : post.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            if !post.metricHighlight.isEmpty {
                Text(post.metricHighlight)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.gold)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
    }
}

/// The full activity history for a profile (opened via "view all activities").
private struct AllActivitiesView: View {
    let name: String
    let posts: [FeedPost]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All activities")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(TCTheme.textPrimary)
                            Text("\(posts.count) · \(name)")
                                .font(.system(size: 13)).foregroundColor(TCTheme.textMuted)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(TCTheme.textMuted)
                                .frame(width: 32, height: 32)
                                .background(TCTheme.panel).clipShape(Circle())
                        }
                    }
                    .padding(.bottom, 4)
                    ForEach(posts) { post in ProfileActivityRow(post: post) }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
    }
}
