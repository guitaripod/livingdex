import UIKit
import AICreditsUI

/// App settings: appearance, purchases, diagnostics, and legal. Opened from the
/// Profile tab. Deliberately small — the game lives in the other tabs.
final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Row {
        case appearance
        case action(title: String, symbol: String, tint: UIColor, handler: () -> Void)
        case link(title: String, symbol: String, url: URL)
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
            Section(header: "Purchases", footer: "Basic identification is free forever.", rows: [
                .action(title: "Restore purchases", symbol: "arrow.clockwise", tint: DesignSystem.Color.accent) { [weak self] in
                    self?.restorePurchases()
                },
            ]),
            Section(header: "Diagnostics", footer: nil, rows: [
                .action(title: "Export logs", symbol: "square.and.arrow.up", tint: DesignSystem.Color.accent) { [weak self] in
                    self?.exportLogs()
                },
            ]),
            Section(header: "Legal", footer: nil, rows: [
                .link(title: "Privacy Policy", symbol: "hand.raised.fill", url: URL(string: "https://mako.midgarcorp.cc/privacy/livingdex")!),
                .link(title: "Terms of Use", symbol: "doc.text.fill", url: URL(string: "https://mako.midgarcorp.cc/terms/livingdex")!),
                .link(title: "Support", symbol: "questionmark.circle.fill", url: URL(string: "https://mako.midgarcorp.cc/support/livingdex")!),
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
        case let .action(title, symbol, tint, _):
            content.text = title
            content.image = UIImage(systemName: symbol)
            content.imageProperties.tintColor = tint
            cell.contentConfiguration = content
        case let .link(title, symbol, _):
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
        case let .action(_, _, _, handler): handler()
        case let .link(_, _, url): UIApplication.shared.open(url)
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

    private func restorePurchases() {
        Task { @MainActor in
            await AICreditsManager.store.restore()
            let alert = UIAlertController(title: "Restore complete", message: "Any previous purchases have been restored.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func exportLogs() {
        guard let logs = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Logs/livingdex.log"),
            FileManager.default.fileExists(atPath: logs.path) else {
            let alert = UIAlertController(title: "No logs yet", message: "Diagnostics appear here after you use the app.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let share = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        present(share, animated: true)
    }
}
