import AICreditsCore
import Foundation
import RevenueCat

/// The tri-state outcome of a live entitlement check. `unknown` means no authoritative
/// answer could be reached (identity bootstrap or the store layer unavailable — typically
/// offline), so the last committed verdict must stand; only `free` is a genuine
/// revocation.
nonisolated enum ProVerdict: Sendable {
    case pro
    case free
    case unknown
}

/// The store-facing seam ``SubscriptionService`` talks through, so the entitlement
/// lifecycle (persistence, revocation policy, debounced foreground refresh) is testable
/// without RevenueCat or the network.
protocol SubscriptionBacking: Sendable {
    func proVerdict() async -> ProVerdict
    func subscriptionPlans() async throws -> [SubscriptionPlan]
    func purchaseSubscription(_ plan: SubscriptionPlan) async throws
    func restoreEntitlements() async throws
}

/// The production backing: the shared AICredits client (which owns identity and RevenueCat
/// configuration) plus a direct RevenueCat entitlement read, because the AICredits
/// `isPremium()` answer is "any active entitlement" while Living Dex's Pro gate must match
/// the `pro` lookup key exactly (``LivingDexPro/entitlement``).
nonisolated struct AICreditsSubscriptionBackend: SubscriptionBacking {
    private let client: AICreditsClient

    init(client: AICreditsClient = AICreditsManager.shared.client) {
        self.client = client
    }

    /// Resolves the exact `pro` entitlement. `client.isPremium()` is invoked first only
    /// for its side effects — it bootstraps identity and configures RevenueCat late, the
    /// package's committed order — and its any-entitlement boolean is discarded. If
    /// RevenueCat never configured or `customerInfo` is unreachable (RevenueCat serves its
    /// cache offline, so this means no cache either) the verdict is `.unknown`, never a
    /// revocation.
    func proVerdict() async -> ProVerdict {
        _ = await client.isPremium()
        guard Purchases.isConfigured else { return .unknown }
        guard let info = try? await Purchases.shared.customerInfo() else { return .unknown }
        return info.entitlements.active[LivingDexPro.entitlement] != nil ? .pro : .free
    }

    func subscriptionPlans() async throws -> [SubscriptionPlan] {
        try await client.subscriptionPlans()
    }

    func purchaseSubscription(_ plan: SubscriptionPlan) async throws {
        _ = try await client.purchaseSubscription(plan)
    }

    func restoreEntitlements() async throws {
        _ = try await client.restore()
    }
}
