import Foundation

// MARK: - Public User Profile

struct PublicUserProfile: Codable, Identifiable {
    var id: UUID
    var displayName: String
    var handicap: Double?
    var homeCourse: String?
    var profileImageURL: String?
    var roundsPlayed: Int = 0
    var followersCount: Int = 0
    var followingCount: Int = 0
    var isFollowing: Bool = false
    var joinedAt: Date = Date()
}

// MARK: - Friend Request

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case declined
    case blocked
}

struct FriendRequest: Codable, Identifiable {
    var id: UUID = UUID()
    var fromUserId: UUID
    var toUserId: UUID
    var status: FriendRequestStatus = .pending
    var sentAt: Date = Date()
    var resolvedAt: Date?
}

// MARK: - Friendship

struct Friendship: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var friendId: UUID
    var createdAt: Date = Date()
}

// MARK: - Feed Visibility

enum FeedVisibility: String, Codable {
    case everyone
    case friends
    case `private`
}

// MARK: - Feed Reaction

struct FeedReaction: Codable, Identifiable {
    var id: UUID = UUID()
    var postId: UUID
    var userId: UUID
    var emoji: String            // "👏", "🔥", "💪"
    var createdAt: Date = Date()
}

// MARK: - Feed Comment

struct FeedComment: Codable, Identifiable {
    var id: UUID = UUID()
    var postId: UUID
    var userId: UUID
    var authorName: String
    var body: String
    var createdAt: Date = Date()
}

// MARK: - Friend Discovery View Models

/// A friend or search result — the minimal public projection returned by RPCs.
struct FriendProfile: Identifiable, Equatable {
    var userId: UUID
    var displayName: String
    var homeCourseName: String?
    var id: UUID { userId }

    var initials: String {
        let parts = displayName.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }
}

/// A pending friend request received by the current user.
struct IncomingFriendRequest: Identifiable, Equatable {
    var requestId: UUID
    var fromUserId: UUID
    var displayName: String
    var sentAt: Date
    var id: UUID { requestId }
}

/// A request from a friend asking the current user to attest (verify) one of their rounds.
/// Decoded from the `round_attestations` table (decoder uses convertFromSnakeCase).
struct IncomingAttestation: Identifiable, Decodable, Equatable {
    let id: UUID
    let roundId: UUID
    let requesterName: String
    let courseName: String
    let score: Int?
    let toPar: Int?
    let status: String
    let createdAt: Date?
}

/// An attestation the current user REQUESTED, so they can see its status and who
/// verified it. Decoded from `round_attestations` (decoder uses convertFromSnakeCase).
struct SentAttestation: Identifiable, Decodable, Equatable {
    let id: UUID
    let roundId: UUID
    let attesterName: String   // filled in once the friend responds
    let courseName: String
    let score: Int?
    let toPar: Int?
    let status: String         // pending | attested | declined
    let createdAt: Date?
    let respondedAt: Date?
}

// MARK: - Feed Notification (gimmes / comments on your posts)

struct FeedNotification: Identifiable, Equatable {
    enum Kind: String { case gimme, comment }
    var id = UUID()
    var kind: Kind
    var actorName: String
    var postId: UUID
    var postTitle: String
    var createdAt: Date

    var message: String {
        switch kind {
        case .gimme:   return "gimme'd \(postTitle)"
        case .comment: return "commented on \(postTitle)"
        }
    }
    var icon: String { kind == .gimme ? "hands.clap.fill" : "bubble.left.fill" }
}

// MARK: - In-Round Suggestion

enum SuggestionType: String, Codable {
    case clubSelection
    case layup
    case courseManagement
    case windAdjustment
}

struct InRoundSuggestion: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var roundId: UUID
    var holeNumber: Int
    var suggestionType: SuggestionType
    var body: String
    var confidenceScore: Double
    var generatedAt: Date = Date()
    var wasAccepted: Bool?
}
