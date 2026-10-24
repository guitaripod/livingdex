import UIKit

/// Shown when the camera can't be used — either access is denied or no capture
/// device is available (Simulator / hardware busy). The Field is camera-first,
/// so this is the fallback surface; it still offers a photo from the library or a
/// bundled sample so the app is never a dead end.
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
                return "Living Dex identifies and collects the life you point the camera at. Enable the camera in Settings, or identify a photo instead."
            case .unavailable:
                return "No camera is available right now. You can still identify a photo from your library, or try a sample."
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
    private let photoButton = UIButton(configuration: .gray())
    private let content = UIStackView()
    private var isWide = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        // The camera surface is always dark; keep semantic label colors readable
        // in Light Mode too.
        overrideUserInterfaceStyle = .dark
        addBackdrop()

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
        bodyLabel.textColor = UIColor(white: 1, alpha: 0.78)
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        var config = UIButton.Configuration.borderedProminent()
        config.baseBackgroundColor = DesignSystem.Color.accent
        config.baseForegroundColor = .black
        config.cornerStyle = .large
        button.configuration = config
        button.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)

        var photoConfig = UIButton.Configuration.gray()
        photoConfig.title = "Identify a photo instead"
        photoConfig.image = UIImage(systemName: "photo.on.rectangle")
        photoConfig.imagePadding = 8
        photoConfig.baseForegroundColor = .white
        photoConfig.cornerStyle = .large
        photoButton.configuration = photoConfig
        photoButton.showsMenuAsPrimaryAction = true

        let texts = UIStackView(arrangedSubviews: [iconView, titleLabel, bodyLabel])
        texts.axis = .vertical
        texts.alignment = .center
        texts.spacing = DesignSystem.Spacing.m
        let actions = UIStackView(arrangedSubviews: [button, photoButton])
        actions.axis = .vertical
        actions.alignment = .center
        actions.spacing = DesignSystem.Spacing.m
        content.addArrangedSubview(texts)
        content.addArrangedSubview(actions)
        content.alignment = .center
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let safe = safeAreaLayoutGuide
        let margin = DesignSystem.Spacing.l
        let centering = content.centerXAnchor.constraint(equalTo: centerXAnchor)
        centering.priority = UILayoutPriority(rawValue: 999)
        let fill = content.widthAnchor.constraint(equalTo: safe.widthAnchor, constant: -2 * margin)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 64),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            centering,
            content.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: margin),
            content.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -margin),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: AdaptiveLayout.wideColumnWidth),
            fill,
        ])
        arrange(wide: false)

        configure(.denied)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The animals illustration, dimmed, so the fallback surface is part of the app rather than a black void.
    private func addBackdrop() {
        let backdrop = UIImageView(image: RealmArt.image(for: .animals))
        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        backdrop.alpha = 0.34
        backdrop.isAccessibilityElement = false
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            backdrop.setContentHuggingPriority(UILayoutPriority(1), for: axis)
            backdrop.setContentCompressionResistancePriority(UILayoutPriority(1), for: axis)
        }
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let wide = bounds.width > bounds.height
        if wide != isWide { arrange(wide: wide) }
    }

    /// The explanation and the actions sit side by side in a landscape window, divided at its
    /// middle where a fold falls, and stacked in a portrait one.
    private func arrange(wide: Bool) {
        isWide = wide
        content.axis = wide ? .horizontal : .vertical
        content.distribution = wide ? .fillEqually : .fill
        content.spacing = wide ? AdaptiveLayout.foldGap : DesignSystem.Spacing.l
    }

    /// Invoked when the (optional) action button is tapped.
    var onAction: (() -> Void)?

    /// Wires the "identify a photo instead" menu to the Field's two photo paths.
    @MainActor
    func setPhotoActions(onLibrary: @escaping @MainActor () -> Void, onSample: @escaping @MainActor () -> Void) {
        photoButton.menu = PhotoSourceMenu.make(onLibrary: onLibrary, onSample: onSample)
    }

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
