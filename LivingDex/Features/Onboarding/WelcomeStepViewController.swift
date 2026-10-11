import UIKit

/// Step 1: three rarity-framed species cards float in a fan over the illustrated backdrop, with a
/// tilt parallax, under the name and promise.
final class WelcomeStepViewController: OnboardingStepViewController {
    private let fan = CardFanView()
    private let titleLabel = OnboardingStyle.label(
        "Living Dex", style: .largeTitle, weight: .heavy, size: 46, alignment: .center)
    private let promise = OnboardingStyle.label(
        "Catch the real world.", style: .title3, weight: .semibold, color: OnboardingStyle.accent, alignment: .center)
    private let detail = OnboardingStyle.label(
        "Point your camera at anything alive. Build a collection of real species, rated by how rare they truly are where you are.",
        style: .callout, color: UIColor.white.withAlphaComponent(0.75), alignment: .center)
    private lazy var beginButton = OnboardingStyle.primaryButton(title: "Begin", symbol: "arrow.right") { [weak self] in
        Haptics.tap()
        self?.onAdvance?()
    }
    private var entranceDone = false

    override var artName: String { "realm-animals" }
    override var showsSkip: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.accessibilityTraits = .header

        let text = UIStackView(arrangedSubviews: [titleLabel, promise, detail])
        text.axis = .vertical
        text.spacing = DesignSystem.Spacing.s
        text.setCustomSpacing(DesignSystem.Spacing.m, after: promise)

        let content = UIStackView(arrangedSubviews: [fan, text])
        content.axis = .vertical
        content.spacing = DesignSystem.Spacing.l
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        beginButton.translatesAutoresizingMaskIntoConstraints = false
        fan.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(content)
        view.addSubview(beginButton)
        let width = content.widthAnchor.constraint(equalToConstant: OnboardingStyle.maxContentWidth)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: DesignSystem.Spacing.l),
            content.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -DesignSystem.Spacing.l),
            width,
            content.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: beginButton.topAnchor, constant: -DesignSystem.Spacing.l),
            fan.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.36),

            beginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            beginButton.widthAnchor.constraint(lessThanOrEqualToConstant: OnboardingStyle.maxContentWidth),
            beginButton.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: DesignSystem.Spacing.l),
            beginButton.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -DesignSystem.Spacing.l),
            beginButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.l),
        ])
        let fill = beginButton.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -DesignSystem.Spacing.l * 2)
        fill.priority = .defaultHigh
        fill.isActive = true

        if !Motion.reduced {
            for item in [fan, titleLabel, promise, detail, beginButton] as [UIView] { item.alpha = 0 }
        }
    }

    override func stepDidAppear() {
        guard !entranceDone else { return }
        entranceDone = true
        guard !Motion.reduced else { return }
        fan.alpha = 1
        fan.playEntrance()
        let items: [UIView] = [titleLabel, promise, detail, beginButton]
        for (i, item) in items.enumerated() {
            item.transform = CGAffineTransform(translationX: 0, y: 16)
            UIView.animate(
                withDuration: 0.6, delay: 0.5 + 0.1 * Double(i),
                usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3
            ) {
                item.alpha = 1
                item.transform = .identity
            }
        }
        Haptics.tap()
    }
}

/// Three species cards fanned out like a hand, each floating on its own slow cycle.
final class CardFanView: UIView {
    private let cards: [FloatingCardView]
    private let angles: [CGFloat] = [-9, 0, 9]

    override init(frame: CGRect) {
        let picks: [(String, String, UIColor)] = [
            ("sample-robin", "European Robin", DesignSystem.Color.rarityUncommon),
            ("sample-red-fox", "Red Fox", DesignSystem.Color.rarityRare),
            ("sample-fly-agaric", "Fly Agaric", DesignSystem.Color.rarityCommon),
        ]
        cards = picks.map { FloatingCardView(photo: SampleLibrary.image(named: $0.0), name: $0.1, accent: $0.2) }
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Three example species cards: European Robin, Red Fox and Fly Agaric"
        for card in [cards[0], cards[2], cards[1]] { addSubview(card) }
        for (i, card) in cards.enumerated() {
            let tilt = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
            tilt.minimumRelativeValue = -10 * CGFloat(i + 1)
            tilt.maximumRelativeValue = 10 * CGFloat(i + 1)
            card.addMotionEffect(tilt)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = min(bounds.height * 0.92, (bounds.width - 40) / 2.24 / 0.76)
        let size = CGSize(width: height * 0.76, height: height)
        for (i, card) in cards.enumerated() {
            card.bounds = CGRect(origin: .zero, size: size)
            card.center = CGPoint(
                x: bounds.midX + CGFloat(i - 1) * size.width * 0.66,
                y: bounds.midY + (i == 1 ? -size.height * 0.04 : size.height * 0.05))
            card.transform = CGAffineTransform(rotationAngle: angles[i] * .pi / 180)
        }
    }

    func playEntrance() {
        for (i, card) in cards.enumerated() {
            let rest = card.transform
            card.alpha = 0
            card.transform = rest.translatedBy(x: 0, y: 90).scaledBy(x: 0.9, y: 0.9)
            UIView.animate(
                withDuration: 0.8, delay: 0.1 * Double(i), usingSpringWithDamping: 0.72, initialSpringVelocity: 0.4
            ) {
                card.alpha = 1
                card.transform = rest
            } completion: { _ in
                card.startFloating(phase: Double(i))
            }
        }
    }
}

/// A trading-card face: the photo, a name plate, and a rarity-coloured frame with a soft glow.
final class FloatingCardView: UIView {
    private let photo = UIImageView()
    private let plate = UILabel()
    private let scrim = CAGradientLayer()

    init(photo image: UIImage?, name: String, accent: UIColor) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.07, green: 0.10, blue: 0.09, alpha: 1)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 3
        layer.borderColor = accent.cgColor
        layer.shadowColor = accent.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 22
        layer.shadowOffset = .zero

        photo.image = image
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.layer.cornerRadius = 17
        photo.layer.cornerCurve = .continuous
        photo.translatesAutoresizingMaskIntoConstraints = false
        addSubview(photo)
        NSLayoutConstraint.activate([
            photo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            photo.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            photo.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            photo.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])

        scrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.78).cgColor]
        scrim.locations = [0.55, 1]
        photo.layer.addSublayer(scrim)

        plate.text = name
        plate.font = OnboardingStyle.font(.subheadline, weight: .heavy)
        plate.textColor = .white
        plate.adjustsFontSizeToFitWidth = true
        plate.minimumScaleFactor = 0.7
        plate.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plate)
        NSLayoutConstraint.activate([
            plate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            plate.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            plate.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = photo.bounds
    }

    /// A gentle vertical bob; each card runs a slightly different period so the fan never moves in lockstep.
    func startFloating(phase: Double) {
        guard !Motion.reduced else { return }
        let bob = CABasicAnimation(keyPath: "position.y")
        bob.fromValue = layer.position.y - 7
        bob.toValue = layer.position.y + 7
        bob.duration = 3.0 + phase * 0.55
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(bob, forKey: "bob")
    }
}
