import Foundation

/// Calls the `ai-coach` Supabase edge function, which routes shot metrics to
/// Claude (via OpenRouter) server-side and returns short coaching text. The API
/// key lives only as a Supabase secret — never in the app.
enum AICoachError: LocalizedError {
    case notConfigured
    case notSignedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI coach isn't set up yet."
        case .notSignedIn:   return "Sign in to use the AI coach."
        case .server(let m): return m
        }
    }
}

struct AICoachService {
    enum Mode: String { case shot, session }

    /// One shot's metrics in the shape the edge function expects.
    struct ShotPayload: Encodable {
        var clubName: String?
        var carryYards: Double?
        var totalYards: Double?
        var rolloutYards: Double?
        var ballSpeedMph: Double?
        var clubSpeedMph: Double?
        var smashFactor: Double?
        var hlaDegrees: Double?
        var hlaDirection: String?
        var vlaDegrees: Double?
        var backspinRpm: Double?
        var sidespinRpm: Double?
        var spinAxisDegrees: Double?
        var clubPathDegrees: Double?
        var faceAngleDegrees: Double?
        var faceToPathDegrees: Double?

        init(_ m: SavedShotMetrics, clubName: String? = nil) {
            self.clubName = clubName
            self.carryYards = m.carryYards
            self.totalYards = m.totalYards
            self.rolloutYards = m.rolloutYards
            self.ballSpeedMph = m.ballSpeedMph
            self.clubSpeedMph = m.clubSpeedMph
            self.smashFactor = m.smashFactor
            self.hlaDegrees = m.hlaDegrees
            self.hlaDirection = m.hlaDirection.isEmpty ? nil : m.hlaDirection
            self.vlaDegrees = m.vlaDegrees
            self.backspinRpm = m.backspinRpm
            self.sidespinRpm = m.sidespinRpm
            self.spinAxisDegrees = m.spinAxisDegrees
            self.clubPathDegrees = m.clubPathDegrees
            self.faceAngleDegrees = m.faceAngleDegrees
            self.faceToPathDegrees = m.faceToPathDegrees
        }
    }

    private struct RequestBody: Encodable { let mode: String; let shots: [ShotPayload] }
    private struct SuccessResponse: Decodable { let coaching: String }
    private struct ErrorResponse: Decodable { let error: String }

    /// Fetches coaching for one shot or a recent-shots session summary.
    static func fetchCoaching(mode: Mode, shots: [ShotPayload]) async throws -> String {
        guard let config = SupabaseConfig.load() else { throw AICoachError.notConfigured }
        guard let token = UserDefaults.standard.string(forKey: "sb_access_token"), !token.isEmpty else {
            throw AICoachError.notSignedIn
        }

        let url = config.functionsBaseURL.appendingPathComponent("ai-coach")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.timeoutInterval = 40
        req.httpBody = try JSONEncoder().encode(RequestBody(mode: mode.rawValue, shots: shots))

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 200, let ok = try? JSONDecoder().decode(SuccessResponse.self, from: data) {
            return ok.coaching
        }
        if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw AICoachError.server(err.error)
        }
        throw AICoachError.server("Coaching is unavailable right now (\(status)).")
    }
}
