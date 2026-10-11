import UIKit

/// A rounded Liquid Glass container. Uses the iOS 26 `UIGlassEffect` so the HUD
/// reads as floating glass over the live camera. Falls back to a system material
/// on the off chance the effect is unavailable.
final class GlassPanel: UIView {
    let contentView = UIView()

    /// - Parameter interactive: reserve the iOS 26 interactive-glass shimmer for
    ///   surfaces the user actually manipulates (the capture control) — using it
    ///   on passive HUD chrome is both wrong and a needless GPU cost.
    init(cornerRadius: CGFloat = DesignSystem.Radius.control, interactive: Bool = false) {
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark
        let effectView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = interactive
            effectView = UIVisualEffectView(effect: glass)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        }
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        addSubview(effectView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(contentView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// A glass pill showing a short status line at the top of the Field view.
final class GlassChipView: UIView {
    private let panel = GlassPanel(cornerRadius: 18)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        // A subtle shadow keeps the status readable over a bright sky (glass over
        // a live camera can drop contrast below legibility).
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.5
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero
        panel.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: DesignSystem.Spacing.m),
            label.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -DesignSystem.Spacing.m),
            label.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: DesignSystem.Spacing.s),
            label.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -DesignSystem.Spacing.s),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String, animated: Bool = true) {
        guard animated else {
            label.text = text
            return
        }
        UIView.transition(with: label, duration: 0.2, options: .transitionCrossDissolve) {
            self.label.text = text
        }
    }
}

/// A glass pill showing how many identifications are left (or "Pro") — a plain
/// meter that doubles as the way to get more.
final class GlassCreditsButton: UIControl {
    private let panel = GlassPanel(cornerRadius: 18, interactive: true)
    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.isUserInteractionEnabled = false
        addSubview(panel)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.5
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -9),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Shows the balance, warming from white to orange to red as it runs out.
    func configure(balance: Int, isPro: Bool) {
        let tint: UIColor
        let text: String
        let spoken: String
        if isPro {
            tint = DesignSystem.Color.accent
            text = "Pro"
            spoken = "Living Dex Pro, unlimited identifications"
            accessibilityHint = nil
        } else {
            tint = balance <= 0 ? .systemRed : (balance <= 3 ? .systemOrange : .white)
            text = balance <= 0 ? "Get more" : "\(balance) left"
            spoken = balance <= 0 ? "No identifications left" : (balance == 1 ? "1 identification left" : "\(balance) identifications left")
            accessibilityHint = "Shows ways to get more identifications"
        }
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        iconView.image = UIImage(systemName: isPro ? "infinity" : "sparkles", withConfiguration: config)
        iconView.tintColor = tint
        label.text = text
        accessibilityLabel = spoken
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            }
        }
    }
}

/// A circular glass button hosting a single SF Symbol — HUD toggles like the
/// torch. Mirrors the capture control's interactive-glass idiom at button size.
final class GlassIconButton: UIControl {
    private let panel = GlassPanel(cornerRadius: 22, interactive: true)
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.isUserInteractionEnabled = false
        addSubview(panel)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.tintColor = .white
        imageView.isUserInteractionEnabled = false
        panel.contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: panel.contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: panel.contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ name: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        imageView.image = UIImage(systemName: name, withConfiguration: config)
    }

    /// Turns the button into a menu trigger: a tap opens `menu` instead of sending
    /// `.touchUpInside`. UIControl has no menu of its own, so a clear UIButton overlay
    /// hosts it.
    var menu: UIMenu? {
        didSet {
            menuOverlay.menu = menu
            menuOverlay.isHidden = menu == nil
        }
    }

    private lazy var menuOverlay: UIButton = {
        let overlay = UIButton(type: .custom)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.showsMenuAsPrimaryAction = true
        overlay.isHidden = true
        overlay.accessibilityElementsHidden = true
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        return overlay
    }()

    /// Tints the glyph to signal an active/on state (e.g. torch lit).
    func setActive(_ active: Bool) {
        imageView.tintColor = active ? DesignSystem.Color.accent : .white
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            }
        }
    }
}

/// The large circular capture control — a glass ring around a solid accent core,
/// with a capturing state that shrinks the core.
final class CaptureButton: UIControl {
    private let ring = GlassPanel(cornerRadius: 38, interactive: true)
    private let core = UIView()
    private var coreSize: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Capture"
        accessibilityHint = "Identifies and collects what the camera is pointed at"
        accessibilityTraits = .button

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.isUserInteractionEnabled = false
        addSubview(ring)

        core.translatesAutoresizingMaskIntoConstraints = false
        core.backgroundColor = DesignSystem.Color.accent
        core.isUserInteractionEnabled = false
        core.layer.cornerCurve = .continuous
        addSubview(core)

        coreSize = core.widthAnchor.constraint(equalToConstant: 58)
        NSLayoutConstraint.activate([
            ring.leadingAnchor.constraint(equalTo: leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: trailingAnchor),
            ring.topAnchor.constraint(equalTo: topAnchor),
            ring.bottomAnchor.constraint(equalTo: bottomAnchor),
            core.centerXAnchor.constraint(equalTo: centerXAnchor),
            core.centerYAnchor.constraint(equalTo: centerYAnchor),
            coreSize,
            core.heightAnchor.constraint(equalTo: core.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        core.layer.cornerRadius = core.bounds.width / 2
    }

    func setCapturing(_ capturing: Bool) {
        coreSize.constant = capturing ? 34 : 58
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.core.layer.cornerRadius = (capturing ? 34 : 58) / 2
            self.layoutIfNeeded()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }
}
