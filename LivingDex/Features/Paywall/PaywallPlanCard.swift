import UIKit

/// A selectable Pro-plan card on the paywall. The billed price + cadence dominate; the
/// monthly-equivalent (annual) sits subordinate beneath it. The recommended annual carries
/// the single "Best value" ribbon. Selection is shown with an accent border, a tinted
/// fill, and a filled check — never color alone (the check glyph and the accessibility
/// `.selected` trait carry it too). Built on the same Liquid-Glass surface as the rest of
/// the Field HUD.
final class PaywallPlanCard: UIControl {
    private let glass = GlassPanel(cornerRadius: DesignSystem.Radius.card)
    private let selectionTint = UIView()
    private let priceLabel = UILabel()
    private let cadenceLabel = UILabel()
    private let headlineLabel = UILabel()
    private let equivalentLabel = UILabel()
    private let ribbon = PlanBadge()
    private let check = UIImageView()

    private let plan: PaywallPlan

    init(plan: PaywallPlan) {
        self.plan = plan
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        apply(selected: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isSelected: Bool {
        didSet { apply(selected: isSelected) }
    }

    override var isHighlighted: Bool {
        didSet { animateHighlight(isHighlighted) }
    }

    private func build() {
        layer.cornerRadius = DesignSystem.Radius.card
        layer.cornerCurve = .continuous
        layer.borderWidth = 2

        glass.isUserInteractionEnabled = false
        glass.translatesAutoresizingMaskIntoConstraints = false

        selectionTint.isUserInteractionEnabled = false
        selectionTint.alpha = 0
        selectionTint.backgroundColor = DesignSystem.Color.accent.withAlphaComponent(0.14)
        selectionTint.translatesAutoresizingMaskIntoConstraints = false

        headlineLabel.font = .preferredFont(forTextStyle: .headline)
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.textColor = .label
        headlineLabel.text = plan.headline
        headlineLabel.numberOfLines = 0

        priceLabel.font = Self.priceFont
        priceLabel.adjustsFontForContentSizeCategory = true
        priceLabel.textColor = .label
        priceLabel.text = plan.displayPrice
        priceLabel.adjustsFontSizeToFitWidth = true
        priceLabel.minimumScaleFactor = 0.6
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        cadenceLabel.font = .preferredFont(forTextStyle: .subheadline)
        cadenceLabel.adjustsFontForContentSizeCategory = true
        cadenceLabel.textColor = .secondaryLabel
        cadenceLabel.text = plan.cadenceCaption

        equivalentLabel.font = .preferredFont(forTextStyle: .footnote)
        equivalentLabel.adjustsFontForContentSizeCategory = true
        equivalentLabel.textColor = .secondaryLabel
        equivalentLabel.numberOfLines = 0
        equivalentLabel.text = plan.monthlyEquivalent
        equivalentLabel.isHidden = (plan.monthlyEquivalent == nil)

        check.contentMode = .scaleAspectFit
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.setContentCompressionResistancePriority(.required, for: .horizontal)

        let priceRow = UIStackView(arrangedSubviews: [priceLabel, cadenceLabel])
        priceRow.axis = .horizontal
        priceRow.alignment = .firstBaseline
        priceRow.spacing = 6

        let textColumn = UIStackView(arrangedSubviews: [headlineLabel, priceRow, equivalentLabel])
        textColumn.axis = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 4
        textColumn.setCustomSpacing(2, after: priceRow)
        installRibbonIfNeeded(in: textColumn)

        let row = UIStackView(arrangedSubviews: [textColumn, check])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DesignSystem.Spacing.m
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: DesignSystem.Spacing.m, left: DesignSystem.Spacing.l,
            bottom: DesignSystem.Spacing.m, right: DesignSystem.Spacing.l)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = false

        addSubview(glass)
        glass.contentView.addSubview(selectionTint)
        glass.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectionTint.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            selectionTint.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            selectionTint.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            selectionTint.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.apply(selected: self.isSelected)
        }

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private static var priceFont: UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title1)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// The recommended (annual) plan carries the single "Best value" chip, folding in the
    /// live savings when one resolved, so the accent signal is never split across two
    /// competing chips on the same card. It sits inside the card above the headline — fully
    /// within the card's bounds so no ancestor clip can shear it (an outside-the-bounds
    /// straddling ribbon is clipped by the cards stack).
    private func installRibbonIfNeeded(in column: UIStackView) {
        guard plan.isRecommended else {
            ribbon.isHidden = true
            return
        }
        let text = plan.savings.map { "Best value · \($0)" } ?? "Best value"
        ribbon.render(text: text)
        column.insertArrangedSubview(ribbon, at: 0)
        column.setCustomSpacing(DesignSystem.Spacing.s, after: ribbon)
    }

