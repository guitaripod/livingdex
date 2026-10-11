import UIKit
import AICreditsCore
import AICreditsUI

/// App settings: appearance, privacy, purchases, diagnostics, legal, and account
/// deletion. Opened from the Profile tab. Deliberately small — the game lives in
/// the other tabs.
final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Row {
        case appearance
        case cloudToggle
        case action(title: String, symbol: String, tint: UIColor, destructive: Bool, handler: () -> Void)
        case link(title: String, symbol: String, url: URL)
        case push(title: String, symbol: String, make: () -> UIViewController)
        case info(title: String, value: String)
    }
    private struct Section { let header: String?; let footer: String?; let rows: [Row] }
    private var sections: [Section] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemGroupedBackground
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        build()
    }

    private func build() {
        sections = [
            Section(header: "Appearance", footer: nil, rows: [.appearance]),
            Section(
                header: "Privacy",
                footer: "Your photo goes to a cloud AI service only when you identify something. Turn this off and Living Dex asks again before the next identification.",
                rows: [.cloudToggle]),
            Section(header: "Purchases", footer: "Every device starts with 30 free identifications.", rows: [
                .action(title: "Restore purchases", symbol: "arrow.clockwise", tint: DesignSystem.Color.accent, destructive: false) { [weak self] in
                    self?.restorePurchases()
                },
            ]),
            Section(header: "Diagnostics", footer: nil, rows: [
                .action(title: "Export logs", symbol: "square.and.arrow.up", tint: DesignSystem.Color.accent, destructive: false) { [weak self] in
                    self?.exportLogs()
                },
            ]),
            Section(header: "Legal", footer: nil, rows: [
                .link(title: "Privacy Policy", symbol: "hand.raised.fill", url: LegalLinks.privacy),
                .link(title: "Terms of Use", symbol: "doc.text.fill", url: LegalLinks.terms),
                .link(title: "Support", symbol: "questionmark.circle.fill", url: LegalLinks.support),
                .push(title: "Credits", symbol: "heart.text.square.fill") { CreditsViewController() },
            ]),
            Section(
                header: "Account",
                footer: "Permanently deletes your Dex, photos, progress and Living Dex account. An App Store subscription is managed separately in iOS Settings.",
                rows: [
                    .action(title: "Delete Account & Data", symbol: "trash.fill", tint: .systemRed, destructive: true) { [weak self] in
                        self?.confirmDeletion()
                    },
                ]),
            Section(header: "About", footer: nil, rows: [.info(title: "Version", value: Self.appVersion)]),
        ]
    }

    private static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].header }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        var content = cell.defaultContentConfiguration()

        switch sections[indexPath.section].rows[indexPath.row] {
        case .appearance:
            content.text = "Theme"
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            let control = UISegmentedControl(items: ["System", "Light", "Dark"])
            control.selectedSegmentIndex = Self.segmentIndex(for: AppSettings.appearance)
            control.addAction(UIAction { action in
                let styles: [UIUserInterfaceStyle] = [.unspecified, .light, .dark]
                AppSettings.appearance = styles[(action.sender as? UISegmentedControl)?.selectedSegmentIndex ?? 0]
            }, for: .valueChanged)
            control.sizeToFit()
            cell.accessoryView = control
        case .cloudToggle:
            content.text = "Cloud identification"
            content.image = UIImage(systemName: "sparkle.magnifyingglass")
            content.imageProperties.tintColor = DesignSystem.Color.accent
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.onTintColor = DesignSystem.Color.accent
            toggle.isOn = AppSettings.hasAcceptedCloudAI
            toggle.addAction(UIAction { action in
                AppSettings.hasAcceptedCloudAI = (action.sender as? UISwitch)?.isOn ?? false
            }, for: .valueChanged)
            toggle.accessibilityLabel = "Cloud identification"
            cell.accessoryView = toggle
        case let .action(title, symbol, tint, destructive, _):
            content.text = title
            content.textProperties.color = destructive ? .systemRed : .label
            content.image = UIImage(systemName: symbol)
            content.imageProperties.tintColor = tint
            cell.contentConfiguration = content
        case let .link(title, symbol, _):
            content.text = title
            content.image = UIImage(systemName: symbol)
            content.imageProperties.tintColor = .secondaryLabel
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
        case let .push(title, symbol, _):
            content.text = title
            content.image = UIImage(systemName: symbol)
            content.imageProperties.tintColor = .secondaryLabel
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
        case let .info(title, value):
            var v = UIListContentConfiguration.valueCell()
            v.text = title
            v.secondaryText = value
            cell.contentConfiguration = v
            cell.selectionStyle = .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case let .action(_, _, _, _, handler): handler()
        case let .link(_, _, url): UIApplication.shared.open(url)
        case let .push(_, _, make): navigationController?.pushViewController(make(), animated: true)
        default: break
        }
    }

    private static func segmentIndex(for style: UIUserInterfaceStyle) -> Int {
        switch style {
        case .light: return 1
        case .dark: return 2
        default: return 0
        }
    }

    // MARK: Actions

    /// Routes through the single ``SubscriptionService/restore()`` path so the Pro gate
    /// updates everywhere, and distinguishes a genuine empty restore from a failed call —
    /// a paying subscriber is never told there was nothing to restore because the App Store
    /// was simply unreachable. The credit balance is refreshed alongside so a restored
    /// consumable purchase (packs) also reflects immediately.
    private func restorePurchases() {
        Task { @MainActor in
            let result = await SubscriptionService.shared.restore()
            await AICreditsManager.store.refresh()
            switch result {
            case .restored:
                presentAlert(
                    title: "Restore complete",
                    message: "Your Living Dex Pro subscription has been restored.")
            case .nothingToRestore:
                presentAlert(
                    title: "No purchases found",
                    message: "There were no previous purchases to restore for this Apple ID.")
            case .failed:
                presentAlert(
                    title: "Restore failed",
                    message: "We couldn't restore your purchases. Check your connection and try again.")
            }
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func exportLogs() {
        guard let logs = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Logs/livingdex.log"),
            FileManager.default.fileExists(atPath: logs.path) else {
            presentAlert(title: "No logs yet", message: "Diagnostics appear here after you use the app.")
            return
        }
        let share = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
            let cell = tableView.indexPathForSelectedRow.flatMap { tableView.cellForRow(at: $0) }
            popover.sourceView = cell ?? view
            popover.sourceRect = (cell ?? view).bounds
        }
        present(share, animated: true)
    }

    /// Asks before the irreversible step, and says plainly what goes and what stays.
    private func confirmDeletion() {
        let alert = UIAlertController(
            title: "Delete account and data?",
            message: "This permanently deletes your Dex, photos, progress, credits and your Living Dex account on our server. It can't be undone.\n\nAn App Store subscription is not cancelled by this — manage it in iOS Settings › Apple ID › Subscriptions.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Delete Everything", style: .destructive) { [weak self] _ in
            self?.performDeletion()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func performDeletion() {
        let overlay = BusyOverlay(message: "Deleting…")
        overlay.show(in: view.window ?? view)
        Task { @MainActor in
            do {
                try await AccountDeletionService.live().deleteEverything()
                AppSettings.reset()
                AppLogger.shared.info("account deleted", category: .app)
                Haptics.tap()
                overlay.hide()
                await AICreditsManager.store.bootstrap()
                (view.window?.windowScene?.delegate as? SceneDelegate)?.presentFirstRun()
            } catch {
                overlay.hide()
                Haptics.failure()
                AppLogger.shared.error("account deletion failed: \(error)", category: .app)
                let offline = (error as? AccountDeletionError) == .offline
                presentAlert(
                    title: "Couldn't delete your account",
                    message: offline
                        ? "You appear to be offline. Nothing was deleted — reconnect and try again."
                        : "Something went wrong on our side. Nothing was deleted — try again in a moment.")
            }
        }
    }
}

/// A dimmed, input-blocking overlay with a spinner and a short message — for the few
/// seconds an irreversible operation runs.
final class BusyOverlay: UIView {
    init(message: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        accessibilityViewIsModal = true

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()

        let label = UILabel()
        label.text = message
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .white
        label.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = DesignSystem.Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(in host: UIView) {
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        alpha = 0
        host.addSubview(self)
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
    }

    func hide() {
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
    }
}
