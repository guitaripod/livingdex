import UIKit

/// One collected species in the dex grid: hero image, rarity dot, common name.
final class DexCell: UICollectionViewCell {
    static let reuseID = "DexCell"

    private let imageView = UIImageView()
    private let nameLabel = UILabel()
    private let rarityDot = UIView()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = DesignSystem.Radius.control
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .tertiarySystemBackground
        contentView.addSubview(imageView)

        rarityDot.translatesAutoresizingMaskIntoConstraints = false
        rarityDot.layer.cornerRadius = 5
        contentView.addSubview(rarityDot)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .preferredFont(forTextStyle: .footnote)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 1
        contentView.addSubview(nameLabel)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .preferredFont(forTextStyle: .caption1)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel
        contentView.addSubview(countLabel)

        isAccessibilityElement = true
        accessibilityTraits = .button
        for sub in [imageView, nameLabel, countLabel, rarityDot] { sub.isAccessibilityElement = false }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.widthAnchor),

            rarityDot.widthAnchor.constraint(equalToConstant: 10),
            rarityDot.heightAnchor.constraint(equalToConstant: 10),
            rarityDot.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 8),
            rarityDot.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -8),

            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            countLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            countLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            countLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }

    func configure(_ entry: DexEntry) {
        nameLabel.text = entry.commonName
        countLabel.text = entry.sightingCount > 1 ? "×\(entry.sightingCount)" : entry.rarity.title
        rarityDot.backgroundColor = entry.rarity.color
        imageView.image = ImageStore.load(entry.bestImagePath)
        let caught = entry.sightingCount == 1 ? "caught once" : "caught \(entry.sightingCount) times"
        accessibilityLabel = "\(entry.commonName), \(entry.rarity.title), \(caught)"
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            }
        }
    }
}
