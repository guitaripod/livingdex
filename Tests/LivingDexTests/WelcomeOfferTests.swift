import XCTest
@testable import LivingDex

@MainActor
final class WelcomeOfferTests: XCTestCase {
    func testTheFieldGoesOnAtOnceWhenNoOfferIsComing() {
        var ran = false
        WelcomeOffer.afterOffer { ran = true }
        XCTAssertTrue(ran)
    }

    func testTheFieldWaitsForTheOfferAndGoesOnWhenItCannotBeShown() {
        let root = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.present(UIViewController(), animated: false)

        WelcomeOffer.hold()
        var ran = false
        WelcomeOffer.afterOffer { ran = true }
        XCTAssertFalse(ran)

        WelcomeOffer.present(over: root)
        XCTAssertTrue(ran)
        XCTAssertFalse(root.presentedViewController is UINavigationController)
    }

    func testTheOfferIsTheProPaywallInTheOnboardingPlacement() {
        let root = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = root
        window.makeKeyAndVisible()

        WelcomeOffer.hold()
        var ran = false
        WelcomeOffer.afterOffer { ran = true }
        WelcomeOffer.present(over: root)

        let paywall = (root.presentedViewController as? UINavigationController)?.viewControllers.first
        XCTAssertTrue(paywall is PaywallViewController)
        XCTAssertFalse(ran)
        (paywall as? PaywallViewController)?.onDidDismiss?()
        XCTAssertTrue(ran)
        WelcomeOffer.afterOffer { ran = false }
        XCTAssertFalse(ran)
    }
}
