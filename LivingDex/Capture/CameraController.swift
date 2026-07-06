import AVFoundation
import CoreMedia
import UIKit

/// Thin wrapper over an AVCaptureSession + photo output. Owns the preview layer;
/// the Field view hosts it and drives capture. Session work runs off the main
/// thread; capture returns Sendable `Data` (the caller builds the UIImage).
///
/// Capture correctness: exactly one in-flight capture at a time, its
/// continuation lock-protected and resumed by exactly one owner (delegate,
/// overlap-rejection, or `stop()`), so it can neither double-resume nor leak.
///
/// Configuration correctness: `configureAndStart()` reports real readiness back
/// through an async result (no wall-clock guessing), and `isConfigured` only
/// latches once a working video input is actually attached — so a transient
/// cold-start attach failure is retried on the next call instead of wedging the
/// "camera unavailable" gate for the whole process lifetime.
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate,
    AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let previewLayer: AVCaptureVideoPreviewLayer

    /// Fired on the main queue exactly once per session start, the instant the
    /// first real `CMSampleBuffer` lands — the only true "pixels are live" signal
    /// (`isRunning` / `DidStartRunning` fire before any frame reaches the layer).
    /// The host uses it to cross-fade the preview in from its loading cover so the
    /// user never sees the bare layer's opaque-black pre-frame state.
    var onFirstFrame: (@Sendable () -> Void)?

    /// Fired on the main queue when the running session is interrupted (e.g. a
    /// phone call or Control Center camera grabs the device) so the host can put
    /// the loading cover back rather than showing a frozen frame. A matching reveal
    /// arrives via `onFirstFrame` once the interruption ends and frames resume.
    var onInterrupted: (@Sendable () -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.guitaripod.livingdex.camera")
    private let videoDataQueue = DispatchQueue(label: "com.guitaripod.livingdex.camera.videodata")

    private let lock = NSLock()
    private var captureContinuation: CheckedContinuation<Data?, Never>?
    /// Armed on each `startRunning()`, disarmed by the first delivered frame, so
    /// every (re)start — cold launch or tab return — emits exactly one reveal.
    private var firstFrameArmed = false

    private var isConfigured = false
    /// True only once a working video input is actually attached — capturing
    /// without one raises an uncatchable ObjC exception, so this gates capture.
    private var hasVideoInput = false
    private var videoDevice: AVCaptureDevice?

    /// Native zoom factor that reads as 1.0× to the user (the wide-lens switch-over
    /// on a virtual multi-lens device, else 1). User zoom is expressed relative to
    /// this so 1.0× is the standard wide field of view.
    private var baselineZoom: CGFloat = 1
    /// User-facing zoom bounds (relative to `baselineZoom`), computed at
    /// configuration and read on the main thread only after the async config
    /// result has resolved.
    private(set) var minUserZoom: CGFloat = 1
    private(set) var maxUserZoom: CGFloat = 1
    private(set) var hasTorch = false

    /// Longest-edge cap for captured photos. The card and grid thumbnails need far
    /// less than a full-sensor frame; capping cuts shutter-to-data latency, cloud
    /// upload bytes, disk growth, and peak memory with no visible quality loss.
    private static let maxPhotoEdge: Int32 = 3024
    /// Hand-held zoom ceiling — beyond this digital zoom is unusable mush.
    private static let maxUserZoomCap: CGFloat = 10

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
        registerSessionObservers()
    }

    private func registerSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(sessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(
            self, selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification, object: session)
        center.addObserver(
            self, selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    @objc private func sessionWasInterrupted(_ note: Notification) {
        let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? -1
        let name: String
        switch AVCaptureSession.InterruptionReason(rawValue: raw) {
        case .videoDeviceNotAvailableInBackground: name = "notAvailableInBackground"
        case .audioDeviceInUseByAnotherClient: name = "audioInUseByAnotherClient"
        case .videoDeviceInUseByAnotherClient: name = "videoInUseByAnotherClient"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: name = "multipleForegroundApps"
        case .videoDeviceNotAvailableDueToSystemPressure: name = "systemPressure"
        default: name = "unknown"
        }
        AppLogger.shared.warn("session interrupted reason=\(raw) (\(name))", category: .capture)
        let callback = onInterrupted
        if let callback { DispatchQueue.main.async { callback() } }
    }

    /// Re-arm the first-frame reveal so resumed frames cross-fade the preview back
    /// in — the session auto-resumes without another `startLocked()`, so nothing
    /// else would re-arm it.
    @objc private func sessionInterruptionEnded(_ note: Notification) {
        AppLogger.shared.info("session interruption ended", category: .capture)
        lock.lock()
        firstFrameArmed = true
        lock.unlock()
    }

    @objc private func sessionRuntimeError(_ note: Notification) {
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
        AppLogger.shared.error("session runtime error=\(String(describing: error))", category: .capture)
    }

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Configures (if needed) and starts the session, resuming with whether a
    /// usable capture device is now attached. Awaiting the real completion removes
    /// the old sleep-and-poll race and the cross-thread read of `hasVideoInput`.
    @discardableResult
    func configureAndStart() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                if !self.isConfigured {
                    self.configureLocked()
                }
                self.startLocked()
                continuation.resume(returning: self.hasVideoInput)
            }
        }
    }

    /// Builds the session graph. `isConfigured` latches true only when a video
    /// input attaches, so a call made while the camera is busy (another app,
    /// FaceTime, cold-start contention) leaves it false and the next call retries
    /// attachment rather than permanently disabling capture.
    private func configureLocked() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if !hasVideoInput {
            attachVideoInputLocked()
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        attachVideoDataOutputLocked()
        if let device = videoDevice {
            applyPhotoDimensionCap(for: device)
        }
        session.commitConfiguration()
        if let device = videoDevice {
            configureZoomBaseline(for: device)
            hasTorch = device.hasTorch
        }
        isConfigured = hasVideoInput
        AppLogger.shared.info("camera configured hardwareCost=\(session.hardwareCost)", category: .capture)
    }

    /// Adds the single permitted video-data output. Its first delivered buffer is
    /// the app's "preview is live" trigger; the same output is the seam the future
    /// on-device Core ML pipeline consumes (a session allows only one, so it is
    /// created once here rather than as a throwaway probe).
    private func attachVideoDataOutputLocked() {
        guard session.canAddOutput(videoDataOutput) else { return }
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        session.addOutput(videoDataOutput)
    }

    private func attachVideoInputLocked() {
        guard let device = Self.preferredDevice() else {
            AppLogger.shared.error("no camera input available", category: .capture)
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            AppLogger.shared.error("camera input attach failed", category: .capture)
            return
        }
        session.addInput(input)
        videoDevice = device
        hasVideoInput = true
    }

    /// Prefers a virtual multi-lens device so pinch zoom crosses the optical
    /// ultra-wide/tele lenses, falling back to the plain wide-angle camera.
    private static func preferredDevice() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    /// Caps `maxPhotoDimensions` to the largest supported frame under
    /// `maxPhotoEdge`, or the smallest available if every option is larger.
    private func applyPhotoDimensionCap(for device: AVCaptureDevice) {
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        guard !supported.isEmpty else { return }
        let underCap = supported.filter { max($0.width, $0.height) <= Self.maxPhotoEdge }
        let chosen = underCap.max { area($0) < area($1) }
            ?? supported.min { area($0) < area($1) }
        if let chosen {
            photoOutput.maxPhotoDimensions = chosen
        }
    }

    private func area(_ dimensions: CMVideoDimensions) -> Int {
        Int(dimensions.width) * Int(dimensions.height)
    }

    /// Maps user zoom so 1.0× is the standard wide field of view and records the
    /// reachable range (ultra-wide below 1×, optical tele above).
    private func configureZoomBaseline(for device: AVCaptureDevice) {
        let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) }
        baselineZoom = max(switchOver ?? 1, 1)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampNative(baselineZoom, for: device)
            device.unlockForConfiguration()
        } catch {
            AppLogger.shared.warn("zoom baseline failed: \(error.localizedDescription)", category: .capture)
        }
        minUserZoom = device.minAvailableVideoZoomFactor / baselineZoom
        maxUserZoom = min(device.maxAvailableVideoZoomFactor / baselineZoom, Self.maxUserZoomCap)
    }

    private func clampNative(_ factor: CGFloat, for device: AVCaptureDevice) -> CGFloat {
        let upper = min(device.maxAvailableVideoZoomFactor, baselineZoom * Self.maxUserZoomCap)
        return min(max(factor, device.minAvailableVideoZoomFactor), upper)
    }

    func start() {
        sessionQueue.async { [weak self] in
            self?.startLocked()
        }
    }

    private func startLocked() {
        guard hasVideoInput, !session.isRunning else { return }
        lock.lock()
        firstFrameArmed = true
        lock.unlock()
        session.startRunning()
    }

    /// Stops the session, first draining any in-flight capture so a stop
    /// mid-capture (e.g. backgrounding) resolves its await instead of leaking.
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.resolveContinuation(with: nil)
            self.lock.lock()
            self.firstFrameArmed = false
            self.lock.unlock()
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: Live controls

    /// Sets the zoom in user units (1.0× == standard wide), clamped to the device's
    /// reachable range. Applied on the session queue under a device config lock.
    func setUserZoom(_ userFactor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let native = self.clampNative(userFactor * self.baselineZoom, for: device)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = native
                device.unlockForConfiguration()
            } catch {
                AppLogger.shared.warn("zoom failed: \(error.localizedDescription)", category: .capture)
            }
        }
    }

    /// Focuses and meters exposure at a device point (0…1, from
    /// `previewLayer.captureDevicePointConverted(fromLayerPoint:)`).
    func focusAndExpose(atDevicePoint point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                AppLogger.shared.warn("focus failed: \(error.localizedDescription)", category: .capture)
            }
        }
    }

    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                AppLogger.shared.warn("torch failed: \(error.localizedDescription)", category: .capture)
            }
        }
    }

    // MARK: Capture

    /// Captures a photo and returns its JPEG data (Sendable), or nil if the
    /// camera is unusable or a capture is already in flight.
    func capture() async -> Data? {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.isConfigured, self.hasVideoInput,
                      self.photoOutput.connection(with: .video) != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                self.lock.lock()
                let busy = self.captureContinuation != nil
                if !busy { self.captureContinuation = continuation }
                self.lock.unlock()
                if busy {
                    continuation.resume(returning: nil)
                    return
                }
                self.photoOutput.capturePhoto(with: self.makePhotoSettings(), delegate: self)
            }
        }
    }

    /// Prioritizes shutter speed over Deep Fusion and caps output resolution to the
    /// dimension chosen at configuration — the app never needs a full-sensor frame.
    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .speed
        let dimensions = photoOutput.maxPhotoDimensions
        if dimensions.width > 0, dimensions.height > 0 {
            settings.maxPhotoDimensions = dimensions
        }
        return settings
    }

    /// Atomically takes ownership of the pending continuation (if any) and
    /// resumes it exactly once. Safe to call from any queue.
    private func resolveContinuation(with data: Data?) {
        lock.lock()
        let continuation = captureContinuation
        captureContinuation = nil
        lock.unlock()
        continuation?.resume(returning: data)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        if let error {
            AppLogger.shared.error("photo capture failed: \(error.localizedDescription)", category: .capture)
        }
        resolveContinuation(with: photo.fileDataRepresentation())
    }

    /// The first buffer after a start means live pixels have reached the graph —
    /// hand the reveal signal to the host exactly once, then go quiet (subsequent
    /// frames are the on-device pipeline's to consume). Runs on `videoDataQueue`;
    /// the armed flag and callback are read under the shared lock.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        let shouldEmit = firstFrameArmed
        if shouldEmit { firstFrameArmed = false }
        let callback = onFirstFrame
        lock.unlock()
        guard shouldEmit, let callback else { return }
        DispatchQueue.main.async { callback() }
    }
}
