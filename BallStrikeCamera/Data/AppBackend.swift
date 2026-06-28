import Foundation
import CoreLocation

// MARK: - Backend Protocol

/// Abstraction layer. Replace LocalBackendService with FirebaseBackendService / SupabaseBackendService later.
protocol AppBackend {
    // Auth
    func currentUser() async throws -> AppUser?
    func signIn(email: String, password: String) async throws -> AppUser
    func createAccount(name: String, email: String, password: String) async throws -> AppUser
    func sendPasswordReset(email: String) async throws
    func resendConfirmationEmail(email: String) async throws
    func refreshSession() async throws
    func continueAsGuest() async throws -> AppUser
    func signOut() async throws

    // Profile
    func saveUserProfile(_ profile: UserProfile) async throws
    func loadUserProfile(userId: UUID) async throws -> UserProfile?

    // Clubs — userId embedded in model
    func saveClub(_ club: UserClub) async throws
    func deleteClub(clubId: UUID, userId: UUID) async throws
    func loadClubs(userId: UUID) async throws -> [UserClub]

    // Shots — userId embedded in model
    func saveShot(_ shot: SavedShot) async throws
    func loadShots(userId: UUID) async throws -> [SavedShot]
    func deleteShot(shotId: UUID, userId: UUID) async throws

    // Replay frames in cloud storage (so replay survives reinstall / works cross-device)
    func uploadShotFrames(userId: UUID, shotId: UUID, frames: [Data]) async throws
    func downloadShotFrames(userId: UUID, shotId: UUID, count: Int) async throws -> [Data]

    // Per-shot composite image (single JPEG; replaces frame storage for replay)
    func uploadShotComposite(userId: UUID, shotId: UUID, jpeg: Data) async throws
    func downloadShotComposite(userId: UUID, shotId: UUID) async throws -> Data?

    // Range sessions — userId embedded in model
    func saveRangeSession(_ session: PracticeSession) async throws
    func deleteRangeSession(sessionId: UUID, userId: UUID) async throws
    func loadRangeSessions(userId: UUID) async throws -> [PracticeSession]

    // Sim sessions — userId embedded in model
    func saveSimSession(_ session: SimSession) async throws
    func deleteSimSession(sessionId: UUID, userId: UUID) async throws
    func loadSimSessions(userId: UUID) async throws -> [SimSession]

    // Course rounds — userId embedded in model
    func saveRound(_ round: CourseRound) async throws
    func deleteCourseRound(roundId: UUID, userId: UUID) async throws
    func loadCourseRounds(userId: UUID) async throws -> [CourseRound]

    // Shared course geometry — keyed by provider/course id, shared across users
    func saveCourseGeometry(_ course: GolfCourse) async throws
    func loadCourseGeometry(courseId: String) async throws -> GolfCourse?
    /// Fuzzy fallback when the exact course_id misses: best name + proximity match.
    func findCourseGeometryNear(name: String, coordinate: CLLocationCoordinate2D?) async throws -> GolfCourse?
    func requestCourseGeometryBackfill(_ course: GolfCourse, reason: String) async throws

    // Feed — userId embedded in model
    func saveFeedPost(_ post: FeedPost) async throws
    func deleteFeedPost(postId: UUID, userId: UUID) async throws
    func loadFeed(userId: UUID) async throws -> [FeedPost]
    func loadHomeSummary(userId: UUID) async throws -> FeedHomeSummary
    func loadFeedPage(userId: UUID, cursor: Date?, limit: Int) async throws -> FeedPage
    func loadEngagement(postIds: [UUID], userId: UUID) async throws -> FeedEngagementSummary
    func loadFriendLeaderboard(userId: UUID, period: FeedLeaderboardPeriod) async throws -> [FeedLeaderboardEntry]
    /// Gimmes + comments others left on the current user's posts (for the notification center).
    func loadFeedNotifications() async throws -> [FeedNotification]

    // Gimmes (feed reactions) — the golf-flavored "kudos"
    func loadGimmes() async throws -> [FeedReaction]
    func addGimme(postId: UUID, userId: UUID) async throws
    func removeGimme(postId: UUID, userId: UUID) async throws

    // Comments
    func loadComments(postId: UUID) async throws -> [FeedComment]
    func addComment(_ comment: FeedComment) async throws

