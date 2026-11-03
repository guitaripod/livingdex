import UIKit

/// The top of the Pro paywall: the fan of rarity-framed cards the first run opened with, the promise, why the
/// paywall is showing, and what Pro adds. Every benefit is something Pro really changes on this device.
final class PaywallHeroView: UIView {
    private let fan = CardFanView()
    private var entranceDone = false

    init(reason: String, showsCloudEntries: Bool = !OnDeviceNarrator.isAvailable) {
        super.init(frame: .zero)
        let eyebrow = OnboardingStyle.label("", style: .caption1, weight: .heavy, color: OnboardingStyle.accent)
        eyebrow.attributedText = NSAttributedString(string: "LIVING DEX PRO", attributes: [.kern: 1.6])
        let title = OnboardingStyle.label(
            String(localized: "Identify without limits."), style: .largeTitle, weight: .heavy, size: 32)
        title.accessibilityTraits = .header
        let reasonLabel = OnboardingStyle.label(
            reason, style: .callout, color: UIColor.white.withAlphaComponent(0.75))

        let text = UIStackView(arrangedSubviews: [eyebrow, title, reasonLabel])
        text.axis = .vertical
        text.spacing = 6
        text.setCustomSpacing(DesignSystem.Spacing.s, after: title)

        let stack = UIStackView(arrangedSubviews: [fan, text, Self.benefits(showsCloudEntries: showsCloudEntries)])
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.m
        stack.setCustomSpacing(DesignSystem.Spacing.s, after: fan)
        addSubview(stack)
        stack.pinEdges(to: self)
        fan.heightAnchor.constraint(equalToConstant: 140).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Deals the cards in once, the first time the paywall is on screen.
    func playEntrance() {
        guard !entranceDone else { return }
        entranceDone = true
        guard !Motion.reduced else { return }
        fan.playEntrance()
    }

    private static func benefits(showsCloudEntries: Bool) -> UIView {
        var rows = [
            row(symbol: "infinity", title: String(localized: "Unlimited identifications"),
                detail: String(localized: "Every bird on the walk, every bug in the garden. No credits to count.")),
            row(symbol: "arrow.counterclockwise", title: String(localized: "Retakes cost nothing"),
                detail: String(localized: "A blur or a bird that flew off? Just shoot again.")),
        ]
        if showsCloudEntries {
            rows.append(row(
                symbol: "text.book.closed.fill", title: String(localized: "A field entry for every catch"),
                detail: String(localized: "This iPhone has no Apple Intelligence, so Pro writes each catch's entry in the cloud.")))
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.m
        return stack
    }

    private static func row(symbol: String, title: String, detail: String) -> UIView {
        let glyph = UIImageView(image: UIImage(
            systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)))
        glyph.tintColor = OnboardingStyle.accent
        glyph.contentMode = .center
        glyph.backgroundColor = OnboardingStyle.accent.withAlphaComponent(0.16)
        glyph.layer.cornerRadius = 12
        glyph.layer.cornerCurve = .continuous
        glyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glyph.widthAnchor.constraint(equalToConstant: 40),
            glyph.heightAnchor.constraint(equalToConstant: 40),
        ])

        let titleLabel = OnboardingStyle.label(title, style: .headline, weight: .bold)
        let detailLabel = OnboardingStyle.label(detail, style: .subheadline, color: UIColor.white.withAlphaComponent(0.7))
        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [glyph, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = DesignSystem.Spacing.m
        row.isAccessibilityElement = true
        row.accessibilityLabel = String(localized: "\(title). \(detail)")
        return row
    }
}
