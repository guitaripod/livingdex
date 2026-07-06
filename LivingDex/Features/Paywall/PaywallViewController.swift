import Combine
import UIKit
import SwiftUI
import AICreditsUI

/// Living Dex Pro's paywall — the naturalist's field companion tier. Shown from the
/// Profile "Cloud IDs" row and from the credits-exhausted capture path. Selectable plan
/// cards where the billed price dominates, the annual default-selected, a single dynamic
/// CTA, honest live pricing with a loading/unavailable state, and Restore / Terms /
/// Privacy in the first screenful.
///
/// EDITORIAL INVARIANT: this sells the *upside* — unlimited Claude cloud identifications
/// and the future "ask the creature" Q&A. On-device identification and narration stay free
/// and are named as such here, and a non-subscriber can always buy consumable credit packs
/// instead (the secondary link) rather than subscribe.
final class PaywallViewController: UIViewController {
    /// Fired once when the paywall leaves the screen via any dismissal path.
    var onDidDismiss: (@MainActor () -> Void)?

    private let service: SubscriptionService
    private let reason: String
    private var cancellables = Set<AnyCancellable>()

    private let scrollView = UIScrollView()
    private let cardsStack = UIStackView()
    private let ctaButton = UIButton(configuration: {
        var config = UIButton.Configuration.borderedProminent()
        config.baseBackgroundColor = DesignSystem.Color.accent
        config.baseForegroundColor = .black
        config.cornerStyle = .large
        config.buttonSize = .large
        config.title = "Subscribe"
        return config
    }())
    private let trialNoteLabel = UILabel()
    private var cards: [PaywallPlanCard] = []
    private var plans: [PaywallPlan] = []
    private var selectedIndex = 0
    private var isPurchasing = false
    private var isRestoring = false
    private lazy var restoreBarItem = UIBarButtonItem(
        title: "Restore",
        primaryAction: UIAction { [weak self] _ in self?.restore() })

    init(
        service: SubscriptionService = .shared,
        reason: String = "Identify without limits, anywhere life turns up."
    ) {
        self.service = service
        self.reason = reason
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Living Dex Pro"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismissPaywall() })
        restoreBarItem.accessibilityHint = "Restores a previous Living Dex Pro purchase on this Apple ID"
        navigationItem.rightBarButtonItem = restoreBarItem

        layoutContent()
        bind()
        Task { await service.loadPlans() }
        AppLogger.shared.info("paywall shown reason=\(reason)", category: .credits)
    }

    private func layoutContent() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        cardsStack.axis = .vertical
        cardsStack.alignment = .fill
        cardsStack.spacing = DesignSystem.Spacing.s

