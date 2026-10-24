import CoreLocation
import LivingDexCore
import UIKit

/// Step 3: location asked in context. A preview of locked slots, then — on grant — the real count of
/// species recorded around the player, counted up. Declining is fine and costs nothing.
final class NearbyStepViewController: OnboardingStepViewController {
    private let titleLabel = OnboardingStyle.label(
        "See what lives near you", style: .largeTitle, weight: .heavy, size: 34)
    private let subtitle = OnboardingStyle.label(
        "Your Nearby tab lists the wild species recorded around you as locked slots. Catch one to unlock it.",
        style: .callout, color: UIColor.white.withAlphaComponent(0.75))
    private let grid = NearbyPreviewGrid()
    private let countLabel = CountUpLabel()
    private let countCaption = OnboardingStyle.label(
        "", style: .subheadline, weight: .semibold, color: UIColor.white.withAlphaComponent(0.8), alignment: .center)
    private let footnote = OnboardingStyle.label(
        "Location is used only while the app is open. You can skip this and turn it on later.",
        style: .footnote, color: UIColor.white.withAlphaComponent(0.6), alignment: .center)
    private lazy var primaryButton = OnboardingStyle.primaryButton(title: "Show what's nearby", symbol: "location.fill") { [weak self] in
        self?.primaryTapped()
    }
    private lazy var laterButton = OnboardingStyle.quietButton(title: "Not now") { [weak self] in
        self?.onAdvance?()
    }
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let requester = LocationPermissionRequester()
    private var phase: Phase = .idle
    private var wideConstraints: [NSLayoutConstraint] = []
    private var compactConstraints: [NSLayoutConstraint] = []
    private var appliedWide: Bool?

    private enum Phase {
        case idle, working, done
    }

    override var artName: String { "realm-plants" }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.accessibilityTraits = .header
        countLabel.alpha = 0
        countCaption.alpha = 0

        let header = UIStackView(arrangedSubviews: [titleLabel, subtitle])
        header.axis = .vertical
        header.spacing = DesignSystem.Spacing.s

        let result = UIStackView(arrangedSubviews: [countLabel, countCaption])
        result.axis = .vertical
        result.spacing = 2
        result.alignment = .center

        let actions = UIStackView(arrangedSubviews: [primaryButton, laterButton, footnote])
        actions.axis = .vertical
        actions.spacing = DesignSystem.Spacing.s

        let gridColumn = UIStackView(arrangedSubviews: [grid, result])
        gridColumn.axis = .vertical
        gridColumn.spacing = DesignSystem.Spacing.m
        gridColumn.alignment = .fill

        content.addArrangedSubview(header)
        content.addArrangedSubview(gridColumn)
        content.spacing = DesignSystem.Spacing.l

        scroll.alwaysBounceVertical = false
        for item in [scroll, actions] as [UIView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        let guide = view.safeAreaLayoutGuide
        let margin = DesignSystem.Spacing.l
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DesignSystem.Spacing.s),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.m),
            grid.heightAnchor.constraint(equalTo: grid.widthAnchor, multiplier: 0.9).withPriority(.defaultHigh),
        ])
        let fillWidth = content.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -margin * 2)
        fillWidth.priority = .defaultHigh
        let fillActions = actions.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -margin * 2)
        fillActions.priority = .defaultHigh
        compactConstraints = [
            fillActions,
            content.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: OnboardingStyle.maxContentWidth),
            fillWidth,
            actions.widthAnchor.constraint(lessThanOrEqualToConstant: OnboardingStyle.maxContentWidth),
            actions.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -DesignSystem.Spacing.s),
            actions.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: margin),
            actions.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -margin),
            actions.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin),
        ]
        wideConstraints = [
            content.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
            content.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -margin),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            header.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.38),
            actions.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin * 1.5),
            actions.widthAnchor.constraint(equalTo: guide.widthAnchor, multiplier: 0.38),
            actions.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin),
        ]
        grid.starterImage = state.chosenStarter?.image
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let wide = isWide
        guard wide != appliedWide else { return }
        appliedWide = wide
        content.axis = wide ? .horizontal : .vertical
        content.alignment = wide ? .top : .fill
        NSLayoutConstraint.deactivate(wide ? compactConstraints : wideConstraints)
        NSLayoutConstraint.activate(wide ? wideConstraints : compactConstraints)
    }

    override func stepDidAppear() {
        grid.starterImage = state.chosenStarter?.image
        grid.startShimmer()
    }

    private func primaryTapped() {
        switch phase {
        case .idle: requestNearby()
        case .working: break
        case .done: onAdvance?()
        }
    }

    private func requestNearby() {
        phase = .working
        Haptics.tap()
        primaryButton.configuration?.showsActivityIndicator = true
        primaryButton.configuration?.title = "Looking around…"
        primaryButton.isEnabled = false
        laterButton.isHidden = true
        Task { @MainActor in
            let status = await requester.request()
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                finish(message: "No problem — turn on location in Settings whenever you want your Nearby list.")
                return
            }
            LocationProvider.shared.warmUp()
            guard let fix = await waitForFix(),
                  let latitude = fix.latitude, let longitude = fix.longitude,
                  let species = await RegionStore.shared.regionalSpecies(latitude: latitude, longitude: longitude),
                  !species.isEmpty
            else {
                finish(message: "Couldn't load your Nearby list right now. It will be ready in the Dex tab.")
                return
            }
            let caught = (try? CollectionStore.shared.stats().speciesCount) ?? 0
            finish(count: species.count, caught: caught)
        }
    }

    private func waitForFix() async -> CaptureContext? {
        for _ in 0..<20 {
            let context = LocationProvider.shared.currentContext()
            if context.latitude != nil { return context }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return nil
    }

    private func finish(count: Int, caught: Int) {
        Haptics.tap()
        countCaption.text = caught > 0
            ? "species live near you — you've caught \(caught)"
            : "species live near you"
        countCaption.accessibilityLabel = "\(count) \(countCaption.text ?? "")"
        UIView.animate(withDuration: 0.4) {
            self.countLabel.alpha = 1
            self.countCaption.alpha = 1
        }
        countLabel.count(to: count)
        grid.revealCaught()
        settle(title: "Continue", symbol: "arrow.right")
    }

    private func finish(message: String) {
        countCaption.text = message
        countCaption.numberOfLines = 0
        UIView.animate(withDuration: 0.4) { self.countCaption.alpha = 1 }
        settle(title: "Continue", symbol: "arrow.right")
    }

    private func settle(title: String, symbol: String) {
        phase = .done
        primaryButton.isEnabled = true
        primaryButton.configuration?.showsActivityIndicator = false
        primaryButton.configuration?.title = title
        primaryButton.configuration?.image = UIImage(systemName: symbol)
        footnote.isHidden = true
    }
}

