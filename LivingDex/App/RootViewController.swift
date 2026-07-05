import UIKit

/// The app's tab shell. The Field (camera-first capture) tab is the default —
/// the app opens ready to catch. Bar backgrounds are left default so iOS 26
/// keeps its Liquid Glass.
final class RootViewController: UITabBarController {
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.tintColor = DesignSystem.Color.accent

        let field = FieldViewController()
        field.tabBarItem = UITabBarItem(
            title: "Field", image: UIImage(systemName: "camera.viewfinder"), selectedImage: nil)

        viewControllers = [
            field,
            wrap(DexViewController(), title: "Dex", symbol: "square.grid.2x2.fill"),
            wrap(ProfileViewController(), title: "Profile", symbol: "person.crop.circle.fill"),
        ]
    }

    private func wrap(_ vc: UIViewController, title: String, symbol: String) -> UINavigationController {
        vc.title = title
        vc.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
}
