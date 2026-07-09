import CoreLocation
import UIKit

/// The Dex — the heart of the game. Two modes:
/// • **Nearby**: your Regional Dex — every species that occurs near you, as
///   fillable slots (locked silhouettes you reveal by catching), with completion.
/// • **Caught**: your lifetime collection, searchable and sortable.
final class DexViewController: UIViewController, UICollectionViewDelegate, UISearchResultsUpdating {
    private enum Section { case main }
    private enum Mode: Int { case nearby, caught }

    private let segmented = UISegmentedControl(items: ["Nearby", "Caught"])
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DexTile>!
    private weak var headerView: DexHeaderView?
    private let refreshControl = UIRefreshControl()

    private enum RegionState { case idle, loading, loaded, failed }
    private var mode: Mode = .nearby
    private var caught: [DexEntry] = []
    private var regional: [RegionSpecies] = []
    private var observer: AnyObject?
    private var regionState: RegionState = .idle
    private var lastRegionCell: RegionCell?
    private var displayedTileCount = 0

    private var sort: Sort = .recent
    private var realmFilter: Realm?
    private var caughtFilter: CaughtFilter = .all
    private var query: String = ""
    private var searchWork: DispatchWorkItem?
    private lazy var locationManager = CLLocationManager()
    private var awaitingRegionFix = false

    private enum Sort: String, CaseIterable { case recent = "Recent", name = "A–Z", rarity = "Rarity" }
    private enum CaughtFilter: CaseIterable {
        case all, caught, uncaught
        var title: String {
            switch self {
            case .all: return "All"
            case .caught: return "Caught"
            case .uncaught: return "Not caught"
            }
        }
    }

    /// Coarse ~0.5° location bucket — matches RegionStore's per-cell cache so a
    /// re-appearance in the same area is a no-op and travel triggers a refetch.
    private struct RegionCell: Equatable { let x: Int; let y: Int }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        navigationItem.titleView = segmented
        #if DEBUG
        if DemoSeeder.route == "caught" { segmented.selectedSegmentIndex = 1; mode = .caught }
        #endif

