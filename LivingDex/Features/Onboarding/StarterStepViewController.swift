import UIKit

/// Step 2: choose a starter. A paging carousel of four real species; the centred card is the choice
/// and the button names it. Confirming runs the viewfinder, mints the catch and shows the real reveal.
final class StarterStepViewController: OnboardingStepViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private let starterCatch: StarterCatch
    private let starters = StarterCatalog.all
    private let titleLabel = OnboardingStyle.label(
        "Choose your starter", style: .largeTitle, weight: .heavy, size: 36)
    private let subtitle = OnboardingStyle.label(
        "Every Dex begins with one real species. Swipe, then pick the one that calls to you.",
        style: .callout, color: UIColor.white.withAlphaComponent(0.75))
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var chooseButton = OnboardingStyle.primaryButton(title: "", symbol: "scope") { [weak self] in
        self?.confirm()
    }
    private let header = UIStackView()

    private var centeredIndex = 0
    private var isMinting = false
    private var enrichments: [String: SpeciesEnrichment] = [:]
    private var compactConstraints: [NSLayoutConstraint] = []
    private var wideConstraints: [NSLayoutConstraint] = []
    private var appliedWide: Bool?

    init(starterCatch: StarterCatch) {
        self.starterCatch = starterCatch
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var artName: String { "realm-fungi" }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.accessibilityTraits = .header
        header.axis = .vertical
        header.spacing = DesignSystem.Spacing.s
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(subtitle)
        header.translatesAutoresizingMaskIntoConstraints = false

        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(StarterCardCell.self, forCellWithReuseIdentifier: StarterCardCell.reuseID)
        collectionView.clipsToBounds = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        chooseButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(collectionView)
        view.addSubview(chooseButton)
        buildConstraints()
        updateButton()
        prefetchEnrichments()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let wide = isWide
        guard wide != appliedWide else { return }
        appliedWide = wide
        NSLayoutConstraint.deactivate(wide ? compactConstraints : wideConstraints)
        NSLayoutConstraint.activate(wide ? wideConstraints : compactConstraints)
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
    }

    override func stepDidAppear() {
        guard !Motion.reduced else { return }
        collectionView.alpha = 0
        collectionView.transform = CGAffineTransform(translationX: 40, y: 0)
        UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.3) {
            self.collectionView.alpha = 1
            self.collectionView.transform = .identity
        }
    }

    private func buildConstraints() {
        let guide = view.safeAreaLayoutGuide
        let margin = DesignSystem.Spacing.l
        compactConstraints = [
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: DesignSystem.Spacing.s),
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
            header.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -margin),
            collectionView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: DesignSystem.Spacing.m),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: chooseButton.topAnchor, constant: -DesignSystem.Spacing.m),
            chooseButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
            chooseButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -margin),
            chooseButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin),
        ]
        wideConstraints = [
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin * 1.5),
            header.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.42),
            chooseButton.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            chooseButton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            chooseButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin),
            collectionView.leadingAnchor.constraint(equalTo: header.trailingAnchor, constant: margin),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            collectionView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin),
        ]
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let wide = isWide
        return UICollectionViewCompositionalLayout { [weak self] _, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(
                widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(wide ? 0.62 : 0.68), heightDimension: .fractionalHeight(1)),
                subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .groupPagingCentered
            section.interGroupSpacing = 12
            section.contentInsets = .init(top: 8, leading: 0, bottom: 8, trailing: 0)
            section.visibleItemsInvalidationHandler = { items, offset, environment in
                let center = offset.x + environment.container.contentSize.width / 2
                var nearest: (index: Int, distance: CGFloat)?
                for item in items {
                    let distance = abs(item.frame.midX - center)
                    let fraction = min(1, distance / (environment.container.contentSize.width * 0.5))
                    let scale = 1 - 0.14 * fraction
                    item.transform = CGAffineTransform(scaleX: scale, y: scale)
                    item.alpha = 1 - 0.5 * fraction
                    if nearest == nil || distance < nearest!.distance { nearest = (item.indexPath.item, distance) }
                }
                if let nearest { self?.didCenter(nearest.index) }
            }
            return section
        }
    }

    private func didCenter(_ index: Int) {
        guard index != centeredIndex, !isMinting else { return }
        centeredIndex = index
        Haptics.tap()
        updateButton()
    }

    private func updateButton() {
        let starter = starters[centeredIndex]
        chooseButton.configuration?.title = "Choose \(starter.commonName)"
        chooseButton.accessibilityLabel = "Choose \(starter.commonName) as your starter"
    }

    // MARK: Collection

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { starters.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: StarterCardCell.reuseID, for: indexPath) as! StarterCardCell
        cell.configure(starters[indexPath.item]) { [weak self] in
            self?.centeredIndex = indexPath.item
            self?.updateButton()
            self?.confirm()
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isMinting else { return }
        if indexPath.item == centeredIndex {
            confirm()
        } else {
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        }
    }

    // MARK: Catch

    /// Starts grounding each starter against GBIF in the background, so the real rarity is ready by
    /// the time one is chosen; an unreachable Worker just leaves the starter Common until it heals.
    private func prefetchEnrichments() {
        for starter in starters {
            Task { @MainActor [weak self] in
                guard case let .resolved(enrichment) = await SpeciesEnricher.shared.enrich(
                    candidate: starter.candidate, context: CaptureContext()) else { return }
                self?.enrichments[starter.id] = enrichment
            }
        }
    }

    private func confirm() {
        guard !isMinting else { return }
        isMinting = true
        chooseButton.isEnabled = false
        let starter = starters[centeredIndex]
        Task { @MainActor in
            await waitForEnrichment(of: starter)
            guard let outcome = starterCatch.mint(starter, enrichment: enrichments[starter.id]) else {
                failMint()
                return
            }
            AppSettings.hasChosenStarter = true
            state.chosenStarter = starter
            await playViewfinder(for: starter, image: outcome.image)
            showReveal(outcome)
        }
    }

    private func waitForEnrichment(of starter: StarterSpecies) async {
        var waited = 0.0
        while enrichments[starter.id] == nil && waited < 1.2 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }
    }

    private func failMint() {
        isMinting = false
        chooseButton.isEnabled = true
        Haptics.failure()
        let alert = UIAlertController(
            title: "Couldn't add your starter", message: "Something went wrong saving it. Try again.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func playViewfinder(for starter: StarterSpecies, image: UIImage) async {
        guard let host = view.window else { return }
        let cell = collectionView.cellForItem(at: IndexPath(item: centeredIndex, section: 0))
        let start = cell.map { $0.convert($0.bounds, to: host) } ?? host.bounds.insetBy(dx: 80, dy: 200)
        let overlay = ViewfinderCatchView(photo: image, from: start)
        overlay.frame = host.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(overlay)
        await overlay.play()
        overlay.removeFromSuperview()
    }

    private func showReveal(_ outcome: StarterCatch.Outcome) {
        let card = CardRevealViewController(
            sighting: outcome.sighting, image: outcome.image, isNewDexEntry: outcome.isNew,
            progress: outcome.progress, caption: "Your starter — a gift to begin your Dex")
        card.modalPresentationStyle = .overFullScreen
        card.modalTransitionStyle = .crossDissolve
        card.onDismiss = { [weak self] in self?.onAdvance?() }
        present(card, animated: true)
    }
}

