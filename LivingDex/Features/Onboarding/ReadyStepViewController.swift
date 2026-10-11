import UIKit

/// Step 4: the three ways in, the free allowance and the consent promise, then the camera.
final class ReadyStepViewController: OnboardingStepViewController {
    private let titleLabel = OnboardingStyle.label(
        "Now find your second", style: .largeTitle, weight: .heavy, size: 36)
    private let subtitle = OnboardingStyle.label(
        "Everything you catch from here is the real thing, rated by how rare it is where you are.",
        style: .callout, color: UIColor.white.withAlphaComponent(0.75))
    private lazy var openButton = OnboardingStyle.primaryButton(title: "Open the camera", symbol: "camera.fill") { [weak self] in
        Haptics.tap()
        self?.onAdvance?()
    }
    private var rows: [UIView] = []
    private var entranceDone = false

    override var artName: String { "realm-animals" }
    override var showsSkip: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.accessibilityTraits = .header

        let options: [(String, String, String)] = [
            ("camera.viewfinder", "Point the camera", "Tap the shutter at anything alive: a bird, a bug, a mushroom, a flower."),
            ("photo.on.rectangle", "Nothing in reach?", "Choose a nature photo from your library with the photo button on the Field tab."),
            ("sparkles", "Just curious?", "Try a sample photo to watch a real identification, no creature needed."),
        ]
        rows = options.map(optionRow)

        let allowance = OnboardingGlassCard(cornerRadius: 18)
        let allowanceIcon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        allowanceIcon.tintColor = OnboardingStyle.accent
        allowanceIcon.contentMode = .scaleAspectFit
        allowanceIcon.setContentHuggingPriority(.required, for: .horizontal)
        let allowanceText = OnboardingStyle.label(
            "You start with 30 free identifications. A photo is sent to cloud AI only after you say yes, and never before.",
            style: .footnote, color: UIColor.white.withAlphaComponent(0.8))
        let allowanceRow = UIStackView(arrangedSubviews: [allowanceIcon, allowanceText])
        allowanceRow.axis = .horizontal
        allowanceRow.spacing = DesignSystem.Spacing.s
        allowanceRow.alignment = .center
        allowanceRow.translatesAutoresizingMaskIntoConstraints = false
        allowance.addSubview(allowanceRow)
        allowanceRow.pinEdges(to: allowance, insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        allowanceIcon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        rows.append(allowance)

        let list = UIStackView(arrangedSubviews: [titleLabel, subtitle] + rows)
        list.axis = .vertical
        list.spacing = DesignSystem.Spacing.m
        list.setCustomSpacing(DesignSystem.Spacing.s, after: titleLabel)
        list.setCustomSpacing(DesignSystem.Spacing.l, after: subtitle)

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        openButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(list)
        view.addSubview(openButton)

        let guide = view.safeAreaLayoutGuide
        let margin = DesignSystem.Spacing.l
        let width = list.widthAnchor.constraint(equalToConstant: OnboardingStyle.maxContentWidth)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: openButton.topAnchor, constant: -DesignSystem.Spacing.m),

            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DesignSystem.Spacing.s),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.s),
            list.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            list.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: margin),
            list.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -margin),
            width,

            openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openButton.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: margin),
            openButton.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -margin),
            openButton.widthAnchor.constraint(lessThanOrEqualToConstant: OnboardingStyle.maxContentWidth),
            openButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin),
        ])
        let fill = openButton.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -margin * 2)
        fill.priority = .defaultHigh
        fill.isActive = true

        if !Motion.reduced { rows.forEach { $0.alpha = 0 } }
    }

    override func stepDidAppear() {
        guard !entranceDone else { return }
        entranceDone = true
        guard !Motion.reduced else { return }
        for (index, row) in rows.enumerated() {
            row.transform = CGAffineTransform(translationX: 0, y: 18)
            UIView.animate(
                withDuration: 0.6, delay: 0.1 + 0.1 * Double(index),
                usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3
            ) {
                row.alpha = 1
                row.transform = .identity
            }
        }
    }

    private func optionRow(_ option: (symbol: String, title: String, detail: String)) -> UIView {
        let icon = UIImageView(image: UIImage(
            systemName: option.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)))
        icon.tintColor = OnboardingStyle.accent
        icon.contentMode = .center
        icon.backgroundColor = OnboardingStyle.accent.withAlphaComponent(0.16)
        icon.layer.cornerRadius = 16
        icon.layer.cornerCurve = .continuous
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let title = OnboardingStyle.label(option.title, style: .headline, weight: .bold)
        let detail = OnboardingStyle.label(option.detail, style: .subheadline, color: UIColor.white.withAlphaComponent(0.72))
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.spacing = DesignSystem.Spacing.m
        row.alignment = .center
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(option.title). \(option.detail)"
        return row
    }
}
