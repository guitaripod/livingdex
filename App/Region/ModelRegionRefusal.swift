import AICreditsCore
import Foundation
import MidgarCore

/// Remembers a model call's refusal for the caller's country, whichever client made the call, so the app stops offering
/// model features there. The refusal spends nothing and is never retried.
enum ModelRegionRefusal {
    /// Records `error` when it is that refusal, from a MidgarHTTPClient call or an AICredits call to mako, and returns
    /// true when it was. Any other error is left alone.
    @discardableResult
    static func record(_ error: any Error) -> Bool {
        if let aiError = error as? AICreditsError, aiError.isUnavailableInRegion {
            return MidgarModelRegion.shared.note(statusCode: MidgarModelRegion.refusalStatus)
        }
        return MidgarModelRegion.shared.note(error)
    }
}
