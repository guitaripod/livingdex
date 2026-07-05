import UIKit

/// One-time first-run explainer. Establishes the core mechanic (point → catch →
/// collect) and that catches build a permanent, rarity-graded dex — the framing a
/// brand-new user needs before landing on a live camera.
final class OnboardingViewController: UIViewController {
    var onFinish: (() -> Void)?

    private struct Point {
        let symbol: String
        let title: String
        let body: String
    }

    private let points: [Point] = [
        .init(symbol: "camera.viewfinder", title: "Point & catch",
              body: "Aim your camera at any living thing — a bird, a bug, a mushroom, a flower — and identify it on the spot."),
        .init(symbol: "square.grid.2x2.fill", title: "Collect the tree of life",
              body: "Every catch is minted into your Dex. Fill it out across animals, plants, and fungi."),
        .init(symbol: "sparkles", title: "Chase the rare",
              body: "Rarity is real — based on how uncommon a species is where you are. Some finds are legendary."),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Welcome to Living Dex"
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.adjustsFontForContentSizeCategory = true
        title.font = UIFont(descriptor: title.font.fontDescriptor.withSymbolicTraits(.traitBold) ?? title.font.fontDescriptor, size: 0)
        title.numberOfLines = 0
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "The only Pokédex where the creatures are real."
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        let pointsStack = UIStackView(arrangedSubviews: points.map(pointRow))
        pointsStack.axis = .vertical
        pointsStack.spacing = DesignSystem.Spacing.l

        var config = UIButton.Configuration.borderedProminent()
        config.title = "Start collecting"
        config.baseBackgroundColor = DesignSystem.Color.accent
        config.cornerStyle = .large
        config.buttonSize = .large
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.onFinish?()
        })

        let content = UIStackView(arrangedSubviews: [title, subtitle, spacer(24), pointsStack])
        content.axis = .vertical
        content.spacing = DesignSystem.Spacing.s
        content.translatesAutoresizingMaskIntoConstraints = false

        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            content.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.l),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.l),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.l),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.l),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.l),
        ])
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
}
