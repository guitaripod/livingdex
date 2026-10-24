import Foundation
import MidgarCommerce

/// One purchasable Living Dex Pro plan as the paywall renders it. The billed price stays
/// the dominant line; the monthly-equivalent and the savings badge are derived for the
/// annual so it reads as the obvious value. Built only from a live StoreKit product
/// (``ProPlanQuote``) — every figure is store-sourced and localized. Until real prices
/// resolve the paywall shows ``PaywallPlansState/loading`` or
/// ``PaywallPlansState/unavailable``; a fabricated price, savings percentage, or trial
/// claim never renders (Guideline 3.1.2).
nonisolated struct PaywallPlan: Sendable, Equatable, Identifiable {
    enum Billing: String, Sendable {
        case annual
        case monthly
    }

    /// The StoreKit product to purchase.
    let product: ProProduct
    let billing: Billing
    /// The localized, store-sourced price. This is the figure that dominates the card.
    let displayPrice: String
    /// The trial length in days, surfaced only when the user is trial-eligible.
    let trialDays: Int?
    /// The derived "≈ $X.XX / mo" line for the annual; `nil` for monthly.
    let monthlyEquivalent: String?
    /// The derived "Save N%" badge for the annual vs. monthly; `nil` otherwise.
    let savings: String?

    var id: String { product.rawValue }

    /// Whether this is the plan Living Dex recommends (the annual). Drives the "Best
    /// value" ribbon and the default selection so the value read is unambiguous.
    var isRecommended: Bool { billing == .annual }

    var headline: String {
        switch billing {
        case .annual: return "Annual"
        case .monthly: return "Monthly"
        }
    }

    var cadenceCaption: String {
        switch billing {
        case .annual: return "per year"
        case .monthly: return "per month"
        }
    }
}

/// The paywall's plan-list state. Prices come only from the store: until live offerings
/// resolve the paywall shows unpriced skeleton rows, and when they cannot be loaded it
/// says so plainly and offers a retry — it never falls back to hardcoded prices.
nonisolated enum PaywallPlansState: Sendable, Equatable {
    case loading
    case loaded([PaywallPlan])
    case unavailable
}

/// What the paywall does with the result of a purchase. A cancel does nothing at all, and a purchase that went through
/// needs nothing either: Pro unlocking is what dismisses the paywall. Only Ask to Buy says something, because the
/// purchase waits for approval and unlocks Pro by itself once it is approved.
nonisolated enum PaywallPurchaseEffect: Equatable {
    case waitForApproval
    case nothing

    static func of(_ result: MidgarPurchaseResult) -> PaywallPurchaseEffect {
        switch result {
        case .pending:
            return .waitForApproval
        case .purchased, .cancelled:
            return .nothing
        @unknown default:
            return .nothing
        }
    }
}

/// What StoreKit reports for one Pro plan in the customer's storefront, with the free trial this customer may still
/// use: the figures a ``PaywallPlan`` is derived from. Nothing here is a price or a trial length of ours.
nonisolated struct ProPlanQuote: Sendable, Equatable {
    let product: ProProduct
    let displayPrice: String
    let price: Decimal
    let currencyCode: String?
    let trialDays: Int?

    init(product: ProProduct, displayPrice: String, price: Decimal, currencyCode: String?, trialDays: Int?) {
        self.product = product
        self.displayPrice = displayPrice
        self.price = price
        self.currencyCode = currencyCode
        self.trialDays = trialDays
    }

    /// The quote for a StoreKit product, with the trial StoreKit says this customer may use, if any.
    init(product: ProProduct, storeProduct: StoreProduct, trial: MidgarTrialPresentation?) {
        self.init(
            product: product,
            displayPrice: storeProduct.displayPrice,
            price: storeProduct.price,
            currencyCode: storeProduct.currencyCode,
            trialDays: trial.flatMap(Self.freeTrialDays(of:)))
    }

    /// The length of a free trial in days, with a week counted as 7, a month as 30 and a year as 365. A paid
    /// introductory offer is not a trial.
    static func freeTrialDays(of presentation: MidgarTrialPresentation) -> Int? {
        guard presentation.isFreeTrial else { return nil }
        let total = presentation.offer.totalDuration
        switch total.unit {
        case .day: return total.value
        case .week: return total.value * 7
        case .month: return total.value * 30
        case .year: return total.value * 365
        }
    }
}

extension PaywallPlan {
    /// Lifts the quotes into the paywall's display models, annual first, so the recommended value reads first. Other
    /// products (should the store ever carry them) are ignored: Living Dex Pro is a monthly and an annual plan.
    static func assemble(from quotes: [ProPlanQuote]) -> [PaywallPlan] {
        let annual = quotes.first { $0.product == .annual }
        let monthly = quotes.first { $0.product == .monthly }
        var plans: [PaywallPlan] = []
        if let annual { plans.append(.live(from: annual, monthlyReference: monthly)) }
        if let monthly { plans.append(.live(from: monthly, monthlyReference: nil)) }
        return plans
    }

    /// Lifts a quote into the paywall's display model, deriving the annual monthly-equivalent and savings from the
    /// real localized prices (so the figures stay honest and currency-correct, never hardcoded).
    static func live(from quote: ProPlanQuote, monthlyReference: ProPlanQuote?) -> PaywallPlan {
        let billing: Billing = quote.product == .annual ? .annual : .monthly
        return PaywallPlan(
            product: quote.product,
            billing: billing,
            displayPrice: quote.displayPrice,
            trialDays: (quote.trialDays ?? 0) > 0 ? quote.trialDays : nil,
            monthlyEquivalent: billing == .annual ? monthlyEquivalentText(for: quote) : nil,
            savings: billing == .annual ? savingsText(annual: quote, monthly: monthlyReference) : nil)
    }

    private static func monthlyEquivalentText(for annual: ProPlanQuote) -> String? {
        let perMonth = (annual.price as NSDecimalNumber).doubleValue / 12.0
        guard perMonth > 0 else { return nil }
        let formatter = currencyFormatter(for: annual.currencyCode)
        guard let formatted = formatter.string(from: NSNumber(value: perMonth)) else { return nil }
        return "≈ \(formatted) / mo"
    }

    private static func savingsText(annual: ProPlanQuote, monthly: ProPlanQuote?) -> String? {
        guard let monthly else { return nil }
        let annualValue = (annual.price as NSDecimalNumber).doubleValue
        let monthlyYear = (monthly.price as NSDecimalNumber).doubleValue * 12.0
        guard monthlyYear > 0, annualValue > 0, annualValue < monthlyYear else { return nil }
        let percent = Int(((monthlyYear - annualValue) / monthlyYear * 100).rounded())
        guard percent > 0 else { return nil }
        return "Save \(percent)%"
    }

    private static func currencyFormatter(for code: String?) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        if let code { formatter.currencyCode = code }
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