        configureCollectionView()
        configureDataSource()
        configureSearch()
        updateBarButtons()
        startObserving()
        locationManager.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if regionState != .loading { fetchRegion(force: false) }
        #if DEBUG
        if DemoSeeder.route == "card", !didDemoPush, let entry = caught.first {
            didDemoPush = true
            navigationController?.pushViewController(CardDetailViewController(entry: entry), animated: false)
        }
        #endif
    }

    #if DEBUG
    private var didDemoPush = false
    #endif

    // MARK: Layout

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1.0 / 3.0), heightDimension: .fractionalHeight(1)))
            item.contentInsets = .init(top: 5, leading: 5, bottom: 5, trailing: 5)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.36)),
                subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 6, leading: 8, bottom: 24, trailing: 8)
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(96)),
                elementKind: DexHeaderView.elementKind, alignment: .top)
            section.boundarySupplementaryItems = [header]
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.register(DexCell.self, forCellWithReuseIdentifier: DexCell.reuseID)
        collectionView.delegate = self
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, DexTile>(collectionView: collectionView) {
            cv, indexPath, tile in
            let cell = cv.dequeueReusableCell(withReuseIdentifier: DexCell.reuseID, for: indexPath) as! DexCell
            cell.configure(tile)
            return cell
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<DexHeaderView>(
            elementKind: DexHeaderView.elementKind
        ) { [weak self] view, _, _ in
            self?.headerView = view
            self?.configureHeaderView(view)
        }
        dataSource.supplementaryViewProvider = { cv, _, indexPath in
            cv.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func configureSearch() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search species"
        navigationItem.searchController = searchController
        navigationItem.preferredSearchBarPlacement = .integrated
    }

    /// Sort (Caught only) + realm filter + a caught/uncaught filter (Nearby only).
    private func updateBarButtons() {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            menu: buildFilterMenu())
        navigationItem.rightBarButtonItems = [item]
    }

    private func buildFilterMenu() -> UIMenu {
        var children: [UIMenuElement] = []
        if mode == .caught {
            let sortActions = Sort.allCases.map { s in
                UIAction(title: s.rawValue, state: sort == s ? .on : .off) { [weak self] _ in
                    self?.sort = s; self?.updateBarButtons(); self?.reload()
                }
            }
            children.append(UIMenu(title: "Sort", options: .displayInline, children: sortActions))
        }
        let realmActions = ([Realm?.none] + Realm.allCases.map { Optional($0) }).map { r in
            UIAction(title: r?.rawValue.capitalized ?? "All realms", state: realmFilter == r ? .on : .off) { [weak self] _ in
                self?.realmFilter = r; self?.updateBarButtons(); self?.reload()
            }
        }
        children.append(UIMenu(title: "Realm", options: .displayInline, children: realmActions))
        if mode == .nearby {
            let showActions = CaughtFilter.allCases.map { f in
                UIAction(title: f.title, state: caughtFilter == f ? .on : .off) { [weak self] _ in
                    self?.caughtFilter = f; self?.updateBarButtons(); self?.reload()
                }
            }
            children.append(UIMenu(title: "Show", options: .displayInline, children: showActions))
        }
        return UIMenu(children: children)
    }

    // MARK: Search

    func updateSearchResults(for searchController: UISearchController) {
        scheduleSearch(searchController.searchBar.text ?? "")
    }

    private func scheduleSearch(_ text: String) {
        searchWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.query != text else { return }
                self.query = text
                self.reload(animated: false)
            }
        }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: Data

    private func startObserving() {
        observer = CollectionStore.shared.observeDex { [weak self] entries in
            MainActor.assumeIsolated {
                self?.caught = entries
                self?.reload()
            }
        }
    }

    private func fetchRegion(force: Bool) {
        let ctx = LocationProvider.shared.currentContext()
        guard let lat = ctx.latitude, let lng = ctx.longitude else {
            refreshControl.endRefreshing()
            reload()
            return
        }
        let cell = RegionCell(x: Int((lat / 0.5).rounded(.down)), y: Int((lng / 0.5).rounded(.down)))
        if !force, regionState == .loaded, cell == lastRegionCell {
            refreshControl.endRefreshing()
            return
        }
        if regionState != .loaded { regionState = .loading }
        reload()
        Task { @MainActor in
            if let species = await RegionStore.shared.regionalSpecies(latitude: lat, longitude: lng) {
                regional = species
                regionState = .loaded
                lastRegionCell = cell
            } else if regionState != .loaded {
                regionState = .failed
            }
            refreshControl.endRefreshing()
            reload()
        }
    }

    @objc private func pullToRefresh() {
        Haptics.tap()
        if mode == .nearby {
            fetchRegion(force: true)
        } else {
            refreshControl.endRefreshing()
        }
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: segmented.selectedSegmentIndex) ?? .nearby
        updateBarButtons()
        reload()
    }

    private func reload(animated: Bool = true) {
        let tiles = (mode == .nearby) ? nearbyTiles() : caughtTiles()
        displayedTileCount = tiles.count
        updateHeader()
        applySnapshot(tiles, animated: animated)
        setNeedsUpdateContentUnavailableConfiguration()
    }

    private func applySnapshot(_ tiles: [DexTile], animated: Bool) {
        // DexTile identity is speciesId; a duplicate id (e.g. a server-sourced
        // Regional payload repeating a species) would trip the diffable data
        // source's "identical items" assertion, so dedupe defensively.
        var seen = Set<String>()
        let tiles = tiles.filter { seen.insert($0.speciesId).inserted }
        let previous = dataSource.snapshot()
        let previousById = Dictionary(
            previous.itemIdentifiers.map { ($0.speciesId, $0) }, uniquingKeysWith: { a, _ in a })
        var snapshot = NSDiffableDataSourceSnapshot<Section, DexTile>()
        snapshot.appendSections([.main])
        snapshot.appendItems(tiles, toSection: .main)
        let reconfigured = tiles.filter { tile in
            guard let old = previousById[tile.speciesId] else { return false }
            return !old.contentEquals(tile)
        }
        if !reconfigured.isEmpty { snapshot.reconfigureItems(reconfigured) }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func nearbyTiles() -> [DexTile] {
        let caughtById = Dictionary(caught.map { ($0.speciesId, $0) }, uniquingKeysWith: { a, _ in a })
        let sciById = Dictionary(regional.map { ($0.speciesId, $0.scientificName) }, uniquingKeysWith: { a, _ in a })
        let tiles: [DexTile] = regional.enumerated().map { i, sp in
            if let e = caughtById[sp.speciesId] {
                return DexTile(number: i + 1, speciesId: sp.speciesId, name: e.commonName,
                               imagePath: e.bestImagePath, rarity: e.rarity, realm: e.realm, locked: false)
            }
            return DexTile(number: i + 1, speciesId: sp.speciesId, name: sp.displayName,
                           imagePath: nil, rarity: sp.rarity, realm: sp.realm, locked: true)
        }
        return tiles.filter { tile in
            if let realm = realmFilter, tile.realm != realm { return false }
            switch caughtFilter {
            case .all: break
            case .caught: if tile.locked { return false }
            case .uncaught: if !tile.locked { return false }
            }
            guard !query.isEmpty else { return true }
            if tile.name.localizedCaseInsensitiveContains(query) { return true }
            return sciById[tile.speciesId]?.localizedCaseInsensitiveContains(query) ?? false
        }
    }

    private func caughtTiles() -> [DexTile] {
        var entries = caught
        if let realm = realmFilter { entries = entries.filter { $0.realm == realm } }
        if !query.isEmpty {
            entries = entries.filter {
                $0.commonName.localizedCaseInsensitiveContains(query) ||
                $0.scientificName.localizedCaseInsensitiveContains(query)
            }
        }
        switch sort {
        case .recent: entries.sort { $0.lastCaughtAt > $1.lastCaughtAt }
        case .name: entries.sort { $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedAscending }
        case .rarity: entries.sort { $0.rarity > $1.rarity }
        }
        return entries.enumerated().map { i, e in
            DexTile(number: i + 1, speciesId: e.speciesId, name: e.commonName,
                    imagePath: e.bestImagePath, rarity: e.rarity, realm: e.realm, locked: false)
        }
    }

    private func updateHeader() {
        if let headerView { configureHeaderView(headerView) }
    }

    private func configureHeaderView(_ header: DexHeaderView) {
        if mode == .nearby {
            let caughtIds = Set(caught.map { $0.speciesId })
            let owned = regional.filter { caughtIds.contains($0.speciesId) }.count
            header.showCompletion(caught: owned, total: regional.count, title: "Nearby")
        } else {
            let rarePlus = caught.filter { $0.rarity >= .rare }.count
            header.showSummary(species: caught.count, detail: rarePlus == 0 ? "your collection" : "\(rarePlus) rare or better")
        }
    }

    // MARK: Empty / loading / error states

    override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
        contentUnavailableConfiguration = unavailableConfiguration()
    }

    private func unavailableConfiguration() -> UIContentUnavailableConfiguration? {
        guard displayedTileCount == 0 else { return nil }
        return mode == .nearby ? nearbyUnavailable() : caughtUnavailable()
    }

    private func nearbyUnavailable() -> UIContentUnavailableConfiguration {
        if LocationProvider.shared.currentContext().latitude == nil {
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: return .loading()
            default: return locationAccessConfiguration()
            }
        }
        if !query.isEmpty { return .search() }
        switch regionState {
        case .idle, .loading:
            return .loading()
        case .failed:
            return emptyConfiguration(
                symbol: "wifi.slash", title: "Can't reach the field guide",
                subtitle: "Check your connection and try again.",
                buttonTitle: "Retry", action: UIAction { [weak self] _ in self?.fetchRegion(force: true) })
        case .loaded:
            if realmFilter != nil || caughtFilter != .all {
                return emptyConfiguration(
                    symbol: "line.3.horizontal.decrease.circle", title: "No matches",
                    subtitle: "No nearby species match the current filters.")
            }
            return emptyConfiguration(
                symbol: "leaf", title: "Nothing catalogued here yet",
                subtitle: "Catch something nearby to start your Regional Dex.")
        }
    }

    private func caughtUnavailable() -> UIContentUnavailableConfiguration {
        if !query.isEmpty { return .search() }
        if realmFilter != nil {
            return emptyConfiguration(
                symbol: "line.3.horizontal.decrease.circle", title: "No matches",
                subtitle: "No caught species match the current filters.")
        }
        return emptyConfiguration(
            symbol: "camera.viewfinder", title: "Your dex is empty",
            subtitle: "Point the camera at anything alive to make your first catch.",
            buttonTitle: "Go to Field", action: UIAction { [weak self] _ in self?.goToField() })
    }

    private func locationAccessConfiguration() -> UIContentUnavailableConfiguration {
        emptyConfiguration(
            symbol: "location.slash", title: "Location access needed",
            subtitle: "Turn on location to reveal the species living near you — your Regional Dex.",
            buttonTitle: "Grant Access", action: UIAction { [weak self] _ in self?.handleLocationAccess() })
    }

    private func emptyConfiguration(
        symbol: String, title: String, subtitle: String?,
        buttonTitle: String? = nil, action: UIAction? = nil
    ) -> UIContentUnavailableConfiguration {
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: symbol)
        config.text = title
        config.secondaryText = subtitle
        if let buttonTitle, let action {
            var button = UIButton.Configuration.bordered()
            button.title = buttonTitle
            button.baseForegroundColor = DesignSystem.Color.accent
            config.button = button
            config.buttonProperties.primaryAction = action
        }
        return config
    }

    private func handleLocationAccess() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Event-driven: the retry is fired by the delegate the moment
            // authorization is granted and a fix lands, not on a fixed timer
            // that usually elapses before the user has answered the dialog.
            awaitingRegionFix = true
            LocationProvider.shared.requestAuthorization()
            locationManager.startUpdatingLocation()
        default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func goToField() {
        tabBarController?.selectedIndex = 0
    }

    // MARK: Selection & context menu

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let tile = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        guard !tile.locked, let entry = caught.first(where: { $0.speciesId == tile.speciesId }) else {
            if tile.locked { showLockedPeek(tile) }
            return
        }
        let detail = CardDetailViewController(entry: entry)
        detail.preferredTransition = .zoom { [weak self] _ in
            guard let self,
                  let indexPath = self.dataSource.indexPath(for: tile),
                  let cell = self.collectionView.cellForItem(at: indexPath) else { return nil }
            return cell
        }
        navigationController?.pushViewController(detail, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let tile = dataSource.itemIdentifier(for: indexPath), !tile.locked else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let release = UIAction(title: "Release", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirmRelease(speciesId: tile.speciesId, name: tile.name,
                                     sourceView: collectionView.cellForItem(at: indexPath))
            }
            return UIMenu(title: tile.name, children: [release])
        }
    }

    /// Shared confirm-and-release flow, mirroring CardDetailViewController's sheet
    /// so the grid's long-press action never destroys photos in a single tap.
    private func confirmRelease(speciesId: String, name: String, sourceView: UIView?) {
        let alert = UIAlertController(
            title: "Release \(name)?",
            message: "This removes it from your dex, along with your photos. It can't be undone.",
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Release", style: .destructive) { [weak self] _ in
            self?.performRelease(speciesId: speciesId)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = sourceView?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }

    private func performRelease(speciesId: String) {
        do {
            try CollectionStore.shared.release(speciesId: speciesId)
            Haptics.tap()
        } catch {
            AppLogger.shared.error("release failed: \(error.localizedDescription)", category: .persistence)
            let alert = UIAlertController(
                title: "Couldn't release",
                message: "Something went wrong releasing that species. Please try again.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func showLockedPeek(_ tile: DexTile) {
        let alert = UIAlertController(
            title: "Not yet caught",
            message: "A \(tile.rarity.title.lowercased()) \(realmNoun(tile.realm)) lives near you. Find it in the field to add it to your dex.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "To the Field", style: .default) { [weak self] _ in
            self?.goToField()
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    private func realmNoun(_ realm: Realm) -> String {
        switch realm {
        case .animals: return "animal"
        case .plants: return "plant"
        case .fungi: return "fungus"
        case .protists: return "protist"
        case .other: return "organism"
        }
    }
}

extension DexViewController: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard awaitingRegionFix else { return }
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.startUpdatingLocation()
            case .denied, .restricted:
                awaitingRegionFix = false
                locationManager.stopUpdatingLocation()
                reload()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let hasFix = !locations.isEmpty
        MainActor.assumeIsolated {
            guard awaitingRegionFix, hasFix else { return }
            awaitingRegionFix = false
            locationManager.stopUpdatingLocation()
            if mode == .nearby { fetchRegion(force: true) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.shared.error("dex location failed: \(error.localizedDescription)", category: .location)
    }
}
