import LivingDexCore
import UIKit

/// The full species card, opened from the Dex. Hero image, an evocative category
/// ("the ___" epithet), rarity + realm, typical size, the narrated Pokédex entry,
/// and a playable call ("cry") where a commercial-safe recording exists. Reads the
/// species' latest sighting.
final class CardDetailViewController: UIViewController {
    private var entry: DexEntry
    private let detailService = SpeciesDetailService()
    private let enricher = SpeciesEnricher.shared
    private let rarityBadge = RarityBadge()
    private var call: SpeciesCall?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let layoutStack = UIStackView()
    private let heroHolder = UIView()
    private var column: ScrollColumn?
    private var arrangement = AdaptiveLayout.Arrangement.stacked
    private var capsHeroHeight = false
    private lazy var heroHeightCap = hero.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: Self.heroHeightShare)
    private let hero = UIImageView()
    private let categoryLabel = UILabel()
    private let sizeLabel = UILabel()
    private let narrationLabel = UILabel()
    private let callButton = UIButton(configuration: .gray())
    private let attributionLabel = UILabel()

    init(entry: DexEntry) {
        self.entry = entry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = entry.commonName
        navigationItem.largeTitleDisplayMode = .never
        configureNavigationActions()
        buildLayout()
        fetchCall()
    }

    private func configureNavigationActions() {
        let shareItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.shareCatch() })
        shareItem.title = "Share"
        shareItem.accessibilityLabel = "Share"
        let releaseAction = UIAction(
            title: "Release",
            image: UIImage(systemName: "trash"),
            attributes: .destructive) { [weak self] _ in self?.confirmRelease() }
        let overflowItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [releaseAction]))
        overflowItem.title = "More"
        overflowItem.accessibilityLabel = "More"
        navigationItem.rightBarButtonItems = [shareItem, overflowItem]
    }

    private func shareCatch() {
        guard let photo = ImageStore.load(entry.bestImagePath) ?? hero.image else { return }
        let model = ShareCardModel(
            commonName: entry.commonName, scientificName: entry.scientificName,
            realm: entry.realm, rarity: entry.rarity, caughtAt: entry.firstCaughtAt, photo: photo)
        let share = UIActivityViewController(
            activityItems: ShareCardRenderer.shareItems(for: model), applicationActivities: nil)
        share.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(share, animated: true)
    }

    private static let heroHeightShare: CGFloat = 0.42

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        column?.centerOnWindow(safeAreaInsets: view.safeAreaInsets)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = scrollView.bounds.size
        let resolved = AdaptiveLayout.Arrangement.resolve(width: size.width, height: size.height)
        let caps = resolved == .stacked && size.width >= AdaptiveLayout.sideBySideMinimumWidth
        guard resolved != arrangement || caps != capsHeroHeight else { return }
        applyArrangement(resolved, capsHeroHeight: caps)
    }

    /// Hero beside the text across a wide landscape window, split evenly so the halves meet
    /// at the fold; stacked otherwise. A tall regular window caps the hero to the region above
    /// a horizontal fold so the text starts below it.
    private func applyArrangement(_ resolved: AdaptiveLayout.Arrangement, capsHeroHeight caps: Bool) {
        arrangement = resolved
        capsHeroHeight = caps
        let sideBySide = resolved == .sideBySide
        layoutStack.axis = sideBySide ? .horizontal : .vertical
        layoutStack.alignment = sideBySide ? .top : .fill
        layoutStack.distribution = sideBySide ? .fillEqually : .fill
        layoutStack.spacing = sideBySide ? AdaptiveLayout.foldGap : DesignSystem.Spacing.m
        column?.maxWidth.constant = sideBySide ? AdaptiveLayout.wideColumnWidth : AdaptiveLayout.readableColumnWidth
        heroHeightCap.isActive = caps
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSighting()
        healIfProvisional()
    }

    /// A capture saved while offline holds only the on-device guess for rarity.
    /// The first time its card is opened online, confirm it against GBIF and
    /// adopt the real rarity + names (or leave it if still unreachable).
    private func healIfProvisional() {
        guard !entry.enriched else { return }
        let candidate = SpeciesCandidate(
            speciesId: entry.speciesId, commonName: entry.commonName,
            scientificName: entry.scientificName, realm: entry.realm,
            rarity: entry.rarity, confidence: 1)
        Task { @MainActor in
            guard case let .resolved(e) = await enricher.enrich(candidate: candidate, context: CaptureContext()) else { return }
            let common = e.adoptedCommonName(current: entry.commonName, scientificName: entry.scientificName)
            guard let healed = try? CollectionStore.shared.healEnrichment(
                speciesId: entry.speciesId, rarity: e.rarity,
                commonName: common, scientificName: entry.scientificName) else { return }
            entry = healed
            rarityBadge.configure(healed.rarity)
            title = healed.commonName
        }
    }

    private func buildLayout() {
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.m

        layoutStack.addArrangedSubview(heroHolder)
        layoutStack.addArrangedSubview(stack)
        scrollView.addSubview(layoutStack)
        column = ScrollColumn(
            content: layoutStack, in: scrollView, of: view, margin: DesignSystem.Spacing.m,
            maxWidth: AdaptiveLayout.readableColumnWidth, top: DesignSystem.Spacing.m, bottom: DesignSystem.Spacing.l)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hero.image = ImageLoader.shared.cached(entry.bestImagePath)
        hero.contentMode = .scaleAspectFill
        hero.clipsToBounds = true
        hero.layer.cornerRadius = DesignSystem.Radius.card
        hero.layer.cornerCurve = .continuous
        hero.translatesAutoresizingMaskIntoConstraints = false
        heroHolder.addSubview(hero)
        let aspect = hero.heightAnchor.constraint(equalTo: hero.widthAnchor, multiplier: 0.9)
        aspect.priority = UILayoutPriority(rawValue: 999)
        NSLayoutConstraint.activate([
            hero.topAnchor.constraint(equalTo: heroHolder.topAnchor),
            hero.leadingAnchor.constraint(equalTo: heroHolder.leadingAnchor),
            hero.trailingAnchor.constraint(equalTo: heroHolder.trailingAnchor),
            hero.bottomAnchor.constraint(equalTo: heroHolder.bottomAnchor),
            aspect,
        ])
        if hero.image == nil {
            ImageLoader.shared.load(entry.bestImagePath) { [weak self] image in self?.hero.image = image }
        }
        applyArrangement(.stacked, capsHeroHeight: false)

        rarityBadge.configure(entry.rarity)
        let rarityRow = UIStackView(arrangedSubviews: [rarityBadge, UIView()])
        rarityRow.axis = .horizontal
        stack.addArrangedSubview(rarityRow)

        // Evocative category ("the ___") — hidden until narrated.
        categoryLabel.font = .systemFont(ofSize: 17, weight: .bold)
        categoryLabel.textColor = DesignSystem.Color.accent
        categoryLabel.adjustsFontForContentSizeCategory = true
        categoryLabel.isHidden = true
        stack.addArrangedSubview(categoryLabel)
        stack.setCustomSpacing(4, after: categoryLabel)

        let sciBase = UIFont.preferredFont(forTextStyle: .callout)
        let sciFont = UIFont(descriptor: sciBase.fontDescriptor.withSymbolicTraits(.traitItalic) ?? sciBase.fontDescriptor, size: 0)
        stack.addArrangedSubview(makeLabel(entry.scientificName, font: sciFont, color: .secondaryLabel))

        sizeLabel.font = .preferredFont(forTextStyle: .footnote)
        sizeLabel.adjustsFontForContentSizeCategory = true
        sizeLabel.textColor = .tertiaryLabel
        sizeLabel.numberOfLines = 0
        stack.addArrangedSubview(sizeLabel)
        setMeta(size: nil)

        stack.addArrangedSubview(HairlineView())

        narrationLabel.font = .preferredFont(forTextStyle: .body)
        narrationLabel.adjustsFontForContentSizeCategory = true
        narrationLabel.textColor = .label
        narrationLabel.numberOfLines = 0
        narrationLabel.text = "Writing this creature's dex entry…"
        stack.addArrangedSubview(narrationLabel)

        // Call ("cry") — hidden until a safe recording is found.
        var callConfig = UIButton.Configuration.tinted()
        callConfig.title = "Play call"
        callConfig.image = UIImage(systemName: "speaker.wave.2.fill")
        callConfig.imagePadding = 8
        callConfig.baseForegroundColor = DesignSystem.Color.accent
        callConfig.baseBackgroundColor = DesignSystem.Color.accent
        callConfig.cornerStyle = .large
        callButton.configuration = callConfig
        callButton.addAction(UIAction { [weak self] _ in self?.playCall() }, for: .touchUpInside)
        callButton.isHidden = true
        stack.addArrangedSubview(callButton)

        attributionLabel.font = .preferredFont(forTextStyle: .caption2)
        attributionLabel.textColor = .tertiaryLabel
        attributionLabel.numberOfLines = 0
        attributionLabel.isHidden = true
        stack.addArrangedSubview(attributionLabel)
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func setMeta(size: String?) {
        var parts = ["\(entry.realm.rawValue.capitalized)", "caught ×\(entry.sightingCount)"]
        if let size, !size.isEmpty { parts.insert(size, at: 1) }
        sizeLabel.text = parts.joined(separator: "  ·  ")
    }

    private func loadSighting() {
        let speciesId = entry.speciesId
        Task { @MainActor in
            let sighting = try? CollectionStore.shared.latestSighting(speciesId: speciesId)
            if let text = sighting?.pokedexEntry, !text.isEmpty {
                narrationLabel.text = text
                narrationLabel.textColor = .label
            } else {
                narrationLabel.text = "No field entry is available for this species yet."
                narrationLabel.textColor = .secondaryLabel
                if let sighting { fillMissingEntry(for: sighting) }
            }
            if let category = sighting?.category, !category.isEmpty {
                categoryLabel.text = "The \(category)"
                categoryLabel.isHidden = false
            }
            setMeta(size: sighting?.typicalSize)
        }
    }

    /// A catch made offline, or on a phone without on-device AI, can reach its card with no
    /// entry written. Once the Worker answers, the sourced summary fills the gap — free,
    /// and only when there is nothing there yet.
    private func fillMissingEntry(for sighting: Sighting) {
        let candidate = SpeciesCandidate(
            speciesId: entry.speciesId, commonName: entry.commonName,
            scientificName: entry.scientificName, realm: entry.realm,
            rarity: entry.rarity, confidence: 1)
        Task { @MainActor in
            guard case let .resolved(enrichment) = await enricher.enrich(candidate: candidate, context: CaptureContext()),
                  let filled = NarratorService.groundedEntry(enrichment.summary),
                  (try? CollectionStore.shared.setNarration(sightingId: sighting.id, entry: filled)) != nil
            else { return }
            narrationLabel.text = filled.displayText
            narrationLabel.textColor = .label
        }
    }

    private func fetchCall() {
        let name = entry.scientificName
        Task { @MainActor in
            guard let call = await detailService.call(scientificName: name) else { return }
            self.call = call
            callButton.isHidden = false
            attributionLabel.text = "Call: \(call.attribution)"
            attributionLabel.isHidden = false
        }
    }

    private func playCall() {
        guard let call else { return }
        Haptics.tap()
        detailService.play(call)
    }

    private func confirmRelease() {
        let alert = UIAlertController(
            title: "Release \(entry.commonName)?",
            message: "This removes it from your dex, along with your photos of it. This can't be undone.",
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Release", style: .destructive) { [weak self] _ in
            guard let self else { return }
            try? CollectionStore.shared.release(speciesId: self.entry.speciesId)
            Haptics.tap()
            self.navigationController?.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(alert, animated: true)
    }

}
