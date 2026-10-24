import Combine
import LivingDexCore
import UIKit
import AICreditsUI

/// Profile & progress: the collection's headline stats, a rarity breakdown, the
/// Living Dex Pro surface, and diagnostics (log export). A collection game lives
/// on visible progress, so this is a first-class tab, not a buried settings page.
final class ProfileViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = ProfileHeaderView()
    private let subscriptions = SubscriptionService.shared
    private var cancellables = Set<AnyCancellable>()

    private enum Row {
        case stat(title: String, value: String)
        case rarity(Rarity, count: Int)
        case pro(balance: Int?, isPro: Bool)
        case action(title: String, symbol: String, handler: () -> Void)
        case info(title: String, value: String)
        case guide
    }
    private struct Section { let header: String?; let rows: [Row] }
    private var sections: [Section] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            primaryAction: UIAction { [weak self] _ in
                self?.navigationController?.pushViewController(SettingsViewController(), animated: true)
            })
        navigationItem.rightBarButtonItem?.title = "Settings"
        view.backgroundColor = .systemGroupedBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(FieldGuideBannerCell.self, forCellReuseIdentifier: FieldGuideBannerCell.reuseID)
        headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: Self.headerHeight)
        tableView.tableHeaderView = headerView
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackedLeading,
        ])

        subscriptions.entitlementPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isViewLoaded, self.view.window != nil else { return }
                self.rebuild()
                self.tableView.reloadData()
            }
            .store(in: &cancellables)

        // The credit balance changes when a pack is bought from the sheet, which
        // doesn't fire viewWillAppear — observe the store so the "credits
        // remaining" row refreshes live instead of only on tab switch.
        AICreditsManager.store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isViewLoaded, self.view.window != nil else { return }
                self.rebuild()
                self.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    private static let headerHeight: CGFloat = 210

    private lazy var stackedLeading = tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
    private lazy var splitLeading = tableView.leadingAnchor.constraint(
        equalTo: view.centerXAnchor, constant: AdaptiveLayout.foldGap / 2)
    private lazy var paneConstraints = [
        headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignSystem.Spacing.s),
        headerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
        headerView.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -AdaptiveLayout.foldGap / 2),
    ]
    private var arrangement = AdaptiveLayout.Arrangement.stacked

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let resolved = AdaptiveLayout.Arrangement.resolve(
            width: safe.width, height: safe.height, minimumWidth: AdaptiveLayout.paneSplitMinimumWidth)
        if resolved != arrangement { applyArrangement(resolved) }
        if arrangement == .stacked, headerView.frame.width != tableView.bounds.width {
            headerView.frame.size.width = tableView.bounds.width
            tableView.tableHeaderView = headerView
        }
    }

    /// On a wide landscape window the progress header takes the left half and the list the
    /// right half, divided at the middle of the window where a fold falls; otherwise the
    /// header scrolls above the list as before.
    private func applyArrangement(_ resolved: AdaptiveLayout.Arrangement) {
        arrangement = resolved
        if resolved == .sideBySide {
            tableView.tableHeaderView = nil
            headerView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(headerView)
            stackedLeading.isActive = false
            splitLeading.isActive = true
            NSLayoutConstraint.activate(paneConstraints)
        } else {
            NSLayoutConstraint.deactivate(paneConstraints)
            headerView.removeFromSuperview()
            headerView.translatesAutoresizingMaskIntoConstraints = true
            headerView.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: Self.headerHeight)
            tableView.tableHeaderView = headerView
            splitLeading.isActive = false
            stackedLeading.isActive = true
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuild()
        tableView.reloadData()
    }

    #if DEBUG
    private var didPresentDemoPaywall = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard DemoSeeder.route == "paywall", !didPresentDemoPaywall else { return }
        didPresentDemoPaywall = true
        DemoSeeder.presentPaywall(from: self)
    }
    #endif

    private func rebuild() {
        let stats = (try? CollectionStore.shared.stats()) ?? .init(speciesCount: 0, totalCatches: 0, byRarity: [:], realms: [], maxRarity: nil)
        let progress = (try? ProgressStore.shared.current()) ?? .initial()
        let balance = CreditsMeter.shared.knownBalance

        headerView.configure(with: progress, speciesCount: stats.speciesCount)

        var collection: [Row] = [
            .stat(title: "Longest streak", value: progress.longestStreak == 1 ? "1 day" : "\(progress.longestStreak) days"),
            .stat(title: "Species collected", value: "\(stats.speciesCount)"),
            .stat(title: "Total catches", value: "\(stats.totalCatches)"),
        ]
        collection += Rarity.allCases
            .filter { (stats.byRarity[$0] ?? 0) > 0 }
            .map { .rarity($0, count: stats.byRarity[$0] ?? 0) }

        sections = [
            Section(header: nil, rows: [.guide]),
            Section(header: "Collection", rows: collection),
            Section(header: "Identify", rows: [.pro(balance: balance, isPro: subscriptions.isPro)]),
            Section(header: "Compete", rows: [
                .action(title: "Leaderboards & achievements", symbol: "trophy.fill") { [weak self] in
                    guard let self else { return }
                    GameCenterService.shared.presentDashboard(from: self)
                },
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
        if case .guide = sections[indexPath.section].rows[indexPath.row] {
            return tableView.dequeueReusableCell(withIdentifier: FieldGuideBannerCell.reuseID, for: indexPath)
        }
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
        case let .pro(balance, isPro):
            content.text = "Identifications"
            content.image = UIImage(systemName: isPro ? "sparkles.rectangle.stack.fill" : "sparkles")
            content.imageProperties.tintColor = DesignSystem.Color.accent
            if isPro {
                content.secondaryText = "Pro — unlimited"
                content.secondaryTextProperties.color = DesignSystem.Color.accent
                content.secondaryTextProperties.font = Self.boldSubheadline
            } else if balance == nil {
                content.secondaryText = "Connect to see your balance"
            } else if let balance, balance <= 0 {
                content.secondaryText = "Go Pro or get credits"
                content.secondaryTextProperties.color = DesignSystem.Color.accent
                content.secondaryTextProperties.font = Self.boldSubheadline
            } else {
                content.secondaryText = balance == 1 ? "1 left" : "\(balance ?? 0) left"
            }
            cell.contentConfiguration = content
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        case let .action(title, symbol, _):
            content.text = title
            content.image = UIImage(systemName: symbol)
            content.imageProperties.tintColor = DesignSystem.Color.accent
            cell.contentConfiguration = content
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        case let .info(title, value):
            cell.contentConfiguration = pairConfig(title: title, value: value)
        case .guide:
            break
        }
        return cell
    }

    private static var boldSubheadline: UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
            .withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        return UIFont(descriptor: descriptor, size: 0)
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
        case let .action(_, _, handler):
            handler()
        case .guide:
            navigationController?.pushViewController(FieldGuideViewController(), animated: true)
        case let .pro(_, isPro):
            if isPro {
                UIApplication.shared.open(subscriptions.manageSubscriptionsURL)
            } else {
                PaywallPresenter.present(from: self)
            }
        default:
            break
        }
    }
}