    // Friends / contacts
    func searchUsers(query: String) async throws -> [FriendProfile]
    func golfersAtHomeCourse() async throws -> [FriendProfile]
    func sendFriendRequest(fromUserId: UUID, toUserId: UUID) async throws
    func loadIncomingRequests() async throws -> [IncomingFriendRequest]
    func acceptFriendRequest(requestId: UUID) async throws
    func declineFriendRequest(requestId: UUID) async throws
    func loadFriends() async throws -> [FriendProfile]
    func createInviteCode(userId: UUID) async throws -> String
    func redeemInvite(code: String) async throws

    // Round attestation (ask a friend to verify a round)
    func requestRoundAttestation(round: CourseRound, requesterId: UUID, requesterName: String, attesterId: UUID) async throws
    func loadIncomingAttestations(userId: UUID) async throws -> [IncomingAttestation]
    func respondToAttestation(id: UUID, accept: Bool) async throws

    // Entitlements & usage
    func loadEntitlement(userId: UUID) async throws -> UserEntitlement
    func loadUsageCounter(userId: UUID, date: String) async throws -> UsageCounter?
    func incrementUsage(userId: UUID, action: EntitlementAction) async throws
}

// MARK: - Default implementations (local fallback)

extension AppBackend {
    func deleteSimSession(sessionId: UUID, userId: UUID) async throws {}
    func deleteCourseRound(roundId: UUID, userId: UUID) async throws {}

    // Default: no cloud frame storage (local backend keeps frames on-device).
    func uploadShotFrames(userId: UUID, shotId: UUID, frames: [Data]) async throws {}
    func downloadShotFrames(userId: UUID, shotId: UUID, count: Int) async throws -> [Data] { [] }
    func uploadShotComposite(userId: UUID, shotId: UUID, jpeg: Data) async throws {}
    func downloadShotComposite(userId: UUID, shotId: UUID) async throws -> Data? { nil }

    // Default: no notifications (local backend has no social graph).
    func loadFeedNotifications() async throws -> [FeedNotification] { [] }

    // Default: no social graph locally.
    func golfersAtHomeCourse() async throws -> [FriendProfile] { [] }

    // Default: no attestation support (local backend has no social graph).
    func requestRoundAttestation(round: CourseRound, requesterId: UUID, requesterName: String, attesterId: UUID) async throws {}
    func loadIncomingAttestations(userId: UUID) async throws -> [IncomingAttestation] { [] }
    func respondToAttestation(id: UUID, accept: Bool) async throws {}

    func loadEntitlement(userId: UUID) async throws -> UserEntitlement {
        UserEntitlement.freeTier(userId: userId)
    }
    func loadUsageCounter(userId: UUID, date: String) async throws -> UsageCounter? {
        nil
    }
    func incrementUsage(userId: UUID, action: EntitlementAction) async throws {
        // no-op for local
    }
    func sendPasswordReset(email: String) async throws {
        // no-op for local
    }
    func resendConfirmationEmail(email: String) async throws {
        // no-op for local
    }
    func refreshSession() async throws {
        // no-op for local
    }
    func saveCourseGeometry(_ course: GolfCourse) async throws {
        // no-op for local; OSMGolfService keeps the on-device cache.
    }
    func loadCourseGeometry(courseId: String) async throws -> GolfCourse? {
        nil
    }
    func findCourseGeometryNear(name: String, coordinate: CLLocationCoordinate2D?) async throws -> GolfCourse? {
        nil
    }
    func requestCourseGeometryBackfill(_ course: GolfCourse, reason: String = "missing_geometry") async throws {
        // no-op for local; the Supabase backend queues server-side geometry work.
    }

    // MARK: Feed summary defaults

    func loadHomeSummary(userId: UUID) async throws -> FeedHomeSummary {
        let now = Date()
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 24 * 3600)

        let rounds = (try? await loadCourseRounds(userId: userId)) ?? []
        let rangeSessions = (try? await loadRangeSessions(userId: userId)) ?? []
        let simSessions = (try? await loadSimSessions(userId: userId)) ?? []
        let shots = (try? await loadShots(userId: userId)) ?? []
        let posts = (try? await loadFeed(userId: userId)) ?? []
        let friends = (try? await loadFriends()) ?? []
        let reactions = (try? await loadGimmes()) ?? []

