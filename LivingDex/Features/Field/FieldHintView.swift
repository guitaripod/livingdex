import UIKit

/// A one-time speech bubble over the photo button for the person with nothing to point at. It
/// points down at the button, fades itself out, and goes away at the first tap anywhere on it.
final class FieldHintView: UIView {
    private let panel = GlassPanel(cornerRadius: 18)
    private let tail = CAShapeLayer()
    private var onDismiss: (() -> Void)?

    init(text: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .staticText

        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        let icon = UIImageView(image: UIImage(
            systemName: "photo.on.rectangle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
        icon.tintColor = DesignSystem.Color.accent
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(row)

        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -11),
        ])

        tail.fillColor = UIColor.white.withAlphaComponent(0.22).cgColor
        layer.addSublayer(tail)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        let x: CGFloat = 38
        path.move(to: CGPoint(x: x - 9, y: bounds.height - 9))
        path.addLine(to: CGPoint(x: x + 9, y: bounds.height - 9))
        path.addLine(to: CGPoint(x: x, y: bounds.height))
        path.close()
        tail.path = path.cgPath
    }

    func show() {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 8)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4) {
            self.alpha = 1
            self.transform = .identity
        }
        UIAccessibility.post(notification: .announcement, argument: accessibilityLabel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in self?.dismiss() }
    }

    @objc private func tapped() {
        dismiss()
    }

    func dismiss() {
        guard let onDismiss else { return }
        self.onDismiss = nil
        UIView.animate(withDuration: 0.3, animations: { self.alpha = 0 }, completion: { _ in
            self.removeFromSuperview()
            onDismiss()
        })
    }
}
