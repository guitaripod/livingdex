import UIKit

/// The Field Guide's front door on the Profile tab: the four main realm illustrations side by side
/// under a dark wash, with the guide's name and a one-line promise over them.
final class FieldGuideBannerCell: UITableViewCell {
    static let reuseID = "FieldGuideBannerCell"

    private static let realms: [Realm] = [.animals, .plants, .fungi, .protists]
    private static let minimumHeight: CGFloat = 132

    private let wash = WashView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundConfiguration = .clear()
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        contentView.layer.cornerRadius = 26
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.backgroundColor = UIColor(white: 0.08, alpha: 1)

        let collage = UIStackView(arrangedSubviews: Self.realms.map(artView))
        collage.axis = .horizontal
        collage.distribution = .fillEqually
        collage.translatesAutoresizingMaskIntoConstraints = false
        collage.isAccessibilityElement = false

        wash.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Field Guide"
        titleLabel.font = Self.rounded(.title2, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0

        subtitleLabel.text = "Every realm of life, illustrated."
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = UIColor(white: 1, alpha: 0.82)
        subtitleLabel.numberOfLines = 0

        chevron.tintColor = UIColor(white: 1, alpha: 0.85)
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        let texts = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        texts.axis = .vertical
        texts.spacing = 3

        let row = UIStackView(arrangedSubviews: [texts, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DesignSystem.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(collage)
        contentView.addSubview(wash)
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight),

            collage.topAnchor.constraint(equalTo: contentView.topAnchor),
            collage.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            collage.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            collage.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            wash.topAnchor.constraint(equalTo: contentView.topAnchor),
            wash.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            wash.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DesignSystem.Spacing.l),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DesignSystem.Spacing.l),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DesignSystem.Spacing.m),
            row.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: DesignSystem.Spacing.m),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Field Guide"
        accessibilityHint = "Every realm of life, illustrated."
        accessibilityTraits = .button
    }

    private func artView(for realm: Realm) -> UIView {
        let view = UIImageView(image: RealmArt.image(for: realm))
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            view.setContentHuggingPriority(UILayoutPriority(1), for: axis)
            view.setContentCompressionResistancePriority(UILayoutPriority(1), for: axis)
        }
        return view
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        let scale: CGFloat = highlighted ? 0.98 : 1
        UIView.animate(withDuration: animated ? 0.15 : 0) {
            self.contentView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    private static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            .withDesign(.rounded) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// A dark wash that is lightest at the top, so the illustrations stay vivid while the text at the
/// bottom stays legible.
private final class WashView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.12).cgColor,
            UIColor.black.withAlphaComponent(0.86).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.2)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
