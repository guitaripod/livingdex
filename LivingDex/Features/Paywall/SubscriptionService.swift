import Combine
import Foundation
import AICreditsCore

/// Living Dex's single source of truth for Pro access and the paywall's plan list. Talks
/// to the store through ``SubscriptionBacking`` (production: ``AICreditsSubscriptionBackend``
/// over the shared ``AICreditsManager`` client, which owns RevenueCat) — never hand-rolls
/// the store layer. Exactly the `pro` entitlement unlocks unlimited Claude cloud
/// identifications; on-device identification and narration are always free and never
/// routed through here, and non-subscribers keep metering cloud calls with consumable
/// credits.
///
/// The last authoritative verdict is persisted (``ProEntitlementStore``) and seeds
/// ``isPro`` at init, so a paying subscriber launching offline keeps Pro until the live
/// check lands; a genuine `free` verdict revokes, an inconclusive check never does.
///
/// The async client actor is bridged to the UI on a `CurrentValueSubject` at this seam;
/// VCs subscribe to ``entitlementPublisher`` / ``plansPublisher``. Plan prices come only
/// from live offerings: when they cannot be loaded ``plansPublisher`` reports
/// ``PaywallPlansState/unavailable`` so the paywall says so and offers a retry — it never
/// invents a price (Guideline 3.1.2).
@MainActor
final class SubscriptionService {
    static let shared = SubscriptionService()

    /// The outcome of a purchase attempt, so the UI can stay silent on a user cancel but
    /// never on a failed transaction.
    enum PurchaseResult: Sendable, Equatable {
        case purchased
        case cancelled
        case failed
    }

    /// The outcome of a restore attempt. A failed call is kept distinct from a
    /// successful-but-empty restore so the UI never tells a paying subscriber there is
    /// nothing to restore when the App Store was simply unreachable.
    enum RestoreResult: Sendable, Equatable {
        case restored
        case nothingToRestore
        case failed
    }

    /// Whether the user currently holds the `pro` entitlement. Drives every Pro gate.
    var isPro: Bool { entitlementSubject.value }

    var entitlementPublisher: AnyPublisher<Bool, Never> {
        entitlementSubject.removeDuplicates().eraseToAnyPublisher()
    }

    /// The plan-list state the paywall renders — live-priced plans (annual-first) when
    /// offerings resolved, else loading or an honest unavailable state.
    var plansPublisher: AnyPublisher<PaywallPlansState, Never> {
        plansSubject.eraseToAnyPublisher()
    }

    private let entitlementSubject: CurrentValueSubject<Bool, Never>
    private let plansSubject = CurrentValueSubject<PaywallPlansState, Never>(.loading)
    private let backend: any SubscriptionBacking
    private let entitlementStore: ProEntitlementStore
    private var lastEntitlementCheck: Date?

    private static let foregroundRefreshInterval: TimeInterval = 5 * 60

    init(
        backend: any SubscriptionBacking = AICreditsSubscriptionBackend(),
        entitlementStore: ProEntitlementStore = ProEntitlementStore()
    ) {
        self.backend = backend
        self.entitlementStore = entitlementStore
        entitlementSubject = CurrentValueSubject(entitlementStore.lastKnownPro)
    }

    /// Boots identity, then refreshes the live entitlement and offerings. Safe to call on
    /// every launch; failures degrade to the committed fallback rather than blocking UI.
    /// Until the live check lands, gates run on the last persisted verdict — a paying
    /// subscriber launching offline keeps Pro, and a fresh install stays free-with-credits.
    func bootstrap() {
        lastEntitlementCheck = .now
        Task { [weak self] in
            await self?.refreshEntitlement()
            await self?.loadPlans()
        }
    }

    /// Re-verifies the entitlement, committing only authoritative verdicts. An inconclusive
    /// check (offline, identity or store unavailable) keeps the current state, so a
    /// subscriber is never locked out mid-session by a dead network — only a genuine `free`
    /// verdict revokes.
    func refreshEntitlement() async {
        lastEntitlementCheck = .now
        switch await backend.proVerdict() {
        case .pro:
            commitEntitlement(true)
        case .free:
            commitEntitlement(false)
        case .unknown:
            AppLogger.shared.info(
                "entitlement check inconclusive, keeping pro=\(isPro)", category: .credits)
        }
    }

    /// Foreground hook: re-verifies the entitlement at most once per five minutes so
    /// revocations and cross-device purchases land without a chatty check on every
    /// activation. Returns whether a refresh was scheduled.
    @discardableResult
    func refreshEntitlementIfStale(now: Date = .now) -> Bool {
        if let lastEntitlementCheck,
            now.timeIntervalSince(lastEntitlementCheck) < Self.foregroundRefreshInterval {
            return false
        }
        lastEntitlementCheck = now
        Task { [weak self] in await self?.refreshEntitlement() }
        return true
    }

