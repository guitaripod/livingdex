import CoreLocation
import CoreMotion

/// One-shot capture context: current coarse location + barometric elevation,
/// used to geo-tag a sighting and re-rank identification against a local prior.
/// Location is While-Using only; failures degrade to a nil-location sighting.
final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private var pending: [(CaptureContext) -> Void] = []
    private var lastElevation: Double?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
                self?.lastElevation = data?.altitude
            }
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Returns the best currently-available context. Non-blocking: uses the last
    /// known fix (requesting a fresh one for next time) so capture stays instant.
    func currentContext() -> CaptureContext {
        manager.requestLocation()
        let loc = manager.location
        return CaptureContext(
            latitude: loc?.coordinate.latitude,
            longitude: loc?.coordinate.longitude,
            elevationMeters: lastElevation ?? loc?.altitude)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.shared.warn("location error: \(error.localizedDescription)", category: .location)
    }
}
