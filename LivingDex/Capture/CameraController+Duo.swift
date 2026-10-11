#if canImport(UIKit, _version: 9127.0.85)
import AVFoundation
import UIKit

/// Camera behaviour that only exists once the displays can change under a running session:
/// switching to a camera that still looks away from the display in use, keeping the preview
/// and photos upright as the app moves between displays, and leaving the preview unmirrored.
/// Everything here is gated to iOS 27.1 so earlier systems keep the single-camera path.
@available(iOS 27.1, *)
extension CameraController {
    /// Moves the session to the camera with `id`. A failed switch puts the previous input
    /// back, so the preview never ends up without a camera.
    func switchDevice(toDeviceWithID id: String) {
        sessionQueue.async { [weak self] in
            guard let self, self.hasVideoInput, id != self.activeDeviceID,
                  let device = AVCaptureDevice(uniqueID: id),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            let previous = self.session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                .first { $0.device.hasMediaType(.video) }
            self.session.beginConfiguration()
            if let previous { self.session.removeInput(previous) }
            guard self.session.canAddInput(input) else {
                if let previous { self.session.addInput(previous) }
                self.session.commitConfiguration()
                AppLogger.shared.warn("camera switch refused for \(device.localizedName)", category: .capture)
                return
            }
            self.session.addInput(input)
            self.setVideoDevice(device)
            self.applyPhotoDimensionCap(for: device)
            self.session.commitConfiguration()
            self.configureZoomBaseline(for: device)
            self.hasTorch = device.hasTorch
            self.adaptToDisplays(for: device)
            AppLogger.shared.info("camera switched to \(device.localizedName)", category: .capture)
            if let callback = self.onDeviceChanged {
                DispatchQueue.main.async { callback() }
            }
        }
    }

    /// Hands orientation to the rotation coordinator for `device`, turns off the sensor
    /// orientation compensation it replaces, and leaves both connections unmirrored: the
    /// Field always looks at the scene behind the display, and that is never a selfie.
    func adaptToDisplays(for device: AVCaptureDevice) {
        if photoOutput.isCameraSensorOrientationCompensationSupported {
            photoOutput.isCameraSensorOrientationCompensationEnabled = false
        }
        leaveUnmirrored(photoOutput.connection(with: .video))
        let deviceID = device.uniqueID
        Task { @MainActor [weak self] in
            guard let device = AVCaptureDevice(uniqueID: deviceID) else { return }
            self?.installRotationCoordinator(for: device)
        }
    }

    /// Applies the latest rotation for photos; called on the session queue just before a capture.
    func applyCaptureRotation() {
        lock.lock()
        let angle = captureRotationAngle
        lock.unlock()
        guard let angle, let connection = photoOutput.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func leaveUnmirrored(_ connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = false
    }

    @MainActor
    private func installRotationCoordinator(for device: AVCaptureDevice) {
        leaveUnmirrored(previewLayer.connection)
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        let preview = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) {
            [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor in self?.rotatePreview(to: angle) }
        }
        let capture = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) {
            [weak self] coordinator, _ in
            self?.storeCaptureRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        }
        displayAdaptation = RotationState(coordinator: coordinator, observations: [preview, capture])
    }

    @MainActor
    private func rotatePreview(to angle: CGFloat) {
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func storeCaptureRotation(_ angle: CGFloat) {
        lock.lock()
        captureRotationAngle = angle
        lock.unlock()
    }

    /// Keeps the coordinator and its observations alive for as long as the camera is.
    private final class RotationState {
        let coordinator: AVCaptureDevice.RotationCoordinator
        let observations: [NSKeyValueObservation]

        init(coordinator: AVCaptureDevice.RotationCoordinator, observations: [NSKeyValueObservation]) {
            self.coordinator = coordinator
            self.observations = observations
        }
    }
}
#endif
