import AICreditsCore
import Foundation
import MidgarCommerce
import MidgarCore
import MidgarCredits
import os
import StoreKit
import StoreKitTest
import Testing
import UIKit
@testable import LivingDex

extension StoreKitSuites {
    /// Buys Living Dex's credit packs through MidgarCredits on a MidgarStore with the app's own configuration, against
    /// `Products.storekit` (the file the scheme runs with), so the pack table, the StoreKit products and mako's validate
    /// request are checked together on a real StoreKit. The gateway is a `URLProtocol` stub, so nothing reaches mako.
    /// StoreKit is process-wide, so the suites under `StoreKitSuites` run serially. A test session signs its
    /// transactions with Xcode's local certificate, so the store never reports them to the ledger. The first purchase on
    /// a fresh simulator can stall: rerun once. The legacy account deletion tests live here too, because they share the
    /// process-wide gateway stub and a suite that resets it must not run beside another. The purchased transaction is
    /// read from the session, not from `Transaction.latest`, which does not reliably return a finished consumable.
    @MainActor
    @Suite(.timeLimit(.minutes(3)))
    struct CreditsPurchaseStoreKitTests {
        private nonisolated static let legacyKey = "legacy-aicredits-key"
        private static let starterProductID = "com.guitaripod.livingdex.credits.starter"
        private static let validatePath = "/v1/credits/purchase/revenuecat/validate"

        private struct Harness {
            let store: MidgarStore
            let credits: MidgarCredits
            let model: CreditsModel
            let session: SKTestSession
            let directory: URL

            func stop() async {
                await credits.stop()
                await store.stop()
                try? FileManager.default.removeItem(at: directory)
            }
        }

        private func makeHarness(purchasing override: (any MidgarCreditsPurchasing)? = nil) throws -> Harness {
            let session = try SKTestSession(contentsOf: productsConfigurationURL)
            session.resetToDefaultState()
            session.clearTransactions()
            session.disableDialogs = true
            session.askToBuyEnabled = false
            CreditsGatewayStub.reset()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("livingdex-credits-" + UUID().uuidString, isDirectory: true)
            let configuration = CreditsGatewayStub.httpConfiguration()
            let identity = StubIdentity()
            let store = MidgarStore(
                configuration: LivingDexPacks.storeConfiguration(directory: directory),
                identity: identity,
                http: MidgarHTTPClient(configuration: configuration)
            )
            let credits = MidgarCredits(
                configuration: LivingDexPacks.creditsConfiguration(directory: directory),
                http: configuration,
                identity: identity,
                purchasing: override ?? SceneAnchoredPurchasing(store: store),
                legacyAPIKey: { Self.legacyKey }
            )
            return Harness(store: store, credits: credits, model: CreditsModel(source: credits), session: session, directory: directory)
        }

        @Test func theConfigurationFileSellsTheFourPacksAtTheirPrices() throws {
            let sold = Dictionary(uniqueKeysWithValues: try StoreKitFile.load().products.map { ($0.productID, $0) })

            #expect(Set(sold.keys) == Set(LivingDexPacks.packProductIDs))
            #expect(sold.values.allSatisfy { $0.type == "Consumable" })
            #expect(sold["com.guitaripod.livingdex.credits.starter"]?.displayPrice == "2.99")
            #expect(sold["com.guitaripod.livingdex.credits.regular"]?.displayPrice == "9.99")
            #expect(sold["com.guitaripod.livingdex.credits.propack"]?.displayPrice == "24.99")
            #expect(sold["com.guitaripod.livingdex.credits.science"]?.displayPrice == "49.99")
            #expect(sold["com.guitaripod.livingdex.credits.starter"]?.referenceName == "Starter")
            #expect(sold["com.guitaripod.livingdex.credits.regular"]?.referenceName == "Regular")
            #expect(sold["com.guitaripod.livingdex.credits.propack"]?.referenceName == "Explorer")
            #expect(sold["com.guitaripod.livingdex.credits.science"]?.referenceName == "Naturalist")
        }

        @Test func thePackTableMatchesMakosCatalog() {
            #expect(LivingDexPacks.all.map(\.id) == ["starter", "regular", "propack", "science"])
            #expect(LivingDexPacks.all.map(\.credits) == [100, 400, 1200, 2600])
            #expect(LivingDexPacks.all.allSatisfy { $0.productID == "com.guitaripod.livingdex.credits." + $0.id })
            #expect(LivingDexPacks.creditsConfiguration().productIDs == LivingDexPacks.packProductIDs)
            #expect(LivingDexPacks.creditsConfiguration().productIDs.allSatisfy(LivingDexPacks.storeConfiguration().productIDs.contains))
        }

