import UIKit

extension Rarity {
    var color: UIColor {
        switch self {
        case .common: return DesignSystem.Color.rarityCommon
        case .uncommon: return DesignSystem.Color.rarityUncommon
        case .rare: return DesignSystem.Color.rarityRare
        case .epic: return DesignSystem.Color.rarityEpic
        case .legendary: return DesignSystem.Color.rarityLegendary
        }
    }

    var title: String { rawValue.capitalized }
}

/// A small colored pill naming a rarity tier.
final class RarityBadge: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func configure(_ rarity: Rarity) {
        label.text = rarity.title.uppercased()
        backgroundColor = rarity.color
    }
}
