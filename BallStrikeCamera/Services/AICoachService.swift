import SwiftUI

/// Local, deterministic coaching — NO network, NO LLM, no token bill (Noah, July 20).
/// Groups the user's own shots by club, computes real per-club averages and
/// tendencies, and returns a STRUCTURED report (stat tiles + short insight rows +
/// one focus) that the card renders visually. Runs on-device in microseconds.
enum AICoachError: LocalizedError {
    case noData
    case notConfigured
    case notSignedIn
    case server(String)
    var errorDescription: String? {
        switch self {
        case .noData:        return "Hit a few shots first and I'll read them for you."
        case .notConfigured: return "AI Coach isn't available right now."
        case .notSignedIn:   return "Sign in to use the AI Coach."
        case .server(let m): return m
        }
    }
}

/// What the card draws. Kept small and visual — a headline, a few key numbers,
/// a handful of one-line reads, and a single focus.
struct CoachReport {
    var headline: String
    var sub: String
    var stats: [Stat]
    var insights: [Insight]
    var focus: String?

    struct Stat: Identifiable { let id = UUID(); let value: String; let label: String }
    struct Insight: Identifiable { let id = UUID(); let icon: String; let tone: Tone; let text: String }
    enum Tone { case good, watch, info }
}

struct AICoachService {
    /// `course` reads on-course shots that only carry a total distance + a lateral miss
    /// (GPS start→end + verified round data) — no launch-monitor numbers. `round`/`bag` are
    /// session-family scopes (whole round, cross-club bag gapping).
    enum Mode: String { case shot, session, course, round, bag }

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
        /// On-course only: signed lateral miss in yards (− left, + right). Set on shots
        /// built from GPS round data, which carry no launch-monitor metrics.
        var lateralYards: Double?

        /// On-course shot: a measured total distance (GPS start→end) and a signed
        /// lateral miss in yards. Everything else stays nil — it doesn't exist here.
        init(courseDistance: Double, lateralYards: Double, clubName: String?) {
            self.clubName = clubName
            self.totalYards = courseDistance
            self.lateralYards = lateralYards
        }

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

