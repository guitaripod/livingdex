import AICreditsCore
import Foundation
import LivingDexCore
import MidgarCredits
import MidgarCreditsUI
import SwiftUI
import Testing
@testable import LivingDex

/// The balance model and the credit store's shortfall, which need neither StoreKit nor the gateway.
@MainActor
@Suite(.serialized)
struct CreditsModelTests {

    /// A wallet the test controls: what a read answers, and the stream of events the model follows.
    private actor ScriptedWallet: MidgarCreditStoreSource {
        struct Offline: Error {}

        private var credits: Int
        private var fails = false
        private let stream: AsyncStream<MidgarCreditsEvent>
        private let continuation: AsyncStream<MidgarCreditsEvent>.Continuation

        init(credits: Int) {
            self.credits = credits
            (stream, continuation) = AsyncStream.makeStream()
        }

        var balance: MidgarCreditsBalance? { balanceValue }

        var unconfirmedPurchases: Int { 0 }

        func set(credits: Int, failing: Bool = false) {
            self.credits = credits
            fails = failing
        }

        func emit(_ event: MidgarCreditsEvent) {
            continuation.yield(event)
        }

        func refresh() async throws -> MidgarCreditsBalance {
            if fails {
                throw Offline()
            }
            return balanceValue
        }

        func offers() async throws -> [MidgarCreditsOffer] { [] }

        func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult { .cancelled }

        func events() async -> AsyncStream<MidgarCreditsEvent> { stream }

        private var balanceValue: MidgarCreditsBalance {
            MidgarCreditsBalance(credits: credits, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        }
    }

    @Test func theBalanceStaysUnknownUntilTheWalletAnswers() {
        let model = CreditsModel(source: ScriptedWallet(credits: 30))

        #expect(model.knownBalance == nil)
    }

    @Test func theBalanceIsReadAtStartAndFollowsTheWalletsEvents() async {
        let wallet = ScriptedWallet(credits: 30)
        let model = CreditsModel(source: wallet)
        let following = Task { await model.run() }
        #expect(await eventually { model.knownBalance == 30 })

        await wallet.emit(.balanceChanged(MidgarCreditsBalance(credits: 130, updatedAt: Date())))
        #expect(await eventually { model.knownBalance == 130 })

        await wallet.set(credits: 530)
        await wallet.emit(.purchaseCredited(packID: "regular", creditsAdded: 400))
        #expect(await eventually { model.knownBalance == 530 })
        following.cancel()
    }

    @Test func aBalanceOfZeroIsKnown() async {
        let model = CreditsModel(source: ScriptedWallet(credits: 0))

        await model.refresh()

        #expect(model.knownBalance == 0)
    }

    @Test func aFailedReadKeepsTheLastBalance() async {
        let wallet = ScriptedWallet(credits: 12)
        let model = CreditsModel(source: wallet)
        await model.refresh()
        #expect(model.knownBalance == 12)

        await wallet.set(credits: 99, failing: true)
        await model.refresh()

        #expect(model.knownBalance == 12)
    }

    @Test func aFailedFirstReadLeavesTheBalanceUnknownNotZero() async {
        let wallet = ScriptedWallet(credits: 0)
        await wallet.set(credits: 0, failing: true)
        let model = CreditsModel(source: wallet)

        await model.refresh()

        #expect(model.knownBalance == nil)
    }

    @Test func aDeletedAccountsBalanceIsForgotten() async {
        let model = CreditsModel(source: ScriptedWallet(credits: 30))
        await model.refresh()

        model.forget()

        #expect(model.knownBalance == nil)
    }

    @Test func aModelWithoutAWalletStaysUnknown() async {
        let model = CreditsModel(source: nil)

        await model.refresh()

        #expect(model.knownBalance == nil)
        #expect(model.source == nil)
        #expect(CreditStoreSheet.makeController(credits: model, shortfall: 1) == nil)
    }

    @Test(arguments: [
        (3, 1, 2),
        (10, 4, 6),
        (1, 1, 1),
        (1, 5, 1)
    ])
    func theShortfallIsWhatIsRequiredBeyondWhatIsAvailable(required: Int, available: Int, shortfall: Int) {
        #expect(CreditShortfall.of(required: required, available: available) == shortfall)
    }

    @Test func aRefusalWithoutNumbersAsksForOneCredit() {
        #expect(CreditShortfall.of(required: nil, available: nil) == 1)
        #expect(CreditShortfall.of(required: 3, available: nil) == 1)
    }

    @Test func insufficientCreditsFromAnAICallReachesTheCreditStoreWithTheShortfall() throws {
        let refused = AICreditsError.insufficientCredits(required: 3, available: 1)
        let error = CloudVisionIdentifier.identifyError(from: refused)
        let shortfall = try #require(error.creditShortfall)
        let paywall = PaywallViewController(access: ProAccess(store: nil), shortfall: shortfall)
        let model = CreditsModel(source: ScriptedWallet(credits: 1))

        let store = CreditStoreSheet.makeController(credits: model, shortfall: try #require(paywall.shortfall))

        #expect(shortfall == 2)
        let sheet = try #require(store as? UIHostingController<CreditStoreSheet>)
        #expect(sheet.rootView.shortfall == 2)
    }

    @Test func aFailureThatIsNotForWantOfCreditsHasNoShortfall() {
        #expect(IdentifyError.offline.creditShortfall == nil)
        #expect(IdentifyError.serverError.creditShortfall == nil)
        #expect(IdentifyError.noSpecies.creditShortfall == nil)
        #expect(IdentifyError.creditsExhausted(shortfall: 4).creditShortfall == 4)
    }
}
