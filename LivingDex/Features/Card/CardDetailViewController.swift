import UIKit

/// The full species card, opened from the Dex. Hero image, an evocative category
/// ("the ___" epithet), rarity + realm, typical size, the narrated Pokédex entry,
/// a playable call ("cry") where a commercial-safe recording exists, and an "ask
/// the creature" entry point. Reads the species' latest sighting.
final class CardDetailViewController: UIViewController {
    private let entry: DexEntry
    private let detailService = SpeciesDetailService()
    private var call: SpeciesCall?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            primaryAction: UIAction { [weak self] _ in self?.confirmRelease() })
        buildLayout()
        fetchCall()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSighting()
    }

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: DesignSystem.Spacing.m),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.m),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.l),
        ])

        let hero = UIImageView(image: ImageStore.load(entry.bestImagePath))
        hero.contentMode = .scaleAspectFill
        hero.clipsToBounds = true
        hero.layer.cornerRadius = DesignSystem.Radius.card
        hero.layer.cornerCurve = .continuous
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.heightAnchor.constraint(equalTo: hero.widthAnchor, multiplier: 0.9).isActive = true
        stack.addArrangedSubview(hero)

        let rarity = RarityBadge()
        rarity.configure(entry.rarity)
        let rarityRow = UIStackView(arrangedSubviews: [rarity, UIView()])
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
        stack.addArrangedSubview(sizeLabel)
        setMeta(size: nil)

        stack.addArrangedSubview(divider())

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

        var config = UIButton.Configuration.borderedProminent()
        config.title = "Ask the creature"
        config.image = UIImage(systemName: "bubble.left.and.text.bubble.right")
        config.imagePadding = 8
        config.baseBackgroundColor = DesignSystem.Color.accent
        config.cornerStyle = .large
        let ask = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.presentAskPlaceholder()
        })
        stack.addArrangedSubview(ask)
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

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return line
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
                narrationLabel.text = "This creature's dex entry will appear once it's written."
                narrationLabel.textColor = .secondaryLabel
            }
            if let category = sighting?.category, !category.isEmpty {
                categoryLabel.text = "The \(category)"
                categoryLabel.isHidden = false
            }
            setMeta(size: sighting?.typicalSize)
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
        alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(alert, animated: true)
    }

    private func presentAskPlaceholder() {
        let alert = UIAlertController(
            title: "Ask the creature",
            message: "Conversational Q&A about this species is a Living Dex Pro feature — coming soon.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
