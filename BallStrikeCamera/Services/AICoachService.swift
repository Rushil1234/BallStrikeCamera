import SwiftUI

/// Local, deterministic coaching — NO network, NO LLM, no token bill (Noah, July 20).
/// Groups the user's own shots by club, computes real per-club averages and
/// tendencies, and returns a STRUCTURED report (stat tiles + short insight rows +
/// one focus) that the card renders visually. Runs on-device in microseconds.
enum AICoachError: LocalizedError {
    case noData
    var errorDescription: String? { "Hit a few shots first and I'll read them for you." }
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
    enum Mode: String { case shot, session }

    struct ShotPayload {
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

        /// Signed horizontal launch: right = +, left = − (straight ≈ 0).
        var signedHLA: Double? {
            guard let d = hlaDegrees else { return nil }
            return (hlaDirection?.lowercased() == "left") ? -d : d
        }
    }

    /// Kept async so callers don't change; returns instantly, never hits the network.
    static func report(mode: Mode, shots: [ShotPayload]) async throws -> CoachReport {
        guard !shots.isEmpty else { throw AICoachError.noData }
        switch mode {
        case .shot:    return CoachEngine.shotReport(shots[0])
        case .session: return CoachEngine.sessionReport(shots)
        }
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