        /// Signed horizontal launch: right = +, left = − (straight ≈ 0).
        var signedHLA: Double? {
            guard let d = hlaDegrees else { return nil }
            return (hlaDirection?.lowercased() == "left") ? -d : d
        }
    }

    /// The free, instant, on-device structured read (shot/session). Never hits the network.
    static func report(mode: Mode, shots: [ShotPayload]) async throws -> CoachReport {
        guard !shots.isEmpty else { throw AICoachError.noData }
        switch mode {
        case .shot:                  return CoachEngine.shotReport(shots[0])
        case .session, .round, .bag: return CoachEngine.sessionReport(shots)
        case .course:                return CoachEngine.courseReport(shots)
        }
    }

    // MARK: - Deep read (opt-in LLM via OpenRouter edge function)

    /// Per-club rollup sent as baseline context so the LLM can talk gapping + dispersion,
    /// not just one instant. Keys match the edge function's ClubStat type.
    struct ClubStat: Encodable {
        var clubName: String
        var count: Int
        var avgCarry: Double?
        var carrySD: Double?
        var avgBall: Double?
        var avgSmash: Double?
        var avgLaunch: Double?
        var avgSideDeg: Double?   // signed: + right, − left
    }

    /// On-course context for a round deep-read. Keys match the edge function's RoundCtx.
    struct RoundContext: Encodable {
        var courseName: String?
        var score: Int?
        var toPar: Int?
        var holes: Int?
        var fairwaysHit: Int?
        var fairwaysTotal: Int?
        var gir: Int?
        var girTotal: Int?
        var putts: Int?
    }

    /// The JSON body POSTed to the ai-coach edge function. `contextLabel` is set by the
    /// client so a saved note can be looked up again (persist coaching without re-spending).
    struct DeepReadRequest: Encodable {
        var mode: String
        var shots: [ShotPayload]?
        var clubs: [ClubStat]?
        var round: RoundContext?
        var notes: String?
        var contextLabel: String?

        static func forShot(_ p: ShotPayload) -> DeepReadRequest {
            .init(mode: "shot", shots: [p], contextLabel: p.clubName?.isEmpty == false ? p.clubName : "Shot")
        }
        static func forSession(_ ps: [ShotPayload]) -> DeepReadRequest {
            .init(mode: "session", shots: ps, contextLabel: "Range session")
        }
        static func forRound(_ ps: [ShotPayload], round: RoundContext) -> DeepReadRequest {
            .init(mode: "round", shots: ps.isEmpty ? nil : ps, round: round,
                  contextLabel: round.courseName?.isEmpty == false ? round.courseName : "Round")
        }
        static func forBag(_ clubs: [ClubStat]) -> DeepReadRequest {
            .init(mode: "bag", clubs: clubs, contextLabel: "Bag gapping")
        }
    }

    private struct DeepReadResponse: Decodable { let coaching: String; let mode: String? }
    private struct DeepReadErrorBody: Decodable { let error: String }

    /// Calls the Pro-gated OpenRouter coach and returns the coaching text. Only fires on an
    /// explicit user tap (the card never auto-runs it), so tokens follow intent.
    static func deepRead(_ request: DeepReadRequest) async throws -> String {
        guard let config = SupabaseConfig.load() else { throw AICoachError.notConfigured }
        guard let token = UserDefaults.standard.string(forKey: "sb_access_token"), !token.isEmpty else {
            throw AICoachError.notSignedIn
        }
        var req = URLRequest(url: config.functionsBaseURL.appendingPathComponent("ai-coach"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200, let decoded = try? JSONDecoder().decode(DeepReadResponse.self, from: data) {
            let text = decoded.coaching.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { throw AICoachError.server("No coaching returned.") }
            return text
        }
        // Surface the function's own message (Pro gate, config, rate) when present.
        if let body = try? JSONDecoder().decode(DeepReadErrorBody.self, from: data) {
            throw AICoachError.server(body.error)
        }
        throw AICoachError.server("Coaching is unavailable right now. Try again in a moment.")
    }

    private struct NoteSummaryRow: Decodable { let summary: String }

    /// The most recent SAVED coaching summary for this (mode, contextLabel), if any — so
    /// reopening a shot/session/round shows the prior read instantly and for FREE instead of
    /// re-calling the paid model. RLS scopes ai_coach_notes to the caller.
    static func latestNoteSummary(mode: String, contextLabel: String?) async -> String? {
        guard let config = SupabaseConfig.load(),
              let token = UserDefaults.standard.string(forKey: "sb_access_token"), !token.isEmpty
        else { return nil }
        var comps = URLComponents(url: config.restBaseURL.appendingPathComponent("ai_coach_notes"),
                                  resolvingAgainstBaseURL: false)!
        var q = [
            URLQueryItem(name: "select", value: "summary"),
            URLQueryItem(name: "mode", value: "eq.\(mode)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        if let label = contextLabel { q.append(URLQueryItem(name: "context_label", value: "eq.\(label)")) }
        comps.queryItems = q
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([NoteSummaryRow].self, from: data)
        else { return nil }
        return rows.first?.summary
    }

    /// Groups shots into per-club baselines for the `bag` / session deep-read context.
    static func clubStats(from shots: [ShotPayload]) -> [ClubStat] {
        var groups: [String: [ShotPayload]] = [:]
        for s in shots where (s.clubName?.isEmpty == false) {
            groups[s.clubName!, default: []].append(s)
        }
        func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0,+) / Double(xs.count) }
        func sd(_ xs: [Double]) -> Double? {
            guard xs.count > 1, let m = mean(xs) else { return nil }
            return (xs.reduce(0) { $0 + ($1-m)*($1-m) } / Double(xs.count-1)).squareRoot()
        }
        func pos(_ xs: [Double?]) -> [Double] { xs.compactMap { $0 }.filter { $0 > 0 } }
        return groups.map { name, gs in
            ClubStat(
                clubName: name, count: gs.count,
                avgCarry: mean(pos(gs.map(\.carryYards))),
                carrySD: sd(pos(gs.map(\.carryYards))),
                avgBall: mean(pos(gs.map(\.ballSpeedMph))),
                avgSmash: mean(pos(gs.map(\.smashFactor))),
                avgLaunch: mean(pos(gs.map(\.vlaDegrees))),
                avgSideDeg: mean(gs.compactMap(\.signedHLA))
            )
        }.sorted { ($0.avgCarry ?? 0) > ($1.avgCarry ?? 0) }
    }
}

// MARK: - The engine

private enum CoachEngine {

    struct ClubRef { let label: String; let launch: ClosedRange<Double> }

    static func ref(for name: String?) -> ClubRef {
        let n = (name ?? "").lowercased()
        func has(_ ss: String...) -> Bool { ss.contains { n.contains($0) } }
        if has("driver") { return ClubRef(label: "driver", launch: 11...16) }
        if has("wood", "fairway") { return ClubRef(label: "fairway wood", launch: 10...16) }
        if has("hybrid", "rescue", "utility") { return ClubRef(label: "hybrid", launch: 13...19) }
        if has("3 iron", "3i", "4 iron", "4i") { return ClubRef(label: "long iron", launch: 13...19) }
        if has("5 iron", "5i", "6 iron", "6i", "7 iron", "7i") { return ClubRef(label: "mid iron", launch: 15...21) }
        if has("8 iron", "8i", "9 iron", "9i") { return ClubRef(label: "short iron", launch: 19...26) }
        if has("pitching", "pw", "gap", "gw", "sand", "sw", "lob", "lw", "wedge") {
            return ClubRef(label: "wedge", launch: 23...34) }
        return ClubRef(label: "club", launch: 0...90)
    }

    private static func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
    private static func stdev(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = mean(xs); return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot()
    }
    private static func pos(_ xs: [Double?]) -> [Double] { xs.compactMap { $0 }.filter { $0 > 0 } }
    private static func i(_ x: Double) -> String { String(Int(x.rounded())) }
    private static func pick(_ xs: [String]) -> String { xs.randomElement() ?? xs.first ?? "" }

    // MARK: session

    static func sessionReport(_ shots: [AICoachService.ShotPayload]) -> CoachReport {
        var groups: [String: [AICoachService.ShotPayload]] = [:]
        for s in shots { groups[s.clubName ?? "Your bag", default: []].append(s) }
        let ordered = groups.sorted { $0.value.count > $1.value.count }
        guard let primary = ordered.first else {
            return CoachReport(headline: "No data", sub: "", stats: [], insights: [], focus: nil)
        }
        let club = primary.key
        let gs = primary.value
        let r = ref(for: club)

        let carries = pos(gs.map(\.carryYards))
        let balls = pos(gs.map(\.ballSpeedMph))
        let smashes = pos(gs.map(\.smashFactor))
        let launches = pos(gs.map(\.vlaDegrees))
        let signed = gs.compactMap(\.signedHLA)

        // stat tiles
        var stats: [CoachReport.Stat] = []
        if !carries.isEmpty { stats.append(.init(value: i(mean(carries)), label: "CARRY yd")) }
        if !balls.isEmpty { stats.append(.init(value: i(mean(balls)), label: "BALL mph")) }
        if !smashes.isEmpty { stats.append(.init(value: String(format: "%.2f", mean(smashes)), label: "SMASH")) }
        else if !launches.isEmpty { stats.append(.init(value: i(mean(launches)) + "°", label: "LAUNCH")) }

        var insights: [CoachReport.Insight] = []
        var priorities: [(Double, String)] = []

        // direction
        if !signed.isEmpty {
            let m = mean(signed), sd = stdev(signed)
            let side = m >= 0 ? "right" : "left"
            let arrow = m >= 0 ? "arrow.up.right" : "arrow.up.left"
            if abs(m) >= 2.5 {
                insights.append(.init(icon: arrow, tone: .watch,
                    text: "Starts ~\(i(abs(m)))° \(side) — a steady miss you can aim off or square up."))
                priorities.append((abs(m) + 2, "Your \(r.label) start line — \(i(abs(m)))° \(side). Alignment-stick drill."))
            } else if sd >= 4 {
                insights.append(.init(icon: "arrow.left.and.right", tone: .watch,
                    text: "Start line wanders ±\(i(sd))° — face control at impact is the lever."))
                priorities.append((sd, "\(r.label.capitalized) face control — start line swings ±\(i(sd))°."))
            } else {
                insights.append(.init(icon: "checkmark", tone: .good, text: "Start line is square and repeatable."))
            }
        }

        // launch
        if !launches.isEmpty, r.label != "club" {
            let m = mean(launches)
            if m < r.launch.lowerBound - 2 {
                insights.append(.init(icon: "arrow.down.right", tone: .watch,
                    text: "Launch low for a \(r.label) (\(i(m))° vs ~\(i(r.launch.lowerBound))°) — ball may be back in your stance."))
                priorities.append((abs(r.launch.lowerBound - m), "\(r.label.capitalized) launch low (\(i(m))°) — ball position forward a touch."))
            } else if m > r.launch.upperBound + 2 {
                insights.append(.init(icon: "arrow.up.right", tone: .watch,
                    text: "Launch high for a \(r.label) (\(i(m))°) — could be adding loft or releasing early."))
            } else {
                insights.append(.init(icon: "checkmark", tone: .good, text: "Launch (\(i(m))°) is right where you want it."))
            }
        }

        // consistency
        if carries.count >= 3 {
            let sd = stdev(carries)
            if sd <= 4 {
                insights.append(.init(icon: "target", tone: .good, text: "Carry is tight (±\(i(sd)) yd) — repeatable strike."))
            } else if sd >= 10 {
                insights.append(.init(icon: "target", tone: .watch, text: "Carry swings ±\(i(sd)) yd — mostly strike quality."))
                priorities.append((sd / 2, "\(r.label.capitalized) strike — carry varies ±\(i(sd)) yd. Center-face drill."))
            }
        }

        // smash
        if !smashes.isEmpty {
            let sm = mean(smashes)
            if sm > 0, sm < 1.30, r.label != "wedge" {
                insights.append(.init(icon: "bolt", tone: .watch,
                    text: "Smash \(String(format: "%.2f", sm)) — off-center strikes are costing ball speed."))
                priorities.append((3, "\(r.label.capitalized) contact — \(String(format: "%.2f", sm)) smash. Face-tape check."))
            }
        }

        if insights.isEmpty {
            insights.append(.init(icon: "sparkles", tone: .info, text: "Clean, repeatable numbers — keep grooving it."))
        }

        let more = ordered.count - 1
        let sub = "\(gs.count) shot\(gs.count == 1 ? "" : "s")"
            + (more > 0 ? " · +\(more) other club\(more == 1 ? "" : "s")" : "")
        let focus = priorities.max(by: { $0.0 < $1.0 })?.1

        return CoachReport(headline: club, sub: sub, stats: Array(stats.prefix(3)),
                           insights: Array(insights.prefix(3)), focus: focus)
    }

    // MARK: on-course session (total distance + lateral miss only)

    /// The same "read like a coach" summary as `sessionReport`, but for on-course shots
    /// whose only signals are how far they went (GPS total) and how far offline they
    /// finished. Distance control + start line, no launch-monitor numbers.
    static func courseReport(_ shots: [AICoachService.ShotPayload]) -> CoachReport {
        var groups: [String: [AICoachService.ShotPayload]] = [:]
        for s in shots { groups[s.clubName ?? "On-course", default: []].append(s) }
        let ordered = groups.sorted { $0.value.count > $1.value.count }
        guard let primary = ordered.first else {
            return CoachReport(headline: "No data", sub: "", stats: [], insights: [], focus: nil)
        }
        let club = primary.key
        let gs = primary.value

        let dists = pos(gs.map(\.totalYards))
        let laterals = gs.compactMap(\.lateralYards)
        let absLat = laterals.map { abs($0) }
        let biasMean = laterals.isEmpty ? 0 : mean(laterals)
        let side = biasMean >= 0 ? "right" : "left"
        let onLine = laterals.isEmpty ? 0
            : Double(laterals.filter { abs($0) <= 20 }.count) / Double(laterals.count) * 100

        // stat tiles
        var stats: [CoachReport.Stat] = []
        if !dists.isEmpty { stats.append(.init(value: i(mean(dists)), label: "TOTAL yd")) }
        if !laterals.isEmpty { stats.append(.init(value: i(onLine) + "%", label: "ON LINE")) }
        if !absLat.isEmpty { stats.append(.init(value: "±" + i(mean(absLat)), label: "MISS yd")) }

        var insights: [CoachReport.Insight] = []
        var priorities: [(Double, String)] = []

        // start line / miss bias
        if !laterals.isEmpty {
            let sd = stdev(laterals)
            let arrow = biasMean >= 0 ? "arrow.up.right" : "arrow.up.left"
            if abs(biasMean) >= 5 {
                insights.append(.init(icon: arrow, tone: .watch,
                    text: "Misses ~\(i(abs(biasMean)))y \(side) on average — aim for it or square the face up."))
                priorities.append((abs(biasMean) + 3, "\(club) miss leans \(i(abs(biasMean)))y \(side) — aim-off or face-control work."))
            } else if sd >= 18 {
                insights.append(.init(icon: "arrow.left.and.right", tone: .watch,
                    text: "Two-way miss (±\(i(sd))y offline) — start-line control is the lever."))
                priorities.append((sd / 2, "\(club) start line swings ±\(i(sd))y — alignment + face at impact."))
            } else {
                insights.append(.init(icon: "checkmark", tone: .good, text: "Dispersion is tight and centered."))
            }
        }

        // distance control
        if dists.count >= 3 {
            let sd = stdev(dists)
            let rel = mean(dists) > 0 ? sd / mean(dists) : 0
            if rel <= 0.08 {
                insights.append(.init(icon: "target", tone: .good, text: "Your \(club) distances repeat within ±\(i(sd))y."))
            } else if rel >= 0.16 {
                insights.append(.init(icon: "target", tone: .watch, text: "Distances swing ±\(i(sd))y — strike or club selection."))
                priorities.append((sd / 3, "\(club) distance control — carries vary ±\(i(sd))y."))
            }
        }

        // finding the line
        if laterals.count >= 4 {
            if onLine >= 70 {
                insights.append(.init(icon: "flag.fill", tone: .good, text: "You find your line \(i(onLine))% of the time (within 20y)."))
            } else if onLine <= 40 {
                insights.append(.init(icon: "flag", tone: .watch, text: "Only \(i(onLine))% land within 20y of line — accuracy is the focus."))
            }
        }

        if insights.isEmpty {
            insights.append(.init(icon: "sparkles", tone: .info, text: "Solid on-course numbers — keep building the sample."))
        }

        let more = ordered.count - 1
        let sub = "\(gs.count) shot\(gs.count == 1 ? "" : "s")"
            + (more > 0 ? " · +\(more) other club\(more == 1 ? "" : "s")" : "")
        let focus = priorities.max(by: { $0.0 < $1.0 })?.1

        return CoachReport(headline: club, sub: sub, stats: Array(stats.prefix(3)),
                           insights: Array(insights.prefix(3)), focus: focus)
    }

    // MARK: single shot

    static func shotReport(_ s: AICoachService.ShotPayload) -> CoachReport {
        let r = ref(for: s.clubName)
        var stats: [CoachReport.Stat] = []
        if let c = s.carryYards, c > 0 { stats.append(.init(value: i(c), label: "CARRY yd")) }
        if let b = s.ballSpeedMph, b > 0 { stats.append(.init(value: i(b), label: "BALL mph")) }
        if let sm = s.smashFactor, sm > 0 { stats.append(.init(value: String(format: "%.2f", sm), label: "SMASH")) }
        else if let v = s.vlaDegrees, v > 0 { stats.append(.init(value: i(v) + "°", label: "LAUNCH")) }

        var insights: [CoachReport.Insight] = []
        if let sig = s.signedHLA, abs(sig) >= 1 {
            let side = sig >= 0 ? "right" : "left"
            insights.append(.init(icon: sig >= 0 ? "arrow.up.right" : "arrow.up.left",
                                  tone: abs(sig) >= 4 ? .watch : .info,
                                  text: "Started \(i(abs(sig)))° \(side)."))
        }
        if let v = s.vlaDegrees, v > 0 {
            insights.append(.init(icon: "arrow.up.forward", tone: .info, text: "Launched at \(i(v))°."))
        }

        var focus: String? = nil
        if let sm = s.smashFactor, sm > 0, sm < 1.28, r.label != "wedge" {
            focus = "Strike was off-center — find the middle and this jumps in ball speed."
        } else if let v = s.vlaDegrees, v > 0, r.label != "club", v < r.launch.lowerBound - 3 {
            focus = "Low launch for a \(r.label) — a touch more loft / forward ball position adds carry."
        } else if let sig = s.signedHLA, abs(sig) >= 4 {
            focus = "That start line is \(i(abs(sig)))° off — check alignment and face at impact."
        } else if !stats.isEmpty {
            insights.append(.init(icon: "checkmark", tone: .good, text: "Solid, well-struck ball."))
        }

        let head = s.clubName ?? "This shot"
        return CoachReport(headline: head, sub: "single shot", stats: Array(stats.prefix(3)),
                           insights: Array(insights.prefix(3)), focus: focus)
    }
}
