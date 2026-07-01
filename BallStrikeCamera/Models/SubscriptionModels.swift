import Foundation

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable, CaseIterable {
    case free
    case basic
    case pro
    case unlimited

    var displayName: String {
        switch self {
        case .free:      return "Free"
        case .basic:     return "Basic"
        case .pro:       return "Pro"
        case .unlimited: return "Unlimited"
        }
    }

    var monthlyShotLimit: Int {
        switch self {
        case .free:      return 50
        case .basic:     return 500
        case .pro:       return 2500
        case .unlimited: return Int.max
        }
    }

    var dailyShotLimit: Int {
        switch self {
        case .free:      return 15
        case .basic:     return 75
        case .pro:       return 300
        case .unlimited: return Int.max
        }
    }

    var canAccessCourseMode: Bool    { self != .free }
    var canAccessSimMode: Bool       { self == .pro || self == .unlimited }
    var canExportVideo: Bool         { self == .pro || self == .unlimited }
    var canAccessAdvancedInsights: Bool { self == .pro || self == .unlimited }
    var maxDevices: Int              { self == .free ? 1 : 1 }

}

// MARK: - Payment Status

enum SubscriptionPaymentStatus: String, Codable {
    case inactive
    case trialing
    case active
    case pastDue     = "past_due"
    case canceled
    case unpaid
    case incomplete

    var isActive: Bool {
        switch self {
        case .active, .trialing: return true
        default: return false
        }
    }
}

// MARK: - User Entitlement

struct UserEntitlement: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var tier: SubscriptionTier
    var paymentStatus: SubscriptionPaymentStatus
    var stripeCustomerId: String?
    var stripeSubscriptionId: String?
    var currentPeriodStart: Date?
    var currentPeriodEnd: Date?
    var cancelAtPeriodEnd: Bool = false
    var updatedAt: Date = Date()
    /// Referral/comp Pro grant that's additive to any Stripe subscription.
    /// Optional so entitlements saved before the column existed still decode.
    var compProUntil: Date? = nil

    static func freeTier(userId: UUID) -> UserEntitlement {
        UserEntitlement(
            userId: userId,
            tier: .free,
            paymentStatus: .inactive
        )
    }

    var isEntitled: Bool {
        tier == .free || paymentStatus.isActive
    }

    /// True while an active referral/comp Pro grant is in effect.
    var hasCompPro: Bool {
        if let until = compProUntil { return until > Date() }
        return false
    }

    var effectiveTier: SubscriptionTier {
        let base: SubscriptionTier = isEntitled ? tier : .free
        // Comp Pro grants Pro-level access without downgrading a higher paid tier.
        guard hasCompPro else { return base }
        return base == .unlimited ? .unlimited : .pro
    }
}

// MARK: - Usage Counter

struct UsageCounter: Codable {
    var userId: UUID
    var date: String          // "YYYY-MM-DD"
    var rangeShots: Int = 0
    var simShots: Int = 0
    var courseRounds: Int = 0

    var totalShots: Int { rangeShots + simShots }

    static func todayKey() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}

// MARK: - Device Registration

struct UserDevice: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var deviceToken: String      // identifierForVendor
    var deviceName: String
    var platform: String = "iOS"
    var appVersion: String
    var registeredAt: Date = Date()
    var lastSeenAt: Date = Date()
    var isActive: Bool = true
}

enum DeviceValidationResult {
    case allowed
    case blocked(activeDevice: UserDevice)
    case transferRequired
}

// MARK: - Entitlement Decision

enum EntitlementAction {
    case rangeShot
    case simShot
    case courseRound
    case exportVideo
    case advancedInsights
    case courseMode
    case simMode
}

struct EntitlementDecision {
    var allowed: Bool
    var reason: String?
    var upgradeURL: URL? = AppConfig.pricingURL

    static let allow = EntitlementDecision(allowed: true)
    static func deny(_ reason: String) -> EntitlementDecision {
        EntitlementDecision(allowed: false, reason: reason)
    }
}

// MARK: - App configuration (non-isolated, reads from bundle)

enum AppConfig {
    static let pricingURL: URL = {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let raw  = dict["PricingURL"] as? String,
           let url  = URL(string: raw) {
            return url
        }
        return URL(string: "https://truecarry.app/pricing")!
    }()

    static let websiteURL: URL = {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let raw  = dict["TrueCarryWebsiteURL"] as? String,
           let url  = URL(string: raw) {
            return url
        }
        return URL(string: "https://truecarry.app")!
    }()
}
