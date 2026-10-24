import Combine
import Foundation
import MidgarCommerce
import MidgarCore
import StoreKit
import StoreKitTest
import Testing
import UIKit
@testable import LivingDex

extension StoreKitSuites {
    /// Buys Living Dex Pro through MidgarStore with the app's own configuration, against `Products.storekit` (the file the
    /// scheme runs with), so the products, prices, trial and entitlement mapping the app ships are checked together on a
    /// real StoreKit. StoreKit is process-wide, so the suites under `StoreKitSuites` run serially. A test session signs
    /// its transactions with Xcode's local certificate, so the store never reports them to the ledger; the ledger is the
    /// gateway stub, which knows the Midgar ID and holds nothing.
    @MainActor
    @Suite(.timeLimit(.minutes(3)))
    struct ProPurchaseStoreKitTests {
        private struct Harness {
            let store: MidgarStore
            let access: ProAccess
            let session: SKTestSession
            let directory: URL
            let suiteName: String

            func stop() async {
                await store.stop()
                try? FileManager.default.removeItem(at: directory)
                UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            }
        }

        private func makeHarness(askToBuy: Bool = false, earlierPurchase: ProProduct? = nil) async throws -> Harness {
            let session = try SKTestSession(contentsOf: productsConfigurationURL)
            session.resetToDefaultState()
            session.clearTransactions()
            session.disableDialogs = true
            session.askToBuyEnabled = false
            if let earlierPurchase {
                _ = try await session.buyProduct(identifier: earlierPurchase.rawValue)
            }
            session.askToBuyEnabled = askToBuy
            CreditsGatewayStub.reset()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("livingdex-pro-" + UUID().uuidString, isDirectory: true)
            let suiteName = "livingdex-pro-tests-" + UUID().uuidString
            let store = MidgarStore(
                configuration: LivingDexPacks.storeConfiguration(directory: directory),
                identity: StubIdentity(),
                http: MidgarHTTPClient(configuration: CreditsGatewayStub.httpConfiguration())
            )
            let access = ProAccess(store: store, entitlementStore: ProEntitlementStore(suiteName: suiteName))
            return Harness(store: store, access: access, session: session, directory: directory, suiteName: suiteName)
        }

        @Test func theConfigurationFileSellsTheTwoPlansAtTheirPricesAndThreeDaysFreeOnTheAnnualOne() throws {
            let file = try StoreKitFile.load()
            let group = try #require(file.subscriptionGroups.first)
            let plans = Dictionary(uniqueKeysWithValues: group.subscriptions.map { ($0.productID, $0) })

            #expect(file.subscriptionGroups.count == 1)
            #expect(group.name == "Living Dex Pro")
            #expect(Set(plans.keys) == Set(LivingDexPacks.proProductIDs))
            #expect(plans[ProProduct.monthly.rawValue]?.displayPrice == "4.99")
            #expect(plans[ProProduct.monthly.rawValue]?.recurringSubscriptionPeriod == "P1M")
            #expect(plans[ProProduct.monthly.rawValue]?.introductoryOffer == nil)
            #expect(plans[ProProduct.annual.rawValue]?.displayPrice == "29.99")
            #expect(plans[ProProduct.annual.rawValue]?.recurringSubscriptionPeriod == "P1Y")
            #expect(plans[ProProduct.annual.rawValue]?.introductoryOffer?.paymentMode == "free")
            #expect(plans[ProProduct.annual.rawValue]?.introductoryOffer?.subscriptionPeriod == "P3D")
            #expect(Set(file.allProducts.map(\.productID)) == Set(LivingDexPacks.productIDs))
        }

        @Test func thePaywallPlansAreWhatStoreKitReportsAnnualFirstWithTheTrialOnTheAnnualPlan() async throws {
            let harness = try await makeHarness()

            let plans = try await harness.access.plans()
            let reported = try await Product.products(for: LivingDexPacks.proProductIDs)

            #expect(plans.map(\.product) == [.annual, .monthly])
            #expect(plans.map(\.displayPrice) == ["$29.99", "$4.99"])
            for plan in plans {
                let product = try #require(reported.first { $0.id == plan.id })
                #expect(plan.displayPrice == product.displayPrice)
            }
            #expect(plans.map(\.trialDays) == [3, nil])
            #expect(plans.first?.savings?.hasPrefix("Save ") == true)
            #expect(plans.last?.savings == nil)
            #expect(plans.first?.monthlyEquivalent?.hasSuffix("/ mo") == true)
            await harness.stop()
        }

