import Foundation

@MainActor
final class FeedViewModel: ObservableObject {

    @Published var posts: [FeedPost] = []
    @Published var homeSummary = FeedHomeSummary.empty
    @Published var leaderboardEntries: [FeedLeaderboardEntry] = []
    @Published var challengePreviews: [FeedChallengePreview] = []
    @Published var gimmeCounts: [UUID: Int] = [:]
    @Published var gimmedByMe: Set<UUID> = []
    @Published var commentCounts: [UUID: Int] = [:]
    @Published var notifications: [FeedNotification] = []
    @Published var friendsCount = 0
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMoreFeed = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private var nextCursor: Date?
    private let pageSize = 20
    let userId: UUID

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
    }

    func load() async {
        // Prevent overlapping loads (task + sheet-dismiss + refresh) from racing and snapping
        // "Your Week" back to stale/0 values.
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            homeSummary = try await backend.loadHomeSummary(userId: userId)
            friendsCount = homeSummary.friendsCount
            let page = try await backend.loadFeedPage(userId: userId, cursor: nil, limit: pageSize)
            posts = page.posts
            nextCursor = page.nextCursor
            hasMoreFeed = page.hasMore
            applyEngagement(try await backend.loadEngagement(postIds: page.posts.map(\.id), userId: userId))
            leaderboardEntries = try await backend.loadFriendLeaderboard(userId: userId, period: .week)
            challengePreviews = makeChallengePreviews(summary: homeSummary, posts: posts)
            // Completed challenges bank permanent credits toward sim-course unlocks
            // (celebration popups fire from inside the service).
            WeeklyGoalsService.shared.syncChallenges(challengePreviews)
            notifications = (try? await backend.loadFeedNotifications()) ?? notifications
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentPost post: FeedPost?) async {
        guard let post, post.id == posts.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMoreFeed, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await backend.loadFeedPage(userId: userId, cursor: nextCursor, limit: pageSize)
            posts.append(contentsOf: page.posts)
            nextCursor = page.nextCursor
            hasMoreFeed = page.hasMore
            applyEngagement(try await backend.loadEngagement(postIds: page.posts.map(\.id), userId: userId))
            challengePreviews = makeChallengePreviews(summary: homeSummary, posts: posts)
            WeeklyGoalsService.shared.syncChallenges(challengePreviews)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Weekly snapshot (current user, last 7 days)

    private var myWeekPosts: [FeedPost] {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        return posts.filter { $0.userId == userId && $0.timestamp >= weekAgo }
    }

    var weeklyActivityCount: Int { homeSummary.weeklyRounds }

    /// Gimmes received this week across the user's own posts.
    var weeklyGimmesReceived: Int {
        homeSummary.gimmesReceived
    }

    /// Optimistic toggle — update the UI immediately, then persist.
    func toggleGimme(_ post: FeedPost) async {
        let id = post.id
        if gimmedByMe.contains(id) {
            gimmedByMe.remove(id)
            gimmeCounts[id] = max(0, (gimmeCounts[id] ?? 1) - 1)
            try? await backend.removeGimme(postId: id, userId: userId)
        } else {
            gimmedByMe.insert(id)
            gimmeCounts[id] = (gimmeCounts[id] ?? 0) + 1
            try? await backend.addGimme(postId: id, userId: userId)
        }
    }

    func gimmeCount(for post: FeedPost) -> Int { gimmeCounts[post.id] ?? 0 }
    func hasGimmed(_ post: FeedPost) -> Bool { gimmedByMe.contains(post.id) }
    func commentCount(for post: FeedPost) -> Int { commentCounts[post.id] ?? post.commentsCount }

    /// Resolve a post by id for opening from a notification. Notifications reference the user's own
    /// posts, which may be older than the currently-loaded feed page, so fall back to a full feed
    /// fetch when it isn't already in `posts`.
    func findPost(id: UUID) async -> FeedPost? {
        if let p = posts.first(where: { $0.id == id }) { return p }
        if let all = try? await backend.loadFeed(userId: userId) {
            return all.first(where: { $0.id == id })
        }
        return nil
    }

    func createPost(title: String, body: String, type: FeedPostType, highlight: String, authorName: String,
                    visibility: FeedVisibility = .everyone, photoData: Data? = nil, extraStats: [FeedStat] = []) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHighlight = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty || !cleanBody.isEmpty || !cleanHighlight.isEmpty
                || !extraStats.isEmpty || photoData != nil else { return }

        let displayTitle: String
        if cleanTitle.isEmpty {
            switch type {
            case .round: displayTitle = "Course Round"
            case .session: displayTitle = "Practice Session"
            case .shot: displayTitle = "Shot Update"
            case .achievement: displayTitle = "True Carry Update"
            }
        } else {
            displayTitle = cleanTitle
        }

        var stats = extraStats
        if !cleanHighlight.isEmpty { stats.append(FeedStat(label: "Highlight", value: cleanHighlight)) }
        let savedPhoto = photoData.flatMap { savePhoto($0) }
        let post = FeedPost(
            userId: userId,
            authorName: authorName,
            type: type,
            title: displayTitle,
            subtitle: cleanBody,
            metricHighlight: cleanHighlight,
            stats: stats,
            timestamp: Date(),
            activityMetadata: FeedActivityMetadata(
                kind: type == .round ? .round : type == .session ? .range : .manual,
                shotCount: type == .session ? firstInteger(in: cleanHighlight) : nil,
                bestCarryYards: type == .shot ? firstInteger(in: cleanHighlight) : nil
            ),
            visibility: visibility,
            photoPath: savedPhoto
        )

        posts.insert(post, at: 0)
        commentCounts[post.id] = 0
        do {
            try await backend.saveFeedPost(post)
        } catch {
            posts.removeAll { $0.id == post.id }
            commentCounts.removeValue(forKey: post.id)
            errorMessage = error.localizedDescription
        }
    }

    /// Writes a post photo to the user's media dir; returns the relative filename
    /// (resolved against `compositeDir` at render time so it survives path changes).
    private func savePhoto(_ data: Data) -> String? {
        let dir = AppStorageManager.compositeDir(userId: userId)
        AppStorageManager.ensureDirectory(dir)
        let filename = "post_\(UUID().uuidString).jpg"
        do {
            try data.write(to: dir.appendingPathComponent(filename))
            return filename
        } catch {
            return nil
        }
    }

    func deletePost(id: UUID) async {
        do {
            try await backend.deleteFeedPost(postId: id, userId: userId)
            posts.removeAll { $0.id == id }
            gimmeCounts.removeValue(forKey: id)
            gimmedByMe.remove(id)
            commentCounts.removeValue(forKey: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyEngagement(_ summary: FeedEngagementSummary) {
        gimmeCounts.merge(summary.gimmeCounts) { _, new in new }
        gimmedByMe.formUnion(summary.gimmedByMe)
        commentCounts.merge(summary.commentCounts) { _, new in new }
    }

    private func makeChallengePreviews(summary: FeedHomeSummary, posts: [FeedPost]) -> [FeedChallengePreview] {
        let bestGIR = posts.compactMap { $0.activityMetadata?.greensInRegulation }.max() ?? 0
        return [
            FeedChallengePreview(
                title: "Weekly Long Drive",
                subtitle: summary.bestCarryYards > 0 ? "\(summary.bestCarryYards) / 280 yd" : "Log a shot to start",
                progress: min(Double(summary.bestCarryYards) / 280.0, 1),
                icon: "bolt.fill"
            ),
            FeedChallengePreview(
                title: "GIR Streak",
                subtitle: bestGIR > 0 ? "\(bestGIR) / 9 greens in a round" : "Finish a scored round",
                // 9 greens = a genuinely strong round and actually completable — /18 meant
                // this challenge could never finish, which broke the sim-unlock ladder.
                progress: min(Double(bestGIR) / 9.0, 1),
                icon: "flag.checkered"
            ),
            FeedChallengePreview(
                title: "Range Volume",
                subtitle: "\(summary.weeklyShots) / 100 shots",
                progress: min(Double(summary.weeklyShots) / 100.0, 1),
                icon: "scope"
            )
        ]
    }

    private func firstInteger(in text: String) -> Int? {
        let pattern = #"[-+]?\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Int(text[range])
    }
}

// MARK: - Comments

@MainActor
final class CommentsViewModel: ObservableObject {
    @Published var comments: [FeedComment] = []
    @Published var draft: String = ""
    @Published var isLoading = false

    private let backend: AppBackend
    private let post: FeedPost
    private let userId: UUID
    private let authorName: String

    init(post: FeedPost, userId: UUID, authorName: String, backend: AppBackend) {
        self.post = post
        self.userId = userId
        self.authorName = authorName
        self.backend = backend
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        comments = (try? await backend.loadComments(postId: post.id)) ?? []
    }

    func submit() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let comment = FeedComment(postId: post.id, userId: userId, authorName: authorName, body: body)
        draft = ""
        comments.append(comment) // optimistic
        do {
            try await backend.addComment(comment)
        } catch {
            comments.removeAll { $0.id == comment.id }
            draft = body
        }
    }
}

// MARK: - Friends / contacts

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [FriendProfile] = []
    @Published var friends: [FriendProfile] = []
    @Published var requests: [IncomingFriendRequest] = []
    @Published var attestations: [IncomingAttestation] = []
    @Published var sentRequestIds: Set<UUID> = []
    @Published var inviteCode: String?
    @Published var redeemCode = ""
    @Published var statusMessage: String?
    @Published var isSearching = false

    private let backend: AppBackend
    let userId: UUID

    init(userId: UUID, backend: AppBackend) {
        self.userId = userId
        self.backend = backend
    }

    func loadAll() async {
        friends = (try? await backend.loadFriends()) ?? []
        requests = (try? await backend.loadIncomingRequests()) ?? []
        attestations = (try? await backend.loadIncomingAttestations(userId: userId)) ?? []
    }

    func respondAttestation(_ attestation: IncomingAttestation, accept: Bool) async {
        do {
            try await backend.respondToAttestation(id: attestation.id, accept: accept)
            attestations.removeAll { $0.id == attestation.id }
            statusMessage = accept ? "Round attested." : "Request declined."
        } catch {
            statusMessage = "Couldn't respond to the request."
        }
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = []; return }
        isSearching = true
        defer { isSearching = false }
        results = (try? await backend.searchUsers(query: q)) ?? []
    }

    func sendRequest(to profile: FriendProfile) async {
        do {
            try await backend.sendFriendRequest(fromUserId: userId, toUserId: profile.userId)
            sentRequestIds.insert(profile.userId)
            statusMessage = "Request sent to \(profile.displayName)."
        } catch {
            statusMessage = "Couldn't send request."
        }
    }

    func accept(_ request: IncomingFriendRequest) async {
        do {
            try await backend.acceptFriendRequest(requestId: request.requestId)
            requests.removeAll { $0.requestId == request.requestId }
            await loadAll()
        } catch {
            statusMessage = "Couldn't accept request."
        }
    }

    func decline(_ request: IncomingFriendRequest) async {
        try? await backend.declineFriendRequest(requestId: request.requestId)
        requests.removeAll { $0.requestId == request.requestId }
    }

    func makeInviteCode() async {
        inviteCode = try? await backend.createInviteCode(userId: userId)
    }

    func redeem() async {
        let code = redeemCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        do {
            var rewardDays = 0
            if let supa = backend as? SupabaseBackendService {
                rewardDays = try await supa.redeemInviteReward(code: code)
            } else {
                try await backend.redeemInvite(code: code)
            }
            redeemCode = ""
            statusMessage = rewardDays > 0
                ? "You're connected — you both earned \(rewardDays) days of Pro!"
                : "You're now connected!"
            await loadAll()
        } catch {
            statusMessage = "Invalid or expired code."
        }
    }

    func isFriend(_ profile: FriendProfile) -> Bool {
        friends.contains { $0.userId == profile.userId }
    }
}
