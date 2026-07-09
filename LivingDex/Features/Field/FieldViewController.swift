import AVFoundation
import UIKit

/// The camera-first "Field" — the app's home. Live preview fills the screen; a
/// Liquid Glass HUD floats the capture control, status, torch, and zoom. One tap
/// runs the spot → identify → collect loop (delegated to `CaptureFlow`) and
/// reveals a minted card; pinch zooms, tap focuses.
final class FieldViewController: UIViewController {
    private let camera = CameraController()
    private let store = CollectionStore.shared
    private let narrator = NarratorService.shared
    private let captureFlow = CaptureFlow.live()

    private let statusChip = GlassChipView()
    private let captureButton = CaptureButton()
    private let permissionView = CameraPermissionView()
    private let torchButton = GlassIconButton()
    private let zoomChip = GlassChipView()
    private let loadingView = CameraLoadingView()

    private var pinchGesture: UIPinchGestureRecognizer!
    private var focusTapGesture: UITapGestureRecognizer!

    private var isBusy = false
    private var didRequestPermission = false
    private var cameraStarted = false
    private var cameraReady = false
    private var isPreviewRevealed = false
    private var isSessionStopped = false

    /// Backstop reveal if no frame arrives within the window (interruption, device
    /// contention) — better to drop the cover than strand the user on it.
    private var revealTimeout: DispatchWorkItem?
    /// Debounced teardown so a quick tab-away/return doesn't cold-start (and
    /// re-cover) the camera on every switch.
    private var pendingStop: DispatchWorkItem?
    private static let stopDebounce: TimeInterval = 0.75
    private static let revealTimeoutSeconds: TimeInterval = 2.0

