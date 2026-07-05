import UIKit

/// Profile & progress: the collection's headline stats, a rarity breakdown, the
/// Living Dex Pro surface, and diagnostics (log export). A collection game lives
/// on visible progress, so this is a first-class tab, not a buried settings page.
final class ProfileViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Row {
        case stat(title: String, value: String)
        case rarity(Rarity, count: Int)
        case pro(balance: Int)
        case action(title: String, symbol: String, handler: () -> Void)
        case info(title: String, value: String)
    }
    private struct Section { let header: String?; let rows: [Row] }
    private var sections: [Section] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemGroupedBackground
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuild()
        tableView.reloadData()
    }

    private func rebuild() {
        let stats = (try? CollectionStore.shared.stats()) ?? .init(speciesCount: 0, totalCatches: 0, byRarity: [:])
        let balance = AICreditsManager.store.balance

        var collection: [Row] = [
            .stat(title: "Species collected", value: "\(stats.speciesCount)"),
            .stat(title: "Total catches", value: "\(stats.totalCatches)"),
        ]
        collection += Rarity.allCases
            .filter { (stats.byRarity[$0] ?? 0) > 0 }
            .map { .rarity($0, count: stats.byRarity[$0] ?? 0) }

        sections = [
            Section(header: "Collection", rows: collection),
            Section(header: "Living Dex Pro", rows: [.pro(balance: balance)]),
            Section(header: "Diagnostics", rows: [
                .action(title: "Export logs", symbol: "square.and.arrow.up") { [weak self] in self?.exportLogs() },
            ]),
            Section(header: "About", rows: [
                .info(title: "Version", value: Self.appVersion),
            ]),
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

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .none
        cell.accessoryView = nil

        switch sections[indexPath.section].rows[indexPath.row] {
        case let .stat(title, value):
            content.text = title
            content.secondaryText = value
            cell.contentConfiguration = pairConfig(title: title, value: value)
        case let .rarity(rarity, count):
            content.text = rarity.title
            content.image = UIImage(systemName: "circle.fill")
            content.imageProperties.tintColor = rarity.color
            content.imageProperties.maximumSize = CGSize(width: 12, height: 12)
            cell.contentConfiguration = content
            let badge = UILabel()
            badge.text = "\(count)"
            badge.font = .preferredFont(forTextStyle: .body)
            badge.textColor = .secondaryLabel
            badge.sizeToFit()
            cell.accessoryView = badge
        case let .pro(balance):
            content.text = "Living Dex Pro"
            content.secondaryText = "Unlimited cloud IDs, rich entries & ask-the-creature · \(balance) credits"
            content.image = UIImage(systemName: "crown.fill")
            content.imageProperties.tintColor = DesignSystem.Color.rarityLegendary
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case let .action(title, symbol, _):
            content.text = title
            content.image = UIImage(systemName: symbol)
            content.imageProperties.tintColor = DesignSystem.Color.accent
            cell.contentConfiguration = content
            cell.selectionStyle = .default
        case let .info(title, value):
            cell.contentConfiguration = pairConfig(title: title, value: value)
        }
        return cell
    }

    private func pairConfig(title: String, value: String) -> UIListContentConfiguration {
        var content = UIListContentConfiguration.valueCell()
        content.text = title
        content.secondaryText = value
        return content
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .pro:
            presentProPlaceholder()
        case let .action(_, _, handler):
            handler()
        default:
            break
        }
    }

    // MARK: Actions

    private func presentProPlaceholder() {
        let alert = UIAlertController(
            title: "Living Dex Pro",
            message: "Unlimited high-accuracy cloud identifications, richer dex entries, and conversational \"ask the creature\" Q&A. Coming soon — basic on-device ID stays free forever.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func exportLogs() {
        guard let logs = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Logs/livingdex.log"),
            FileManager.default.fileExists(atPath: logs.path) else {
            let alert = UIAlertController(title: "No logs yet", message: "Diagnostics will appear here after you use the app.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let share = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        present(share, animated: true)
    }
}