/// A starter option: the photo full-bleed, the realm tag, and the name with its field-guide epithet.
private final class StarterCardCell: UICollectionViewCell {
    static let reuseID = "StarterCardCell"

    private let photo = UIImageView()
    private let scrim = CAGradientLayer()
    private let tagLabel = UILabel()
    private let tagPill = UIView()
    private let nameLabel = OnboardingStyle.label("", style: .title2, weight: .heavy, size: 24)
    private let epithet = OnboardingStyle.label("", style: .subheadline, weight: .bold, color: OnboardingStyle.accent)
    private let scientific = UILabel()
    private var onActivate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 26
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.layer.borderWidth = 1.5
        contentView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 10)

        photo.contentMode = .scaleAspectFill
        photo.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(photo)
        photo.pinEdges(to: contentView)

        scrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.82).cgColor]
        scrim.locations = [0.5, 1]
        contentView.layer.addSublayer(scrim)

        tagLabel.font = OnboardingStyle.font(.caption1, weight: .heavy)
        tagLabel.textColor = .white
        tagLabel.translatesAutoresizingMaskIntoConstraints = false
        tagPill.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        tagPill.layer.cornerRadius = 13
        tagPill.layer.cornerCurve = .continuous
        tagPill.translatesAutoresizingMaskIntoConstraints = false
        tagPill.addSubview(tagLabel)
        contentView.addSubview(tagPill)

        let italic = UIFont.italicSystemFont(ofSize: 14)
        scientific.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: italic)
        scientific.textColor = UIColor.white.withAlphaComponent(0.7)
        scientific.adjustsFontForContentSizeCategory = true
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        nameLabel.numberOfLines = 1

        let text = UIStackView(arrangedSubviews: [epithet, nameLabel, scientific])
        text.axis = .vertical
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(text)

        NSLayoutConstraint.activate([
            tagPill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            tagPill.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            tagLabel.topAnchor.constraint(equalTo: tagPill.topAnchor, constant: 5),
            tagLabel.bottomAnchor.constraint(equalTo: tagPill.bottomAnchor, constant: -5),
            tagLabel.leadingAnchor.constraint(equalTo: tagPill.leadingAnchor, constant: 11),
            tagLabel.trailingAnchor.constraint(equalTo: tagPill.trailingAnchor, constant: -11),
            text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = contentView.bounds
    }

    func configure(_ starter: StarterSpecies, onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
        photo.image = starter.image
        tagLabel.text = starter.tag.uppercased()
        nameLabel.text = starter.commonName
        epithet.text = "The \(starter.category)"
        scientific.text = starter.scientificName
        accessibilityLabel = "\(starter.commonName), \(starter.tag). The \(starter.category)."
        accessibilityHint = "Chooses it as your starter"
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

/// The catch beat: the chosen photo lifts into a viewfinder, four brackets close in, the shutter flashes.
private final class ViewfinderCatchView: UIView {
    private let photo: UIImageView
    private let start: CGRect
    private let brackets = CAShapeLayer()
    private let flash = UIView()

    init(photo image: UIImage, from start: CGRect) {
        photo = UIImageView(image: image)
        self.start = start
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0)
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.layer.cornerRadius = 26
        photo.layer.cornerCurve = .continuous
        photo.frame = start
        addSubview(photo)

        brackets.strokeColor = OnboardingStyle.accent.cgColor
        brackets.fillColor = UIColor.clear.cgColor
        brackets.lineWidth = 4
        brackets.lineCap = .round
        brackets.opacity = 0
        layer.addSublayer(brackets)

        flash.backgroundColor = .white
        flash.alpha = 0
        flash.isUserInteractionEnabled = false
        addSubview(flash)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        flash.frame = bounds
    }

    /// Plays the whole beat and returns when the flash has faded.
    func play() async {
        layoutIfNeeded()
        let width = min(bounds.width * 0.76, 360)
        let target = CGRect(
            x: bounds.midX - width / 2, y: bounds.midY - width * 0.62, width: width, height: width * 1.24)
        guard !Motion.reduced else {
            photo.frame = target
            Haptics.shutter()
            await animate(0.25) { self.backgroundColor = UIColor.black.withAlphaComponent(0.6) }
            return
        }
        await animate(0.55, spring: true) {
            self.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            self.photo.frame = target
        }
        brackets.path = Self.bracketPath(in: target.insetBy(dx: -14, dy: -14), arm: 34).cgPath
        let closing = CABasicAnimation(keyPath: "path")
        closing.fromValue = Self.bracketPath(in: target.insetBy(dx: -90, dy: -110), arm: 34).cgPath
        closing.toValue = brackets.path
        closing.duration = 0.45
        closing.timingFunction = CAMediaTimingFunction(name: .easeOut)
        brackets.add(closing, forKey: "close")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.3
        brackets.opacity = 1
        brackets.add(fade, forKey: "fade")
        try? await Task.sleep(nanoseconds: 650_000_000)
        Haptics.shutter()
        await animate(0.08) { self.flash.alpha = 0.9 }
        await animate(0.3) {
            self.flash.alpha = 0
            self.brackets.opacity = 0
        }
    }

    private func animate(_ duration: TimeInterval, spring: Bool = false, _ changes: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            if spring {
                UIView.animate(
                    withDuration: duration, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.4,
                    options: [], animations: changes
                ) { _ in continuation.resume() }
            } else {
                UIView.animate(withDuration: duration, animations: changes) { _ in continuation.resume() }
            }
        }
    }

    /// Four L-shaped corner marks around a rectangle.
    private static func bracketPath(in rect: CGRect, arm: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1), (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1), (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (point, dx, dy) in corners {
            path.move(to: CGPoint(x: point.x + dx * arm, y: point.y))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + dy * arm))
        }
        return path
    }
}
