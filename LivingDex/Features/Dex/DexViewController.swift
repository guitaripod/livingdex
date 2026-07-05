import UIKit

/// The collection — every species the player has caught, rarest-recent first.
/// Driven reactively by GRDB `ValueObservation`, so a fresh catch appears the
/// instant its card is minted. Empty until the first capture.
final class DexViewController: UIViewController, UICollectionViewDelegate {
    private enum Section { case main }

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DexEntry>!
    private let emptyLabel = UILabel()
    private var observer: AnyObject?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Dex"
        configureCollectionView()
        configureDataSource()
        configureEmptyState()
        startObserving()
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let columns = 3
            let item = NSCollectionLayoutItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
            item.contentInsets = .init(top: 5, leading: 5, bottom: 5, trailing: 5)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(160)),
                repeatingSubitem: item, count: columns)
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
            _ = environment
            return section
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.register(DexCell.self, forCellWithReuseIdentifier: DexCell.reuseID)
        collectionView.delegate = self
        view.addSubview(collectionView)
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, DexEntry>(collectionView: collectionView) {
            collectionView, indexPath, entry in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: DexCell.reuseID, for: indexPath) as! DexCell
            cell.configure(entry)
            return cell
        }
    }

    private func configureEmptyState() {
        emptyLabel.text = "Your dex is empty.\nPoint the camera at anything alive to make your first catch."
        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.l),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.l),
        ])
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let entry = dataSource.itemIdentifier(for: indexPath) else { return }
        navigationController?.pushViewController(CardDetailViewController(entry: entry), animated: true)
    }

    private func startObserving() {
        observer = CollectionStore.shared.observeDex { [weak self] entries in
            guard let self else { return }
            self.emptyLabel.isHidden = !entries.isEmpty
            self.navigationItem.prompt = entries.isEmpty ? nil : "\(entries.count) species collected"
            var snapshot = NSDiffableDataSourceSnapshot<Section, DexEntry>()
            snapshot.appendSections([.main])
            snapshot.appendItems(entries, toSection: .main)
            self.dataSource.apply(snapshot, animatingDifferences: true)
        }
    }
}