    private var currentUserZoom: CGFloat = 1
    private var pinchStartZoom: CGFloat = 1
    private var torchOn = false
    private var zoomChipHide: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        AppLogger.shared.info("field view loaded", category: .capture)
        view.backgroundColor = .black
        camera.previewLayer.opacity = 0
        view.layer.addSublayer(camera.previewLayer)

        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)

        setupHUD()
        setupGestures()

        camera.onFirstFrame = { [weak self] in self?.revealPreview() }
        camera.onInterrupted = { [weak self] in self?.handleInterruption() }

        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)

        NSLayoutConstraint.activate([
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        camera.previewLayer.frame = view.bounds
    }

    /// Shows the loading cover as the Field appears, then starts the camera only
    /// when the app is already `.active`. Starting while the scene is still
    /// `foregroundInactive` (the case during launch) makes AVFoundation interrupt
    /// the session with `videoDeviceNotAvailableInBackground` — frames flow for a
    /// beat, then freeze for seconds until the app finally activates. So on a cold
    /// launch we wait for `didBecomeActive`; a warm tab-return (already active)
    /// starts immediately. A pending debounced stop is cancelled so a quick
    /// tab-away/return keeps the live preview.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Haptics.prepare()
        pendingStop?.cancel()
        pendingStop = nil
        guard CameraController.authorizationStatus() == .authorized else { return }
        LocationProvider.shared.requestAuthorization()
        if UIApplication.shared.applicationState == .active {
            resumeCameraIfNeeded()
        } else if !isPreviewRevealed {
            beginPreviewCover()
        }
    }

    /// The permission prompt (and its denied/gate handling) waits for the view to
    /// fully settle so the system alert never fires mid-transition, and so a
    /// first-run user isn't prompted behind onboarding.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didRequestPermission else { return }
        didRequestPermission = true
        switch CameraController.authorizationStatus() {
        case .authorized:
            LocationProvider.shared.requestAuthorization()
        case .notDetermined:
            requestCameraAccess()
        default:
            showPermissionGate()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if torchOn { toggleTorch() }
        cancelRevealTimeout()
        scheduleDebouncedStop()
    }

    /// The camera can only run when the app is `.active`, so this is the correct
    /// moment to (re)start on a cold launch and to recover after the app returns
    /// from the background — but only while the Field is actually on screen.
    @objc private func appDidBecomeActive() {
        guard isViewLoaded, view.window != nil,
              CameraController.authorizationStatus() == .authorized else { return }
        pendingStop?.cancel()
        pendingStop = nil
        resumeCameraIfNeeded()
    }

    /// The system reclaims the camera when the app leaves the active state; tear
    /// down immediately (no debounce) and re-cover so the next activation reveals
    /// cleanly rather than flashing a stale frame.
    @objc private func appWillResignActive() {
        cancelRevealTimeout()
        if isPreviewRevealed { beginPreviewCover() }
        camera.stop()
        isSessionStopped = true
    }

    /// A live-session interruption (phone call, Control Center camera, or a
    /// launch-time background window) froze the feed — hold the loading cover and
    /// stop the reveal timeout so we never cross-fade to a frozen frame.
    /// `CameraController` re-arms `onFirstFrame`, so the reveal fires when frames
    /// actually resume.
    private func handleInterruption() {
        cancelRevealTimeout()
        beginPreviewCover()
    }

    // MARK: Setup

    private func setupHUD() {
        statusChip.translatesAutoresizingMaskIntoConstraints = false
        statusChip.setText("Point at anything alive")
        // Hidden until a live session reveals the preview: on a cold, not-yet-
        // authorized launch these must not sit tappable above the loading cover /
        // permission dialog (a tap would run capture against a dead camera).
        statusChip.isHidden = true
        view.addSubview(statusChip)

        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.isHidden = true
        captureButton.addTarget(self, action: #selector(didTapCapture), for: .touchUpInside)
        view.addSubview(captureButton)

        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.isHidden = true
        torchButton.setSymbol("flashlight.off.fill")
        torchButton.accessibilityLabel = "Torch off"
        torchButton.addTarget(self, action: #selector(didTapTorch), for: .touchUpInside)
        view.addSubview(torchButton)

        zoomChip.translatesAutoresizingMaskIntoConstraints = false
        zoomChip.isHidden = true
        view.addSubview(zoomChip)

        permissionView.translatesAutoresizingMaskIntoConstraints = false
        permissionView.isHidden = true
        permissionView.onAction = {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }
        view.addSubview(permissionView)

        NSLayoutConstraint.activate([
            statusChip.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusChip.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignSystem.Spacing.m),

            torchButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -DesignSystem.Spacing.m),
            torchButton.centerYAnchor.constraint(equalTo: statusChip.centerYAnchor),
            torchButton.widthAnchor.constraint(equalToConstant: 44),
            torchButton.heightAnchor.constraint(equalToConstant: 44),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.l),
            captureButton.widthAnchor.constraint(equalToConstant: 76),
            captureButton.heightAnchor.constraint(equalToConstant: 76),

            zoomChip.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomChip.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -DesignSystem.Spacing.m),

            permissionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            permissionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            permissionView.topAnchor.constraint(equalTo: view.topAnchor),
            permissionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupGestures() {
        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinchGesture.delegate = self
        pinchGesture.isEnabled = false
        view.addGestureRecognizer(pinchGesture)

        focusTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap))
        focusTapGesture.delegate = self
        focusTapGesture.isEnabled = false
        view.addGestureRecognizer(focusTapGesture)
    }

    // MARK: Camera lifecycle

    private func requestCameraAccess() {
        Task { @MainActor in
            let granted = await CameraController.requestAccess()
            if granted {
                permissionView.isHidden = true
                startCamera()
            } else {
                showPermissionGate()
            }
        }
    }

    /// Recovers when returning to the tab: a still-running session (quick switch,
    /// debounced stop cancelled) is already live and needs nothing; a stopped one
    /// re-covers and restarts, revealing on its next first frame; an unattached one
    /// re-configures so the "unavailable" gate is never permanent.
    private func resumeCameraIfNeeded() {
        if !cameraStarted || !cameraReady {
            startCamera()
        } else if isSessionStopped {
            beginPreviewCover()
            camera.start()
            armRevealTimeout()
        }
    }

    /// Configures + starts the session, then waits for the first real frame (or the
    /// timeout) to reveal — the preview is never shown while it is still black.
    private func startCamera() {
        cameraStarted = true
        isSessionStopped = false
        beginPreviewCover()
        Task { @MainActor in
            let ready = await camera.configureAndStart()
            cameraReady = ready
            if ready {
                armRevealTimeout()
            } else {
                showCameraUnavailable()
            }
        }
    }

    /// Restores the opaque loading cover and hides the HUD ahead of a (re)start, so
    /// the reveal cross-fade always animates from a clean loading state.
    private func beginPreviewCover() {
        isPreviewRevealed = false
        loadingView.isHidden = false
        loadingView.alpha = 1
        loadingView.startBreathing()
        camera.previewLayer.opacity = 0
        captureButton.isHidden = true
        statusChip.isHidden = true
        torchButton.isHidden = true
        zoomChip.isHidden = true
        UIAccessibility.post(notification: .announcement, argument: "Camera loading")
    }

    /// Cross-fades the live preview in and dismisses the loading cover the instant
    /// real pixels land (driven by `CameraController.onFirstFrame`), or on the
    /// backstop timeout. Idempotent per presentation.
    private func revealPreview() {
        guard !isPreviewRevealed else { return }
        isPreviewRevealed = true
        cancelRevealTimeout()
        dismissGates()
        configureCameraControls()

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.3
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        camera.previewLayer.opacity = 1
        camera.previewLayer.add(fade, forKey: "reveal")

        UIView.animate(withDuration: 0.3) {
            self.loadingView.alpha = 0
        } completion: { _ in
            self.loadingView.isHidden = true
            self.loadingView.stopBreathing()
            UIAccessibility.post(notification: .announcement, argument: "Camera ready")
        }
        Haptics.tap()
    }

    private func armRevealTimeout() {
        cancelRevealTimeout()
        let work = DispatchWorkItem { [weak self] in
            AppLogger.shared.warn("preview reveal timed out — no first frame", category: .capture)
            self?.revealPreview()
        }
        revealTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealTimeoutSeconds, execute: work)
    }

    private func cancelRevealTimeout() {
        revealTimeout?.cancel()
        revealTimeout = nil
    }

    private func scheduleDebouncedStop() {
        pendingStop?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isSessionStopped = true
            self.camera.stop()
        }
        pendingStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopDebounce, execute: work)
    }

    private func dismissGates() {
        permissionView.isHidden = true
        captureButton.isHidden = false
        statusChip.isHidden = false
    }

    /// Enables the live controls once a device is confirmed attached — driven by
    /// the real configuration result, never a timer.
    private func configureCameraControls() {
        currentUserZoom = 1
        torchOn = false
        torchButton.setActive(false)
        torchButton.setSymbol("flashlight.off.fill")
        torchButton.accessibilityLabel = "Torch off"
        torchButton.isHidden = !camera.hasTorch
        pinchGesture.isEnabled = true
        focusTapGesture.isEnabled = true
    }

    private func showPermissionGate() {
        permissionView.configure(.denied)
        presentGate()
    }

    private func showCameraUnavailable() {
        permissionView.configure(.unavailable)
        presentGate()
    }

    private func presentGate() {
        cancelRevealTimeout()
        loadingView.isHidden = true
        loadingView.stopBreathing()
        permissionView.isHidden = false
        captureButton.isHidden = true
        statusChip.isHidden = true
        torchButton.isHidden = true
        zoomChip.isHidden = true
        pinchGesture.isEnabled = false
        focusTapGesture.isEnabled = false
    }

    // MARK: Live controls

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartZoom = currentUserZoom
        case .changed:
            let proposed = pinchStartZoom * gesture.scale
            let clamped = min(max(proposed, camera.minUserZoom), camera.maxUserZoom)
            currentUserZoom = clamped
            camera.setUserZoom(clamped)
            showZoomChip(clamped)
        case .ended, .cancelled, .failed:
            scheduleZoomChipHide()
        default:
            break
        }
    }

    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        let devicePoint = camera.previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        camera.focusAndExpose(atDevicePoint: devicePoint)
        showFocusReticle(at: point)
        Haptics.tap()
    }

    @objc private func didTapTorch() {
        toggleTorch()
        Haptics.tap()
    }

    private func toggleTorch() {
        torchOn.toggle()
        camera.setTorch(torchOn)
        torchButton.setActive(torchOn)
        torchButton.setSymbol(torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
        torchButton.accessibilityLabel = torchOn ? "Torch on" : "Torch off"
    }

    private func showZoomChip(_ factor: CGFloat) {
        zoomChipHide?.cancel()
        zoomChip.isHidden = false
        zoomChip.setText(String(format: "%.1f×", factor), animated: false)
    }

    private func scheduleZoomChipHide() {
        let work = DispatchWorkItem { [weak self] in self?.zoomChip.isHidden = true }
        zoomChipHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func showFocusReticle(at point: CGPoint) {
        let reticle = focusReticle
        view.bringSubviewToFront(reticle)
        reticle.center = point
        reticle.layer.removeAllAnimations()
        reticle.alpha = 1
        reticle.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            reticle.transform = .identity
        }
        UIView.animate(withDuration: 0.3, delay: 0.7, options: []) {
            reticle.alpha = 0
        }
    }

    private lazy var focusReticle: UIView = {
        let reticle = UIView(frame: CGRect(x: 0, y: 0, width: 74, height: 74))
        reticle.layer.borderColor = DesignSystem.Color.accent.cgColor
        reticle.layer.borderWidth = 1.5
        reticle.layer.cornerRadius = 6
        reticle.layer.cornerCurve = .continuous
        reticle.isUserInteractionEnabled = false
        reticle.alpha = 0
        view.addSubview(reticle)
        return reticle
    }()

    // MARK: Capture

    @objc private func didTapCapture() {
        guard !isBusy else { return }
        isBusy = true
        Haptics.shutter()
        captureButton.setCapturing(true)
        statusChip.setText("Identifying…")

        Task { @MainActor in
            let data = await camera.capture()
            guard let data, let image = UIImage(data: data) else {
                Haptics.failure()
                finishCapture(reset: "Couldn't capture — try again")
                return
            }
            await process(image)
        }
    }

    /// Renders the outcome of the capture pipeline. All decisions and side effects
    /// happen inside `CaptureFlow.run`; the view controller only surfaces state.
    private func process(_ image: UIImage) async {
        let context = LocationProvider.shared.currentContext()
        switch await captureFlow.run(image: image, context: context) {
        case let .identifyFailed(error):
            Haptics.failure()
            finishCapture(reset: Self.message(for: error))
            if case .creditsExhausted = error { promptGoProForCredits() }
        case .lowConfidence:
            Haptics.failure()
            finishCapture(reset: Self.lowConfidenceMessage)
        case .unresolvedSpecies:
            Haptics.failure()
            finishCapture(reset: "Couldn't confirm that species — try a clearer, closer shot")
        case .saveFailed:
            Haptics.failure()
            finishCapture(reset: "Couldn't save that catch — try again")
        case let .minted(capture):
            AppLogger.shared.info("captured \(capture.sighting.commonName) new=\(capture.isNew)", category: .capture)
            presentCard(for: capture.sighting, image: capture.image, isNew: capture.isNew, progress: capture.progress)
            finishCapture(reset: "Point at anything alive")
            narrate(capture.candidate, sightingId: capture.sighting.id, grounding: capture.grounding)
        }
    }

    /// Offers the way out of the metered cap the instant a cloud ID is refused for want of
    /// credits: go Pro for unlimited cloud IDs, or top up consumable credits. Silent for a
    /// user who already holds Pro (they should never hit this) — the alert would be noise.
    private func promptGoProForCredits() {
        guard !SubscriptionService.shared.isPro else { return }
        let alert = UIAlertController(
            title: "Out of cloud IDs",
            message: "You've used your cloud identifications. Go Pro for unlimited cloud IDs, or add credits to keep identifying.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Go Pro", style: .default) { [weak self] _ in
            guard let self else { return }
            PaywallPresenter.present(from: self, reason: "You've hit the cloud-ID cap.")
        })
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel))
        present(alert, animated: true)
    }

    private static let lowConfidenceMessage = "No clear living thing — get closer to a plant, animal, or bug"

    /// Distinct, honest recovery copy per identification failure — an offline user
    /// or one out of credits is never told their photo was simply bad.
    private static func message(for error: IdentifyError) -> String {
        switch error {
        case .offline: return "You're offline — reconnect and try again"
        case .creditsExhausted: return "Out of cloud IDs — add credits to keep identifying"
        case .serverError: return "Identification hiccup — try again in a moment"
        case .noSpecies: return lowConfidenceMessage
        }
    }

    /// Fills the Pokédex entry in the background (on-device model first, cloud
    /// fallback), grounded in the Worker fact-sheet. Never blocks the capture loop.
    private func narrate(_ candidate: SpeciesCandidate, sightingId: String, grounding: String?) {
        Task.detached { [narrator, store] in
            guard let entry = await narrator.entry(for: candidate, grounding: grounding) else { return }
            do {
                try store.setNarration(sightingId: sightingId, entry: entry)
            } catch {
                AppLogger.shared.error("persist narration failed: \(error)", category: .persistence)
            }
        }
    }

    private func presentCard(for sighting: Sighting, image: UIImage, isNew: Bool, progress: ProgressEvent?) {
        let card = CardRevealViewController(sighting: sighting, image: image, isNewDexEntry: isNew, progress: progress)
        card.modalPresentationStyle = .overFullScreen
        card.modalTransitionStyle = .crossDissolve
        present(card, animated: true)
    }

    private func finishCapture(reset text: String) {
        isBusy = false
        captureButton.setCapturing(false)
        statusChip.setText(text)
    }
}

extension FieldViewController: UIGestureRecognizerDelegate {
    /// Keeps focus taps off the HUD controls (capture ring, torch, permission gate)
    /// so tapping a button never also drops a focus reticle behind it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === focusTapGesture, let touched = touch.view else { return true }
        return !touched.isDescendant(of: captureButton)
            && !touched.isDescendant(of: torchButton)
            && !touched.isDescendant(of: permissionView)
    }
}
