import AVFoundation
import AVKit
import UIKit

/// Which camera the Field should stream from when the displays can face opposite ways.
/// The viewfinder must look at the scene behind the display the person is using, so a
/// camera that already does is kept and otherwise the best-ranked one that does is chosen.
enum CameraDirectionPolicy {
    struct Candidate: Equatable, Sendable {
        let uniqueID: String
        let deviceType: String
    }

    /// The camera to switch to, or nil when the active one already looks away from the
    /// display or there is nothing better to offer. A lower index in `ranking` wins and
    /// unranked types come last, in the order given.
    static func replacement(activeID: String?, backwardFacing: [Candidate], ranking: [String]) -> Candidate? {
        guard !backwardFacing.isEmpty else { return nil }
        if let activeID, backwardFacing.contains(where: { $0.uniqueID == activeID }) { return nil }
        let ranked = backwardFacing.enumerated().map { offset, candidate in
            (rank: ranking.firstIndex(of: candidate.deviceType) ?? ranking.count, offset: offset, candidate: candidate)
        }
        return ranked.min { ($0.rank, $0.offset) < ($1.rank, $1.offset) }?.candidate
    }
}

#if canImport(UIKit, _version: 9127.0.85)
/// Watches which of the device's cameras look away from the display showing the preview and
/// asks for a switch when the active one stops doing so, for instance when the person opens
/// the Duo and moves from the outer display to the inner one. Only the direction of each
/// camera is read here; the capture session is changed by the caller on its own queue.
@available(iOS 27.1, *)
@MainActor
final class CameraDirectionMonitor {
    private var coordinator: AVCaptureDeviceDirectionCoordinator?
    private let activeDeviceID: @Sendable () -> String?
    private let onReplacement: @MainActor (String) -> Void

    /// The built-in cameras the Field may capture from, best first: every rear camera and both
    /// ultra-wide cameras that sit on the outer and inner displays.
    private static let rankedTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        .builtInUltraWideCamera, .builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera,
    ]

    init(
        view: UIView,
        activeDeviceID: @escaping @Sendable () -> String?,
        onReplacement: @escaping @MainActor (String) -> Void
    ) {
        self.activeDeviceID = activeDeviceID
        self.onReplacement = onReplacement
        coordinator = AVCaptureDeviceDirectionCoordinator(view: view, deviceTypes: Self.rankedTypes) { [weak self] map in
            let backward = Self.backwardFacing(in: map)
            MainActor.assumeIsolated { self?.directionsChanged(backward) }
        }
    }

    /// Re-reads the current directions, for the moment the session first attaches a camera: the
    /// coordinator reported its starting configuration before there was an active camera to
    /// compare it with, and it reports nothing more until a camera changes direction.
    func reevaluate() {
        guard let map = coordinator?.deviceDirections else { return }
        directionsChanged(Self.backwardFacing(in: map))
    }

    nonisolated private static func backwardFacing(in map: AVCaptureDeviceDirectionMap) -> [CameraDirectionPolicy.Candidate] {
        map.backwardFacingDeviceDescriptors.map {
            CameraDirectionPolicy.Candidate(uniqueID: $0.uniqueID, deviceType: $0.deviceType.rawValue)
        }
    }

    private func directionsChanged(_ backward: [CameraDirectionPolicy.Candidate]) {
        let replacement = CameraDirectionPolicy.replacement(
            activeID: activeDeviceID(), backwardFacing: backward, ranking: Self.rankedTypes.map(\.rawValue))
        guard let replacement else { return }
        AppLogger.shared.info("camera direction changed, switching to \(replacement.deviceType)", category: .capture)
        onReplacement(replacement.uniqueID)
    }
}
#endif
