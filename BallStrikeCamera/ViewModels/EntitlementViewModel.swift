import Foundation
import SwiftUI

@MainActor
final class EntitlementViewModel: ObservableObject {

    @Published var entitlement: UserEntitlement = UserEntitlement.freeTier(userId: UUID())
    @Published var usage: UsageCounter?
    @Published var isLoading = false

    @AppStorage("tc_dev_mode") private var _isDeveloperModeStored: Bool = false

    /// Only honoured for explicitly authorised user IDs — prevents guests from
    /// keeping developer mode active if they had it toggled before the toggle was removed.
    private static let authorisedDevUserIds: Set<String> = [
        "35eabe3f-68db-43e1-bf4d-4995ccb3301a"  // noahtobias19@gmail.com
    ]

    var isDeveloperMode: Bool {
        get { Self.authorisedDevUserIds.contains(entitlement.userId.uuidString) }
        set { _isDeveloperModeStored = newValue }
    }

    var backend: AppBackend

    init(backend: AppBackend) {
        self.backend = backend
    }

    // MARK: - Load

    func load(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        // Authorised dev accounts always get unlimited regardless of DB state.
        if Self.authorisedDevUserIds.contains(userId.uuidString) {
            entitlement = UserEntitlement(
                id: UUID(), userId: userId, tier: .unlimited,
                paymentStatus: .active,
                stripeCustomerId: nil, stripeSubscriptionId: nil,
                currentPeriodStart: nil,
                currentPeriodEnd: Calendar.current.date(byAdding: .year, value: 73, to: Date()),
                cancelAtPeriodEnd: false
            )
            _isDeveloperModeStored = true
            return
        }
        entitlement = (try? await backend.loadEntitlement(userId: userId)) ?? UserEntitlement.freeTier(userId: userId)
        usage = try? await backend.loadUsageCounter(userId: userId, date: UsageCounter.todayKey())
    }

    func refresh(userId: UUID) async {
        await load(userId: userId)
    }

    // MARK: - Decision helpers

    func canPerform(_ action: EntitlementAction) -> EntitlementDecision {
        if isDeveloperMode { return .allow }
        return EntitlementService.decide(action: action, entitlement: entitlement, usage: usage)
    }

    var canStartRangeSession: Bool {
        canPerform(.rangeShot).allowed
    }

    var canStartCourseRound: Bool {
        canPerform(.courseMode).allowed
    }

    var canStartSimSession: Bool {
        canPerform(.simMode).allowed
    }

    var canExportVideo: Bool {
        canPerform(.exportVideo).allowed
    }

    var canAccessAdvancedInsights: Bool {
        canPerform(.advancedInsights).allowed
    }

    var remainingDailyShots: Int {
        if isDeveloperMode { return Int.max }
        return EntitlementService.remainingDailyShots(entitlement: entitlement, usage: usage)
    }

    var tierDisplayName: String {
        if isDeveloperMode { return "Developer" }
        return entitlement.effectiveTier.displayName
    }

    var isFreeTier: Bool {
        if isDeveloperMode { return false }
        return entitlement.effectiveTier == .free
    }

    var upgradeURL: URL { AppConfig.pricingURL }
}
