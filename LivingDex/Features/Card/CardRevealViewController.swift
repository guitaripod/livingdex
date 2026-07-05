import UIKit

/// The card-mint reveal — the dopamine beat after a catch. A glass card scales in
/// over a dimmed field with the captured image, a confidence signal, rarity drama
/// (glow + sparkle for epic/legendary), and a "NEW" banner for a first-ever entry.
/// Haptics escalate with rarity; Reduce Motion downgrades to a fade. Swipe down or
/// tap to dismiss.
final class CardRevealViewController: UIViewController {
    private let sighting: Sighting
    private let image: UIImage
    private let isNewDexEntry: Bool
    private let progress: ProgressEvent?

    private let card = GlassPanel(cornerRadius: DesignSystem.Radius.card)
    private var sparkleLayer: CAEmitterLayer?
    private var dismissAnimator: UIViewPropertyAnimator?

    init(sighting: Sighting, image: UIImage, isNewDexEntry: Bool, progress: ProgressEvent? = nil) {
        self.sighting = sighting
        self.image = image
        self.isNewDexEntry = isNewDexEntry
        self.progress = progress
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Always a dark dim backdrop — keep semantic label colors light-on-dark
        // in both appearances.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissCard)))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))
        configureRarityGlow()
        buildCard()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Haptics.caught(rarity: sighting.rarity, isNew: isNewDexEntry)
        announce()
        animateIn()
        if sighting.rarity == .epic || sighting.rarity == .legendary, !Motion.reduced {
            addSparkle()
        }
    }

    // MARK: Reveal

