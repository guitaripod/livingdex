import UIKit

/// The in-app Field Guide — an educational hub that explains the whole app and
/// the real science behind it: how catching works, what each realm of life
/// actually *is* (answering "wait, what even is fungi?"), how rarity is earned
/// from real ecology, and where the data comes from. Pure layout over
/// `FieldGuide` content; realm art is the bundled Gemini illustration set.
final class FieldGuideViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Field Guide"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: DesignSystem.Spacing.l, right: 0)
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = DesignSystem.Spacing.m
        scrollView.addSubview(stack)

        let pad = DesignSystem.Spacing.m
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: pad),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -pad),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])

        buildContent()
    }

    private func buildContent() {
        stack.addArrangedSubview(heroHeader())

        stack.addArrangedSubview(sectionHeader("How it works"))
        for (index, step) in FieldGuide.steps.enumerated() {
            stack.addArrangedSubview(stepRow(step, number: index + 1))
        }

        stack.addArrangedSubview(sectionHeader("The realms of life"))
        stack.addArrangedSubview(captionLabel("Every living thing belongs to one of these great branches. Here's what makes each one what it is."))
        for realm in FieldGuide.realms {
            stack.addArrangedSubview(realmCard(realm))
        }

        stack.addArrangedSubview(sectionHeader("Rarity"))
        stack.addArrangedSubview(bodyLabel(FieldGuide.rarityIntro))
        stack.addArrangedSubview(rarityCard())

        stack.addArrangedSubview(sectionHeader("Good to know"))
        stack.addArrangedSubview(conceptsCard())

        stack.setCustomSpacing(DesignSystem.Spacing.l, after: stack.arrangedSubviews[0])
    }

    // MARK: Hero

    private func heroHeader() -> UIView {
        let title = UILabel()
        title.text = FieldGuide.introTitle
        title.font = boldFont(.largeTitle)
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = FieldGuide.introSubtitle
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        let column = UIStackView(arrangedSubviews: [title, subtitle])
        column.axis = .vertical
        column.spacing = DesignSystem.Spacing.s
        return column
    }

    // MARK: How it works

    private func stepRow(_ step: FieldGuide.Step, number: Int) -> UIView {
        let badge = UIImageView(image: UIImage(systemName: step.symbol))
        badge.contentMode = .center
        badge.tintColor = DesignSystem.Color.accent
        badge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        badge.backgroundColor = DesignSystem.Color.accent.withAlphaComponent(0.14)
        badge.layer.cornerRadius = 21
        badge.layer.cornerCurve = .continuous
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 42),
            badge.heightAnchor.constraint(equalToConstant: 42),
        ])

        let title = UILabel()
        title.text = "\(number). \(step.title)"
        title.font = boldFont(.headline)
        title.numberOfLines = 0

        let body = UILabel()
        body.text = step.body
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = .secondaryLabel
        body.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [title, body])
        text.axis = .vertical
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [badge, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DesignSystem.Spacing.m
        return card(row)
    }

    // MARK: Realm card

    private func realmCard(_ info: FieldGuide.RealmInfo) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = DesignSystem.Radius.card
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true

        let image = UIImageView(image: UIImage(named: info.assetName))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.backgroundColor = UIColor(red: 0.05, green: 0.08, blue: 0.08, alpha: 1)

        let scrim = GradientView()
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.colors = [UIColor.clear, UIColor.black.withAlphaComponent(0.65)]
        scrim.locations = [0.4, 1.0]

        let name = UILabel()
        name.text = info.name
        name.font = boldFont(.title1)
        name.textColor = .white
        name.translatesAutoresizingMaskIntoConstraints = false

        let tagline = UILabel()
        tagline.text = info.tagline
        tagline.font = boldFont(.subheadline)
        tagline.textColor = UIColor(white: 1, alpha: 0.9)
        tagline.translatesAutoresizingMaskIntoConstraints = false

        let glyph = UIImageView(image: UIImage(systemName: DexTile.realmSymbol(info.realm)))
        glyph.tintColor = .white
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        glyph.translatesAutoresizingMaskIntoConstraints = false

        let whatIsIt = bodyLabel(info.whatIsIt)
        let examplesTitle = miniHeader("You might catch")
        let examples = UIStackView(arrangedSubviews: info.examples.map(bulletRow))
        examples.axis = .vertical
        examples.spacing = 6

        let tip = tipRow(info.catchTip)

        let body = UIStackView(arrangedSubviews: [whatIsIt, examplesTitle, examples, tip])
        body.axis = .vertical
        body.spacing = DesignSystem.Spacing.m
        body.translatesAutoresizingMaskIntoConstraints = false
        body.isLayoutMarginsRelativeArrangement = true
        body.layoutMargins = UIEdgeInsets(
            top: DesignSystem.Spacing.m, left: DesignSystem.Spacing.m,
            bottom: DesignSystem.Spacing.m, right: DesignSystem.Spacing.m)

        container.addSubview(image)
        container.addSubview(scrim)
        container.addSubview(glyph)
        container.addSubview(name)
        container.addSubview(tagline)
        container.addSubview(body)
        container.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            image.topAnchor.constraint(equalTo: container.topAnchor),
            image.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            image.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: 0.62),

            scrim.leadingAnchor.constraint(equalTo: image.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: image.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: image.bottomAnchor),
            scrim.heightAnchor.constraint(equalTo: image.heightAnchor, multiplier: 0.6),

            glyph.topAnchor.constraint(equalTo: image.topAnchor, constant: DesignSystem.Spacing.m),
            glyph.trailingAnchor.constraint(equalTo: image.trailingAnchor, constant: -DesignSystem.Spacing.m),

            name.leadingAnchor.constraint(equalTo: image.leadingAnchor, constant: DesignSystem.Spacing.m),
            name.trailingAnchor.constraint(lessThanOrEqualTo: image.trailingAnchor, constant: -DesignSystem.Spacing.m),
            tagline.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            tagline.trailingAnchor.constraint(lessThanOrEqualTo: image.trailingAnchor, constant: -DesignSystem.Spacing.m),
            tagline.bottomAnchor.constraint(equalTo: image.bottomAnchor, constant: -DesignSystem.Spacing.m),
            name.bottomAnchor.constraint(equalTo: tagline.topAnchor, constant: -2),

            body.topAnchor.constraint(equalTo: image.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func tipRow(_ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "lightbulb.fill"))
        icon.tintColor = DesignSystem.Color.accent
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline),
                .foregroundColor: UIColor.label,
            ])
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DesignSystem.Spacing.s
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        let bg = UIView()
        bg.backgroundColor = DesignSystem.Color.accent.withAlphaComponent(0.10)
        bg.layer.cornerRadius = DesignSystem.Radius.control
        bg.layer.cornerCurve = .continuous
        row.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: bg.topAnchor),
            row.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            icon.topAnchor.constraint(equalTo: label.topAnchor, constant: 2),
        ])
        return bg
    }

    // MARK: Rarity

    private func rarityCard() -> UIView {
        let rows = FieldGuide.rarityTiers.map(rarityRow)
        let column = UIStackView(arrangedSubviews: rows)
        column.axis = .vertical
        column.spacing = DesignSystem.Spacing.m
        return card(column)
    }

    private func rarityRow(_ info: FieldGuide.RarityInfo) -> UIView {
        let badge = RarityBadge()
        badge.configure(info.rarity)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.translatesAutoresizingMaskIntoConstraints = false

        let meaning = UILabel()
        meaning.text = info.meaning
        meaning.font = .preferredFont(forTextStyle: .subheadline)
        meaning.adjustsFontForContentSizeCategory = true
        meaning.textColor = .secondaryLabel
        meaning.numberOfLines = 0

        let badgeHolder = UIView()
        badgeHolder.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: badgeHolder.topAnchor),
            badge.leadingAnchor.constraint(equalTo: badgeHolder.leadingAnchor),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: badgeHolder.trailingAnchor),
            badge.bottomAnchor.constraint(lessThanOrEqualTo: badgeHolder.bottomAnchor),
            badgeHolder.widthAnchor.constraint(equalToConstant: 104),
        ])

        let row = UIStackView(arrangedSubviews: [badgeHolder, meaning])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DesignSystem.Spacing.s
        return row
    }

    // MARK: Concepts

    private func conceptsCard() -> UIView {
        var blocks: [UIView] = []
        for (index, concept) in FieldGuide.concepts.enumerated() {
            if index > 0 { blocks.append(divider()) }
            let title = UILabel()
            title.text = concept.title
            title.font = boldFont(.headline)
            title.numberOfLines = 0
            let body = UILabel()
            body.text = concept.body
            body.font = .preferredFont(forTextStyle: .subheadline)
            body.adjustsFontForContentSizeCategory = true
            body.textColor = .secondaryLabel
            body.numberOfLines = 0
            let block = UIStackView(arrangedSubviews: [title, body])
            block.axis = .vertical
            block.spacing = 4
            blocks.append(block)
        }
        let column = UIStackView(arrangedSubviews: blocks)
        column.axis = .vertical
        column.spacing = DesignSystem.Spacing.m
        return card(column)
    }

    // MARK: Building blocks

    private func card(_ content: UIView) -> UIView {
        let bg = UIView()
        bg.backgroundColor = .secondarySystemGroupedBackground
        bg.layer.cornerRadius = DesignSystem.Radius.card
        bg.layer.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(content)
        let p = DesignSystem.Spacing.m
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: bg.topAnchor, constant: p),
            content.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: p),
            content.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -p),
            content.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -p),
        ])
        return bg
    }

    private func sectionHeader(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = boldFont(.footnote)
        label.textColor = DesignSystem.Color.accent
        label.numberOfLines = 0
        let holder = UIStackView(arrangedSubviews: [label])
        holder.isLayoutMarginsRelativeArrangement = true
        holder.layoutMargins = UIEdgeInsets(top: DesignSystem.Spacing.m, left: 4, bottom: 0, right: 4)
        return holder
    }

    private func miniHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = boldFont(.caption1)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 0
        return label
    }

    private func captionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private func bodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .callout)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        return label
    }

    private func bulletRow(_ text: String) -> UIView {
        let dot = UILabel()
        dot.text = "•"
        dot.font = boldFont(.subheadline)
        dot.textColor = DesignSystem.Color.accent
        dot.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [dot, label])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DesignSystem.Spacing.s
        return row
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    private func boldFont(_ style: UIFont.TextStyle) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
            .withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// A simple gradient-backed view for the realm-card scrim (a plain layer would
/// need manual frame syncing; this keeps it in Auto Layout).
final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    var colors: [UIColor] = [] { didSet { gradient.colors = colors.map(\.cgColor) } }
    var locations: [NSNumber] = [] { didSet { gradient.locations = locations } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
