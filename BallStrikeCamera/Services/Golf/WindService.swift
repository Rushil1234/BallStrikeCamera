import Foundation
import CoreLocation
import WeatherKit

/// Fetches live wind for course mode via Apple WeatherKit. Named `WindService` (not WeatherService)
/// to avoid colliding with `WeatherKit.WeatherService`.
///
/// Requires the **WeatherKit** capability on the App ID and the `com.apple.developer.weatherkit`
/// entitlement (added to BallStrikeCamera.entitlements). Without provisioning, `fetch` fails
/// gracefully and surfaces `errorText` so the UI can fall back to "wind unavailable".
@MainActor
final class WindService: ObservableObject {

    struct Reading {
        let speedMph: Double
        let fromDegrees: Double     // meteorological: direction the wind blows FROM
        let gustMph: Double?
        let fetchedAt: Date
    }

    @Published private(set) var reading: Reading?
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    private let service = WeatherKit.WeatherService.shared

    /// True once we've fetched for roughly this location recently (5 min) — avoids hammering the API.
    private var lastCoord: CLLocationCoordinate2D?

    func fetch(at coord: CLLocationCoordinate2D, force: Bool = false) async {
        guard CLLocationCoordinate2DIsValid(coord) else { return }
        if !force, let r = reading, let last = lastCoord,
           Date().timeIntervalSince(r.fetchedAt) < 300,
           Self.metersBetween(last, coord) < 400 {
            return   // fresh enough
        }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let current = try await service.weather(for: location, including: .current)
            let mph  = current.wind.speed.converted(to: .milesPerHour).value
            let dir  = current.wind.direction.converted(to: .degrees).value
            let gust = current.wind.gust?.converted(to: .milesPerHour).value
            reading = Reading(speedMph: mph, fromDegrees: dir, gustMph: gust, fetchedAt: Date())
            lastCoord = coord
        } catch {
            errorText = "Wind unavailable"
            print("[WindService] fetch failed: \(error)")
        }
    }

    private static func metersBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
