import UIKit

/// Presents the Living Dex Pro paywall. The paywall never blocks the free Dex, so it is
/// always a dismissible sheet — surfaced from the Profile "Identifications" row, the Field
/// credits meter, and the credits-exhausted capture path.
@MainActor
enum PaywallPresenter {
    /// Presents the paywall as a page sheet. No-op when the user is already Pro (the
    /// caller should instead reflect the active entitlement).
    static func present(
        from presenter: UIViewController,
        access: ProAccess = .shared,
        reason: String = "Identify without limits, anywhere life turns up.",
        shortfall: Int? = nil,
        fixedPlans: [PaywallPlan]? = nil
    ) {
        guard !access.isPro else { return }
        let paywall = PaywallViewController(
            access: access, reason: reason, shortfall: shortfall, fixedPlans: fixedPlans)
        let nav = UINavigationController(rootViewController: paywall)
        nav.navigationBar.tintColor = DesignSystem.Color.accent
        nav.modalPresentationStyle = .pageSheet
        presenter.present(nav, animated: true)
    }
}
