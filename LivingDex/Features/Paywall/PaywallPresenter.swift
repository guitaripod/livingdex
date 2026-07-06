import UIKit

/// Presents the Living Dex Pro paywall. The paywall never blocks the free core (on-device
/// identification and narration), so it is always a dismissible sheet — surfaced from the
/// Profile "Cloud IDs" row and from the credits-exhausted capture path.
@MainActor
enum PaywallPresenter {
    /// Presents the paywall as a page sheet. No-op when the user is already Pro (the
    /// caller should instead reflect the active entitlement).
    static func present(
        from presenter: UIViewController,
        service: SubscriptionService = .shared,
        reason: String = "Identify without limits, anywhere life turns up."
    ) {
        guard !service.isPro else { return }
        let paywall = PaywallViewController(service: service, reason: reason)
        let nav = UINavigationController(rootViewController: paywall)
        nav.navigationBar.tintColor = DesignSystem.Color.accent
        nav.modalPresentationStyle = .pageSheet
        presenter.present(nav, animated: true)
    }
}
