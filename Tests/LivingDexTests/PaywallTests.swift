import XCTest
@testable import LivingDex

final class PaywallTests: XCTestCase {

    private func quote(
        _ product: ProProduct, price: Decimal, displayPrice: String, trialDays: Int? = nil
    ) -> ProPlanQuote {
        ProPlanQuote(product: product, displayPrice: displayPrice, price: price, currencyCode: "USD", trialDays: trialDays)
    }

    func testAssembleIsAnnualFirst() {
        let plans = PaywallPlan.assemble(from: [
            quote(.monthly, price: 4.99, displayPrice: "$4.99"),
            quote(.annual, price: 29.99, displayPrice: "$29.99"),
        ])
        XCTAssertEqual(plans.map(\.billing), [.annual, .monthly])
        XCTAssertEqual(plans.map(\.product), [.annual, .monthly])
        XCTAssertEqual(plans.first?.displayPrice, "$29.99")
    }

    func testAnnualDerivesMonthlyEquivalentAndSavings() {
        let plans = PaywallPlan.assemble(from: [
            quote(.annual, price: 29.99, displayPrice: "$29.99"),
            quote(.monthly, price: 4.99, displayPrice: "$4.99"),
        ])
        let annual = try? XCTUnwrap(plans.first)
        XCTAssertNotNil(annual?.monthlyEquivalent)
        XCTAssertTrue(annual?.monthlyEquivalent?.contains("mo") ?? false)
        XCTAssertEqual(annual?.savings, "Save 50%")
    }

    func testMonthlyHasNoDerivedEquivalentOrSavings() {
        let plans = PaywallPlan.assemble(from: [quote(.monthly, price: 4.99, displayPrice: "$4.99")])
        XCTAssertEqual(plans.count, 1)
        XCTAssertNil(plans.first?.monthlyEquivalent)
        XCTAssertNil(plans.first?.savings)
        XCTAssertFalse(plans.first?.isRecommended ?? true)
    }

    func testNoQuotesMeanNoPlans() {
        XCTAssertTrue(PaywallPlan.assemble(from: []).isEmpty)
    }

    func testATrialShowsOnlyWhenTheCustomerMayUseOne() {
        let eligible = PaywallPlan.assemble(from: [quote(.annual, price: 29.99, displayPrice: "$29.99", trialDays: 3)])
        let used = PaywallPlan.assemble(from: [quote(.annual, price: 29.99, displayPrice: "$29.99", trialDays: nil)])
        let empty = PaywallPlan.assemble(from: [quote(.annual, price: 29.99, displayPrice: "$29.99", trialDays: 0)])
        XCTAssertEqual(eligible.first?.trialDays, 3)
        XCTAssertNil(used.first?.trialDays)
        XCTAssertNil(empty.first?.trialDays)
    }

    func testThePlanIdIsTheStoreKitProductId() {
        let plans = PaywallPlan.assemble(from: [
            quote(.annual, price: 29.99, displayPrice: "$29.99"),
            quote(.monthly, price: 4.99, displayPrice: "$4.99"),
        ])
        XCTAssertEqual(
            plans.map(\.id),
            ["com.guitaripod.livingdex.pro.annual", "com.guitaripod.livingdex.pro.monthly"])
    }
}
