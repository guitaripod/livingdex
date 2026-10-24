import Combine
import Foundation
import MidgarCommerce
import MidgarCore
import UIKit

/// Whether this person has Pro, and the plans the paywall sells. The purchase engine is MidgarStore: it buys, finishes,
/// listens to `Transaction.updates` and reports to the ledger, and its entitlements are StoreKit's current
/// entitlements united with the ledger's answer for the Midgar ID. A subscription bought before the move is an Apple
/// transaction like any other, so it keeps Pro here with no network.
///
/// `isPro` follows the store's `entitlementsChanged`, so an Ask to Buy purchase unlocks Pro by itself when it is
/// approved, and a refund or a lapsed subscription takes it away. Every answer of the store is committed to
/// ``ProEntitlementStore`` and seeds `isPro` at the next launch, so a subscriber never sees the free state for the
/// moments before the store has answered. The store is nil where the app reaches no Midgar service (a test host or a
/// demo capture), and `isPro` then stays at its seed.
@MainActor
final class ProAccess {
    static let shared = ProAccess(store: LivingDexMidgar.shared.store)

    @Published private(set) var isPro: Bool

    private let store: MidgarStore?
    private let entitlementStore: ProEntitlementStore

    init(store: MidgarStore?, entitlementStore: ProEntitlementStore = ProEntitlementStore()) {
        self.store = store
        self.entitlementStore = entitlementStore
        isPro = entitlementStore.lastKnownPro
        guard let store else {
            return
        }
        Task { [weak self] in
            for await event in await store.events() {
                await self?.handle(event)
            }
        }
        Task { [weak self] in
            await store.reportPurchaseHistory()
            await self?.readEntitlements()
        }
    }

    var entitlementPublisher: AnyPublisher<Bool, Never> {
        $isPro.removeDuplicates().eraseToAnyPublisher()
    }

    /// The App Store manage-subscriptions destination, so the user changes or cancels billing where Apple owns it.
    nonisolated var manageSubscriptionsURL: URL {
        URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    /// The plans on offer, annual first, with StoreKit's prices and the free trial this customer may use. Empty where
    /// the app has no store. Throws when StoreKit cannot load the products.
    func plans() async throws -> [PaywallPlan] {
        guard let store else {
            return []
        }
        let sold = try await store.products()
        let trials = (try? await MidgarTrialPolicy().presentations(for: LivingDexPacks.proProductIDs)) ?? [:]
        let quotes = ProProduct.allCases.compactMap { product in
            sold.first { $0.id == product.rawValue }.map {
                ProPlanQuote(product: product, storeProduct: $0, trial: trials[product.rawValue])
            }
        }
        return PaywallPlan.assemble(from: quotes)
    }

    /// Buys a plan through the store, which carries the Midgar ID as `appAccountToken`. The confirmation sheet is
    /// anchored to `scene` when there is one.
    func purchase(_ product: ProProduct, in scene: UIScene?) async throws -> MidgarPurchaseResult {
        guard let store else {
            throw MidgarStoreError.unsupportedPlatform
        }
        let result: MidgarPurchaseResult
        if let scene {
            result = try await store.purchase(product.rawValue, confirmIn: scene)
        } else {
            result = try await store.purchase(product.rawValue)
        }
        await readEntitlements()
        MidgarLog.info("purchase \(result) \(product.rawValue)", category: .credits)
        return result
    }

    /// Asks the App Store to sync and reads the entitlements again.
    func restore() async throws {
        do {
            try await store?.restore()
        } catch {
            await readEntitlements()
            throw error
        }
        await readEntitlements()
        MidgarLog.info("restore ok pro=\(isPro)", category: .credits)
    }

    /// Brings the store up to date, then reads the entitlements: for the moments a decision must not rest on the
    /// seed of a store that has not answered yet.
    func refresh() async {
        await store?.refresh()
        await readEntitlements()
    }

    private func readEntitlements() async {
        guard let store else {
            return
        }
        let pro = await store.isEntitled(to: LivingDexPacks.proEntitlement)
        entitlementStore.record(pro)
        if pro != isPro {
            MidgarLog.info("entitlement refreshed pro=\(pro)", category: .credits)
        }
        isPro = pro
    }

    private func handle(_ event: MidgarStoreEvent) async {
        switch event {
        case .entitlementsChanged, .purchaseApproved:
            await readEntitlements()
        case .refused(let productID):
            MidgarLog.error("Store refused an unverified transaction for \(productID)", category: .credits)
        }
    }
}

/// Persists the last answer of the store about `pro` in standard `UserDefaults`, so ``ProAccess`` can seed `isPro` before
/// the store has answered. When nothing was ever persisted the default is `false`, keeping free-with-credits as the
/// failure default. Living Dex has no app group, so the standard suite is the right store here.
nonisolated struct ProEntitlementStore: Sendable {
    private enum Key {
        static let lastKnownPro = "livingdex.subscription.lastKnownPro.v1"
    }

    private let suiteName: String?

    /// - Parameter suiteName: an optional `UserDefaults` suite, used by tests to isolate the verdict; production uses the
    ///   standard suite (Living Dex has no app group).
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
