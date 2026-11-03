import MidgarCore
import UIKit

/// Presents the Living Dex Pro paywall. The paywall never blocks the free Dex, so it is
/// always a dismissible sheet — surfaced from the Profile "Identifications" row, the Field
/// credits meter, the credits-exhausted capture path, a growing Dex and the end of the first run.
@MainActor
enum PaywallPresenter {
    /// Why the paywall is up when nothing more specific called it.
    static let defaultReason = String(localized: "For walks where every hedge hides something new.")

    /// Presents the paywall as a page sheet in the dark look of the first run. No-op when the user is already Pro
    /// (the caller should instead reflect the active entitlement), and then `onDismiss` is not called.
    @discardableResult
    static func present(
        from presenter: UIViewController,
        access: ProAccess = .shared,
        reason: String = defaultReason,
        shortfall: Int? = nil,
        fixedPlans: [PaywallPlan]? = nil,
        placement: MidgarSignal.Placement = .feature,
        onDismiss: (@MainActor () -> Void)? = nil
    ) -> Bool {
        guard !access.isPro else { return false }
        let paywall = PaywallViewController(
            access: access, reason: reason, shortfall: shortfall, fixedPlans: fixedPlans, placement: placement)
        paywall.onDidDismiss = onDismiss
        let nav = UINavigationController(rootViewController: paywall)
        nav.overrideUserInterfaceStyle = .dark
        nav.navigationBar.tintColor = .white
        nav.modalPresentationStyle = .pageSheet
        presenter.present(nav, animated: true)
        return true
    }
}

/// The one paywall a new player sees without asking for it: as the first run hands over to the Field, with the
/// starter in the Dex and the camera not yet asked for. The Field holds its camera prompt until the offer closes,
/// so the system alert never lands on top of it.
@MainActor
enum WelcomeOffer {
    private static var waiting: [@MainActor () -> Void]?

    /// Marks the offer as coming. Call before the Field is put on screen.
    static func hold() {
        waiting = waiting ?? []
    }

    /// Presents the offer over `root`, or lets the Field go on at once when it cannot be shown (Pro already, or
    /// another screen in the way).
    static func present(over root: UIViewController) {
        guard waiting != nil else { return }
        guard root.presentedViewController == nil, PaywallPresenter.present(
            from: root, reason: String(localized: "Your Dex is ready. Pro lets you fill it as fast as you find things."),
            placement: .onboarding, onDismiss: { release() })
        else {
            release()
            return
        }
    }

    /// Runs `action` now, or once the offer has closed when it is coming or up.
    static func afterOffer(_ action: @escaping @MainActor () -> Void) {
        guard waiting != nil else {
            action()
            return
        }
        waiting?.append(action)
    }

    private static func release() {
        let actions = waiting ?? []
        waiting = nil
        actions.forEach { $0() }
    }
}
