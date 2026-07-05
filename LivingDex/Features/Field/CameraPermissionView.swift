import UIKit

/// Shown when the camera can't be used — either access is denied or no capture
/// device is available (Simulator / hardware busy). The Field is camera-first,
/// so this is the fallback surface.
final class CameraPermissionView: UIView {
    enum State {
        case denied
        case unavailable

        var title: String {
            switch self {
            case .denied: return "Camera access needed"
            case .unavailable: return "Camera unavailable"
            }
        }

        var body: String {
            switch self {
            case .denied:
                return "Living Dex identifies and collects the life you point the camera at. Enable the camera in Settings to start your dex."
            case .unavailable:
                return "No camera is available here. Living Dex needs a device camera — run it on your iPhone to start catching."
            }
        }

        var actionTitle: String? {
            switch self {
            case .denied: return "Open Settings"
            case .unavailable: return nil
            }
        }
    }

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let button = UIButton(configuration: .borderedProminent())

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        iconView.image = UIImage(systemName: "camera.viewfinder")
        iconView.tintColor = DesignSystem.Color.accent
        iconView.contentMode = .scaleAspectFit

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        var config = UIButton.Configuration.borderedProminent()
        config.baseBackgroundColor = DesignSystem.Color.accent
        config.cornerStyle = .large
        button.configuration = config
        button.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, bodyLabel, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = DesignSystem.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 64),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignSystem.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignSystem.Spacing.l),
        ])

        configure(.denied)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Invoked when the (optional) action button is tapped.
    var onAction: (() -> Void)?

    func configure(_ state: State) {
        titleLabel.text = state.title
        bodyLabel.text = state.body
        if let action = state.actionTitle {
            button.isHidden = false
            button.configuration?.title = action
        } else {
            button.isHidden = true
        }
    }
}