        @Test func oneStoreSellsTheProPlansWithTheEntitlementAndThePacksWithout() {
            let configuration = LivingDexPacks.storeConfiguration()

            #expect(Set(configuration.productIDs) == Set(LivingDexPacks.proProductIDs + LivingDexPacks.packProductIDs))
            #expect(configuration.entitlementsByProduct == [
                "com.guitaripod.livingdex.pro.monthly": "pro",
                "com.guitaripod.livingdex.pro.annual": "pro"
            ])
            #expect(configuration.mode == .purchases)
            #expect(configuration.appID == "living-dex")
        }

        @Test func theOffersAreTheFourPacksWithStoreKitsPrices() async throws {
            let harness = try makeHarness()

            let offers = try await harness.credits.offers()

            #expect(offers.map(\.pack.id) == ["starter", "regular", "propack", "science"])
            #expect(offers.map(\.product.displayPrice) == ["$2.99", "$9.99", "$24.99", "$49.99"])
            #expect(offers.map(\.product.displayName) == ["Starter", "Regular", "Explorer", "Naturalist"])
            await harness.stop()
        }

        @Test func buyingTheStarterCarriesTheMidgarIDAndPostsMakosValidateRoute() async throws {
            let harness = try makeHarness()
            CreditsGatewayStub.setBalance(30)
            let observing = Task { await harness.model.run() }
            #expect(await eventually { harness.model.knownBalance == 30 })
            CreditsGatewayStub.setBalance(130)
            CreditsGatewayStub.setValidate([.credited(added: 100, newBalance: 130)])

            let result = try await harness.credits.buy("starter")

            #expect(result == .credited(packID: "starter", creditsAdded: 100, balance: 130))
            let transaction = try #require(harness.session.allTransactions().first)
            #expect(transaction.productIdentifier == Self.starterProductID)
            let posted = CreditsGatewayStub.requests(method: "POST", pathSuffix: Self.validatePath)
            let request = try #require(posted.first)
            #expect(posted.count == 1)
            let body = try request.json()
            #expect(body["pack_id"] == "starter")
            #expect(body["product_id"] == Self.starterProductID)
            #expect(body["purchase_token"] == String(transaction.identifier))
            #expect(body["platform"] == "ios")
            let signed = try SignedTransactionPayload(jws: try #require(body["signed_transaction"]))
            #expect(signed.transactionId == String(transaction.identifier))
            #expect(signed.productId == Self.starterProductID)
            #expect(signed.appAccountToken?.uppercased() == StubIdentity.midgarID)
            #expect(request.header("X-App-ID") == "living-dex")
            #expect(request.header("Authorization") == "Bearer " + Self.legacyKey)
            #expect(request.header("X-Midgar-Token") == StubIdentity.accessToken)
            #expect(await eventually { harness.model.knownBalance == 130 })
            #expect(await harness.credits.unconfirmedPurchases == 0)
            observing.cancel()
            await harness.stop()
        }

        @Test func aCreditPendingAnswerKeepsTheReceiptAndALaterRefreshCreditsIt() async throws {
            let harness = try makeHarness()
            CreditsGatewayStub.setBalance(30)
            CreditsGatewayStub.setValidate([.error(status: 409, code: "credit_pending", message: "The credit is on its way.")])

            let result = try await harness.credits.buy("starter")

            #expect(result == .creditPending(packID: "starter", credits: 100))
            #expect(await harness.credits.unconfirmedPurchases == 1)
            let validations = CreditsGatewayStub.requests(method: "POST", pathSuffix: Self.validatePath)
            let transactionIDs = try Set(validations.map { try $0.json()["purchase_token"] })
            #expect(validations.count == 4)
            #expect(transactionIDs.count == 1)
            let kept = try Data(contentsOf: harness.directory.appendingPathComponent("credits-living-dex.json"))
            #expect(String(decoding: kept, as: UTF8.self).contains(Self.starterProductID))

            CreditsGatewayStub.setBalance(130)
            CreditsGatewayStub.setValidate([.credited(added: 100, newBalance: 130)])
            let balance = try await harness.credits.refresh()

            #expect(balance.credits == 130)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            let retried = CreditsGatewayStub.requests(method: "POST", pathSuffix: Self.validatePath)
            #expect(retried.count == 5)
            #expect(try Set(retried.map { try $0.json()["purchase_token"] }) == transactionIDs)
            await harness.stop()
        }

        @Test func aCancelledPurchaseCreditsNothingAndPostsNothing() async throws {
            let harness = try makeHarness(purchasing: CancellingPurchasing())

            let result = try await harness.credits.buy("starter")

            #expect(result == .cancelled)
            #expect(CreditsGatewayStub.requests(method: "POST", pathSuffix: Self.validatePath).isEmpty)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            await harness.stop()
        }

        @Test func aStoreKitFailureThrowsAndPostsNothing() async throws {
            let harness = try makeHarness()
            try await harness.session.setSimulatedError(.generic(.unknown), forAPI: .purchase)

            await #expect(throws: MidgarCreditsError.self) {
                _ = try await harness.credits.buy("starter")
            }

            #expect(CreditsGatewayStub.requests(method: "POST", pathSuffix: Self.validatePath).isEmpty)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            #expect(harness.session.allTransactions().isEmpty)
            await harness.stop()
        }

        @Test func anUnknownPackIsRefusedBeforeStoreKitIsAsked() async throws {
            let harness = try makeHarness()

            await #expect(throws: MidgarCreditsError.self) {
                _ = try await harness.credits.buy("huge")
            }

            #expect(CreditsGatewayStub.requests(method: "POST", pathSuffix: Self.validatePath).isEmpty)
            #expect(harness.session.allTransactions().isEmpty)
            await harness.stop()
        }

        @Test func deletingTheLegacyAccountSendsTheKeyAloneAndThenAsksNothingMore() async throws {
            CreditsGatewayStub.reset()
            let credits = makeCredits(legacyKey: "legacy-key")

            try await deleter(credits).deleteRemoteAccount()

            let deletes = CreditsGatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity")
            let request = try #require(deletes.first)
            #expect(deletes.count == 1)
            #expect(request.header("Authorization") == "Bearer legacy-key")
            #expect(request.header("X-Midgar-Token") == nil)
            #expect(request.header("X-App-ID") == "living-dex")
            await credits.stop()
        }

        @Test func noLegacyKeyMeansNothingToDelete() async throws {
            CreditsGatewayStub.reset()
            let credits = makeCredits(legacyKey: nil)

            try await deleter(credits).deleteRemoteAccount()

            #expect(CreditsGatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity").isEmpty)
            await credits.stop()
        }

        @Test(arguments: [401, 404])
        func aKeyOrAccountMakoNoLongerKnowsCountsAsDeleted(status: Int) async throws {
            CreditsGatewayStub.reset()
            CreditsGatewayStub.setLegacyDelete(.error(status: status, code: "gone", message: "Gone."))
            let credits = makeCredits(legacyKey: "legacy-key")

            try await deleter(credits).deleteRemoteAccount()

            #expect(CreditsGatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity").count == 1)
            await credits.stop()
        }

        @Test(arguments: [500, 503])
        func aFailedLegacyDeletionIsAServerFailureSoNothingLocalIsErased(status: Int) async throws {
            CreditsGatewayStub.reset()
            CreditsGatewayStub.setLegacyDelete(.error(status: status, code: "wallet_unavailable", message: "The wallet is unavailable."))
            let credits = makeCredits(legacyKey: "legacy-key")
            let erased = ErasedFlag()
            let service = AccountDeletionService(
                remote: deleter(credits), signOut: {}, eraseLocal: { erased.set() })

            await #expect(throws: AccountDeletionError.server) {
                try await service.deleteEverything()
            }

            #expect(!erased.value)
            #expect(CreditsGatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity").count == 1)
            await credits.stop()
        }

        @Test func anAnswerThatNeverCameReadsAsOffline() {
            #expect(LegacyAccountDeleter.accountDeletionError(for: MidgarCreditsError.offline) == .offline)
            #expect(LegacyAccountDeleter.accountDeletionError(for: AICreditsError.transport("down")) == .offline)
            #expect(LegacyAccountDeleter.accountDeletionError(for: MidgarCreditsError.walletUnavailable) == .server)
            #expect(LegacyAccountDeleter.accountDeletionError(for: AICreditsError.unauthorized) == .server)
        }

        private func deleter(_ credits: MidgarCredits) -> LegacyAccountDeleter {
            LegacyAccountDeleter(credits: credits, client: AICreditsManager.shared.client)
        }

        private func makeCredits(legacyKey: String?) -> MidgarCredits {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("livingdex-credits-" + UUID().uuidString, isDirectory: true)
            return MidgarCredits(
                configuration: LivingDexPacks.creditsConfiguration(directory: directory),
                http: CreditsGatewayStub.httpConfiguration(),
                identity: StubIdentity(),
                purchasing: CancellingPurchasing(),
                legacyAPIKey: { legacyKey }
            )
        }
    }
}

