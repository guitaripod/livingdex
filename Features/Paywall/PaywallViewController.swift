import Combine
import MidgarCommerce
import MidgarCore
import UIKit

/// Living Dex Pro's paywall — the naturalist's field companion tier, in the dark illustrated look of the first run.
/// Shown at the end of the first run, from the Profile "Identifications" row, the Field credits meter, a growing Dex
/// and the credits-exhausted capture path. The card fan and what Pro changes on top, selectable plan cards where the
/// billed price dominates, the annual default-selected, a single dynamic CTA pinned with its price line, honest live
/// pricing with a loading/unavailable state, and Restore in the bar and the footer.
///
/// EDITORIAL INVARIANT: this sells exactly what Pro does — unlimited identifications.
/// Browsing the Dex, field entries and Nearby stay free
/// and are named as such here, and a non-subscriber can always buy consumable credit packs
/// instead (the secondary link) rather than subscribe.
final class PaywallViewController: UIViewController {
    /// Fired once when the paywall leaves the screen via any dismissal path.
    var onDidDismiss: (@MainActor () -> Void)?

    /// How many more credits the refused identification needed, which the credit store shows as its banner, or nil when
    /// the player opened the paywall themselves.
    let shortfall: Int?

    private let access: ProAccess
    private let reason: String
    private let fixedPlans: [PaywallPlan]?
    private let placement: MidgarSignal.Placement
    private var hasNotedShown = false
    private var cancellables = Set<AnyCancellable>()

    private let scrollView = UIScrollView()
    private static let columnWidth: CGFloat = 560
    private let cardsStack = UIStackView()
    private let ctaButton = UIButton(configuration: {
        var config = UIButton.Configuration.borderedProminent()
        config.baseBackgroundColor = DesignSystem.Color.accent
        config.baseForegroundColor = .black
        config.cornerStyle = .large
        config.buttonSize = .large
        config.title = String(localized: "Go Pro")
        return config
    }())
    private let trialNoteLabel = UILabel()
    private lazy var hero = PaywallHeroView(reason: reason)
    private var cards: [PaywallPlanCard] = []
    private var plans: [PaywallPlan] = []
    private var selectedIndex = 0
    private var isPurchasing = false
    private var isRestoring = false
    private lazy var restoreBarItem = UIBarButtonItem(
        primaryAction: UIAction(title: String(localized: "Restore"), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            self?.restore()
        })

    init(
        access: ProAccess = .shared,
        reason: String = PaywallPresenter.defaultReason,
        shortfall: Int? = nil,
        fixedPlans: [PaywallPlan]? = nil,
        placement: MidgarSignal.Placement = .feature
    ) {
        self.access = access
        self.reason = reason
        self.shortfall = shortfall
        self.fixedPlans = fixedPlans
        self.placement = placement
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hero.playEntrance()
        noteShownOnce()
    }