        ctaButton.addTarget(self, action: #selector(didTapCTA), for: .touchUpInside)
        ctaButton.titleLabel?.adjustsFontForContentSizeCategory = true

        trialNoteLabel.font = .preferredFont(forTextStyle: .footnote)
        trialNoteLabel.adjustsFontForContentSizeCategory = true
        trialNoteLabel.textColor = .secondaryLabel
        trialNoteLabel.numberOfLines = 0
        trialNoteLabel.textAlignment = .center

        let column = UIStackView(arrangedSubviews: [
            makeHeader(),
            makeBenefits(),
            makeFreeCoreNote(),
            cardsStack,
            ctaButton,
            trialNoteLabel,
            makeAutoRenewDisclosure(),
            makeCreditsLink(),
            makeLegalFooter(),
        ])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = DesignSystem.Spacing.l
        column.setCustomSpacing(DesignSystem.Spacing.m, after: cardsStack)
        column.setCustomSpacing(DesignSystem.Spacing.m, after: ctaButton)
        column.setCustomSpacing(DesignSystem.Spacing.s, after: trialNoteLabel)
        column.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(column)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            column.topAnchor.constraint(equalTo: content.topAnchor, constant: DesignSystem.Spacing.l),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -DesignSystem.Spacing.l),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DesignSystem.Spacing.l),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -DesignSystem.Spacing.l),
            column.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -2 * DesignSystem.Spacing.l),
        ])
    }

    private func makeHeader() -> UIView {
        let eyebrow = UILabel()
        eyebrow.font = .preferredFont(forTextStyle: .caption1)
        eyebrow.adjustsFontForContentSizeCategory = true
        eyebrow.textColor = DesignSystem.Color.accent
        eyebrow.attributedText = NSAttributedString(string: "LIVING DEX PRO", attributes: [.kern: 1.4])

        let title = UILabel()
        title.font = {
            let base = UIFont.preferredFont(forTextStyle: .largeTitle)
            let d = base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
            return UIFont(descriptor: d, size: 0)
        }()
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .label
        title.numberOfLines = 0
        title.text = "Unlimited cloud identifications."

        let subtitle = UILabel()
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        subtitle.text = "\(reason) Pro lifts the cloud-ID cap so every tricky find gets Claude's best guess — no credits to count, no meter to watch."

        let stack = UIStackView(arrangedSubviews: [eyebrow, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = DesignSystem.Spacing.s
        return stack
    }

    private func makeBenefits() -> UIView {
        let rows: [(String, String, String)] = [
            ("sparkles", "Unlimited Claude cloud IDs",
             "Point at anything alive and get a confident cloud identification, as often as you like — no credit balance to top up."),
            ("bubble.left.and.text.bubble.right.fill", "Ask the creature (coming soon)",
             "Follow up on any catch — habitat, diet, how to tell it apart from look-alikes — answered from a grounded field library."),
            ("bolt.badge.clock.fill", "Priority cloud lookups",
             "Your identifications skip the metered queue non-subscribers share, so hard finds resolve fast."),
        ]
        let stack = UIStackView(arrangedSubviews: rows.map(benefitRow))
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = DesignSystem.Spacing.m
        return stack
    }

    private func benefitRow(symbol: String, title: String, detail: String) -> UIView {
        let glyph = UIImageView(image: UIImage(systemName: symbol))
        glyph.tintColor = DesignSystem.Color.accent
        glyph.contentMode = .scaleAspectFit
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        glyph.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let titleLabel = UILabel()
        titleLabel.font = .preferredFont(forTextStyle: .callout)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.text = title

        let detailLabel = UILabel()
        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.text = detail

        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.alignment = .leading
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [glyph, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DesignSystem.Spacing.m
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(title). \(detail)"
        return row
    }

    private func makeFreeCoreNote() -> UIView {
        let glyph = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
        glyph.tintColor = DesignSystem.Color.accent
        glyph.contentMode = .scaleAspectFit
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        glyph.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = "On-device identification and every Pokédex narration stay free, forever. Pro is the cloud upside — not a gate on catching."

        let row = UIStackView(arrangedSubviews: [glyph, label])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DesignSystem.Spacing.s
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: DesignSystem.Spacing.m, left: DesignSystem.Spacing.m,
            bottom: DesignSystem.Spacing.m, right: DesignSystem.Spacing.m)
        row.isAccessibilityElement = true
        row.accessibilityLabel = label.text

        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = DesignSystem.Radius.control
        container.layer.cornerCurve = .continuous
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    private func bind() {
        service.plansPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.render(state) }
            .store(in: &cancellables)

        service.entitlementPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPro in
                guard isPro else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self?.dismissPaywall()
            }
            .store(in: &cancellables)
    }

    private func render(_ state: PaywallPlansState) {
        switch state {
        case .loading: renderLoading()
        case .unavailable: renderUnavailable()
        case .loaded(let plans): renderLoaded(plans)
        }
    }

    private func renderLoaded(_ plans: [PaywallPlan]) {
        self.plans = plans
        selectedIndex = plans.firstIndex { $0.billing == .annual } ?? 0
        cards = plans.enumerated().map { index, plan in
            let card = PaywallPlanCard(plan: plan)
            card.isSelected = index == selectedIndex
            card.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            return card
        }
        replaceCardRows(with: cards)
        updateCTA()
    }

    private func renderLoading() {
        plans = []
        cards = []
        replaceCardRows(with: [PaywallPlanSkeletonCard(), PaywallPlanSkeletonCard()])
        updateCTA()
    }

    /// The honest no-pricing state: when live offerings cannot be loaded the paywall says
    /// so and offers a retry instead of substituting a fabricated price.
    private func renderUnavailable() {
        plans = []
        cards = []
        replaceCardRows(with: [makePricingUnavailableCard()])
        updateCTA()
    }

    private func replaceCardRows(with views: [UIView]) {
        cardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach(cardsStack.addArrangedSubview)
    }

    private func select(_ index: Int) {
        guard index != selectedIndex, plans.indices.contains(index) else { return }
        selectedIndex = index
        Haptics.tap()
        for (i, card) in cards.enumerated() { card.isSelected = (i == index) }
        updateCTA()
    }

    private func updateCTA() {
        guard plans.indices.contains(selectedIndex) else {
            ctaButton.configuration?.title = "Subscribe"
            ctaButton.isEnabled = false
            trialNoteLabel.text = nil
            return
        }
        ctaButton.isEnabled = !isPurchasing
        let plan = plans[selectedIndex]
        ctaButton.configuration?.title = ctaTitle(for: plan)
        trialNoteLabel.text = trialNote(for: plan)
    }

    private func ctaTitle(for plan: PaywallPlan) -> String {
        if let days = plan.trialDays { return "Start \(days)-day free trial" }
        return "Subscribe"
    }

    private func trialNote(for plan: PaywallPlan) -> String {
        switch plan.billing {
        case .annual where plan.trialDays != nil:
            return "No payment due now. \(plan.trialDays!) days free, then \(plan.displayPrice)/year. Cancel anytime."
        case .annual:
            return "\(plan.displayPrice)/year, billed annually. Cancel anytime."
        case .monthly where plan.trialDays != nil:
            return "No payment due now. \(plan.trialDays!) days free, then \(plan.displayPrice)/month. Cancel anytime."
        case .monthly:
            return "\(plan.displayPrice)/month. Cancel anytime."
        }
    }

    private func makeAutoRenewDisclosure() -> UIView {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = "Subscriptions auto-renew unless cancelled at least 24h before the period ends. Manage in your Apple ID settings."
        return label
    }

    /// The secondary path: a non-subscriber who would rather pay per-use can buy consumable
    /// cloud-ID credit packs instead of subscribing.
    private func makeCreditsLink() -> UIView {
        let button = UIButton(type: .system)
        button.setTitle("Prefer to pay per use? Buy cloud-ID credits", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.tintColor = DesignSystem.Color.accent
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.presentCreditStore() }, for: .touchUpInside)
        return button
    }

    private func presentCreditStore() {
        let store = AICreditsManager.store
        let host = UIHostingController(rootView: CreditStoreView().environmentObject(store))
        present(host, animated: true)
    }

    private func makeLegalFooter() -> UIView {
        let links = UIStackView()
        links.axis = .horizontal
        links.alignment = .center
        links.distribution = .fillEqually
        for (title, url) in [
            ("Terms", "https://mako.midgarcorp.cc/terms/livingdex"),
            ("Privacy", "https://mako.midgarcorp.cc/privacy/livingdex"),
            ("Restore", ""),
        ] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.tintColor = .secondaryLabel
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in
                if url.isEmpty { self?.restore() }
                else if let link = URL(string: url) { self?.open(link) }
            }, for: .touchUpInside)
            links.addArrangedSubview(button)
        }
        return links
    }

    @objc private func didTapCTA() {
        guard plans.indices.contains(selectedIndex) else { return }
        let plan = plans[selectedIndex]
        setPurchasing(true)
        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.purchase(plan)
            self.setPurchasing(false)
            guard case .failed = result else { return }
            self.presentAlert(
                "Purchase didn't complete",
                message: "You were not charged. Check your connection and try again.")
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        setRestoring(true)
        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.restore()
            self.setRestoring(false)
            switch result {
            case .restored:
                break
            case .nothingToRestore:
                self.presentAlert(
                    "Nothing to restore",
                    message: "No active Living Dex Pro purchase was found on this Apple ID. "
                        + "If you subscribed on another device, sign in with the same Apple ID and try again.")
            case .failed:
                self.presentAlert(
                    "Couldn't reach the App Store",
                    message: "Check your connection and try again.")
            }
        }
    }

    private func setRestoring(_ restoring: Bool) {
        isRestoring = restoring
        if restoring {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = DesignSystem.Color.accent
            spinner.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        } else {
            navigationItem.rightBarButtonItem = restoreBarItem
        }
    }

    private func setPurchasing(_ purchasing: Bool) {
        isPurchasing = purchasing
        ctaButton.isEnabled = !purchasing
        ctaButton.configuration?.showsActivityIndicator = purchasing
        cards.forEach { $0.isEnabled = !purchasing }
    }

    private func makePricingUnavailableCard() -> UIView {
        let glass = GlassPanel(cornerRadius: DesignSystem.Radius.card)
        glass.translatesAutoresizingMaskIntoConstraints = false

        let message = UILabel()
        message.font = .preferredFont(forTextStyle: .callout)
        message.adjustsFontForContentSizeCategory = true
        message.textColor = .secondaryLabel
        message.numberOfLines = 0
        message.textAlignment = .center
        message.text = "Pricing unavailable — check your connection."

        let retry = UIButton(type: .system)
        retry.setTitle("Retry", for: .normal)
        retry.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        retry.titleLabel?.adjustsFontForContentSizeCategory = true
        retry.tintColor = DesignSystem.Color.accent
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        retry.accessibilityHint = "Loads Living Dex Pro pricing from the App Store again"
        retry.addAction(UIAction { [weak self] _ in self?.retryLoadPlans() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [message, retry])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = DesignSystem.Spacing.s
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: DesignSystem.Spacing.m, left: DesignSystem.Spacing.l,
            bottom: DesignSystem.Spacing.m, right: DesignSystem.Spacing.l)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(glass)
        glass.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: container.topAnchor),
            glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
        ])
        return container
    }

    /// Re-runs the plans load, which also re-attempts the credits client's identity
    /// bootstrap when the first-launch registration failed.
    private func retryLoadPlans() {
        AppLogger.shared.info("paywall pricing retry", category: .credits)
        Task { [weak self] in await self?.service.loadPlans() }
    }

    private func presentAlert(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            self?.presentAlert("Couldn't open link", message: "Please try again in a moment.")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || navigationController?.isBeingDismissed == true else { return }
        onDidDismiss?()
        onDidDismiss = nil
    }

    /// Dismisses the whole paywall stack from the presenting side — dismissing `self` would
    /// swallow a presented alert (restore/purchase feedback) instead.
    private func dismissPaywall() {
        if let navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
        } else if let presenting = presentingViewController ?? navigationController?.presentingViewController {
            presenting.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}
