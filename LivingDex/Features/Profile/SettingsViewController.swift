import MidgarPortal
import MidgarUI
import UIKit

/// Settings: the Midgar portal card on top of MidgarUI's settings list with Living Dex's sections, hosted as a child
/// so the screen keeps pushing onto the Profile tab's navigation stack. Opened from the Profile tab. Deliberately
/// small, because the game lives in the other tabs: appearance, privacy, purchases, diagnostics, legal and account
/// deletion.
///
/// Rows read their values when built, so a change is shown by building them again with ``refreshList()``.
final class SettingsViewController: UIViewController {
    private lazy var list = MidgarSettingsViewController(
        title: "Settings",
        sections: makeSections(),
        portalCardView: MidgarEntryView(config: LivingDexMidgar.shared.portalConfig),
        theme: .livingDex
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemGroupedBackground
        embedList()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshList()
    }

    /// Builds every row again from the current state.
    func refreshList() {
        list.sections = makeSections()
    }

    private func embedList() {
        addChild(list)
        list.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(list.view)
        NSLayoutConstraint.activate([
            list.view.topAnchor.constraint(equalTo: view.topAnchor),
            list.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            list.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        list.didMove(toParent: self)
    }
}
