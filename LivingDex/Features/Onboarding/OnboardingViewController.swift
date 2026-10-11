import UIKit

/// One-time first-run explainer. Establishes the core mechanic (point → catch →
/// collect), that rarity is real, and — before the camera appears — that
/// identification runs in the cloud with 30 free tries to start.
final class OnboardingViewController: UIViewController {
    var onFinish: (() -> Void)?

    private struct Point {
        let symbol: String
        let title: String
        let body: String
    }

    private let points: [Point] = [
        .init(symbol: "camera.viewfinder", title: "Point & catch",
              body: "Aim at a bird, a bug, a mushroom or a flower — or pick a photo — and Living Dex names it."),
        .init(symbol: "square.grid.2x2.fill", title: "Fill your Dex",
              body: "Every new species joins your collection. The Nearby tab shows what lives around you."),
        .init(symbol: "sparkles", title: "Chase the rare",
              body: "Rarity is real: how uncommon a species is where you are. Some finds are legendary."),
    ]

    private var animatedViews: [UIView] = []
    private var didAnimate = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let hero = makeHero()

        let title = UILabel()
        title.text = "Living Dex"
        title.font = Self.font(.largeTitle, weight: .heavy)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.textAlignment = .center
        title.accessibilityTraits = .header

        let subtitle = UILabel()
        subtitle.text = "The field guide where the creatures are real."
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        let rows = points.map(pointRow)
        let pointsStack = UIStackView(arrangedSubviews: rows)
        pointsStack.axis = .vertical
        pointsStack.spacing = DesignSystem.Spacing.l

        let heroRow = UIStackView(arrangedSubviews: [UIView(), hero, UIView()])
        heroRow.distribution = .equalCentering

        let content = UIStackView(arrangedSubviews: [heroRow, title, subtitle, spacer(20), pointsStack])
        content.axis = .vertical
        content.spacing = DesignSystem.Spacing.s
        content.setCustomSpacing(DesignSystem.Spacing.m, after: heroRow)
        content.translatesAutoresizingMaskIntoConstraints = false

        let footnote = UILabel()
        footnote.text = "Identification runs in the cloud. Every device starts with 30 free identifications, and we ask before your first photo is sent."
        footnote.font = .preferredFont(forTextStyle: .footnote)
        footnote.adjustsFontForContentSizeCategory = true
        footnote.textColor = .secondaryLabel
        footnote.numberOfLines = 0
        footnote.textAlignment = .center

        var config = UIButton.Configuration.borderedProminent()
        config.title = "Start collecting"
        config.baseBackgroundColor = DesignSystem.Color.accent
        config.baseForegroundColor = .black
        config.cornerStyle = .large
        config.buttonSize = .large
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.onFinish?()
        })

        let footer = UIStackView(arrangedSubviews: [footnote, button])
        footer.axis = .vertical
        footer.spacing = DesignSystem.Spacing.m
        footer.translatesAutoresizingMaskIntoConstraints = false

        let topSpacer = UIView()
        let bottomSpacer = UIView()
        let centered = UIStackView(arrangedSubviews: [topSpacer, content, bottomSpacer])
        centered.axis = .vertical
        centered.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        scroll.addSubview(centered)

        view.addSubview(scroll)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -DesignSystem.Spacing.m),

            centered.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            centered.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            centered.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: DesignSystem.Spacing.l),
            centered.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -DesignSystem.Spacing.l),
            centered.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
            topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor),
            topSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: DesignSystem.Spacing.s),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.l),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.l),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.l),
        ])

        animatedViews = [heroRow, title, subtitle] + rows
        if !Motion.reduced { animatedViews.forEach { $0.alpha = 0 } }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimate else { return }
        didAnimate = true
        guard !Motion.reduced else { return }
        for (index, item) in animatedViews.enumerated() {
            item.transform = CGAffineTransform(translationX: 0, y: 18)
            UIView.animate(
                withDuration: 0.55, delay: 0.08 * Double(index),
                usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3
            ) {
                item.alpha = 1
                item.transform = .identity
            }
        }
    }

    /// The app mark: a viewfinder framing a leaf on the brand's emerald gradient.
    private func makeHero() -> UIView {
        let tile = GradientTileView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.widthAnchor.constraint(equalToConstant: 96).isActive = true
        tile.heightAnchor.constraint(equalToConstant: 96).isActive = true
        tile.layer.cornerRadius = 22
        tile.layer.cornerCurve = .continuous
        tile.clipsToBounds = true
        tile.isAccessibilityElement = false

        let frame = UIImageView(image: UIImage(
            systemName: "viewfinder", withConfiguration: UIImage.SymbolConfiguration(pointSize: 62, weight: .light)))
        let leaf = UIImageView(image: UIImage(
            systemName: "leaf.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)))
        for glyph in [frame, leaf] {
            glyph.tintColor = .white
            glyph.contentMode = .center
            glyph.translatesAutoresizingMaskIntoConstraints = false
            tile.addSubview(glyph)
            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor).isActive = true
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor).isActive = true
        }
        return tile
    }

    private func pointRow(_ point: Point) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: point.symbol))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let title = UILabel()
        title.text = point.title
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0

        let body = UILabel()
        body.text = point.body
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = .secondaryLabel
        body.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [title, body])
        text.axis = .vertical
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.spacing = DesignSystem.Spacing.m
        row.alignment = .top
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(point.title). \(point.body)"
        return row
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    private static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// A view whose backing layer is the app's emerald gradient.
private final class GradientTileView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [
            UIColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1).cgColor,
            UIColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
