import XCTest
import AICreditsCore
@testable import LivingDex

final class PaywallTests: XCTestCase {

    private func plan(_ period: SubscriptionPlan.Period, id: String, price: Decimal, localized: String) -> SubscriptionPlan {
        SubscriptionPlan(
            id: id,
            productID: "com.guitaripod.livingdex.pro.\(id)",
            localizedPrice: localized,
            price: price,
            currencyCode: "USD",
            period: period,
            trialDays: nil,
            trialEligible: false)
    }

    // MARK: assemble

    func testAssembleIsAnnualFirst() {
        let plans = SubscriptionService.assemble(live: [
            plan(.monthly, id: "monthly", price: 4.99, localized: "$4.99"),
            plan(.annual, id: "annual", price: 29.99, localized: "$29.99"),
        ])
        XCTAssertEqual(plans.map(\.billing), [.annual, .monthly])
        XCTAssertEqual(plans.first?.displayPrice, "$29.99")
    }

    func testAnnualDerivesMonthlyEquivalentAndSavings() {
        let plans = SubscriptionService.assemble(live: [
            plan(.annual, id: "annual", price: 29.99, localized: "$29.99"),
            plan(.monthly, id: "monthly", price: 4.99, localized: "$4.99"),
        ])
        let annual = try? XCTUnwrap(plans.first)
        XCTAssertNotNil(annual?.monthlyEquivalent)
        XCTAssertTrue(annual?.monthlyEquivalent?.contains("mo") ?? false)
        XCTAssertEqual(annual?.savings, "Save 50%")
    }

    func testMonthlyHasNoDerivedEquivalentOrSavings() {
        let plans = SubscriptionService.assemble(live: [
            plan(.monthly, id: "monthly", price: 4.99, localized: "$4.99"),
        ])
        XCTAssertEqual(plans.count, 1)
        XCTAssertNil(plans.first?.monthlyEquivalent)
        XCTAssertNil(plans.first?.savings)
        XCTAssertFalse(plans.first?.isRecommended ?? true)
    }

    func testWeeklyIsIgnored() {
        let plans = SubscriptionService.assemble(live: [
            plan(.weekly, id: "weekly", price: 1.99, localized: "$1.99"),
        ])
        XCTAssertTrue(plans.isEmpty)
    }

    // MARK: restore-result mapping

    @MainActor
    func testRestoreMapsToRestoredWhenVerdictPro() async {
        let service = makeService(backend: FakeBacking(verdict: .pro))
        let result = await service.restore()
        XCTAssertEqual(result, .restored)
        XCTAssertTrue(service.isPro)
    }

    @MainActor
    func testRestoreMapsToNothingToRestoreWhenVerdictFree() async {
        let service = makeService(backend: FakeBacking(verdict: .free))
        let result = await service.restore()
        XCTAssertEqual(result, .nothingToRestore)
        XCTAssertFalse(service.isPro)
    }

    @MainActor
    func testRestoreMapsToFailedWhenBackendThrows() async {
        let service = makeService(backend: FakeBacking(verdict: .free, restoreThrows: true))
        let result = await service.restore()
        XCTAssertEqual(result, .failed)
    }

    @MainActor
    func testInconclusiveVerdictKeepsLastKnownPro() async {
        let store = ProEntitlementStore(suiteName: freshSuite())
        store.record(true)
        let service = SubscriptionService(backend: FakeBacking(verdict: .unknown), entitlementStore: store)
        XCTAssertTrue(service.isPro)
        await service.refreshEntitlement()
        XCTAssertTrue(service.isPro)
    }

    // MARK: helpers

    @MainActor
    private func makeService(backend: FakeBacking) -> SubscriptionService {
        SubscriptionService(backend: backend, entitlementStore: ProEntitlementStore(suiteName: freshSuite()))
    }

    private func freshSuite() -> String { "paywall-tests-\(UUID().uuidString)" }
}

private struct FakeBacking: SubscriptionBacking {
    let verdict: ProVerdict
    var restoreThrows = false

    func proVerdict() async -> ProVerdict { verdict }
    func subscriptionPlans() async throws -> [SubscriptionPlan] { [] }
    func purchaseSubscription(_ plan: SubscriptionPlan) async throws {}
    func restoreEntitlements() async throws {
        if restoreThrows { throw AICreditsError.transport("offline") }
    }
}
