#if DEBUG
import UIKit

/// DEBUG-only routes beyond the first-screen ones in `DemoSeeder`: Field Guide,
/// Settings (the guide also scrolled to its realm cards), the cloud consent sheet, Dex search, and a chosen species' card.
/// `LIVINGDEX_DEMO_SPECIES` names the species the `card` route opens (by common
/// name) and `LIVINGDEX_DEMO_QUERY` is the text the `search` route types.
extension DemoSeeder {
    private static let tabForRoute: [String: Int] = ["consent": 0, "search": 1, "guide": 2, "guide-realms": 2, "settings": 2]

    private static let defaultSearchQuery = "bl"

    /// Helsinki, so Nearby and the sighting tags are the same on every launch and need no fix.
    static var demoContext: CaptureContext? {
        isEnabled ? CaptureContext(latitude: 60.1699, longitude: 24.9384, elevationMeters: 12) : nil
    }

    static var showsFieldBackdrop: Bool {
        route == "field" || route == "consent"
    }

    static var searchQuery: String? {
        route == "search" ? (ProcessInfo.processInfo.environment["LIVINGDEX_DEMO_QUERY"] ?? defaultSearchQuery) : nil
    }

    /// The entry the `card` route opens: the species named in the environment when it
    /// was caught, else the most recent catch.
    static func cardEntry(in caught: [DexEntry]) -> DexEntry? {
        let name = ProcessInfo.processInfo.environment["LIVINGDEX_DEMO_SPECIES"]
        return caught.first { $0.commonName == name } ?? caught.first
    }

    /// Opens the screen a non-tab route asks for, once the tab shell is on screen.
    @MainActor
    static func openRoute(on root: UITabBarController) {
        if let index = tabForRoute[route] { root.selectedIndex = index }
        switch route {
        case "guide": push(FieldGuideViewController(), on: root)
        case "guide-realms":
            let guide = FieldGuideViewController()
            push(guide, on: root)
            guide.scrollToRealms()
        case "settings": push(SettingsViewController(), on: root)
        case "consent":
            guard let field = root.viewControllers?.first else { return }
            CloudConsent.request(from: field) { _ in }
        default: break
        }
    }

    @MainActor
    private static func push(_ screen: UIViewController, on root: UITabBarController) {
        guard let profile = root.viewControllers?[2] as? UINavigationController else { return }
        profile.pushViewController(screen, animated: false)
    }
}
#endif
