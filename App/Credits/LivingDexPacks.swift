import Foundation
import MidgarCommerce
import MidgarCredits

/// The Pro subscriptions Living Dex sells. Both grant the `pro` entitlement of the registry's `[commerce]` table and
/// share one subscription group, "Living Dex Pro".
nonisolated enum ProProduct: String, CaseIterable {
    case monthly = "com.guitaripod.livingdex.pro.monthly"
    case annual = "com.guitaripod.livingdex.pro.annual"
}

/// Everything Living Dex sells, in one place: the store configuration, the credits configuration and the tests all read
/// this table. The pack ids and amounts are mako's catalog for the `livingdex` tenant, and mako requires each product
/// id to be its `rc_product_prefix` (`com.guitaripod.livingdex.credits.`) plus the pack id. Prices are StoreKit's, from
/// the App Store records and `Products.storekit`.
nonisolated enum LivingDexPacks {
    static let proEntitlement = "pro"

    static let starter = MidgarCreditsPack(id: "starter", productID: "com.guitaripod.livingdex.credits.starter", credits: 100)
    static let regular = MidgarCreditsPack(id: "regular", productID: "com.guitaripod.livingdex.credits.regular", credits: 400)
    static let propack = MidgarCreditsPack(id: "propack", productID: "com.guitaripod.livingdex.credits.propack", credits: 1200)
    static let science = MidgarCreditsPack(id: "science", productID: "com.guitaripod.livingdex.credits.science", credits: 2600)

    static let all = [starter, regular, propack, science]

    static let packProductIDs = all.map(\.productID)

    static let proProductIDs = ProProduct.allCases.map(\.rawValue)

    static let productIDs = proProductIDs + packProductIDs

    /// One store sells everything: the two Pro plans grant `pro`, the packs are consumables that grant no entitlement
    /// (MidgarCredits credits them through mako).
    static func storeConfiguration(directory: URL? = nil) -> MidgarStoreConfiguration {
        MidgarStoreConfiguration(
            appID: LivingDexMidgar.appID,
            productIDs: productIDs,
            entitlementsByProduct: Dictionary(uniqueKeysWithValues: proProductIDs.map { ($0, proEntitlement) }),
            mode: .purchases,
            directory: directory
        )
    }

    static func creditsConfiguration(directory: URL? = nil) -> MidgarCreditsConfiguration {
        MidgarCreditsConfiguration(packs: all, directory: directory)
    }
}
