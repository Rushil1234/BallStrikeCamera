import Foundation

// MARK: - Feature Flags

enum FeatureFlag: String, CaseIterable {
    case advancedAnalytics   = "advancedAnalytics"
    case clubRecommendation  = "clubRecommendation"
    case simIntegration      = "simIntegration"
    case socialFeed          = "socialFeed"
    case cloudSync           = "cloudSync"

    var displayName: String {
        switch self {
        case .advancedAnalytics:  return "Advanced Analytics"
        case .clubRecommendation: return "Club Recommendation"
        case .simIntegration:     return "Sim Integration"
        case .socialFeed:         return "Social Feed"
        case .cloudSync:          return "Cloud Sync"
        }
    }

    var requiredTier: SubscriptionStatus { .pro }
}

// MARK: - Gate helper

extension FeatureFlag {
    /// Whether the current user can access this feature.
    func isEnabled(for status: SubscriptionStatus) -> Bool {
        switch status {
        case .admin: return true
        case .pro:   return requiredTier == .pro || requiredTier == .free
        case .free:  return requiredTier == .free
        }
    }
}
