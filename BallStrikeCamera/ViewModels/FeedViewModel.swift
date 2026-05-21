import Foundation

@MainActor
final class FeedViewModel: ObservableObject {

    @Published var posts: [FeedPost] = []
    @Published var gimmeCounts: [UUID: Int] = [:]
    @Published var gimmedByMe: Set<UUID> = []
    @Published var friendsCount = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    let userId: UUID

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await backend.loadFeed(userId: userId)
            let reactions = (try? await backend.loadGimmes()) ?? []
            recomputeGimmes(reactions)
            friendsCount = ((try? await backend.loadFriends()) ?? []).count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Weekly snapshot (current user, last 7 days)

    private var myWeekPosts: [FeedPost] {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        return posts.filter { $0.userId == userId && $0.timestamp >= weekAgo }
    }

    var weeklyActivityCount: Int { myWeekPosts.count }

    /// Gimmes received this week across the user's own posts.
    var weeklyGimmesReceived: Int {
        myWeekPosts.reduce(0) { $0 + (gimmeCounts[$1.id] ?? 0) }
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

    func deletePost(id: UUID) async {
        do {
            try await backend.deleteFeedPost(postId: id, userId: userId)
            posts.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recomputeGimmes(_ reactions: [FeedReaction]) {
        var counts: [UUID: Int] = [:]
        var mine = Set<UUID>()
        for r in reactions {
            counts[r.postId, default: 0] += 1
            if r.userId == userId { mine.insert(r.postId) }
        }
        gimmeCounts = counts
        gimmedByMe = mine
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
        try? await backend.addComment(comment)
    }
}

// MARK: - Friends / contacts

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [FriendProfile] = []
    @Published var friends: [FriendProfile] = []
    @Published var requests: [IncomingFriendRequest] = []
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
            try await backend.redeemInvite(code: code)
            redeemCode = ""
            statusMessage = "You're now connected!"
            await loadAll()
        } catch {
            statusMessage = "Invalid or expired code."
        }
    }

    func isFriend(_ profile: FriendProfile) -> Bool {
        friends.contains { $0.userId == profile.userId }
    }
}
