import Foundation

// MARK: - Supabase configuration
// Read from Secrets.plist in the app bundle (never committed).
// Falls back to LocalBackendService if missing or malformed.

struct SupabaseConfig {
    let baseURL: URL        // e.g. https://aoxturoezgecwceudeef.supabase.co
    let anonKey: String

    // Derived service endpoints
    var restBaseURL: URL     { baseURL.appendingPathComponent("rest/v1") }
    var authBaseURL: URL     { baseURL.appendingPathComponent("auth/v1") }
    var storageBaseURL: URL  { baseURL.appendingPathComponent("storage/v1") }
    var rpcBaseURL: URL      { restBaseURL.appendingPathComponent("rpc") }

    static func load() -> SupabaseConfig? {
        guard
            let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
            let rawURL = dict["SupabaseURL"] as? String, !rawURL.isEmpty,
            let anonKey = dict["SupabaseAnonKey"] as? String, !anonKey.isEmpty
        else {
            print("[TrueCarry] Supabase config missing — using LocalBackendService")
            return nil
        }

        // Defensively strip /rest/v1 suffix so callers always work from baseURL
        let normalized = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/rest/v1/", with: "")
            .replacingOccurrences(of: "/rest/v1", with: "")

        guard let url = URL(string: normalized) else {
            print("[TrueCarry] Supabase config invalid URL '\(rawURL)' — using LocalBackendService")
            return nil
        }

        guard !anonKey.hasPrefix("YOUR_") else {
            print("[TrueCarry] Supabase anon key is a placeholder — using LocalBackendService")
            return nil
        }

        print("[TrueCarry] Supabase config found — using SupabaseBackendService (\(url.host ?? "?"))")
        return SupabaseConfig(baseURL: url, anonKey: anonKey)
    }
}
