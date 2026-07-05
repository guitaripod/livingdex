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

    func setText(_ text: String) {
        UIView.transition(with: label, duration: 0.2, options: .transitionCrossDissolve) {
            self.label.text = text
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