/// A flag the erase closure of the deletion service sets, readable after the call returned.
private final class ErasedFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var value: Bool { state.withLock { $0 } }

    func set() { state.withLock { $0 = true } }
}

/// The store with every purchase confirmed in the host app's window scene, as StoreKit needs inside a test host.
/// Everything else is the store itself, and MidgarCredits sells through this exactly as it sells through the store.
private nonisolated struct SceneAnchoredPurchasing: MidgarCreditsPurchasing {
    let store: MidgarStore

    func products() async throws -> [StoreProduct] {
        try await store.products()
    }

    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult {
        try await purchase(productID, in: store)
    }

    func events() async -> AsyncStream<MidgarStoreEvent> {
        await store.events()
    }

    @MainActor
    private func purchase(_ productID: String, in store: MidgarStore) async throws -> MidgarReceiptResult {
        try await store.purchaseReceipt(productID, confirmIn: try hostScene())
    }
}

/// The customer dismissing the purchase sheet, which StoreKitTest cannot script (a simulated `userCancelled` error
/// surfaces as a StoreKit failure, not as the `userCancelled` result): the store answers `.cancelled` itself, which is
/// what MidgarStore returns for the real result. Nothing is bought and StoreKit is not asked. It also serves as the
/// store of a wallet that only reads and deletes in the tests.
private nonisolated struct CancellingPurchasing: MidgarCreditsPurchasing {
    func products() async throws -> [StoreProduct] { [] }

    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult { .cancelled }

    func events() async -> AsyncStream<MidgarStoreEvent> { AsyncStream { _ in } }
}
