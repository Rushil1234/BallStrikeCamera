import SwiftUI

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
                    authorName: session.userProfile?.displayName ?? session.currentUser?.name ?? "You",
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
    @State private var commentingPost: FeedPost?

    init(userId: UUID, authorName: String, backend: AppBackend) {
        self.userId = userId
        self.authorName = authorName
        self.backend = backend
        _vm = StateObject(wrappedValue: FeedViewModel(userId: userId, backend: backend))
    }

    private var userInitials: String {
        let parts = authorName.components(separatedBy: " ")
        if parts.count >= 2, let f = parts[0].first, let l = parts[1].first { return "\(f)\(l)" }
        return String(authorName.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        Button { showFriends = true } label: {
                            Image(systemName: "person.2")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(TCTheme.textSecondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        TCProfileAvatarButton(initials: userInitials,
                                              devMode: session.entitlementVM.isDeveloperMode) { showProfile = true }
                    }
                    weeklySnapshot
                    sectionGap
                    if vm.posts.isEmpty && !vm.isLoading {
                        emptyState
                    } else {
                        ForEach(Array(vm.posts.enumerated()), id: \.element.id) { _, post in
                            FeedPostRow(
                                post: post,
                                authorName: authorName,
                                gimmeCount: vm.gimmeCount(for: post),
                                hasGimmed: vm.hasGimmed(post),
                                onGimme: { Task { await vm.toggleGimme(post) } },
                                onComment: { commentingPost = post }
                            )
                            sectionGap
                        }
                        caughtUpNote
                    }
                    Spacer(minLength: 120)
                }
            }
            .refreshable { await vm.load() }
        }
        .navigationBarHidden(true)
        .task { await vm.load() }
        .sheet(isPresented: $showFriends, onDismiss: { Task { await vm.load() } }) {
            NavigationStack { FriendsView(userId: userId, backend: backend) }
                .tcAppearance()
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { TrueCarryProfileView() }
                .tcAppearance()
        }
        .sheet(item: $commentingPost) { post in
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

    // MARK: Weekly snapshot

    private var weeklySnapshot: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Weekly Snapshot")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Spacer()
                Button { showFriends = true } label: {
                    Text("See More")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                snapshotMetric(title: "Activities", value: "\(vm.weeklyActivityCount)")
                snapshotMetric(title: "Gimmes", value: "\(vm.weeklyGimmesReceived)")
                snapshotMetric(title: "Friends", value: "\(vm.friendsCount)")
            }
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
    }

    private func snapshotMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            HStack(spacing: 4) {
                Image(systemName: "triangle.fill").font(.system(size: 7))
                Text(value)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(TCTheme.textMuted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Empty / footer

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.golf")
                .font(.system(size: 34))
                .foregroundColor(TCTheme.sage.opacity(0.7))
            Text("Your feed is quiet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
            Text("Add friends to see their rounds and range sessions — your own activity shows up here too.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
            Button { showFriends = true } label: {
                Text("Find Friends")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.background)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(TCTheme.gold)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 48)
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

// MARK: - Feed Post Card (Strava-style, full-bleed)

private struct FeedPostRow: View {
    let post: FeedPost
    let authorName: String
    let gimmeCount: Int
    let hasGimmed: Bool
    let onGimme: () -> Void
    let onComment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: avatar + name + time/type
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
                    }
                    .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
            }

            // Title
            Text(post.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Stat columns
            if !post.stats.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(post.stats) { stat in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stat.label)
                                .font(.system(size: 13))
                                .foregroundColor(TCTheme.textMuted)
                            Text(stat.value)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(TCTheme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if !post.subtitle.isEmpty {
                Text(post.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textSecondary)
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
                    Image(systemName: "bubble.right")
                        .font(.system(size: 19))
                        .foregroundColor(TCTheme.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 19))
                    .foregroundColor(TCTheme.textSecondary)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 18)
        .background(TCTheme.background)
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
