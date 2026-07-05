import UIKit

/// The full species card, opened from the Dex grid. Shows the hero image, names,
/// rarity + realm, the Claude-authored Pokédex entry (if narrated yet), capture
/// metadata, and an "ask the creature" entry point (Pro). Reads the species'
/// latest sighting for image + narration + geo/elevation.
final class CardDetailViewController: UIViewController {
    private let entry: DexEntry
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let narrationLabel = UILabel()

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
        buildLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-read on each appearance: the Claude entry fills in the background
        // after capture, so returning to this screen surfaces it once written.
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

        let sciBase = UIFont.preferredFont(forTextStyle: .callout)
        let sciFont = UIFont(descriptor: sciBase.fontDescriptor.withSymbolicTraits(.traitItalic) ?? sciBase.fontDescriptor, size: 0)
        stack.addArrangedSubview(titleLabel(entry.scientificName, font: sciFont, color: .secondaryLabel))
        stack.addArrangedSubview(titleLabel(
            "\(entry.realm.rawValue.capitalized) · caught ×\(entry.sightingCount)",
            font: .preferredFont(forTextStyle: .footnote), color: .tertiaryLabel))

        narrationLabel.font = .preferredFont(forTextStyle: .body)
        narrationLabel.adjustsFontForContentSizeCategory = true
        narrationLabel.textColor = .label
        narrationLabel.numberOfLines = 0
        narrationLabel.text = "Writing this creature's dex entry…"
        stack.addArrangedSubview(narrationLabel)

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

    private func titleLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func loadSighting() {
        let speciesId = entry.speciesId
        Task { @MainActor in
            let sighting = try? CollectionStore.shared.latestSighting(speciesId: speciesId)
            if let text = sighting?.pokedexEntry, !text.isEmpty {
                narrationLabel.text = text
            } else {
                narrationLabel.text = "This creature's dex entry will appear once it's written."
                narrationLabel.textColor = .secondaryLabel
            }
        }
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
