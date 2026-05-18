import Foundation

// MARK: - Pure static entitlement logic (no backend dependency)
// Server enforces limits; this is client-side pre-check only.

enum EntitlementService {

    static func decide(action: EntitlementAction, entitlement: UserEntitlement, usage: UsageCounter?) -> EntitlementDecision {
        let tier = entitlement.effectiveTier

        switch action {

        case .courseMode:
            return tier.canAccessCourseMode
                ? .allow
                : .deny("Course mode requires a Basic subscription or higher.")

        case .simMode:
            return tier.canAccessSimMode
                ? .allow
                : .deny("Simulator mode requires a Pro subscription.")

        case .exportVideo:
            return tier.canExportVideo
                ? .allow
                : .deny("Video export requires a Pro subscription.")

        case .advancedInsights:
            return tier.canAccessAdvancedInsights
                ? .allow
                : .deny("Advanced insights require a Pro subscription.")

        case .rangeShot:
            if let u = usage {
                if u.rangeShots >= tier.dailyShotLimit {
                    return .deny("You've hit your daily shot limit (\(tier.dailyShotLimit) shots). Upgrade for more.")
                }
            }
            return .allow

        case .simShot:
            guard tier.canAccessSimMode else {
                return .deny("Simulator mode requires a Pro subscription.")
            }
            if let u = usage {
                if u.simShots >= tier.dailyShotLimit {
                    return .deny("Daily shot limit reached. Upgrade for more.")
                }
            }
            return .allow

        case .courseRound:
            guard tier.canAccessCourseMode else {
                return .deny("Course mode requires a Basic subscription or higher.")
            }
            return .allow
        }
    }

    // MARK: Convenience booleans

    static func canStartRangeSession(entitlement: UserEntitlement, usage: UsageCounter?) -> Bool {
        decide(action: .rangeShot, entitlement: entitlement, usage: usage).allowed
    }

    static func canStartCourseRound(entitlement: UserEntitlement) -> Bool {
        entitlement.effectiveTier.canAccessCourseMode
    }

    static func canStartSimSession(entitlement: UserEntitlement) -> Bool {
        entitlement.effectiveTier.canAccessSimMode
    }

    static func canExportVideo(entitlement: UserEntitlement) -> Bool {
        entitlement.effectiveTier.canExportVideo
    }

    static func canAccessAdvancedInsights(entitlement: UserEntitlement) -> Bool {
        entitlement.effectiveTier.canAccessAdvancedInsights
    }

    static func remainingDailyShots(entitlement: UserEntitlement, usage: UsageCounter?) -> Int {
        let limit = entitlement.effectiveTier.dailyShotLimit
        guard limit < Int.max else { return Int.max }
        let used = usage?.totalShots ?? 0
        return max(0, limit - used)
    }
}