    private func commitEntitlement(_ pro: Bool) {
        entitlementStore.record(pro)
        entitlementSubject.send(pro)
        AppLogger.shared.info("entitlement refreshed pro=\(pro)", category: .credits)
    }

    /// Pulls live RevenueCat subscription plans and republishes them annual-first. Failures
    /// and empty offerings publish `.unavailable` (the paywall says so and offers a retry)
    /// unless store-priced plans already resolved, which stay — a hardcoded price is never
    /// substituted. Each call re-runs the client's identity bootstrap when needed, so a
    /// retry also recovers from a failed first-launch mako registration.
    func loadPlans() async {
        if !hasLoadedPlans { plansSubject.send(.loading) }
        let live: [SubscriptionPlan]
        do {
            live = try await backend.subscriptionPlans()
        } catch {
            AppLogger.shared.warn("subscription plans load failed: \(error)", category: .credits)
            markPlansUnavailableIfNeverLoaded()
            return
        }
        let plans = Self.assemble(live: live)
        guard !plans.isEmpty else {
            markPlansUnavailableIfNeverLoaded()
            return
        }
        plansSubject.send(.loaded(plans))
    }

    private var hasLoadedPlans: Bool {
        if case .loaded = plansSubject.value { return true }
        return false
    }

    /// Downgrades to the unavailable state only when no live plans ever resolved — a
    /// refresh failure never discards already-loaded, store-sourced prices.
    private func markPlansUnavailableIfNeverLoaded() {
        guard !hasLoadedPlans else { return }
        plansSubject.send(.unavailable)
    }

    /// Purchases a live, store-priced plan through the AICredits client; on success the
    /// entitlement is re-verified so every gate updates.
    func purchase(_ plan: PaywallPlan) async -> PurchaseResult {
        do {
            try await backend.purchaseSubscription(Self.asSubscription(plan))
            await refreshEntitlement()
            AppLogger.shared.info("purchase ok \(plan.productID)", category: .credits)
            return .purchased
        } catch AICreditsError.purchaseCancelled {
            return .cancelled
        } catch {
            AppLogger.shared.error("purchase failed \(plan.productID): \(error)", category: .credits)
            return .failed
        }
    }

    func restore() async -> RestoreResult {
        do {
            try await backend.restoreEntitlements()
            await refreshEntitlement()
            AppLogger.shared.info("restore ok pro=\(entitlementSubject.value)", category: .credits)
            return entitlementSubject.value ? .restored : .nothingToRestore
        } catch {
            AppLogger.shared.error("restore failed: \(error)", category: .credits)
            return .failed
        }
    }

    /// The App Store manage-subscriptions destination, so the user changes or cancels
    /// billing where Apple owns it.
    nonisolated var manageSubscriptionsURL: URL {
        URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    /// Reconstructs the minimal live ``SubscriptionPlan`` the client needs to purchase —
    /// only the package `id` reaches RevenueCat, so the dropped price/currency fields are
    /// immaterial here.
    private static func asSubscription(_ plan: PaywallPlan) -> SubscriptionPlan {
        SubscriptionPlan(
            id: plan.id,
            productID: plan.productID,
            localizedPrice: plan.displayPrice,
            price: 0,
            currencyCode: nil,
            period: plan.billing == .monthly ? .monthly : .annual,
            trialDays: plan.trialDays,
            trialEligible: plan.trialDays != nil)
    }

    /// Lifts the live subscription plans into the paywall's display models, annual first,
    /// so the recommended value reads first. Weekly or other periods (should the store ever
    /// carry them) are ignored — Living Dex Pro is a monthly/annual subscription.
    nonisolated static func assemble(live: [SubscriptionPlan]) -> [PaywallPlan] {
        let annual = live.first { $0.period == .annual }
        let monthly = live.first { $0.period == .monthly }
        var plans: [PaywallPlan] = []
        if let annual { plans.append(.live(from: annual, monthlyReference: monthly)) }
        if let monthly { plans.append(.live(from: monthly, monthlyReference: nil)) }
        return plans
    }
}

/// Persists the last authoritative `pro` verdict in standard `UserDefaults` so gates can
/// be seeded before RevenueCat resolves — a paying subscriber launching offline is not
/// shown locked Pro surfaces. When nothing was ever persisted the default is `false`,
/// keeping free-with-credits as the failure default. Living Dex has no app group, so the
/// standard suite is the right store here.
nonisolated struct ProEntitlementStore: Sendable {
    private enum Key {
        static let lastKnownPro = "livingdex.subscription.lastKnownPro.v1"
    }

    private let suiteName: String?

    /// - Parameter suiteName: an optional `UserDefaults` suite, used by tests to isolate
    ///   the verdict; production uses the standard suite (Living Dex has no app group).
    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        guard let suiteName else { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    var lastKnownPro: Bool { defaults.bool(forKey: Key.lastKnownPro) }

    func record(_ pro: Bool) {
        defaults.set(pro, forKey: Key.lastKnownPro)
    }
}
