#if DEBUG
import Foundation
import MidgarCommerce
import MidgarCredits
import MidgarCreditsUI

/// The wallet of a demo capture: a fixed balance, the four packs at their store prices and no network. Buying does
/// nothing, so a capture can never charge anything.
nonisolated struct DemoCreditsSource: MidgarCreditStoreSource {
    /// The balance the Field meter shows in the store screenshots.
    static let fieldCredits = 27

    let credits: Int

    var balance: MidgarCreditsBalance? {
        get async { fixedBalance }
    }

    var unconfirmedPurchases: Int {
        get async { 0 }
    }

    func refresh() async throws -> MidgarCreditsBalance {
        fixedBalance
    }

    func offers() async throws -> [MidgarCreditsOffer] {
        LivingDexPacks.all.compactMap { pack in
            Self.storeListing[pack.id].map { name, price in
                MidgarCreditsOffer(
                    pack: pack,
                    product: StoreProduct(id: pack.productID, displayName: name, description: "", displayPrice: price)
                )
            }
        }
    }

    func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult {
        .cancelled
    }

    func events() async -> AsyncStream<MidgarCreditsEvent> {
        AsyncStream { _ in }
    }

    private static let storeListing = [
        LivingDexPacks.starter.id: ("Starter", "$2.99"),
        LivingDexPacks.regular.id: ("Regular", "$9.99"),
        LivingDexPacks.propack.id: ("Explorer", "$24.99"),
        LivingDexPacks.science.id: ("Naturalist", "$49.99")
    ]

    private var fixedBalance: MidgarCreditsBalance {
        MidgarCreditsBalance(credits: credits, updatedAt: Date())
    }
}
#endif
