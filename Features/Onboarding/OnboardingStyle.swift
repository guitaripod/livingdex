import UIKit

/// The shared look of the first-run flow: rounded type that scales with Dynamic Type, the
/// brand's accent buttons, and the dark ink the illustrations sit on.
@MainActor
enum OnboardingStyle {
    static let ink = UIColor(red: 0.02, green: 0.05, blue: 0.04, alpha: 1)
    static let maxContentWidth: CGFloat = 520
    static let accent = UIColor(red: 0.20, green: 0.80, blue: 0.55, alpha: 1)

    private static let baseSizes: [UIFont.TextStyle: CGFloat] = [
        .largeTitle: 34, .title1: 28, .title2: 22, .title3: 20, .headline: 17, .body: 17,
        .callout: 16, .subheadline: 15, .footnote: 13, .caption1: 12,
    ]

    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular, size: CGFloat? = nil) -> UIFont {
        let pointSize = size ?? baseSizes[style] ?? 17
        var font = UIFont.systemFont(ofSize: pointSize, weight: weight)
        if let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: rounded, size: pointSize)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font, maximumPointSize: pointSize * 1.5)
    }

    static func label(
        _ text: String, style: UIFont.TextStyle, weight: UIFont.Weight = .regular, size: CGFloat? = nil,
        color: UIColor = .white, alignment: NSTextAlignment = .natural, lines: Int = 0
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font(style, weight: weight, size: size)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = lines
        return label
    }

    static func primaryButton(title: String, symbol: String? = nil, action: @escaping @MainActor () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = symbol.flatMap { UIImage(systemName: $0) }
        config.imagePadding = 8
        config.baseBackgroundColor = accent
        config.baseForegroundColor = .black
        config.cornerStyle = .capsule
        config.buttonSize = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font(.headline, weight: .bold)
            return attributes
        }
        return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }

    static func quietButton(title: String, action: @escaping @MainActor () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.7)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font(.subheadline, weight: .semibold)
            return attributes
        }
        return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }
}

/// Soft glass behind a block of onboarding content.
final class OnboardingGlassCard: UIView {
    init(cornerRadius: CGFloat = 22) {
        super.init(frame: .zero)
        backgroundColor = UIColor.white.withAlphaComponent(0.08)
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

extension UIView {
    /// Pins the view to the superview's edges.
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }
}
