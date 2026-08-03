@preconcurrency import CoreLocation
import Foundation

@MainActor
final class LocationTrackingService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let enabledDefaultsKey = "tougeDash.history.locationEnabled"

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var latestLocation: RecordedLocation?
    @Published private(set) var lastError: String?
    @Published private(set) var isTracking = false

    private let manager = CLLocationManager()
    private var driveActive = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    var authorizationLabel: String {
        if isEnabled,
           !driveActive,
           authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            return "Gotowy · GPS ruszy po połączeniu z autem"
        }
        return switch authorizationStatus {
        case .notDetermined: "Wymaga zgody"
        case .restricted: "Ograniczona"
        case .denied: "Wyłączona w Ustawieniach"
        case .authorizedAlways: "Zawsze"
        case .authorizedWhenInUse: "Podczas używania"
        @unknown default: "Nieznana"
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        objectWillChange.send()

        guard enabled else {
            manager.stopUpdatingLocation()
            isTracking = false
            latestLocation = nil
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if driveActive { startIfAuthorized() }
        case .denied, .restricted:
            lastError = "Włącz dostęp do lokalizacji dla Touge Dash w Ustawieniach iOS."
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isEnabled, driveActive {
            startIfAuthorized()
        }
    }

    func setDriveActive(_ active: Bool) {
        guard driveActive != active else { return }
        driveActive = active
        if active {
            startIfAuthorized()
        } else {
            manager.stopUpdatingLocation()
            isTracking = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isEnabled,
              let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100 else { return }

        latestLocation = RecordedLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            timestamp: location.timestamp
        )
        lastError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        lastError = error.localizedDescription
    }

    private func startIfAuthorized() {
        guard isEnabled, driveActive,
              authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isTracking = true
        lastError = nil
    }
}
