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
            return
        } catch {
            print("[WindService] WeatherKit fetch failed: \(error)")
        }
        // WeatherKit is unavailable (provisioning, offline, etc.) — fall back to OpenWeatherMap so
        // wind still works. Feeds the same `Reading` the UI already renders, so once WeatherKit is
        // fixed this path just stops being exercised — no UI changes needed either way.
        do {
            reading = try await fetchFromOpenWeatherMap(at: coord)
            lastCoord = coord
        } catch {
            errorText = "Wind unavailable"
            print("[WindService] OpenWeatherMap fetch failed: \(error)")
        }
    }

    private func fetchFromOpenWeatherMap(at coord: CLLocationCoordinate2D) async throws -> Reading {
        guard let key = OpenWeatherMapConfig.apiKey,
              var components = URLComponents(string: OpenWeatherMapConfig.currentWeatherURL) else {
            throw URLError(.userAuthenticationRequired)
        }
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(coord.latitude)),
            URLQueryItem(name: "lon", value: String(coord.longitude)),
            URLQueryItem(name: "appid", value: key),
            URLQueryItem(name: "units", value: "imperial")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenWeatherMapCurrentResponse.self, from: data)
        return Reading(speedMph: decoded.wind.speed,
                       fromDegrees: decoded.wind.deg,
                       gustMph: decoded.wind.gust,
                       fetchedAt: Date())
    }

    private static func metersBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

/// OpenWeatherMap's `/data/2.5/weather` response, `units=imperial` (speed/gust already in mph;
/// `deg` is meteorological — direction the wind blows FROM — matching WeatherKit's convention).
private struct OpenWeatherMapCurrentResponse: Decodable {
    struct Wind: Decodable {
        let speed: Double
        let deg: Double
        let gust: Double?
    }
    let wind: Wind
}
