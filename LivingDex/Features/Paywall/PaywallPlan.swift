import Foundation
import AICreditsCore

/// One purchasable Living Dex Pro plan as the paywall renders it. The billed price stays
/// the dominant line; the monthly-equivalent and the savings badge are derived for the
/// annual so it reads as the obvious value. Built only from a live RevenueCat
/// ``SubscriptionPlan`` — every figure is store-sourced and localized. Until real prices
/// resolve the paywall shows ``PaywallPlansState/loading`` or
/// ``PaywallPlansState/unavailable``; a fabricated price, savings percentage, or trial
/// claim never renders (Guideline 3.1.2).
nonisolated struct PaywallPlan: Sendable, Equatable, Identifiable {
    enum Billing: String, Sendable {
        case annual
        case monthly
    }

    /// The RevenueCat package identifier to purchase.
    let id: String
    let productID: String
    let billing: Billing
    /// The localized, store-sourced price. This is the figure that dominates the card.
    let displayPrice: String
    /// The trial length in days, surfaced only when the user is trial-eligible.
    let trialDays: Int?
    /// The derived "≈ $X.XX / mo" line for the annual; `nil` for monthly.
    let monthlyEquivalent: String?
    /// The derived "Save N%" badge for the annual vs. monthly; `nil` otherwise.
    let savings: String?

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

/// The RevenueCat entitlement that unlocks Living Dex Pro (unlimited Claude cloud
/// identifications + the future "ask the creature" Q&A). The backend re-verifies it on
/// every metered request; the client value only drives UI gating.
enum LivingDexPro {
    static let entitlement = "pro"
}

extension PaywallPlan {
    /// Lifts a live RevenueCat ``SubscriptionPlan`` into the paywall's display model,
    /// deriving the annual monthly-equivalent and savings from the real localized prices
    /// (so the figures stay honest and currency-correct, never hardcoded).
    static func live(
        from plan: SubscriptionPlan, monthlyReference: SubscriptionPlan?
    ) -> PaywallPlan {
        let billing: Billing = plan.period == .annual ? .annual : .monthly
        return PaywallPlan(
            id: plan.id,
            productID: plan.productID,
            billing: billing,
            displayPrice: plan.localizedPrice,
            trialDays: (plan.trialEligible && (plan.trialDays ?? 0) > 0) ? plan.trialDays : nil,
            monthlyEquivalent: billing == .annual ? monthlyEquivalentText(for: plan) : nil,
            savings: billing == .annual ? savingsText(annual: plan, monthly: monthlyReference) : nil)
    }

    private static func monthlyEquivalentText(for annual: SubscriptionPlan) -> String? {
        let perMonth = (annual.price as NSDecimalNumber).doubleValue / 12.0
        guard perMonth > 0 else { return nil }
        let formatter = currencyFormatter(for: annual.currencyCode)
        guard let formatted = formatter.string(from: NSNumber(value: perMonth)) else { return nil }
        return "≈ \(formatted) / mo"
    }

    private static func savingsText(annual: SubscriptionPlan, monthly: SubscriptionPlan?) -> String? {
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