        let weeklyRounds = rounds.filter { ($0.endedAt ?? $0.startedAt) >= weekAgo && $0.endedAt != nil }.count
        let weeklyShots = shots.filter { $0.timestamp >= weekAgo }.count
        let bestShotCarry = shots
            .filter { $0.timestamp >= weekAgo }
            .map { Int($0.metrics.carryYards.rounded()) }
            .max() ?? 0
        let bestSessionCarry = rangeSessions
            .filter { ($0.endedAt ?? $0.startedAt) >= weekAgo }
            .map { Int($0.summary.bestCarry.rounded()) }
            .max() ?? 0
        let myWeekPostIds = Set(posts.filter { $0.userId == userId && $0.timestamp >= weekAgo }.map(\.id))
        let gimmesReceived = reactions.filter { myWeekPostIds.contains($0.postId) }.count

        return FeedHomeSummary(
            weeklyRounds: weeklyRounds,
            weeklyShots: weeklyShots,
            bestCarryYards: max(bestShotCarry, bestSessionCarry),
            activeStreakDays: activeStreakDays(
                rounds: rounds,
                rangeSessions: rangeSessions,
                simSessions: simSessions,
                shots: shots,
                posts: posts.filter { $0.userId == userId }
            ),
            friendsCount: friends.count,
            gimmesReceived: gimmesReceived
        )
    }

    func loadFeedPage(userId: UUID, cursor: Date?, limit: Int) async throws -> FeedPage {
        let feed = try await loadFeed(userId: userId)
        let sorted = feed.sorted { $0.timestamp > $1.timestamp }
        let pageSource = cursor.map { cursorDate in
            sorted.filter { $0.timestamp < cursorDate }
        } ?? sorted
        let cappedLimit = max(1, limit)
        let pagePosts = Array(pageSource.prefix(cappedLimit))
        let hasMore = pageSource.count > cappedLimit
        return FeedPage(posts: pagePosts, nextCursor: hasMore ? pagePosts.last?.timestamp : nil, hasMore: hasMore)
    }

    func loadEngagement(postIds: [UUID], userId: UUID) async throws -> FeedEngagementSummary {
        let wanted = Set(postIds)
        guard !wanted.isEmpty else { return FeedEngagementSummary() }

        let reactions = ((try? await loadGimmes()) ?? []).filter { wanted.contains($0.postId) }
        var summary = FeedEngagementSummary()
        for reaction in reactions {
            summary.gimmeCounts[reaction.postId, default: 0] += 1
            if reaction.userId == userId {
                summary.gimmedByMe.insert(reaction.postId)
            }
        }
        for id in postIds {
            let comments = (try? await loadComments(postId: id)) ?? []
            summary.commentCounts[id] = comments.count
        }
        return summary
    }

    func loadFriendLeaderboard(userId: UUID, period: FeedLeaderboardPeriod) async throws -> [FeedLeaderboardEntry] {
        let days = period == .week ? -7 : -30
        let start = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date().addingTimeInterval(Double(days) * 24 * 3600)
        let posts = ((try? await loadFeed(userId: userId)) ?? []).filter { $0.timestamp >= start }
        var longestDrive: [UUID: FeedLeaderboardEntry] = [:]
        var bestScore: [UUID: FeedLeaderboardEntry] = [:]
        var practiceShots: [UUID: FeedLeaderboardEntry] = [:]

        for post in posts {
            let author = post.authorName
            if let drive = post.activityMetadata?.bestCarryYards ?? bestYardage(in: post) {
                let entry = FeedLeaderboardEntry(
                    userId: post.userId,
                    displayName: author,
                    metric: .longestDrive,
                    value: drive,
                    subtitle: post.title
                )
                if drive > (longestDrive[post.userId]?.value ?? 0) {
                    longestDrive[post.userId] = entry
                }
            }

            if let score = post.activityMetadata?.totalScore, post.type == .round {
                let entry = FeedLeaderboardEntry(
                    userId: post.userId,
                    displayName: author,
                    metric: .bestScore,
                    value: score,
                    subtitle: post.title
                )
                if score < (bestScore[post.userId]?.value ?? Int.max) {
                    bestScore[post.userId] = entry
                }
            }

            if let shots = post.activityMetadata?.shotCount ?? shotCount(in: post), shots > 0 {
                let existing = practiceShots[post.userId]
                practiceShots[post.userId] = FeedLeaderboardEntry(
                    userId: post.userId,
                    displayName: author,
                    metric: .practiceShots,
                    value: (existing?.value ?? 0) + shots,
                    subtitle: period == .week ? "This week" : "This month"
                )
            }
        }

        let driveEntries = longestDrive.values.sorted { $0.value > $1.value }.prefix(3)
        let scoreEntries = bestScore.values.sorted { $0.value < $1.value }.prefix(3)
        let practiceEntries = practiceShots.values.sorted { $0.value > $1.value }.prefix(3)
        return Array(driveEntries + scoreEntries + practiceEntries)
    }

    private func activeStreakDays(
        rounds: [CourseRound],
        rangeSessions: [PracticeSession],
        simSessions: [SimSession],
        shots: [SavedShot],
        posts: [FeedPost]
    ) -> Int {
        let calendar = Calendar.current
        var activeDays = Set<Date>()
        rounds.forEach { activeDays.insert(calendar.startOfDay(for: $0.endedAt ?? $0.startedAt)) }
        rangeSessions.forEach { activeDays.insert(calendar.startOfDay(for: $0.endedAt ?? $0.startedAt)) }
        simSessions.forEach { activeDays.insert(calendar.startOfDay(for: $0.endedAt ?? $0.startedAt)) }
        shots.forEach { activeDays.insert(calendar.startOfDay(for: $0.timestamp)) }
        posts.forEach { activeDays.insert(calendar.startOfDay(for: $0.timestamp)) }

        var streak = 0
        var day = calendar.startOfDay(for: Date())
        while activeDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    private func bestYardage(in post: FeedPost) -> Int? {
        let values = ([post.metricHighlight] + post.stats.map(\.value))
            .compactMap { firstInteger(in: $0) }
        return values.max()
    }

    private func shotCount(in post: FeedPost) -> Int? {
        if let stat = post.stats.first(where: { $0.label.localizedCaseInsensitiveContains("shot") }) {
            return firstInteger(in: stat.value)
        }
        if post.subtitle.localizedCaseInsensitiveContains("shot") {
            return firstInteger(in: post.subtitle)
        }
        return nil
    }

    private func firstInteger(in text: String) -> Int? {
        let pattern = #"[-+]?\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Int(text[range])
    }

    // MARK: Social defaults (local/guest mode has no social graph)

    func loadGimmes() async throws -> [FeedReaction] { [] }
    func addGimme(postId: UUID, userId: UUID) async throws {}
    func removeGimme(postId: UUID, userId: UUID) async throws {}
    func loadComments(postId: UUID) async throws -> [FeedComment] { [] }
    func addComment(_ comment: FeedComment) async throws {}
    func searchUsers(query: String) async throws -> [FriendProfile] { [] }
    func sendFriendRequest(fromUserId: UUID, toUserId: UUID) async throws {}
    func loadIncomingRequests() async throws -> [IncomingFriendRequest] { [] }
    func acceptFriendRequest(requestId: UUID) async throws {}
    func declineFriendRequest(requestId: UUID) async throws {}
    func loadFriends() async throws -> [FriendProfile] { [] }
    func createInviteCode(userId: UUID) async throws -> String { String(UUID().uuidString.prefix(8)).uppercased() }
    func redeemInvite(code: String) async throws {}
}

// MARK: - Backend Errors

enum BackendError: LocalizedError {
    case userNotFound
    case wrongPassword
    case emailAlreadyExists
    case emailConfirmationRequired(String)
    case notAuthenticated
    case saveFailed(String)
    case loadFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .userNotFound:        return "Account not found."
        case .wrongPassword:       return "Incorrect password."
        case .emailAlreadyExists:  return "An account with this email already exists."
        case .emailConfirmationRequired(let email):
            return "Check \(email) to confirm your account, then sign in."
        case .notAuthenticated:    return "You must be signed in."
        case .saveFailed(let m):   return "Save failed: \(m)"
        case .loadFailed(let m):   return "Load failed: \(m)"
        case .networkError(let m): return "Network error: \(m)"
        }
    }
}