        @Test(arguments: ProProduct.allCases)
        func everyPlanGrantsProAndCarriesTheMidgarID(_ product: ProProduct) async throws {
            let harness = try await makeHarness()
            #expect(!harness.access.isPro)

            let result = try await harness.access.purchase(product, in: try hostScene())

            #expect(result == .purchased)
            #expect(harness.access.isPro)
            #expect(await harness.store.isEntitled(to: "pro"))
            let transaction = try #require(await currentTransaction(for: product))
            #expect(transaction.appAccountToken == UUID(uuidString: StubIdentity.midgarID))
            #expect(CreditsGatewayStub.requests(method: "POST", pathSuffix: "/v1/ledger/transactions").isEmpty)
            #expect(ProEntitlementStore(suiteName: harness.suiteName).lastKnownPro)
            await harness.stop()
        }

        @Test func aRestoreFindsAnEarlierPurchase() async throws {
            let harness = try await makeHarness(earlierPurchase: .monthly)

            try await harness.access.restore()

            #expect(harness.access.isPro)
            #expect(await harness.store.isEntitled(to: "pro"))
            await harness.stop()
        }

        @Test func aRestoreWithNothingToRestoreLeavesProOff() async throws {
            let harness = try await makeHarness()

            try await harness.access.restore()

            #expect(!harness.access.isPro)
            await harness.stop()
        }

        @Test func aRefundTakesProAway() async throws {
            let harness = try await makeHarness()
            _ = try await harness.access.purchase(.annual, in: try hostScene())
            #expect(harness.access.isPro)

            let transaction = try #require(harness.session.allTransactions().first)
            try harness.session.refundTransaction(identifier: UInt(transaction.identifier))

            #expect(await eventually { !harness.access.isPro })
            await harness.stop()
        }

        @Test func aLapsedMonthlyPlanTakesProAwayAtTheNextRefresh() async throws {
            let harness = try await makeHarness()
            _ = try await harness.access.purchase(.monthly, in: try hostScene())
            #expect(harness.access.isPro)

            let transaction = try #require(harness.session.allTransactions().first)
            try harness.session.disableAutoRenewForTransaction(identifier: UInt(transaction.identifier))
            try harness.session.expireSubscription(productIdentifier: ProProduct.monthly.rawValue)

            #expect(await eventually {
                await harness.access.refresh()
                return !harness.access.isPro
            })
            await harness.stop()
        }

        @Test func askToBuyIsPendingUntilApprovedAndThenUnlocksProByItself() async throws {
            let harness = try await makeHarness(askToBuy: true)
            var unlocked = 0
            let observer = harness.access.entitlementPublisher.filter { $0 }.sink { _ in unlocked += 1 }

            let result = try await harness.access.purchase(.monthly, in: try hostScene())

            #expect(result == .pending)
            #expect(PaywallPurchaseEffect.of(result) == .waitForApproval)
            #expect(!harness.access.isPro)
            #expect(unlocked == 0)

            let waiting = try #require(harness.session.allTransactions().first)
            try harness.session.approveAskToBuyTransaction(identifier: UInt(waiting.identifier))

            #expect(await eventually { harness.access.isPro })
            #expect(await eventually { unlocked == 1 })
            observer.cancel()
            await harness.stop()
        }

        @Test func aCancelShowsNothingAndAPurchaseThatWentThroughNeedsNoMessage() {
            #expect(PaywallPurchaseEffect.of(.cancelled) == .nothing)
            #expect(PaywallPurchaseEffect.of(.purchased) == .nothing)
            #expect(PaywallPurchaseEffect.of(.pending) == .waitForApproval)
        }

        @Test func aSubscriberKeepsProOnAnOfflineLaunchFromTheLastAnswer() {
            let suiteName = "livingdex-pro-tests-" + UUID().uuidString
            let remembered = ProEntitlementStore(suiteName: suiteName)
            remembered.record(true)
            defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

            #expect(ProAccess(store: nil, entitlementStore: remembered).isPro)
            #expect(!ProAccess(store: nil, entitlementStore: ProEntitlementStore(suiteName: suiteName + ".empty")).isPro)
        }

        private func currentTransaction(for product: ProProduct) async -> Transaction? {
            var found: Transaction?
            _ = await eventually {
                for await verification in Transaction.currentEntitlements {
                    if case .verified(let transaction) = verification, transaction.productID == product.rawValue {
                        found = transaction
                        return true
                    }
                }
                return false
            }
            return found
        }
    }
}