/// Asks for While-Using location and reports the answer once, whether the prompt appeared or the
/// decision was already made.
@MainActor
final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    func request() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }
        manager.delegate = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard status != .notDetermined, let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: status)
        }
    }
}

/// A big number that counts up to its value.
final class CountUpLabel: UILabel {
    private var task: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = OnboardingStyle.font(.largeTitle, weight: .heavy, size: 64)
        textColor = OnboardingStyle.accent
        textAlignment = .center
        adjustsFontForContentSizeCategory = true
        text = "0"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func count(to value: Int) {
        task?.cancel()
        guard !Motion.reduced, value > 0 else {
            text = "\(value)"
            return
        }
        task = Task { @MainActor [weak self] in
            let steps = 36
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = 1 - pow(1 - Double(step) / Double(steps), 3)
                self?.text = "\(Int((Double(value) * progress).rounded()))"
                try? await Task.sleep(nanoseconds: 24_000_000)
            }
            self?.text = "\(value)"
        }
    }
}

/// A preview of the Nearby tab: locked slots with a slow shimmer, the starter already in place.
final class NearbyPreviewGrid: UIView {
    private var tiles: [UIView] = []
    private let columns = 4
    private let rows = 4
    private let symbols = ["pawprint.fill", "leaf.fill", "circle.hexagongrid.fill", "bird.fill", "leaf.fill", "pawprint.fill"]
    var starterImage: UIImage? {
        didSet { (tiles.first as? PreviewTile)?.setPhoto(starterImage) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "A preview of your Nearby tab with locked species slots"
        for index in 0..<(columns * rows) {
            let tile = PreviewTile(symbol: symbols[index % symbols.count])
            tiles.append(tile)
            addSubview(tile)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 8
        let width = (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        for (index, tile) in tiles.enumerated() {
            let column = index % columns
            let row = index / columns
            tile.frame = CGRect(
                x: CGFloat(column) * (width + gap), y: CGFloat(row) * (height + gap), width: width, height: height)
        }
    }

    func startShimmer() {
        guard !Motion.reduced else { return }
        for (index, tile) in tiles.enumerated() where index != 0 {
            UIView.animate(
                withDuration: 1.6, delay: 0.12 * Double(index), options: [.autoreverse, .repeat, .allowUserInteraction]
            ) { tile.alpha = 0.55 }
        }
    }

    func revealCaught() {
        (tiles.first as? PreviewTile)?.markCaught()
    }
}

private final class PreviewTile: UIView {
    private let glyph = UIImageView()
    private let photo = UIImageView()
    private let badge = UIImageView()

    init(symbol: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.38)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        clipsToBounds = true

        glyph.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        glyph.tintColor = UIColor.white.withAlphaComponent(0.6)
        glyph.contentMode = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        glyph.pinEdges(to: self)

        photo.contentMode = .scaleAspectFill
        photo.isHidden = true
        photo.translatesAutoresizingMaskIntoConstraints = false
        addSubview(photo)
        photo.pinEdges(to: self)

        badge.image = UIImage(systemName: "checkmark.circle.fill")
        badge.tintColor = OnboardingStyle.accent
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setPhoto(_ image: UIImage?) {
        photo.image = image
        photo.isHidden = image == nil
        glyph.isHidden = image != nil
        layer.borderColor = image == nil ? UIColor.white.withAlphaComponent(0.2).cgColor : OnboardingStyle.accent.cgColor
        layer.borderWidth = image == nil ? 1 : 2
    }

    func markCaught() {
        guard !photo.isHidden else { return }
        badge.isHidden = false
        guard !Motion.reduced else { return }
        badge.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        UIView.animate(withDuration: 0.5, delay: 0.2, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
            self.badge.transform = .identity
        }
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
