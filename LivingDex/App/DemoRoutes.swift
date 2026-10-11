#if DEBUG
import UIKit

/// DEBUG-only routes beyond the first-screen ones in `DemoSeeder`: Field Guide,
/// Settings (the guide also scrolled to its realm cards), the cloud consent sheet, Dex search, a chosen species' card,
/// and the shareable trading cards written to Documents/sharecards for the store artwork.
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
        case "sharecards": exportShareCards()
        case "consent":
            guard let field = root.viewControllers?.first else { return }
            CloudConsent.request(from: field) { _ in }
        default: break
        }
    }

    /// Renders a trading card for every demo species into `Documents/sharecards/<speciesId>.png`.
    @MainActor
    private static func exportShareCards() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("sharecards", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, sample) in samples.enumerated() {
            guard let photo = photo(for: sample) else { continue }
            let model = ShareCardModel(
                commonName: sample.common, scientificName: sample.scientific, realm: sample.realm,
                rarity: sample.rarity, caughtAt: Date().addingTimeInterval(-Double(index) * 3600), photo: photo)
            let name = sample.common.lowercased().replacingOccurrences(of: " ", with: "-")
            try? ShareCardRenderer.render(model).pngData()?.write(to: folder.appendingPathComponent("\(name).png"))
        }
        AppLogger.shared.info("demo share cards exported", category: .app)
    }

    @MainActor
    private static func push(_ screen: UIViewController, on root: UITabBarController) {
        guard let profile = root.viewControllers?[2] as? UINavigationController else { return }
        profile.pushViewController(screen, animated: false)
    }
}
#endif
