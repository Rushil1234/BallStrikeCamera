import Foundation

// MARK: - OpenWeatherMap Configuration
// API key is loaded from Secrets.plist (gitignored), same convention as GolfCourseAPIConfig.
// Used as WindService's fallback wind source while the WeatherKit entitlement is unresolved.

enum OpenWeatherMapConfig {
    static let currentWeatherURL = "https://api.openweathermap.org/data/2.5/weather"

    static var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let key  = dict["OpenWeatherMapKey"] as? String,
              !key.isEmpty,
              key != "PUT_KEY_HERE",
              !key.hasPrefix("YOUR_")
        else { return nil }
        return key
    }

    static var isConfigured: Bool { apiKey != nil }
}