    private func apply(selected: Bool) {
        let border = (selected ? DesignSystem.Color.accent : UIColor.separator)
        layer.borderColor = border.resolvedColor(with: traitCollection).cgColor
        selectionTint.alpha = selected ? 1 : 0
        check.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        check.tintColor = selected ? DesignSystem.Color.accent : .secondaryLabel
        accessibilityTraits = selected ? [.button, .selected] : [.button]
        accessibilityLabel = accessibilityCopy()
        accessibilityHint = selected ? nil : "Selects this plan"
    }

    private func animateHighlight(_ highlighted: Bool) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            alpha = highlighted ? 0.85 : 1
            return
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = highlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            self.alpha = highlighted ? 0.92 : 1
        }
    }

    private func accessibilityCopy() -> String {
        var parts: [String] = []
        if plan.isRecommended { parts.append("Best value") }
        parts.append("\(plan.headline), \(plan.displayPrice) \(plan.cadenceCaption)")
        if let equivalent = plan.monthlyEquivalent {
            parts.append(equivalent
                .replacingOccurrences(of: "≈", with: "about")
                .replacingOccurrences(of: "/ mo", with: "per month"))
        }
        if let savings = plan.savings { parts.append(savings) }
        return parts.joined(separator: ", ")
    }
}

/// The unpriced placeholder row shown while live store pricing resolves: the same glass
/// footprint as ``PaywallPlanCard`` with quietly pulsing bars where the headline and price
/// will land. A numeric price, savings figure, or trial claim never renders here — figures
/// appear only once the store supplies them.
final class PaywallPlanSkeletonCard: UIView {
    private let barsColumn = UIStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        startPulse()
    }

    private func build() {
        layer.cornerRadius = DesignSystem.Radius.card
        layer.cornerCurve = .continuous
        layer.borderWidth = 2
        applyBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.applyBorder()
        }

        let glass = GlassPanel(cornerRadius: DesignSystem.Radius.card)
        glass.translatesAutoresizingMaskIntoConstraints = false

        barsColumn.axis = .vertical
        barsColumn.alignment = .leading
        barsColumn.spacing = DesignSystem.Spacing.s
        barsColumn.isLayoutMarginsRelativeArrangement = true
        barsColumn.layoutMargins = UIEdgeInsets(
            top: DesignSystem.Spacing.m, left: DesignSystem.Spacing.l,
            bottom: DesignSystem.Spacing.m, right: DesignSystem.Spacing.l)
        barsColumn.translatesAutoresizingMaskIntoConstraints = false
        barsColumn.addArrangedSubview(makeBar(width: 96, height: 16))
        barsColumn.addArrangedSubview(makeBar(width: 150, height: 26))

        addSubview(glass)
        glass.contentView.addSubview(barsColumn)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            barsColumn.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            barsColumn.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
            barsColumn.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            barsColumn.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Loading pricing from the App Store"
    }

    private func applyBorder() {
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }

    private func makeBar(width: CGFloat, height: CGFloat) -> UIView {
        let bar = UIView()
        bar.backgroundColor = .separator
        bar.layer.cornerRadius = height / 2
        bar.layer.cornerCurve = .continuous
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: width),
            bar.heightAnchor.constraint(equalToConstant: height),
        ])
        return bar
    }

    private func startPulse() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        barsColumn.alpha = 1
        UIView.animate(
            withDuration: 0.9, delay: 0,
            options: [.repeat, .autoreverse, .curveEaseInOut, .allowUserInteraction]
        ) {
            self.barsColumn.alpha = 0.4
        }
    }
}

/// The single "Best value · Save N%" ribbon on the recommended plan — a padded, kerned
/// all-caps pill on the app's accent, its foreground forced dark for contrast on the
/// green in both appearances. Grows with Dynamic Type instead of clipping.
private final class PlanBadge: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func render(text: String) {
        isHidden = false
        label.attributedText = NSAttributedString(string: text.uppercased(), attributes: [.kern: 0.8])
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerCurve = .continuous
        backgroundColor = DesignSystem.Color.accent
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignSystem.Spacing.s),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignSystem.Spacing.s),
        ])
        isAccessibilityElement = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.height / 2, DesignSystem.Radius.control)
    }
}
