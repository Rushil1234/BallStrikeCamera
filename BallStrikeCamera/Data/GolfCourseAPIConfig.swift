import Foundation

// MARK: - GolfCourse API Configuration
// API key is loaded from Secrets.plist (gitignored).
// Copy Secrets.plist.example → Secrets.plist and insert your key locally.
// NEVER commit the real key to source control.
// Production: route through a backend proxy so the key is not in the app binary.

enum GolfCourseAPIConfig {
    static let baseURL = "https://api.golfcourseapi.com/v1"

    // MARK: Key loading

    /// Returns the API key if Secrets.plist exists and has a value, otherwise nil.
    static var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let key  = dict["GolfCourseAPIKey"] as? String,
              !key.isEmpty,
              key != "PUT_KEY_HERE",
              !key.hasPrefix("YOUR_")
        else { return nil }
        return key
    }

    static var isConfigured: Bool { apiKey != nil }

    // MARK: Request helper

    static func makeRequest(path: String) -> URLRequest? {
        guard let key = apiKey,
              let url = URL(string: "\(baseURL)/\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        return req
    }
}
