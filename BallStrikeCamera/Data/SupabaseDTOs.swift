import Foundation

// MARK: - Auth DTOs

struct SupabaseSignInRequest: Encodable {
    let email: String
    let password: String
}

struct SupabaseSignUpRequest: Encodable {
    let email: String
    let password: String
    let data: [String: String]?
}

struct SupabaseAuthResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case tokenType    = "token_type"
        case expiresIn    = "expires_in"
        case refreshToken = "refresh_token"
        case user
    }
}

struct SupabaseSignUpResponse: Decodable {
    let accessToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case tokenType    = "token_type"
        case expiresIn    = "expires_in"
        case refreshToken = "refresh_token"
        case user
    }
}

struct SupabaseUser: Decodable {
    let id: String
    let email: String?
    let userMetadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }
}

// MARK: - Table Row DTOs

struct SupabaseProfileRow: Codable {
    var id: String
    var userId: String
    var displayName: String
    var handedness: String
    var distanceUnit: String
    var speedUnit: String
    var homeCourseName: String
    var profileImagePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId          = "user_id"
        case displayName     = "display_name"
        case handedness      = "handedness"
        case distanceUnit    = "distance_unit"
        case speedUnit       = "speed_unit"
        case homeCourseName  = "home_course_name"
        case profileImagePath = "profile_image_path"
    }

    func toUserProfile() -> UserProfile? {
        guard let uid = UUID(uuidString: userId) else { return nil }
        return UserProfile(
            id: UUID(uuidString: id) ?? UUID(),
            userId: uid,
            displayName: displayName,
            handedness: Handedness(rawValue: handedness) ?? .right,
            distanceUnit: DistanceUnit(rawValue: distanceUnit) ?? .yards,
            speedUnit: SpeedUnit(rawValue: speedUnit) ?? .mph,
            homeCourseName: homeCourseName,
            profileImagePath: profileImagePath
        )
    }
}

struct SupabaseEntitlementRow: Codable {
    var id: String
    var userId: String
    var tier: String
    var paymentStatus: String
    var stripeCustomerId: String?
    var stripeSubscriptionId: String?
    var currentPeriodStart: String?
    var currentPeriodEnd: String?
    var cancelAtPeriodEnd: Bool
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId               = "user_id"
        case tier
        case paymentStatus        = "payment_status"
        case stripeCustomerId     = "stripe_customer_id"
        case stripeSubscriptionId = "stripe_subscription_id"
        case currentPeriodStart   = "current_period_start"
        case currentPeriodEnd     = "current_period_end"
        case cancelAtPeriodEnd    = "cancel_at_period_end"
        case updatedAt            = "updated_at"
    }

    func toUserEntitlement() -> UserEntitlement? {
        guard let uid = UUID(uuidString: userId) else { return nil }
        let iso = ISO8601DateFormatter()
        return UserEntitlement(
            id: UUID(uuidString: id) ?? UUID(),
            userId: uid,
            tier: SubscriptionTier(rawValue: tier) ?? .free,
            paymentStatus: SubscriptionPaymentStatus(rawValue: paymentStatus) ?? .inactive,
            stripeCustomerId: stripeCustomerId,
            stripeSubscriptionId: stripeSubscriptionId,
            currentPeriodStart: currentPeriodStart.flatMap { iso.date(from: $0) },
            currentPeriodEnd: currentPeriodEnd.flatMap { iso.date(from: $0) },
            cancelAtPeriodEnd: cancelAtPeriodEnd
        )
    }
}

struct SupabaseCourseGeometryRow: Codable {
    var courseId: String
    var courseName: String
    var city: String
    var state: String
    var source: String
    var geometryState: String?
    var confidence: Double?
    var schemaVersion: Int?
    var generatedBy: String?
    var validationErrors: [String]?
    var imagerySource: String?
    var payload: GolfCourse
    var submittedBy: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case courseId = "course_id"
        case courseName = "course_name"
        case city
        case state
        case source
        case geometryState = "geometry_state"
        case confidence
        case schemaVersion = "schema_version"
        case generatedBy = "generated_by"
        case validationErrors = "validation_errors"
        case imagerySource = "imagery_source"
        case payload
        case submittedBy = "submitted_by"
        case updatedAt = "updated_at"
    }

    func toGolfCourse() -> GolfCourse {
        var course = payload
        let state = CourseGeometryState(rawValue: geometryState ?? "") ?? .accepted
        course.geometryMetadata = CourseGeometryMetadata(
            state: state,
            confidence: confidence,
            source: source,
            schemaVersion: schemaVersion ?? 1,
            generatedBy: generatedBy,
            validationErrors: validationErrors ?? [],
            imagerySource: imagerySource,
            updatedAt: updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
        return course
    }
}

