import Foundation
import SwiftUI

@MainActor
final class EntitlementViewModel: ObservableObject {

    @Published var entitlement: UserEntitlement = UserEntitlement.freeTier(userId: UUID())
    @Published var usage: UsageCounter?
    @Published var isLoading = false

    @AppStorage("tc_dev_mode") var isDeveloperMode: Bool = false

    private let backend: AppBackend

    init(backend: AppBackend) {
        self.backend = backend
    }

    // MARK: - Load

    func load(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
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
