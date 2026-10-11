import UIKit

/// Asks, once and in plain language, before the first photo leaves the device for
/// cloud identification. Declining keeps the photo on the device and the player in
/// the app; the question simply returns on the next identification.
final class CloudConsentViewController: UIViewController {
    var onDecision: ((Bool) -> Void)?

    private var didDecide = false
    private var allowed = false
    private let contentStack = UIStackView()
    private let buttonStack = UIStackView()

    private struct Point {
        let symbol: String
        let text: String
    }

    private let points: [Point] = [
        .init(symbol: "lock.fill", text: "Sent over an encrypted connection, and only when you identify. Nothing uploads in the background."),
        .init(symbol: "person.crop.circle.badge.xmark", text: "No sign-up needed. Your photos are never shown to other players."),
        .init(symbol: "trash", text: "Delete your account and everything stored about you at any time in Settings."),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLayout()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        decide(allowed)
    }

    private func buildLayout() {
        let icon = UIImageView(image: UIImage(
            systemName: "sparkle.magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .center
        icon.backgroundColor = DesignSystem.Color.accent.withAlphaComponent(0.14)
        icon.layer.cornerRadius = 36
        icon.layer.cornerCurve = .continuous
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        icon.isAccessibilityElement = false

        let title = UILabel()
        title.text = "Identify with cloud AI"
        title.font = Self.font(.title2, weight: .bold)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.numberOfLines = 0
        title.accessibilityTraits = .header

        let body = UILabel()
        body.text = "To name what you point at, Living Dex sends your photo to a cloud AI service (Google Gemini, through our server) that finds the species. That is the only thing it is used for."
        body.font = .preferredFont(forTextStyle: .callout)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = .secondaryLabel
        body.textAlignment = .center
        body.numberOfLines = 0

        let pointsStack = UIStackView(arrangedSubviews: points.map(pointRow))
        pointsStack.axis = .vertical
        pointsStack.spacing = DesignSystem.Spacing.m

        let iconRow = UIStackView(arrangedSubviews: [UIView(), icon, UIView()])
        iconRow.distribution = .equalCentering

        let content = contentStack
        [iconRow, title, body, pointsStack].forEach(content.addArrangedSubview)
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = DesignSystem.Spacing.m
        content.setCustomSpacing(DesignSystem.Spacing.l, after: body)
        content.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        scroll.addSubview(content)

        var allow = UIButton.Configuration.borderedProminent()
        allow.title = "Allow & identify"
        allow.baseBackgroundColor = DesignSystem.Color.accent
        allow.baseForegroundColor = .black
        allow.cornerStyle = .large
        allow.buttonSize = .large
        let allowButton = UIButton(configuration: allow, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.allowed = true
            self?.dismiss(animated: true)
        })

        var decline = UIButton.Configuration.plain()
        decline.title = "Not now"
        decline.baseForegroundColor = .secondaryLabel
        let declineButton = UIButton(configuration: decline, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })

        var policy = UIButton.Configuration.plain()
        policy.title = "Read the Privacy Policy"
        policy.baseForegroundColor = DesignSystem.Color.accent
        policy.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .footnote)
            return attributes
        }
        let policyButton = UIButton(configuration: policy, primaryAction: UIAction { _ in
            UIApplication.shared.open(LegalLinks.privacy)
        })

        let buttons = buttonStack
        [allowButton, declineButton, policyButton].forEach(buttons.addArrangedSubview)
        buttons.axis = .vertical
        buttons.spacing = 2
        buttons.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scroll)
        view.addSubview(buttons)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -DesignSystem.Spacing.s),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DesignSystem.Spacing.l + 4),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: DesignSystem.Spacing.l),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -DesignSystem.Spacing.l),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.m),

            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.l),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.l),
            buttons.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.s),
        ])
    }

    /// The sheet height that shows everything without scrolling at the current text size.
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        loadViewIfNeeded()
        let fit = CGSize(width: width - DesignSystem.Spacing.l * 2, height: UIView.layoutFittingCompressedSize.height)
        func height(of stack: UIStackView) -> CGFloat {
            stack.systemLayoutSizeFitting(
                fit, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        }
        return height(of: contentStack) + height(of: buttonStack) + 112
    }

    private func pointRow(_ point: Point) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: point.symbol))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let label = UILabel()
        label.text = point.text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = DesignSystem.Spacing.m
        row.alignment = .top
        row.isAccessibilityElement = true
        row.accessibilityLabel = point.text
        return row
    }

    private func decide(_ allowed: Bool) {
        guard !didDecide else { return }
        didDecide = true
        onDecision?(allowed)
    }

    private static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// The consent gate in front of every cloud identification.
enum CloudConsent {
    /// Runs `proceed` immediately when consent was already given; otherwise asks first
    /// and runs it only on "Allow".
    @MainActor
    static func ensure(from presenter: UIViewController, then proceed: @escaping () -> Void) {
        guard !AppSettings.hasAcceptedCloudAI else {
            proceed()
            return
        }
        request(from: presenter) { granted in
            if granted { proceed() }
        }
    }

    /// Always shows the consent sheet; on "Allow" records consent. Reports the decision once
    /// the sheet is gone, so a follow-up presentation never collides with it.
    @MainActor
    static func request(from presenter: UIViewController, completion: @escaping (Bool) -> Void) {
        let sheet = CloudConsentViewController()
        sheet.onDecision = { allowed in
            if allowed {
                AppSettings.hasAcceptedCloudAI = true
                AppLogger.shared.info("cloud AI consent granted", category: .app)
            }
            completion(allowed)
        }
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            let width = presenter.view.bounds.width
            presentation.detents = [
                .custom { [weak sheet] context in
                    min(context.maximumDetentValue, sheet?.preferredHeight(forWidth: width) ?? context.maximumDetentValue)
                },
                .large(),
            ]
            presentation.prefersGrabberVisible = true
        }
        presenter.present(sheet, animated: true)
    }
}
