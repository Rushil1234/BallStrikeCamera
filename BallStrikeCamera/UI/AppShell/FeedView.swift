import SwiftUI
import PhotosUI
import ImageIO

// MARK: - Home wrapper
// Routed from the bottom dock's Home tab. Waits for the signed-in user before
// constructing the feed so the view model always has a valid identity.

struct FeedHomeView: View {
    @EnvironmentObject var session: AuthSessionStore

    var body: some View {
        Group {
            if let uid = session.currentUser?.id {
                FeedView(
                    userId: uid,
                    authorName: session.displayHandle,
                    backend: session.backend
                )
            } else {
                ZStack {
                    TCTheme.background.ignoresSafeArea()
                    ProgressView().tint(TCTheme.gold)
                }
            }
        }
    }
}

// MARK: - Home feed (Strava-style)

struct FeedView: View {
    @EnvironmentObject var session: AuthSessionStore
    @StateObject private var vm: FeedViewModel
    private let authorName: String
    private let userId: UUID
    private let backend: AppBackend

    @State private var showFriends = false
    @State private var showProfile = false
    @State private var showComposer = false
    @State private var showNotifications = false
    @State private var showLeaderboards = false
    @State private var profilePost: FeedPost?
    @AppStorage("tc_feed_notifs_seen_ts") private var notifsLastSeenTs: Double = 0
    @State private var greeting: HomeGreeting = HomeGreeting.all.first!
    @State private var commentingPost: FeedPost?
    @State private var showRangeCamera = false
    @State private var showCourseSearch = false

    /// Holds the course+tee atomically so fullScreenCover(item:) never sees a partial state.
    /// Mirrors TrueCarryPlayView's fix for the same bug: presenting a boolean-driven
    /// fullScreenCover whose content closure reads separate @State vars can race the search
    /// sheet's own dismissal and render blank — see the staged/pendingRound handoff below.
    private struct PendingRound: Identifiable {
        let id = UUID(); let course: GolfCourse; let tee: TeeBox
    }
    @State private var pendingRound: PendingRound?
    @State private var stagedRound: PendingRound?
    @State private var unfinishedRound: CourseRound?
    @State private var challengeRefresh = 0   // bumps VerifiedChallengeCard's reload

    init(userId: UUID, authorName: String, backend: AppBackend) {
        self.userId = userId
        self.authorName = authorName
        self.backend = backend
        _vm = StateObject(wrappedValue: FeedViewModel(userId: userId, backend: backend))
    }

    private var unreadNotifs: Int {
        vm.notifications.filter { $0.createdAt.timeIntervalSince1970 > notifsLastSeenTs }.count
    }

    private var userInitials: String {
        let parts = authorName.components(separatedBy: " ")
        if parts.count >= 2, let f = parts[0].first, let l = parts[1].first { return "\(f)\(l)" }
        return String(authorName.prefix(2)).uppercased()
    }

