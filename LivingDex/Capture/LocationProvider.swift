import CoreLocation
import CoreMotion

/// One-shot capture context: current coarse location + barometric elevation,
/// used to geo-tag a sighting and re-rank identification against a local prior.
/// Location is While-Using only; failures degrade to a nil-location sighting.
///
/// Rather than streaming location/altitude for the whole app lifetime, it *warms*
/// a fix on demand — on authorization, on app foreground, and whenever the last
/// fix has gone stale — then stops both the location and altimeter streams once a
/// fresh reading lands, so a capture is still instant without a permanently-lit
/// location indicator or a continuously-running barometer.
final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()
    private var lastElevation: Double?
    private var lastLocation: CLLocation?
    private var lastFixAt: Date?
    private var isUpdatingLocation = false
    private var isUpdatingAltitude = false

    /// A stored fix older than this is treated as stale — currentContext re-warms
    /// so the *next* capture geo-tags with a fresh position rather than one from
    /// hours ago.
    private let fixValidity: TimeInterval = 300

    /// A fix at least this accurate ends a warm-up burst.
    private let acceptableAccuracy: CLLocationAccuracy = 200

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Starts a short warm-up burst (location + altimeter) if authorized. Called
    /// on authorization, on foreground, and when a stored fix has gone stale.
    func warmUp() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationUpdates()
            startAltitudeUpdates()
        default:
            break
        }
    }

    /// Stops any in-flight warm-up burst — used on background so nothing streams
    /// while the app isn't visible.
    func stopUpdates() {
        stopLocationUpdates()
        stopAltitudeUpdates()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        warmUp()
    }

    /// Returns the best currently-available context. Non-blocking: uses the last
    /// warmed fix so capture stays instant, and opportunistically re-warms when
    /// that fix is stale so subsequent captures aren't geo-tagged with an old one.
    func currentContext() -> CaptureContext {
        if isFixStale { warmUp() }
        let loc = lastLocation ?? manager.location
        return CaptureContext(
            latitude: loc?.coordinate.latitude,
            longitude: loc?.coordinate.longitude,
            elevationMeters: lastElevation ?? loc?.altitude)
    }

    private var isFixStale: Bool {
        guard let lastFixAt else { return true }
        return Date().timeIntervalSince(lastFixAt) > fixValidity
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastLocation = loc
        lastFixAt = Date()
        if loc.horizontalAccuracy > 0 && loc.horizontalAccuracy <= acceptableAccuracy {
            stopLocationUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.shared.warn("location error: \(error.localizedDescription)", category: .location)
    }

    private func startLocationUpdates() {
        guard !isUpdatingLocation else { return }
        isUpdatingLocation = true
        manager.startUpdatingLocation()
    }

    private func stopLocationUpdates() {
        guard isUpdatingLocation else { return }
        isUpdatingLocation = false
        manager.stopUpdatingLocation()
    }

    private func startAltitudeUpdates() {
        guard !isUpdatingAltitude, CMAltimeter.isAbsoluteAltitudeAvailable() else { return }
        isUpdatingAltitude = true
        altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let altitude = data?.altitude else { return }
            self.lastElevation = altitude
            self.stopAltitudeUpdates()
        }
    }

    private func stopAltitudeUpdates() {
        guard isUpdatingAltitude else { return }
        isUpdatingAltitude = false
        altimeter.stopAbsoluteAltitudeUpdates()
    }
}
