import UIKit

/// A single dex slot, from either a caught species or a locked regional target.
struct DexTile: Hashable {
    var number: Int
    var speciesId: String
    var name: String
    var imagePath: String?
    var rarity: Rarity
    var realm: Realm
    var locked: Bool

    static func realmSymbol(_ realm: Realm) -> String {
        switch realm {
        case .animals: return "pawprint.fill"
        case .plants: return "leaf.fill"
        case .fungi: return "circle.hexagongrid.fill"
        case .protists: return "drop.fill"
        case .other: return "sparkle"
        }
    }
}

/// A premium dex tile: full-bleed artwork under a bottom scrim with the name and
/// dex number, a rarity pip, and a distinct locked (uncaught) silhouette state.
/// Images decode off-main via `ImageLoader` so the grid stays smooth at 120 Hz.
final class DexCell: UICollectionViewCell {
    static let reuseID = "DexCell"

    private let imageView = UIImageView()
    private let lockedIcon = UIImageView()
    private let scrim = CAGradientLayer()
    private let nameLabel = UILabel()
    private let numberLabel = UILabel()
    private let rarityPip = UIView()
    private var token = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.backgroundColor = .secondarySystemBackground

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

        lockedIcon.translatesAutoresizingMaskIntoConstraints = false
        lockedIcon.contentMode = .scaleAspectFit
        lockedIcon.tintColor = .quaternaryLabel
        contentView.addSubview(lockedIcon)

        scrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.72).cgColor]
        scrim.locations = [0.45, 1.0]
        contentView.layer.addSublayer(scrim)

        rarityPip.translatesAutoresizingMaskIntoConstraints = false
        rarityPip.layer.cornerRadius = 3
        contentView.addSubview(rarityPip)

        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        numberLabel.font = .systemFont(ofSize: 11, weight: .bold)
        numberLabel.textColor = UIColor(white: 1, alpha: 0.85)
        applyShadow(numberLabel)
        contentView.addSubview(numberLabel)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.8
        applyShadow(nameLabel)
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            lockedIcon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            lockedIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -6),
            lockedIcon.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.34),
            lockedIcon.heightAnchor.constraint(equalTo: lockedIcon.widthAnchor),

            rarityPip.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            rarityPip.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            rarityPip.widthAnchor.constraint(equalToConstant: 22),
            rarityPip.heightAnchor.constraint(equalToConstant: 6),

            numberLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            numberLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyShadow(_ label: UILabel) {
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.6
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        token = UUID()
        imageView.image = nil
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            }
        }
    }

    func configure(_ tile: DexTile) {
        numberLabel.text = String(format: "#%03d", tile.number)
        rarityPip.backgroundColor = tile.rarity.color

        if tile.locked {
            imageView.isHidden = true
            scrim.isHidden = true
            lockedIcon.isHidden = false
            // A "who's that?" mystery mark — we have no art for uncaught species.
            lockedIcon.image = UIImage(systemName: "questionmark")
            lockedIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(weight: .bold)
            nameLabel.text = "???"
            nameLabel.textColor = UIColor(white: 1, alpha: 0.5)
            rarityPip.alpha = 0.55
            isAccessibilityElement = true
            accessibilityLabel = "Slot \(tile.number), \(tile.rarity.title), not yet caught"
            return
        }

        imageView.isHidden = false
        scrim.isHidden = false
        lockedIcon.isHidden = true
        nameLabel.text = tile.name
        nameLabel.textColor = .white
        rarityPip.alpha = 1
        isAccessibilityElement = true
        accessibilityLabel = "\(tile.name), \(tile.rarity.title), number \(tile.number)"
        accessibilityTraits = .button

        guard let path = tile.imagePath, !path.isEmpty else { return }
        let current = token
        if let hit = ImageLoader.shared.cached(path) {
            imageView.image = hit
        } else {
            ImageLoader.shared.load(path) { [weak self] image in
                guard let self, self.token == current else { return }
                self.imageView.image = image
            }
        }
    }
}