    /// Home-screen banner for a round that's still in progress (endedAt == nil) —
    /// e.g. the app was closed mid-round. Tapping routes to the Play tab and reopens it.
    private func resumeRoundBanner(_ round: CourseRound) -> some View {
        Button {
            NotificationCenter.default.post(name: .tcResumeRound, object: nil)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(TCTheme.goldGradient)
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("ROUND IN PROGRESS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.gold)
                        .tracking(1.2)
                    Text(round.courseName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1)
                    let played = round.holes.filter { $0.score != nil }.count
                    Text("\(played)/\(round.holes.count) holes scored — tap to resume")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
            }
            .tcCard()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, TCTheme.hPad)
    }

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain)
            ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCHeaderIconButton(icon: "trophy.fill") { showLeaderboards = true }
                        TCHeaderIconButton(icon: "bell.fill", badge: unreadNotifs) { showNotifications = true }
                        TCHeaderIconButton(icon: "person.2.fill") { showFriends = true }
                        TCProfileAvatarButton(initials: userInitials,
                                              devMode: session.entitlementVM.isDeveloperMode) { showProfile = true }
                    }
                    if let r = unfinishedRound {
                        resumeRoundBanner(r)
                        sectionGap
                    }
                    activityHero
                    sectionGap
                    if !vm.drafts.isEmpty {
                        draftsSection
                        sectionGap
                    }
                    homeSummarySection
                    sectionGap
                    challengesSection
                        .id("tc.feed.challenges")
                    sectionGap
                    if vm.posts.isEmpty && !vm.isLoading {
                        emptyState
                    } else {
                        feedSectionHeader
                        ForEach(Array(vm.posts.enumerated()), id: \.element.id) { _, post in
                            FeedPostRow(
                                post: post,
                                authorName: authorName,
                                gimmeCount: vm.gimmeCount(for: post),
                                hasGimmed: vm.hasGimmed(post),
                                commentCount: vm.commentCount(for: post),
                                canDelete: post.userId == userId,
                                onGimme: { Task { await vm.toggleGimme(post) } },
                                onComment: { commentingPost = post },
                                onDelete: { Task { await vm.deletePost(id: post.id) } },
                                onOpenProfile: post.userId == userId ? nil : { profilePost = post }
                            )
                            .task { await vm.loadMoreIfNeeded(currentPost: post) }
                            sectionGap
                        }
                        if vm.isLoadingMore {
                            ProgressView()
                                .tint(TCTheme.gold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                        }
                        caughtUpNote
                    }
                    Spacer(minLength: 120)
                }
            }
            .refreshable {
                challengeRefresh += 1   // quiet re-load of the verified challenge board
                await vm.load()
            }
            #if DEBUG
            // Screenshot harness: TC_DEBUG_SCROLL=challenges jumps the feed to the
            // weekly-challenge board. Absent from release builds.
            .onAppear {
                if ProcessInfo.processInfo.environment["TC_DEBUG_SCROLL"] == "challenges" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { scrollProxy.scrollTo("tc.feed.challenges", anchor: .top) }
                    }
                }
            }
            #endif
            }
        }
        .navigationBarHidden(true)
        .task {
            // Seed instantly from the prewarmed cache so the page (posts + "Your Week") isn't
            // empty / showing 0s on first paint.
            if vm.posts.isEmpty, !session.cachedFeedPosts.isEmpty {
                vm.posts = session.cachedFeedPosts
            }
            if let hs = session.cachedHomeSummary { vm.homeSummary = hs }
            await vm.load()
            await vm.loadDrafts()
            let all = (try? await backend.loadCourseRounds(userId: userId)) ?? []
            unfinishedRound = all.first(where: { $0.endedAt == nil })
        }
        // Deletions + finishing a round must recompute the feed, drafts, and
        // "Your Week" summary immediately.
        .onReceive(NotificationCenter.default.publisher(for: .tcDataChanged)) { _ in
            Task {
                await vm.load()
                await vm.loadDrafts()
                let all = (try? await backend.loadCourseRounds(userId: userId)) ?? []
                unfinishedRound = all.first(where: { $0.endedAt == nil })
            }
        }
        .sheet(isPresented: $showFriends, onDismiss: { Task { await vm.load() } }) {
            NavigationStack { FriendsView(userId: userId, backend: backend) }
                .tcAppearance()
        }
        .sheet(isPresented: $showLeaderboards) {
            NavigationStack { LeaderboardView(userId: userId, backend: backend) }
                .tcAppearance()
        }
        .sheet(item: $profilePost) { post in
            NavigationStack {
                PublicProfileView(
                    userId: post.userId,
                    displayName: post.authorName,
                    homeCourse: nil,
                    posts: vm.posts.filter { $0.userId == post.userId }
                )
            }
            .tcAppearance()
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { TrueCarryProfileView() }
                .tcAppearance()
        }
        .sheet(isPresented: $showNotifications) {
            NavigationStack {
                NotificationsView(notifications: vm.notifications) { postId in
                    // Open the related post's comments. Resolve the post even when it isn't in the
                    // currently-loaded feed page; small delay lets the sheet dismiss first.
                    Task {
                        guard let post = await vm.findPost(id: postId) else { return }
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        commentingPost = post
                    }
                }
            }
            .tcAppearance()
            .task { await vm.refreshNotifications() }
            .onAppear { notifsLastSeenTs = Date().timeIntervalSince1970 }
        }
        .fullScreenCover(isPresented: $showRangeCamera) {
            RangeCameraScreen(userId: userId, backend: backend)
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
        .sheet(isPresented: $showCourseSearch, onDismiss: {
            // Present the round ONLY after the search sheet has fully dismissed. Triggering the
            // fullScreenCover while the sheet is still on screen makes SwiftUI present a blank/white
            // cover whose body never renders (presentation race) — the cause of the white screen.
            if let staged = stagedRound {
                stagedRound = nil
                pendingRound = staged
            }
        }) {
            NavigationStack {
                CourseSearchView(userId: userId) { course, tee in
                    stagedRound = PendingRound(course: course, tee: tee)
                    showCourseSearch = false
                }
            }
            .tcAppearance()
        }
        .fullScreenCover(item: $pendingRound) { pr in
            CourseModeGPSHoleView(
                userId: userId,
                backend: backend,
                initialCourse: pr.course,
                initialTeeBox: pr.tee
            )
        }
        .sheet(isPresented: $showComposer, onDismiss: { Task { await vm.load() } }) {
            NavigationStack {
                FeedComposeSheet(authorName: authorName) { title, body, type, highlight, visibility, photoData, extraStats in
                    await vm.createPost(
                        title: title,
                        body: body,
                        type: type,
                        highlight: highlight,
                        authorName: authorName,
                        visibility: visibility,
                        photoData: photoData,
                        extraStats: extraStats
                    )
                }
            }
            .tcAppearance()
        }
        .sheet(item: $commentingPost, onDismiss: { Task { await vm.load() } }) { post in
            NavigationStack {
                CommentsSheet(post: post, userId: userId, authorName: authorName, backend: backend)
            }
            .tcAppearance()
        }
    }

    private var sectionGap: some View {
        Rectangle()
            .fill(TCTheme.panelDeep)
            .frame(height: 8)
    }

    private var activityHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                SpinningGolfBallView(size: 82, period: 7)
                    .frame(width: 86, height: 86)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting.headline)
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundColor(TCTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(greeting.sub)
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.textMuted)
                }
            }

            HStack(spacing: 10) {
                HeroActionButton(title: "Start Round", icon: "flag.fill", accent: TCTheme.gold) {
                    stagedRound = nil
                    showCourseSearch = true
                }
                HeroActionButton(title: "Start Range", icon: "scope", accent: TCTheme.sage) {
                    showRangeCamera = true
                }
            }

            Button { showComposer = true } label: {
                HStack(spacing: 12) {
                    AvatarCircle(name: authorName, size: 34)
                    Text("Post a round, range note, or win")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TCTheme.textMuted)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(TCTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                        .strokeBorder(TCTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
        .background(TCTheme.background)
        .onAppear { greeting = HomeGreeting.all.randomElement() ?? greeting }
    }

    private var homeSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            brandedTitle("Your Week")
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                snapshotMetric(title: "Rounds", value: "\(vm.homeSummary.weeklyRounds)")
                snapshotMetric(title: "Shots", value: "\(vm.homeSummary.weeklyShots)")
                snapshotMetric(title: "Best Carry", value: vm.homeSummary.bestCarryYards > 0 ? "\(vm.homeSummary.bestCarryYards)" : "--", unit: vm.homeSummary.bestCarryYards > 0 ? "yd" : "")
            }
            HStack(spacing: 0) {
                snapshotMetric(title: "Streak", value: "\(vm.homeSummary.activeStreakDays)", unit: "days")
                snapshotMetric(title: "Gimmes", value: "\(vm.homeSummary.gimmesReceived)")
                snapshotMetric(title: "Friends", value: "\(vm.homeSummary.friendsCount)")
            }
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
        // Solid section background like its siblings — without it this band
        // showed the page texture and read as a different tone.
        .background(TCTheme.background)
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Friends Leaderboard", actionTitle: "Friends") { showFriends = true }
            if vm.leaderboardEntries.isEmpty {
                compactEmptyRow("Add friends or finish activities to light up the board.")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(vm.leaderboardEntries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        LeaderboardPreviewRow(rank: index + 1, entry: entry)
                    }
                }
            }
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
        .background(TCTheme.background)
    }

    private var draftsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ready to share")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Spacer()
                Text("\(vm.drafts.count) draft\(vm.drafts.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }
            Text("From your recent play — nothing posts until you say so.")
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
            ForEach(vm.drafts) { draft in
                DraftRow(
                    draft: draft,
                    onShare: { Task { await vm.shareDraft(draft) } },
                    onDismiss: { vm.dismissDraft(draft) }
                )
            }
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
        .background(TCTheme.background)
    }

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Weekly Challenges", actionTitle: "Post") { showComposer = true }
            // The camera-verified global board now lives in the Leaderboards hub
            // (trophy button) — this section keeps the actionable weekly challenges.
            VStack(spacing: 8) {
                ForEach(vm.challengePreviews) { challenge in
                    ChallengePreviewRow(challenge: challenge)
                }
            }
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
        .background(TCTheme.background)
    }

    private var feedSectionHeader: some View {
        HStack {
            brandedTitle("Activity Feed")
            Spacer()
            Text("\(vm.posts.count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(TCTheme.textMuted)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
        .background(TCTheme.background)
    }

    /// Section title with the small Marker Gold tick — the brand header treatment.
    private func brandedTitle(_ title: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(TCTheme.gold)
                .frame(width: 3, height: 14)
                .clipShape(Capsule())
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
        }
    }

    private func snapshotMetric(title: String, value: String, unit: String = "") -> some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            brandedTitle(title)
            Spacer()
            Button(action: action) {
                HStack(spacing: 3) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.gold)
            }
            .buttonStyle(.plain)
        }
    }

    private func compactEmptyRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(TCTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
    }

    // MARK: Empty / footer

    private var emptyState: some View {
        GolfBallEmptyField(
            title: "Your feed is quiet",
            message: "Add friends to see their rounds and range sessions. Your own activity shows up here too.",
            actionTitle: "Find Friends",
            action: { showFriends = true }
        )
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 28)
    }

    private var caughtUpNote: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(TCTheme.sage.opacity(0.6))
            Text("You're all caught up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Home Components

private struct HeroActionButton: View {
    let title: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(TCTheme.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TCTheme.primaryFill)
                .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickStartTile: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
            .padding(12)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

private struct DraftRow: View {
    let draft: FeedDraft
    let onShare: () -> Void
    let onDismiss: () -> Void
    @State private var sharing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(draft.kindLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(TCTheme.onPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(TCTheme.gold)
                    .clipShape(Capsule())
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.post.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1)
                    Text(draft.post.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text(draft.post.metricHighlight)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.gold)
            }
            HStack(spacing: 10) {
                Button(action: { sharing = true; onShare() }) {
                    Text(sharing ? "Sharing…" : "Share")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(TCTheme.goldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(sharing)
                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(TCTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                .strokeBorder(TCTheme.gold.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct LeaderboardPreviewRow: View {
    let rank: Int
    let entry: FeedLeaderboardEntry

    /// Podium tints: gold, silver, bronze; the rest stay muted.
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
                .frame(width: 24, height: 24)
                .background(rankTint.opacity(0.13))
                .clipShape(Circle())
            AvatarCircle(name: entry.displayName, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                    .fitOneLine(0.6)
                Text(entry.metric.title)
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(entry.value)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(TCTheme.textPrimary)
                    if !entry.metric.unit.isEmpty {
                        Text(entry.metric.unit)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(TCTheme.textMuted)
                    }
                }
                Text(entry.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
    }
}

private struct ChallengePreviewRow: View {
    let challenge: FeedChallengePreview

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: challenge.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(TCTheme.gold)
                .frame(width: 34, height: 34)
                .background(TCTheme.gold.opacity(0.13))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(challenge.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    Spacer()
                    Text("\(Int((challenge.progress * 100).rounded()))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                }
                ProgressView(value: min(max(challenge.progress, 0), 1))
                    .tint(TCTheme.gold)
                Text(challenge.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
        }
        .padding(12)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
    }
}

private struct FeedActivitySummary: View {
    let metadata: FeedActivityMetadata
    let fallbackStats: [FeedStat]
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(TCTheme.gold)
                    .frame(width: 42, height: 42)
                    .background(TCTheme.gold.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                    Text(detail)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(metadata.primaryValue)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    if !metadata.primaryUnit.isEmpty {
                        Text(metadata.primaryUnit)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(TCTheme.textMuted)
                    }
                }
            }

            FeedStatColumns(stats: stats)
        }
    }

    private var icon: String {
        switch metadata.kind {
        case .round: return "flag.fill"
        case .range: return "scope"
        case .sim: return "display"
        case .manual: return "sparkles"
        }
    }

    private var label: String {
        switch metadata.kind {
        case .round: return "ROUND"
        case .range: return "RANGE SESSION"
        case .sim: return "SIM SESSION"
        case .manual: return "UPDATE"
        }
    }

    private var detail: String {
        metadata.courseName ?? metadata.clubName ?? metadata.providerName ?? (subtitle.isEmpty ? "True Carry activity" : subtitle)
    }

    private var stats: [FeedStat] {
        switch metadata.kind {
        case .round:
            return [
                FeedStat(label: "To Par", value: metadata.scoreToPar.map(scoreToParText) ?? "--"),
                FeedStat(label: "Fairways", value: metadata.fairwaysHit.map { "\($0)" } ?? "--"),
                FeedStat(label: "GIR", value: metadata.greensInRegulation.map { "\($0)" } ?? "--"),
                FeedStat(label: "Putts", value: metadata.putts.map { "\($0)" } ?? "--")
            ]
        case .range:
            return [
                FeedStat(label: "Shots", value: metadata.shotCount.map { "\($0)" } ?? "--"),
                FeedStat(label: "Avg Carry", value: metadata.averageCarryYards.map { "\($0) yd" } ?? "--"),
                FeedStat(label: "Best", value: metadata.bestCarryYards.map { "\($0) yd" } ?? "--")
            ]
        case .sim:
            return [
                FeedStat(label: "Shots", value: metadata.shotCount.map { "\($0)" } ?? "--"),
                FeedStat(label: "Source", value: metadata.providerName ?? "Simulator")
            ]
        case .manual:
            return fallbackStats.isEmpty ? [FeedStat(label: "Highlight", value: metadata.primaryValue)] : fallbackStats
        }
    }

    private func scoreToParText(_ value: Int) -> String {
        value == 0 ? "E" : value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct FeedStatColumns: View {
    let stats: [FeedStat]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(stats.prefix(4)) { stat in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.label)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(stat.value)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Feed Post Card (Strava-style, full-bleed)

private struct FeedPostRow: View {
    let post: FeedPost
    let authorName: String
    let gimmeCount: Int
    let hasGimmed: Bool
    let commentCount: Int
    let canDelete: Bool
    let onGimme: () -> Void
    let onComment: () -> Void
    let onDelete: () -> Void
    var onOpenProfile: (() -> Void)? = nil

    @State private var loadedPhoto: Image?
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    /// Decodes the post photo downsampled to roughly its on-screen size (`ImageIO` thumbnailing
    /// never allocates the full-resolution bitmap). The old computed-property version called
    /// `UIImage(contentsOfFile:)` synchronously on the main thread on every body re-evaluation,
    /// at full camera resolution, for every photo post in the feed — displayed at only 200pt tall.
    /// That much simultaneous full-size GPU-backed image content competes with MapKit's own tile
    /// surface pool, and was the likely cause of course mode hanging when started from this screen
    /// (fine from tabs with no photo feed) — see CourseModeGPSHoleView's white-screen investigation.
    private static func downsampledPhoto(at url: URL, maxPixelSize: CGFloat) -> Image? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: avatar + name + time/type — tap avatar/name to open the profile.
            HStack(spacing: 12) {
                Button { onOpenProfile?() } label: {
                    HStack(spacing: 12) {
                        AvatarCircle(name: post.authorName, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.authorName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(TCTheme.textPrimary)
                            HStack(spacing: 6) {
                                Image(systemName: typeIcon).font(.system(size: 11))
                                Text("\(timeText) · \(typeLabel)")
                                    .font(.system(size: 13))
                                if let vis = post.visibility, vis != .everyone {
                                    Image(systemName: vis == .private ? "lock.fill" : "person.2.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .foregroundColor(TCTheme.textMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(onOpenProfile == nil)
                Spacer()
                Menu {
                    Button {
                        // Render the branded TrueCarry card and open the share sheet.
                        if let url = renderActivityShareCard(post: post) {
                            shareURL = url
                            showShareSheet = true
                        }
                    } label: {
                        Label("Share card", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: shareText) {
                        Label("Share as text", systemImage: "text.quote")
                    }
                    if canDelete {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete Post", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            // Title
            Text(post.title)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let metadata = post.activityMetadata {
                FeedActivitySummary(metadata: metadata, fallbackStats: post.stats, subtitle: post.subtitle)
            } else if !post.stats.isEmpty {
                FeedStatColumns(stats: post.stats)
            } else if !post.subtitle.isEmpty {
                Text(post.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textSecondary)
            }

            if let photo = loadedPhoto {
                photo
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // "You gave a gimme" line
            if hasGimmed {
                HStack(spacing: 8) {
                    AvatarCircle(name: authorName, size: 22)
                    Text("You gave a gimme")
                        .font(.system(size: 13))
                        .foregroundColor(TCTheme.textMuted)
                }
            }

            Rectangle().fill(TCTheme.border).frame(height: 1)

            // Actions
            HStack {
                Button(action: onGimme) {
                    Image(systemName: hasGimmed ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 20))
                        .foregroundColor(hasGimmed ? TCTheme.gold : TCTheme.textSecondary)
                }
                .buttonStyle(.plain)
                if gimmeCount > 0 {
                    Text("\(gimmeCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Button(action: onComment) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 19))
                        if commentCount > 0 {
                            Text("\(commentCount)")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(TCTheme.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    if let url = renderActivityShareCard(post: post) {
                        shareURL = url
                        showShareSheet = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 19))
                        .foregroundColor(TCTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
        .background(TCTheme.background)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .task(id: post.photoPath) {
            guard let path = post.photoPath else { loadedPhoto = nil; return }
            let url = AppStorageManager.compositeDir(userId: post.userId).appendingPathComponent(path)
            let scale = await MainActor.run { UIScreen.main.scale }
            loadedPhoto = await Task.detached(priority: .userInitiated) {
                Self.downsampledPhoto(at: url, maxPixelSize: 400 * scale)
            }.value
        }
    }

    private var timeText: String { relativeTime(post.timestamp) }

    private var typeLabel: String {
        switch post.type {
        case .round:       return "Round"
        case .session:     return "Practice"
        case .shot:        return "Shot"
        case .achievement: return "Achievement"
        }
    }

    private var typeIcon: String {
        switch post.type {
        case .round:       return "flag.fill"
        case .session:     return "target"
        case .shot:        return "figure.golf"
        case .achievement: return "trophy.fill"
        }
    }

    private var shareText: String {
        var parts = ["\(post.authorName) on True Carry", post.title]
        if !post.subtitle.isEmpty { parts.append(post.subtitle) }
        if !post.metricHighlight.isEmpty { parts.append("Highlight: \(post.metricHighlight)") }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Compose Sheet

private struct FeedComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let authorName: String
    let onPost: (String, String, FeedPostType, String, FeedVisibility, Data?, [FeedStat]) async -> Void

    @State private var title = ""
    @State private var bodyText = ""
    @State private var highlight = ""
    @State private var type: FeedPostType = .achievement
    @State private var visibility: FeedVisibility = .everyone
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var statChips: [FeedStat] = []
    @State private var statLabel = ""
    @State private var statValue = ""
    @State private var isPosting = false

    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !statChips.isEmpty || photoData != nil
    }

    var body: some View {
        ZStack {
            TCTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        AvatarCircle(name: authorName, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authorName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(TCTheme.textPrimary)
                            Text("Sharing to your True Carry feed")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                        }
                    }

                    Picker("Post type", selection: $type) {
                        Text("Update").tag(FeedPostType.achievement)
                        Text("Round").tag(FeedPostType.round)
                        Text("Range").tag(FeedPostType.session)
                        Text("Shot").tag(FeedPostType.shot)
                    }
                    .pickerStyle(.segmented)

                    feedField(title: "Title", placeholder: "e.g. Best range session this month", text: $title)
                    feedField(title: "Details", placeholder: "What happened out there?", text: $bodyText, axis: .vertical)

                    photoSection
                    statsSection
                    feedField(title: "Highlight", placeholder: "e.g. 287 yd drive, +4", text: $highlight)
                    visibilitySection

                    TCPrimaryGoldButton(title: isPosting ? "Posting..." : "Post to Feed", icon: "paperplane.fill") {
                        guard canPost, !isPosting else { return }
                        isPosting = true
                        Task {
                            await onPost(title, bodyText, type, highlight, visibility, photoData, statChips)
                            dismiss()
                        }
                    }
                    .disabled(!canPost || isPosting)
                    .opacity(canPost ? 1 : 0.55)
                }
                .padding(TCTheme.hPad)
            }
        }
        .navigationTitle("New Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }.foregroundColor(TCTheme.textMuted)
            }
        }
        .onChange(of: photoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    // MARK: Photo

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("Photo")
            if let photoData, let ui = UIImage(data: photoData) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button { self.photoData = nil; self.photoItem = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white, Color.black.opacity(0.45))
                    }
                    .padding(8)
                }
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(TCTheme.gold)
                        Text("Add a photo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TCTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(TCTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                            .strokeBorder(TCTheme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                }
            }
        }
    }

    // MARK: Stats chips

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Stats")
            if !statChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(statChips) { chip in
                            HStack(spacing: 6) {
                                Text(chip.label.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(TCTheme.textMuted)
                                Text(chip.value)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(TCTheme.textPrimary)
                                Button { statChips.removeAll { $0.id == chip.id } } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(TCTheme.textMuted)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(TCTheme.panelRaised)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Label", text: $statLabel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(TCTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                TextField("Value", text: $statValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(TCTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                Button {
                    let l = statLabel.trimmingCharacters(in: .whitespaces)
                    let v = statValue.trimmingCharacters(in: .whitespaces)
                    guard !l.isEmpty, !v.isEmpty else { return }
                    statChips.append(FeedStat(label: l, value: v))
                    statLabel = ""; statValue = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(TCTheme.gold)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Visibility

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("Who can see this")
            Picker("", selection: $visibility) {
                Text("Everyone").tag(FeedVisibility.everyone)
                Text("Friends").tag(FeedVisibility.friends)
                Text("Private").tag(FeedVisibility.private)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundColor(TCTheme.textMuted)
    }

    private func feedField(title: String, placeholder: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(title)
            TextField(placeholder, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 4...8 : 1...1)
                .textFieldStyle(.plain)
                .foregroundColor(TCTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(TCTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                        .strokeBorder(TCTheme.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - Comments Sheet

private struct CommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: CommentsViewModel

    init(post: FeedPost, userId: UUID, authorName: String, backend: AppBackend) {
        _vm = StateObject(wrappedValue: CommentsViewModel(post: post, userId: userId, authorName: authorName, backend: backend))
    }

    var body: some View {
        ZStack {
            TCTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if vm.comments.isEmpty && !vm.isLoading {
                            Text("No comments yet. Be the first.")
                                .font(.system(size: 13))
                                .foregroundColor(TCTheme.textMuted)
                                .padding(.top, 24)
                        }
                        ForEach(vm.comments) { comment in
                            HStack(alignment: .top, spacing: 10) {
                                AvatarCircle(name: comment.authorName, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(comment.authorName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(TCTheme.textPrimary)
                                    Text(comment.body)
                                        .font(.system(size: 14))
                                        .foregroundColor(TCTheme.textSecondary)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(TCTheme.hPad)
                }
                composer
            }
        }
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.foregroundColor(TCTheme.gold)
            }
        }
        .task { await vm.load() }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Add a comment…", text: $vm.draft)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(TCTheme.panel)
                .clipShape(Capsule())
                .foregroundColor(TCTheme.textPrimary)
            Button { Task { await vm.submit() } } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(TCTheme.gold)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 12)
        .background(TCTheme.background)
    }
}

// MARK: - Home greeting (rotating)

/// A short, rotating headline + subline shown at the top of the feed. One is
/// picked at random each time the home tab appears — keeps the top light and fresh.
struct HomeGreeting: Hashable {
    let headline: String
    let sub: String

    static let all: [HomeGreeting] = [
        .init(headline: "Welcome back", sub: "Let's make today count."),
        .init(headline: "Ready to tee it up?", sub: "Your bag's waiting."),
        .init(headline: "Bear every yard", sub: "One swing at a time."),
        .init(headline: "Good to see you", sub: "Let's dial it in."),
        .init(headline: "Back for more", sub: "Chase a tighter number."),
        .init(headline: "Game on", sub: "Track it, own it."),
        .init(headline: "Let's get to work", sub: "Every shot tells a story."),
        .init(headline: "Tee high, aim true", sub: "Today's round starts here."),
        .init(headline: "Welcome back", sub: "Pick up where you left off."),
        .init(headline: "Fresh round, fresh start", sub: "Go bury a few putts."),
    ]
}

// MARK: - Shared bits

struct AvatarCircle: View {
    let name: String
    var size: CGFloat = 42

    private var initials: String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }

    private var tint: Color {
        let palette: [Color] = [TCTheme.gold, TCTheme.sage, TCTheme.goldLight, TCTheme.sageBright]
        let idx = abs(name.hashValue) % palette.count
        return palette[idx]
    }

    var body: some View {
        Circle()
            .fill(tint.opacity(0.20))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(tint)
            )
    }
}

func relativeTime(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: Date())
}

// MARK: - Notifications center (gimmes + comments on your posts)

struct NotificationsView: View {
    let notifications: [FeedNotification]
    var onSelect: ((UUID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain).ignoresSafeArea()
            if notifications.isEmpty {
                GolfBallEmptyField(
                    title: "No notifications yet",
                    message: "When golfers gimme or comment on your rounds and posts, it shows up here."
                )
                .padding(.horizontal, TCTheme.hPad)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(notifications) { n in
                            Button {
                                let pid = n.postId
                                dismiss()
                                onSelect?(pid)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill((n.kind == .gimme ? TCTheme.gold : TCTheme.sage).opacity(0.16))
                                            .frame(width: 42, height: 42)
                                        Image(systemName: n.icon)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(n.kind == .gimme ? TCTheme.gold : TCTheme.sage)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        (Text(n.actorName).font(.system(size: 14, weight: .bold))
                                            + Text(" \(n.message)").font(.system(size: 14)))
                                            .foregroundColor(TCTheme.textPrimary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(relativeTime(n.createdAt))
                                            .font(.system(size: 12))
                                            .foregroundColor(TCTheme.textMuted)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(TCTheme.textUltraMuted)
                                }
                                .padding(12)
                                .background(TCTheme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                                        .strokeBorder(TCTheme.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }.foregroundColor(TCTheme.gold)
            }
        }
    }
}
