import Foundation
import LivingDexCore

/// How many more credits an action needs than the wallet holds, which the credit store shows as its banner.
nonisolated enum CreditShortfall {
    /// What mako's 402 reports as required and available, at least 1, and 1 when it reports no numbers: an
    /// identification costs a credit, so something is missing whenever mako refuses one.
    static func of(required: Int?, available: Int?) -> Int {
        guard let required, let available else {
            return 1
        }
        return max(required - available, 1)
    }
}

extension IdentifyError {
    /// How many more credits the refused identification needed, or nil when the failure was not for want of credits.
    var creditShortfall: Int? {
        if case .creditsExhausted(let shortfall) = self {
            return shortfall
        }
        return nil
    }
}
