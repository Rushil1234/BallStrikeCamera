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
