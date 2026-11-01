import MidgarCommerce
import UIKit

/// When a revealed catch offers Living Dex Pro, through the shared ``MidgarOfferPolicy``: after the tenth catch, a third
/// of the way through the free identifications, then after every seventh and at least three days apart, three times in
/// all, never to a Pro player.
@MainActor
enum CatchOffer {
    static let policy = MidgarOfferPolicy(appID: LivingDexMidgar.appID, firstOfferAfter: 10, laterOfferEvery: 7)

    /// Counts a catch the player just closed and offers Pro over `host` when the policy says it is the moment.
    static func offerIfDue(over host: UIViewController) {
        guard policy.noteValue(isOwned: ProAccess.shared.isPro) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard host.presentedViewController == nil, host.view.window != nil else { return }
            policy.noteOffered()
            PaywallPresenter.present(
                from: host, reason: "Your Dex is growing. Pro keeps you identifying without limits, anywhere life turns up.")
        }
    }
}
