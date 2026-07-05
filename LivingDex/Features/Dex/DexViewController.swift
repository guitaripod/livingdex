import UIKit

/// The Dex — the heart of the game. Two modes:
/// • **Nearby**: your Regional Dex — every species that occurs near you, as
///   fillable slots (locked silhouettes you reveal by catching), with completion.
/// • **Caught**: your lifetime collection, searchable and sortable.
final class DexViewController: UIViewController, UICollectionViewDelegate, UISearchResultsUpdating {
    private enum Section { case main }
    private enum Mode: Int { case nearby, caught }

    private let segmented = UISegmentedControl(items: ["Nearby", "Caught"])
    private let header = DexHeaderView()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DexTile>!
    private let emptyLabel = UILabel()

    private var mode: Mode = .nearby
    private var caught: [DexEntry] = []
    private var regional: [RegionSpecies] = []
    private var observer: AnyObject?
    private var didLoadRegion = false

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
        collectionView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: collectionView.topAnchor, constant: 120),
            emptyLabel.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: -40),
        ])
    }

    private func configureSearchAndSort() {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search your dex"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = true
        updateSortButton()
    }

    private func updateSortButton() {
        let sortActions = Sort.allCases.map { s in
            UIAction(title: s.rawValue, state: sort == s ? .on : .off) { [weak self] _ in
                self?.sort = s; self?.updateSortButton(); self?.reload()
            }
        }
        let realmActions = ([nil] + Realm.allCases.map { Optional($0) }).map { r in
            UIAction(title: r?.rawValue.capitalized ?? "All realms", state: realmFilter == r ? .on : .off) { [weak self] _ in
                self?.realmFilter = r; self?.updateSortButton(); self?.reload()
            }
        }
        let menu = UIMenu(children: [
            UIMenu(title: "Sort", options: .displayInline, children: sortActions),
            UIMenu(title: "Filter", options: .displayInline, children: realmActions),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"), menu: menu)
    }

    // MARK: Data

    private func startObserving() {
        observer = CollectionStore.shared.observeDex { [weak self] entries in
            self?.caught = entries
            self?.reload()
        }
    }

    private func loadRegionIfNeeded() {
        guard !didLoadRegion else { return }
        let ctx = LocationProvider.shared.currentContext()
        guard let lat = ctx.latitude, let lng = ctx.longitude else { reload(); return }
        didLoadRegion = true
        Task { @MainActor in
            regional = await RegionStore.shared.regionalSpecies(latitude: lat, longitude: lng)
            reload()
        }
    }

    @objc private func modeChanged() {
        mode = Mode(rawValue: segmented.selectedSegmentIndex) ?? .nearby
        navigationItem.rightBarButtonItem?.isHidden = (mode == .nearby)
        reload()
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        if mode == .caught { reload() }
    }

    private func reload() {
        let tiles = (mode == .nearby) ? nearbyTiles() : caughtTiles()
        updateHeader()
        emptyLabel.text = emptyText(for: tiles)
        emptyLabel.isHidden = !tiles.isEmpty
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
            if regional.isEmpty {
                return LocationProvider.shared.currentContext().latitude == nil
                    ? "Grant location access to reveal the species living near you — your Regional Dex."
                    : "Finding the species near you…"
            }
            return ""
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

    private func showLockedPeek(_ tile: DexTile) {
        let alert = UIAlertController(
            title: "Not yet caught",
            message: "A \(tile.rarity.title.lowercased()) \(tile.realm.rawValue) species lives near you. Find it in the field to add it to your dex.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
