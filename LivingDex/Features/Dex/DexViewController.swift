import UIKit

/// The Dex — the heart of the game. Two modes:
/// • **Nearby**: your Regional Dex — every species that occurs near you, as
///   fillable slots (locked silhouettes you reveal by catching), with completion.
/// • **Caught**: your lifetime collection, searchable and sortable.
final class DexViewController: UIViewController, UICollectionViewDelegate, UISearchBarDelegate {
    private enum Section { case main }
    private enum Mode: Int { case nearby, caught }

    private let segmented = UISegmentedControl(items: ["Nearby", "Caught"])
    private let searchBar = UISearchBar()
    private let header = DexHeaderView()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DexTile>!
    private let emptyLabel = UILabel()

    private enum RegionState { case idle, loading, loaded, failed }
    private var mode: Mode = .nearby
    private var caught: [DexEntry] = []
    private var regional: [RegionSpecies] = []
    private var observer: AnyObject?
    private var regionState: RegionState = .idle
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var sort: Sort = .recent
    private var realmFilter: Realm?
    private var query: String = ""
    private enum Sort: String, CaseIterable { case recent = "Recent", name = "A–Z", rarity = "Rarity" }

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
        configureHeader()
        configureDataSource()
        configureEmptyState()
        configureSearchAndSort()
        startObserving()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadRegionIfNeeded()
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
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.register(DexCell.self, forCellWithReuseIdentifier: DexCell.reuseID)
        collectionView.delegate = self
        view.addSubview(collectionView)
    }

    private func configureHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: header.bottomAnchor),
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
    }

    private func configureEmptyState() {
        emptyLabel.font = .preferredFont(forTextStyle: .callout)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isUserInteractionEnabled = true
        emptyLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryRegion)))
        collectionView.addSubview(emptyLabel)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        collectionView.addSubview(spinner)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: collectionView.topAnchor, constant: 120),
            emptyLabel.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: -40),
            spinner.centerXAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 16),
        ])
    }

    private func configureSearchAndSort() {
        searchBar.placeholder = "Search your dex"
        searchBar.delegate = self
        searchBar.showsCancelButton = true
        searchBar.searchBarStyle = .minimal
        updateBarButtons()
    }

    /// Sort/filter menu + a search button, shown only in Caught mode.
    private func updateBarButtons() {
        guard mode == .caught else { navigationItem.rightBarButtonItems = []; return }
        let sortActions = Sort.allCases.map { s in
            UIAction(title: s.rawValue, state: sort == s ? .on : .off) { [weak self] _ in
                self?.sort = s; self?.updateBarButtons(); self?.reload()
            }
        }
        let realmActions = ([nil] + Realm.allCases.map { Optional($0) }).map { r in
            UIAction(title: r?.rawValue.capitalized ?? "All realms", state: realmFilter == r ? .on : .off) { [weak self] _ in
                self?.realmFilter = r; self?.updateBarButtons(); self?.reload()
            }
        }
        let sortItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            menu: UIMenu(children: [
                UIMenu(title: "Sort", options: .displayInline, children: sortActions),
                UIMenu(title: "Filter", options: .displayInline, children: realmActions),
            ]))
        let searchItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"),
                                         primaryAction: UIAction { [weak self] _ in self?.beginSearch() })
        navigationItem.rightBarButtonItems = [sortItem, searchItem]
    }

    private func beginSearch() {
        navigationItem.titleView = searchBar
        searchBar.becomeFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        query = ""
        searchBar.resignFirstResponder()
        navigationItem.titleView = segmented
        reload()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText
        reload()
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

    private func loadRegionIfNeeded() {
        guard regionState == .idle || regionState == .failed else { return }
        let ctx = LocationProvider.shared.currentContext()
        guard let lat = ctx.latitude, let lng = ctx.longitude else { reload(); return }
        regionState = .loading
        reload()
        Task { @MainActor in
            if let species = await RegionStore.shared.regionalSpecies(latitude: lat, longitude: lng) {
                regional = species
                regionState = .loaded
            } else {
                regionState = .failed
            }
            reload()
        }
    }

    @objc private func retryRegion() {
        guard mode == .nearby, regionState == .failed else { return }
        Haptics.tap()
        loadRegionIfNeeded()
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: segmented.selectedSegmentIndex) ?? .nearby
        updateBarButtons()
        reload()
    }

    private func reload() {
        let tiles = (mode == .nearby) ? nearbyTiles() : caughtTiles()
        updateHeader()
        emptyLabel.text = emptyText(for: tiles)
        emptyLabel.isHidden = !tiles.isEmpty
        if mode == .nearby && regionState == .loading && tiles.isEmpty { spinner.startAnimating() } else { spinner.stopAnimating() }
        var snapshot = NSDiffableDataSourceSnapshot<Section, DexTile>()
        snapshot.appendSections([.main])
        snapshot.appendItems(tiles, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func nearbyTiles() -> [DexTile] {
        let byId = Dictionary(caught.map { ($0.speciesId, $0) }, uniquingKeysWith: { a, _ in a })
        return regional.enumerated().map { i, sp in
            if let e = byId[sp.speciesId] {
                return DexTile(number: i + 1, speciesId: sp.speciesId, name: e.commonName,
                               imagePath: e.bestImagePath, rarity: e.rarity, realm: e.realm, locked: false)
            }
            return DexTile(number: i + 1, speciesId: sp.speciesId, name: sp.displayName,
                           imagePath: nil, rarity: sp.rarity, realm: sp.realm, locked: true)
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
        if mode == .nearby {
            let caughtIds = Set(caught.map { $0.speciesId })
            let owned = regional.filter { caughtIds.contains($0.speciesId) }.count
            header.showCompletion(caught: owned, total: regional.count, title: "Nearby")
        } else {
            let rarePlus = caught.filter { $0.rarity >= .rare }.count
            header.showSummary(species: caught.count, detail: rarePlus == 0 ? "your collection" : "\(rarePlus) rare or better")
        }
    }

    private func emptyText(for tiles: [DexTile]) -> String {
        if mode == .nearby {
            guard regional.isEmpty else { return "" }
            if LocationProvider.shared.currentContext().latitude == nil {
                return "Grant location access to reveal the species living near you — your Regional Dex."
            }
            switch regionState {
            case .loading: return "Finding the species near you…"
            case .failed: return "Couldn't reach the field guide.\nTap to retry."
            case .loaded: return "No catalogued species near this spot yet — try catching something to start your Regional Dex."
            case .idle: return "Finding the species near you…"
            }
        }
        return query.isEmpty
            ? "Your dex is empty.\nPoint the camera at anything alive to make your first catch."
            : "No matches for “\(query)”."
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let tile = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.tap()
        guard !tile.locked, let entry = caught.first(where: { $0.speciesId == tile.speciesId }) else {
            if tile.locked { showLockedPeek(tile) }
            return
        }
        navigationController?.pushViewController(CardDetailViewController(entry: entry), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let tile = dataSource.itemIdentifier(for: indexPath), !tile.locked else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let release = UIAction(title: "Release", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                try? CollectionStore.shared.release(speciesId: tile.speciesId)
                Haptics.tap()
            }
            return UIMenu(title: tile.name, children: [release])
        }
    }

    private func showLockedPeek(_ tile: DexTile) {
        let alert = UIAlertController(
            title: "Not yet caught",
            message: "A \(tile.rarity.title.lowercased()) \(tile.realm.rawValue) species lives near you. Find it in the field to add it to your dex.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
