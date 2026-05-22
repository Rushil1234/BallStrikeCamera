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

    // Gimmes (feed reactions) — the golf-flavored "kudos"
    func loadGimmes() async throws -> [FeedReaction]
    func addGimme(postId: UUID, userId: UUID) async throws
    func removeGimme(postId: UUID, userId: UUID) async throws

    // Comments
    func loadComments(postId: UUID) async throws -> [FeedComment]
    func addComment(_ comment: FeedComment) async throws

    // Friends / contacts
    func searchUsers(query: String) async throws -> [FriendProfile]
    func sendFriendRequest(fromUserId: UUID, toUserId: UUID) async throws
    func loadIncomingRequests() async throws -> [IncomingFriendRequest]
    func acceptFriendRequest(requestId: UUID) async throws
    func declineFriendRequest(requestId: UUID) async throws
    func loadFriends() async throws -> [FriendProfile]
    func createInviteCode(userId: UUID) async throws -> String
    func redeemInvite(code: String) async throws

    // Entitlements & usage
    func loadEntitlement(userId: UUID) async throws -> UserEntitlement
    func loadUsageCounter(userId: UUID, date: String) async throws -> UsageCounter?
    func incrementUsage(userId: UUID, action: EntitlementAction) async throws
}

// MARK: - Default implementations (local fallback)

extension AppBackend {
    func deleteSimSession(sessionId: UUID, userId: UUID) async throws {}
    func deleteCourseRound(roundId: UUID, userId: UUID) async throws {}

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
