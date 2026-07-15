import Foundation
import CoreLocation
import Combine

// MARK: - Location Service

@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var locationError: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // No distance filter: standing over the ball still yields ~1Hz fixes, so yardages
        // tick live instead of freezing until the player walks 5+ meters.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    /// During an active round the app keeps receiving fixes with the screen locked or the app
    /// backgrounded, so the lock-screen widget / Live Activity yardages stay current. Scoped to
    /// rounds only — background GPS outside a round would just burn battery.
    func beginRoundBackgroundUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func endRoundBackgroundUpdates() {
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func startUpdating() {
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    // MARK: - Distance helpers

    /// Distance in yards from user's current location to a coordinate.
    func distanceInYards(to coordinate: CLLocationCoordinate2D) -> Double? {
        guard let current = currentLocation else { return nil }
        let from = CLLocation(latitude: current.latitude, longitude: current.longitude)
        let to   = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to) * 1.09361
    }

    /// Distances to front, middle, and back of green if coordinates exist.
    func greenDistances(front: CLLocationCoordinate2D?,
                        center: CLLocationCoordinate2D?,
                        back: CLLocationCoordinate2D?) -> GreenDistances {
        GreenDistances(
            front:  front.flatMap  { distanceInYards(to: $0) }.map { Int($0.rounded()) },
            center: center.flatMap { distanceInYards(to: $0) }.map { Int($0.rounded()) },
            back:   back.flatMap   { distanceInYards(to: $0) }.map { Int($0.rounded()) }
        )
    }

    /// Distance in yards between any two arbitrary coordinates.
    static func distanceInYards(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let b = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return a.distance(from: b) * 1.09361
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            currentLocation = loc.coordinate
            locationError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationError = error.localizedDescription
        }
    }
}