    /// Reports the paywall once per presentation, not again when a sheet over it closes.
    private func noteShownOnce() {
        guard !hasNotedShown else { return }
        hasNotedShown = true
        MidgarPaywallMoments.noteShown(placement: placement)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = OnboardingStyle.ink
        navigationItem.title = nil
        navigationItem.backButtonTitle = "Living Dex Pro"
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        navigationItem.standardAppearance = bar
        navigationItem.scrollEdgeAppearance = bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismissPaywall() })
        restoreBarItem.accessibilityHint = String(localized: "Restores a previous Living Dex Pro purchase on this Apple ID")
        navigationItem.rightBarButtonItem = restoreBarItem

        layoutContent()
        bind()
        loadPlans()
        MidgarLog.info("paywall shown reason=\(reason)", category: .credits)
    }

    /// The illustrated backdrop of the first run, a scrolling column (the hero, the plans and the fine print) and,
    /// pinned beneath it, the purchase bar, so the button and its price line are on screen at every scroll position.
    private func layoutContent() {
        let backdrop = OnboardingBackdropView()
        view.addSubview(backdrop)
        backdrop.pinEdges(to: view)
        backdrop.show(art: "realm-animals", animated: false)

        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        cardsStack.axis = .vertical
        cardsStack.alignment = .fill
        cardsStack.spacing = DesignSystem.Spacing.s

        let column = UIStackView(arrangedSubviews: [
            hero,
            cardsStack,
            makeFreeCoreNote(),
            makeAutoRenewDisclosure(),
            makeCreditsLink(),
            makeLegalFooter(),
        ])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = DesignSystem.Spacing.m
        column.setCustomSpacing(DesignSystem.Spacing.l, after: hero)
        scrollView.addSubview(column)

        let purchaseBar = makePurchaseBar()
        view.addSubview(purchaseBar)

        _ = ScrollColumn(
            content: column, in: scrollView, of: view, margin: DesignSystem.Spacing.l,
            maxWidth: Self.columnWidth, top: DesignSystem.Spacing.s, bottom: DesignSystem.Spacing.l)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: purchaseBar.topAnchor),
            purchaseBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            purchaseBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            purchaseBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// The button and the price line it commits to, over a fade into the ink so the column scrolls out beneath it.
    private func makePurchaseBar() -> UIView {
        ctaButton.addTarget(self, action: #selector(didTapCTA), for: .touchUpInside)
        ctaButton.titleLabel?.adjustsFontForContentSizeCategory = true
        ctaButton.configuration?.cornerStyle = .capsule
        ctaButton.configuration?.baseBackgroundColor = OnboardingStyle.accent
        ctaButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = OnboardingStyle.font(.headline, weight: .bold)
            return attributes
        }

        trialNoteLabel.font = OnboardingStyle.font(.footnote)
        trialNoteLabel.adjustsFontForContentSizeCategory = true
        trialNoteLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        trialNoteLabel.numberOfLines = 0
        trialNoteLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [ctaButton, trialNoteLabel])
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false

        let bar = PurchaseBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        let width = stack.widthAnchor.constraint(equalTo: bar.widthAnchor, constant: -DesignSystem.Spacing.l * 2)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: DesignSystem.Spacing.m),
            stack.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: Self.columnWidth),
            width,
            stack.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.s),
        ])
        return bar
    }

    /// The reassurance beside the price: what stays free, and the free allowance every device starts with.
    private func makeFreeCoreNote() -> UIView {
        let label = OnboardingStyle.label(
            String(localized: "Your Dex, Nearby and field entries stay free. Every device starts with 30 free identifications, and everything you catch stays yours."),
            style: .footnote, color: UIColor.white.withAlphaComponent(0.6), alignment: .center)
        return label
    }

    /// Loads the plans from StoreKit. A failure, or a store that sells none, is the honest unavailable state with a
    /// retry, unless plans were already shown, which stay: a refresh failure never discards store-sourced prices.
    private func loadPlans() {
        if let fixedPlans {
            render(.loaded(fixedPlans))
            return
        }
        if plans.isEmpty { render(.loading) }
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await self.access.plans()
                self.render(loaded.isEmpty ? .unavailable : .loaded(loaded))
            } catch {
                MidgarLog.notice("subscription plans load failed: \(error)", category: .credits)
                if self.plans.isEmpty { self.render(.unavailable) }
            }
        }
    }

    private func bind() {
        access.entitlementPublisher
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
        // A re-emission of the same plans (e.g. a foreground-triggered reload)
        // must not wipe the user's current selection back to annual.
        guard plans != self.plans else { return }
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
            ctaButton.configuration?.title = String(localized: "Go Pro")
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
        if let days = plan.trialDays { return String(localized: "Start \(days)-day free trial") }
        return String(localized: "Go Pro")
    }

    private func trialNote(for plan: PaywallPlan) -> String {
        switch plan.billing {
        case .annual where plan.trialDays != nil:
            return String(localized: "No payment due now. \(plan.trialDays!) days free, then \(plan.displayPrice)/year. Cancel anytime.")
        case .annual:
            return String(localized: "\(plan.displayPrice)/year, billed annually. Cancel anytime.")
        case .monthly where plan.trialDays != nil:
            return String(localized: "No payment due now. \(plan.trialDays!) days free, then \(plan.displayPrice)/month. Cancel anytime.")
        case .monthly:
            return String(localized: "\(plan.displayPrice)/month. Cancel anytime.")
        }
    }

    private func makeAutoRenewDisclosure() -> UIView {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = String(localized: "Subscriptions auto-renew unless cancelled at least 24h before the period ends. Manage in your Apple ID settings.")
        return label
    }

    /// The secondary path: a non-subscriber who would rather pay per-use can buy consumable
    /// cloud-ID credit packs instead of subscribing.
    private func makeCreditsLink() -> UIView {
        let button = UIButton(type: .system)
        button.setTitle(String(localized: "Prefer to pay per use? Buy identification credits"), for: .normal)
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
        guard let store = CreditStoreSheet.makeController(credits: .shared, shortfall: shortfall) else { return }
        present(store, animated: true)
    }

    private func makeLegalFooter() -> UIView {
        let links = UIStackView()
        links.axis = .horizontal
        links.alignment = .center
        links.distribution = .fillEqually
        for (title, url) in [
            (String(localized: "Terms"), LegalLinks.terms.absoluteString),
            (String(localized: "Privacy"), LegalLinks.privacy.absoluteString),
            (String(localized: "Restore"), ""),
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
            do {
                let result = try await self.access.purchase(plan.product, in: self.view.window?.windowScene)
                self.setPurchasing(false)
                if PaywallPurchaseEffect.of(result) == .waitForApproval {
                    self.presentAlert(
                        String(localized: "Waiting for approval"),
                        message: String(localized: "Your purchase is waiting for approval. Living Dex Pro unlocks by itself once it is approved."))
                }
            } catch {
                self.setPurchasing(false)
                MidgarLog.error("purchase failed \(plan.product.rawValue): \(error)", category: .credits)
                ReviewPrompt.notePurchaseFailure()
                self.presentAlert(
                    String(localized: "Purchase didn't complete"),
                    message: String(localized: "You were not charged. Check your connection and try again."))
            }
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        setRestoring(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.access.restore()
                self.setRestoring(false)
                guard !self.access.isPro else { return }
                self.presentAlert(
                    String(localized: "Nothing to restore"),
                    message: String(localized: "No active Living Dex Pro purchase was found on this Apple ID. If you subscribed on another device, sign in with the same Apple ID and try again."))
            } catch {
                self.setRestoring(false)
                MidgarLog.error("restore failed: \(error)", category: .credits)
                self.presentAlert(
                    String(localized: "Couldn't reach the App Store"),
                    message: String(localized: "Check your connection and try again."))
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
        message.text = String(localized: "Pricing unavailable — check your connection.")

        let retry = UIButton(type: .system)
        retry.setTitle(String(localized: "Retry"), for: .normal)
        retry.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        retry.titleLabel?.adjustsFontForContentSizeCategory = true
        retry.tintColor = DesignSystem.Color.accent
        retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        retry.accessibilityHint = String(localized: "Loads Living Dex Pro pricing from the App Store again")
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

    private func retryLoadPlans() {
        MidgarLog.info("paywall pricing retry", category: .credits)
        loadPlans()
    }

    private func presentAlert(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            self?.presentAlert(String(localized: "Couldn't open link"), message: String(localized: "Please try again in a moment."))
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

/// The pinned purchase bar's ground: the ink fading in over the column that scrolls beneath it.
private final class PurchaseBarView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [
            OnboardingStyle.ink.withAlphaComponent(0).cgColor,
            OnboardingStyle.ink.withAlphaComponent(0.94).cgColor,
            OnboardingStyle.ink.cgColor,
        ]
        gradient.locations = [0, 0.22, 1]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
