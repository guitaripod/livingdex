import UIKit

/// A row of the realms of life, each an illustrated medallion with its count. In the Dex it is both
/// a progress read-out and the realm filter: tap a realm to see only it, tap again to clear.
final class RealmStripView: UIView {
    struct Entry {
        let realm: Realm
        let detail: String
    }

    var onSelect: ((Realm?) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var chips: [Realm: RealmChip] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        stack.axis = .horizontal
        stack.spacing = 14
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ entries: [Entry], selected: Realm?) {
        if chips.keys.sorted(by: { $0.rawValue < $1.rawValue }) != entries.map(\.realm).sorted(by: { $0.rawValue < $1.rawValue }) {
            chips.values.forEach { $0.removeFromSuperview() }
            chips = [:]
            for entry in entries {
                let chip = RealmChip(realm: entry.realm)
                chip.addAction(UIAction { [weak self, weak chip] _ in
                    guard let self, let chip else { return }
                    Haptics.tap()
                    self.onSelect?(chip.isChosen ? nil : entry.realm)
                }, for: .touchUpInside)
                chips[entry.realm] = chip
                stack.addArrangedSubview(chip)
            }
        }
        for entry in entries {
            chips[entry.realm]?.update(detail: entry.detail, chosen: selected == entry.realm, filtering: selected != nil)
        }
    }
}

private final class RealmChip: UIControl {
    private let realm: Realm
    private let medallion = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private(set) var isChosen = false

    init(realm: Realm) {
        self.realm = realm
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button

        medallion.image = RealmArt.tile(for: realm, seed: 4)
        medallion.contentMode = .scaleAspectFill
        medallion.clipsToBounds = true
        medallion.layer.cornerRadius = 30
        medallion.layer.borderWidth = 2.5
        medallion.layer.borderColor = UIColor.separator.cgColor
        medallion.isUserInteractionEnabled = false
        medallion.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.text = RealmArt.displayName(realm)
        nameLabel.font = .systemFont(ofSize: 12, weight: .bold)
        nameLabel.textColor = .label
        nameLabel.textAlignment = .center
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.8

        detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center

        let labels = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 0
        labels.isUserInteractionEnabled = false
        let column = UIStackView(arrangedSubviews: [medallion, labels])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 5
        column.isUserInteractionEnabled = false
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        column.pinEdges(to: self)
        NSLayoutConstraint.activate([
            medallion.widthAnchor.constraint(equalToConstant: 60),
            medallion.heightAnchor.constraint(equalToConstant: 60),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(detail: String, chosen: Bool, filtering: Bool) {
        isChosen = chosen
        detailLabel.text = detail
        medallion.layer.borderColor = (chosen ? DesignSystem.Color.accent : UIColor.separator).cgColor
        UIView.animate(withDuration: 0.2) {
            self.alpha = filtering && !chosen ? 0.5 : 1
        }
        accessibilityLabel = "\(RealmArt.displayName(realm)), \(detail)"
        accessibilityTraits = chosen ? [.button, .selected] : .button
        accessibilityHint = chosen ? "Shows all realms" : "Shows only \(RealmArt.displayName(realm).lowercased())"
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }
}
