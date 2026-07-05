import AVFoundation
import UIKit

/// The camera-first "Field" — the app's home. Live preview fills the screen; a
/// Liquid Glass HUD floats the capture control and status. One tap runs the
/// spot → identify → collect loop and reveals a minted card.
final class FieldViewController: UIViewController {
    private let camera = CameraController()
    private let identifier: SpeciesIdentifier = SpeciesIdentifierFactory.make()
    private let store = CollectionStore.shared
    private let narrator = NarratorService.shared
    private let enricher = SpeciesEnricher.shared

    private let statusChip = GlassChipView()
    private let captureButton = CaptureButton()
    private let permissionView = CameraPermissionView()
    private var isBusy = false

    private var hasConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        AppLogger.shared.info("field view loaded", category: .capture)
        view.backgroundColor = .black
        view.layer.addSublayer(camera.previewLayer)
        setupHUD()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        camera.previewLayer.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Haptics.prepare()
        // Request camera/location only once the Field is actually on screen — not
        // eagerly at load — so a first-run user isn't prompted behind onboarding.
        if !hasConfigured {
            hasConfigured = true
            LocationProvider.shared.requestAuthorization()
            configureCameraIfAllowed()
        } else if CameraController.authorizationStatus() == .authorized {
            camera.start()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camera.stop()
    }

    private func setupHUD() {
        statusChip.translatesAutoresizingMaskIntoConstraints = false
        statusChip.setText("Point at anything alive")
        view.addSubview(statusChip)

        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(didTapCapture), for: .touchUpInside)
        view.addSubview(captureButton)

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

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.l),
            captureButton.widthAnchor.constraint(equalToConstant: 76),
            captureButton.heightAnchor.constraint(equalToConstant: 76),

            permissionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            permissionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            permissionView.topAnchor.constraint(equalTo: view.topAnchor),
            permissionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureCameraIfAllowed() {
        switch CameraController.authorizationStatus() {
        case .authorized:
            startCamera()
        case .notDetermined:
            requestCameraAccess()
        default:
            showPermissionGate()
        }
    }

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

    private func startCamera() {
        camera.configureAndStart()
        // `canCapture` flips async after configuration; if no usable device
        // attached (Simulator, hardware busy), surface a distinct state rather
        // than a black screen with a dead shutter.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if !camera.canCapture { showCameraUnavailable() }
        }
    }

    private func showPermissionGate() {
        permissionView.configure(.denied)
        permissionView.isHidden = false
        captureButton.isHidden = true
        statusChip.isHidden = true
    }

    private func showCameraUnavailable() {
        permissionView.configure(.unavailable)
        permissionView.isHidden = false
        captureButton.isHidden = true
        statusChip.isHidden = true
    }

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

    private func process(_ image: UIImage) async {
        let context = LocationProvider.shared.currentContext()
        let result = await identifier.identify(image, context: context)
        guard var top = result.top else {
            Haptics.failure()
            finishCapture(reset: "No match — reframe and retry")
            return
        }

        // Enrich with real rarity + fact-sheet from the domain Worker (GBIF/Wikipedia).
        // Best-effort: on timeout/failure the on-device candidate's values stand.
        var grounding: String?
        if let enrichment = await enricher.enrich(candidate: top, context: context) {
            top.rarity = enrichment.rarity
            if let name = enrichment.commonName, !name.isEmpty { top.commonName = name }
            grounding = enrichment.summary
        }

        let id = UUID().uuidString
        let path = ImageStore.save(image, id: id) ?? ""
        let sighting = Sighting(
            id: id,
            speciesId: top.speciesId,
            commonName: top.commonName,
            scientificName: top.scientificName,
            realm: top.realm,
            rarity: top.rarity,
            confidence: top.confidence,
            capturedAt: Date(),
            latitude: context.latitude,
            longitude: context.longitude,
            elevationMeters: context.elevationMeters,
            imagePath: path,
            pokedexEntry: nil)

        var isNew = false
        do {
            isNew = try store.save(sighting)
            AppLogger.shared.info("captured \(top.commonName) new=\(isNew)", category: .capture)
        } catch {
            AppLogger.shared.error("save sighting failed: \(error)", category: .persistence)
        }

        let event = try? ProgressStore.shared.record(rarity: top.rarity, isNew: isNew)
        if let event {
            AppLogger.shared.info("progress +\(event.xpGained)xp streak=\(event.streak) level=\(event.leveledUpTo.map(String.init) ?? "-")", category: .capture)
        }

        if let stats = try? store.stats(), let progress = try? ProgressStore.shared.current() {
            GameCenterService.shared.recordCatch(context: AchievementContext(
                speciesCount: stats.speciesCount, realms: stats.realms,
                maxRarity: stats.maxRarity, longestStreak: progress.longestStreak))
        }

        presentCard(for: sighting, image: image, isNew: isNew, progress: event)
        finishCapture(reset: "Point at anything alive")
        narrate(top, sightingId: id, grounding: grounding)
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