/// Bridges compact app data tables that store the full Swift model in a JSONB `payload` column.
struct SupabasePayloadRow<Payload: Codable>: Codable {
    var id: String
    var userId: String
    var payload: Payload
    var timestamp: Date?
    var startedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case payload
        case timestamp
        case startedAt = "started_at"
    }
}

// MARK: - Feed / Social Row DTOs

/// Bridges the `feed_posts` table (id, user_id, payload JSONB, visibility, timestamp)
/// to/from the flat `FeedPost` model. The post body lives in `payload`.
struct SupabaseFeedPostRow: Codable {
    var id: String
    var userId: String
    var payload: FeedPost
    var visibility: String
    var timestamp: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case payload
        case visibility
        case timestamp
    }

    func toFeedPost() -> FeedPost? {
        var post = payload
        if let uid = UUID(uuidString: userId) { post.userId = uid }
        if let pid = UUID(uuidString: id) { post.id = pid }
        if let ts = ISO8601DateFormatter.tcFlexible.date(from: timestamp) { post.timestamp = ts }
        return post
    }
}

/// Row returned by the `feed_reactions` table (one "gimme" per user per post).
struct SupabaseReactionRow: Codable {
    var id: String
    var postId: String
    var userId: String
    var emoji: String

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case emoji
    }
}

/// Row returned by the `feed_comments` table.
struct SupabaseCommentRow: Codable {
    var id: String
    var postId: String
    var userId: String
    var authorName: String
    var body: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case userId = "user_id"
        case authorName = "author_name"
        case body
        case createdAt = "created_at"
    }

    func toFeedComment() -> FeedComment? {
        guard let pid = UUID(uuidString: postId), let uid = UUID(uuidString: userId) else { return nil }
        return FeedComment(
            id: UUID(uuidString: id) ?? UUID(),
            postId: pid,
            userId: uid,
            authorName: authorName,
            body: body,
            createdAt: ISO8601DateFormatter.tcFlexible.date(from: createdAt) ?? Date()
        )
    }
}

/// Minimal public profile returned by the `search_users` / `list_friends` RPCs.
struct SupabaseUserSearchRow: Codable {
    var userId: String
    var displayName: String
    var homeCourseName: String?
    var profileImagePath: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case homeCourseName = "home_course_name"
        case profileImagePath = "profile_image_path"
    }

    func toFriendProfile() -> FriendProfile? {
        guard let uid = UUID(uuidString: userId) else { return nil }
        return FriendProfile(userId: uid, displayName: displayName, homeCourseName: homeCourseName)
    }
}

/// Row returned by the `list_incoming_requests` RPC.
struct SupabaseIncomingRequestRow: Codable {
    var requestId: String
    var fromUserId: String
    var displayName: String
    var sentAt: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case fromUserId = "from_user_id"
        case displayName = "display_name"
        case sentAt = "sent_at"
    }

    func toIncomingRequest() -> IncomingFriendRequest? {
        guard let rid = UUID(uuidString: requestId), let uid = UUID(uuidString: fromUserId) else { return nil }
        return IncomingFriendRequest(
            requestId: rid,
            fromUserId: uid,
            displayName: displayName,
            sentAt: ISO8601DateFormatter.tcFlexible.date(from: sentAt) ?? Date()
        )
    }
}

/// Supabase `timestamptz` values may or may not carry fractional seconds; parse both.
enum SupabaseDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func parse(_ string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}

extension ISO8601DateFormatter {
    /// Convenience shim so call sites read `ISO8601DateFormatter.tcFlexible.date(from:)`.
    static let tcFlexible = FlexibleParser()
    struct FlexibleParser { func date(from string: String) -> Date? { SupabaseDate.parse(string) } }
}

// MARK: - Generic helpers

struct SupabaseError: Decodable {
    let message: String
    let code: String?
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self)  { value = v; return }
        if let v = try? c.decode(Int.self)     { value = v; return }
        if let v = try? c.decode(Double.self)  { value = v; return }
        if let v = try? c.decode(Bool.self)    { value = v; return }
        value = ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as String: try c.encode(v)
        case let v as Int:    try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Bool:   try c.encode(v)
        default:              try c.encodeNil()
        }
    }
}