    private func animateIn() {
        if Motion.reduced {
            card.alpha = 0
            UIView.animate(withDuration: 0.25) { self.card.alpha = 1 }
            return
        }
        card.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        card.alpha = 0
        let damping: CGFloat = sighting.rarity == .legendary ? 0.62 : 0.72
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: damping, initialSpringVelocity: 0.7) {
            self.card.transform = .identity
            self.card.alpha = 1
        }
    }

    private func configureRarityGlow() {
        let intensity: Float
        switch sighting.rarity {
        case .common, .uncommon: intensity = 0
        case .rare: intensity = 0.5
        case .epic: intensity = 0.8
        case .legendary: intensity = 1.0
        }
        guard intensity > 0 else { return }
        card.layer.shadowColor = sighting.rarity.color.cgColor
        card.layer.shadowRadius = CGFloat(24 * intensity)
        card.layer.shadowOpacity = intensity
        card.layer.shadowOffset = .zero
    }

    private func addSparkle() {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: card.frame.midX, y: card.frame.minY)
        emitter.emitterSize = CGSize(width: card.frame.width, height: 2)
        emitter.emitterShape = .line
        let cell = CAEmitterCell()
        cell.birthRate = 40
        cell.lifetime = 1.6
        cell.velocity = 90
        cell.velocityRange = 40
        cell.emissionRange = .pi
        cell.scale = 0.05
        cell.scaleRange = 0.03
        cell.spin = 2
        cell.color = sighting.rarity.color.cgColor
        cell.contents = Self.sparkImage()?.cgImage
        emitter.emitterCells = [cell]
        view.layer.addSublayer(emitter)
        sparkleLayer = emitter
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { emitter.birthRate = 0 }
    }

    private static func sparkImage() -> UIImage? {
        let size = CGSize(width: 12, height: 12)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
    }

    private func announce() {
        let prefix = isNewDexEntry ? "New dex entry. " : "Caught. "
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(prefix)\(sighting.commonName), \(sighting.rarity.title), \(Int(sighting.confidence * 100)) percent match.")
    }

    // MARK: Layout

    private func buildCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let grabber = UIView()
        grabber.backgroundColor = UIColor.white.withAlphaComponent(0.4)
        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false

        let photo = UIImageView(image: image)
        photo.translatesAutoresizingMaskIntoConstraints = false
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.layer.cornerRadius = DesignSystem.Radius.control
        photo.layer.cornerCurve = .continuous
        photo.layer.borderWidth = 3
        photo.layer.borderColor = ConfidenceLevel(sighting.confidence).color.cgColor
        photo.isAccessibilityElement = true
        photo.accessibilityLabel = "Photo of \(sighting.commonName)"

        let rarity = RarityBadge()
        rarity.translatesAutoresizingMaskIntoConstraints = false
        rarity.configure(sighting.rarity)

        let confidence = confidenceChip()

        let badges = UIStackView(arrangedSubviews: [rarity, confidence, UIView()])
        badges.axis = .horizontal
        badges.spacing = DesignSystem.Spacing.s
        badges.alignment = .center

        let common = scalingLabel(sighting.commonName, style: .title1, weight: .heavy, color: .white)
        common.numberOfLines = 2
        let scientific = scalingLabel(sighting.scientificName, style: .subheadline, italic: true, color: .secondaryLabel)
        let meta = scalingLabel(
            "\(sighting.realm.rawValue.capitalized) · \(ConfidenceLevel(sighting.confidence).label) (\(Int(sighting.confidence * 100))%)",
            style: .footnote, weight: .medium, color: .tertiaryLabel)

        let stack = UIStackView(arrangedSubviews: [badges, common, scientific, meta])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(DesignSystem.Spacing.s, after: badges)
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let progressView = progressRow() {
            stack.addArrangedSubview(progressView)
            stack.setCustomSpacing(DesignSystem.Spacing.s, after: meta)
        }

        card.contentView.addSubview(grabber)
        card.contentView.addSubview(photo)
        card.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.l),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.l),

            grabber.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: DesignSystem.Spacing.s),
            grabber.centerXAnchor.constraint(equalTo: card.contentView.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            photo.topAnchor.constraint(equalTo: grabber.bottomAnchor, constant: DesignSystem.Spacing.s),
            photo.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: DesignSystem.Spacing.m),
            photo.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -DesignSystem.Spacing.m),
            photo.heightAnchor.constraint(equalTo: photo.widthAnchor, multiplier: 0.85),

            stack.topAnchor.constraint(equalTo: photo.bottomAnchor, constant: DesignSystem.Spacing.m),
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: DesignSystem.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -DesignSystem.Spacing.m),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -DesignSystem.Spacing.l),
        ])

        if isNewDexEntry { addNewBanner() }
    }

    /// A compact "+40 XP · 🔥 3 · Level 4!" progress line under the card meta.
    private func progressRow() -> UIView? {
        guard let progress else { return nil }
        var parts: [String] = ["+\(progress.xpGained) XP"]
        if progress.streak > 1 { parts.append("🔥 \(progress.streak)") }
        if let level = progress.leveledUpTo { parts.append("Level \(level)!") }
        let label = scalingLabel(parts.joined(separator: "  ·  "), style: .subheadline, weight: .semibold, color: .white)
        label.isAccessibilityElement = true
        var a11y = "Gained \(progress.xpGained) experience."
        if progress.streak > 1 { a11y += " \(progress.streak) day streak." }
        if let level = progress.leveledUpTo { a11y += " Reached level \(level)." }
        label.accessibilityLabel = a11y
        return label
    }

    private func confidenceChip() -> UIView {
        let level = ConfidenceLevel(sighting.confidence)
        let dot = UIView()
        dot.backgroundColor = level.color
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let label = scalingLabel(level.label, style: .caption1, weight: .semibold, color: .white)
        let chip = UIStackView(arrangedSubviews: [dot, label])
        chip.axis = .horizontal
        chip.spacing = 5
        chip.alignment = .center
        chip.isAccessibilityElement = true
        chip.accessibilityLabel = "\(level.label), \(Int(sighting.confidence * 100)) percent"
        return chip
    }

    private func scalingLabel(
        _ text: String, style: UIFont.TextStyle, weight: UIFont.Weight = .regular,
        italic: Bool = false, color: UIColor
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = color
        label.adjustsFontForContentSizeCategory = true
        let base = UIFont.preferredFont(forTextStyle: style)
        if italic {
            label.font = UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitItalic) ?? base.fontDescriptor, size: 0)
        } else {
            let descriptor = base.fontDescriptor.addingAttributes(
                [.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            label.font = UIFont(descriptor: descriptor, size: 0)
        }
        return label
    }

    private func addNewBanner() {
        let banner = PaddedLabel()
        banner.text = "NEW DEX ENTRY"
        banner.font = .systemFont(ofSize: 13, weight: .heavy)
        banner.textColor = .black
        banner.backgroundColor = DesignSystem.Color.accent
        banner.textAlignment = .center
        banner.layer.cornerRadius = 10
        banner.layer.cornerCurve = .continuous
        banner.clipsToBounds = true
        banner.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: DesignSystem.Spacing.l),
            banner.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -DesignSystem.Spacing.l),
        ])
        guard !Motion.reduced else { return }
        banner.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        banner.alpha = 0
        UIView.animate(withDuration: 0.4, delay: 0.25, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8) {
            banner.transform = .identity
            banner.alpha = 1
        }
    }

    // MARK: Dismiss

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view).y
        switch gesture.state {
        case .changed:
            let offset = max(0, translation)
            card.transform = CGAffineTransform(translationX: 0, y: offset)
            view.backgroundColor = UIColor.black.withAlphaComponent(0.55 * (1 - min(offset / 400, 0.7)))
        case .ended, .cancelled:
            if translation > 120 || gesture.velocity(in: view).y > 800 {
                dismissCard()
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                    self.card.transform = .identity
                    self.view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
                }
            }
        default:
            break
        }
    }

    @objc private func dismissCard() {
        Haptics.tap()
        dismiss(animated: true)
    }
}

/// A label with inset padding (for the NEW banner pill).
private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
