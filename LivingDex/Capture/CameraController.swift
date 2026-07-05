import AVFoundation
import UIKit

/// Thin wrapper over an AVCaptureSession + photo output. Owns the preview layer;
/// the Field view hosts it and drives capture. Session work runs off the main
/// thread; capture returns Sendable `Data` (the caller builds the UIImage).
///
/// Capture correctness: exactly one in-flight capture at a time, its
/// continuation lock-protected and resumed by exactly one owner (delegate,
/// overlap-rejection, or `stop()`), so it can neither double-resume nor leak.
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let previewLayer: AVCaptureVideoPreviewLayer

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.guitaripod.livingdex.camera")

    private let lock = NSLock()
    private var captureContinuation: CheckedContinuation<Data?, Never>?

    private(set) var isConfigured = false
    /// True only once a working video input is actually attached — capturing
    /// without one raises an uncatchable ObjC exception, so this gates capture.
    private var hasVideoInput = false

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Whether a usable capture device was attached during configuration.
    var canCapture: Bool { hasVideoInput }

    func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { self?.start(); return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.hasVideoInput = true
            } else {
                AppLogger.shared.error("no camera input available", category: .capture)
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()
            self.isConfigured = true
            self.start()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, self.hasVideoInput, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Drain any in-flight capture so a stop mid-capture (e.g. backgrounding)
            // resolves the await instead of wedging it forever.
            self.resolveContinuation(with: nil)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

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
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
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
        error: Error?
    ) {
        if let error {
            AppLogger.shared.error("photo capture failed: \(error.localizedDescription)", category: .capture)
        }
        resolveContinuation(with: photo.fileDataRepresentation())
    }
}
