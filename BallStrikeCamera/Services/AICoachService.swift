import Foundation

/// Local, deterministic coaching — NO network, NO LLM, no token bill (Noah, July 20).
/// Groups the user's own shots by club, computes real per-club averages and
/// tendencies, and builds natural-language feedback from decision-tree rules with
/// varied phrasing. Everything below runs on-device in microseconds.
enum AICoachError: LocalizedError {
    case noData
    var errorDescription: String? { "Hit a few shots first and I'll read them for you." }
}

struct AICoachService {
    enum Mode: String { case shot, session }

    /// One shot's metrics. Positive values are magnitudes with a separate direction
    /// string, matching SavedShotMetrics; 0 means "not measured" for the positive ones.
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

    /// Kept async so callers don't change, but it returns instantly and never hits
    /// the network. Throws only when there's nothing to read.
    static func fetchCoaching(mode: Mode, shots: [ShotPayload]) async throws -> String {
        guard !shots.isEmpty else { throw AICoachError.noData }
        switch mode {
        case .shot:    return CoachEngine.shotReport(shots[0])
        case .session: return CoachEngine.sessionReport(shots)
        }
    }
}

// MARK: - The engine

private enum CoachEngine {

    // Rough amateur/mid-speed reference windows per club family. Used gently — only
    // to flag a launch that's clearly off, never as gospel.
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
        return ClubRef(label: "club", launch: 0...90)   // unknown → skip launch advice
    }

    // MARK: helpers
    private static func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
    private static func stdev(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = mean(xs); return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot()
    }
    private static func pos(_ xs: [Double?]) -> [Double] { xs.compactMap { $0 }.filter { $0 > 0 } }
    private static func i(_ x: Double) -> String { String(Int(x.rounded())) }
    private static func pick(_ xs: [String]) -> String { xs.randomElement() ?? xs.first ?? "" }

    // MARK: session

    static func sessionReport(_ shots: [AICoachService.ShotPayload]) -> String {
        var groups: [String: [AICoachService.ShotPayload]] = [:]
        for s in shots { groups[s.clubName ?? "Your shots", default: []].append(s) }
        let focus = groups.sorted { $0.value.count > $1.value.count }.prefix(3)

        var out: [String] = []
        let clubList = focus.map { $0.key }.joined(separator: ", ")
        out.append(pick([
            "Read on your last \(shots.count) shots — \(clubList) got the most reps.",
            "Here's what your last \(shots.count) shots are telling me.",
            "Looked over \(shots.count) shots — a few patterns stand out."
        ]))

        var priorities: [(score: Double, tip: String)] = []
        for (club, gs) in focus {
            out.append("")
            out.append(clubBlock(club, gs, priorities: &priorities))
        }

        if let top = priorities.max(by: { $0.score < $1.score }) {
            out.append("")
            out.append("Focus: \(top.tip)")
        }
        return out.joined(separator: "\n")
    }

    private static func clubBlock(_ club: String, _ gs: [AICoachService.ShotPayload],
                                  priorities: inout [(score: Double, tip: String)]) -> String {
        let r = ref(for: club)
        let carries = pos(gs.map(\.carryYards))
        let balls = pos(gs.map(\.ballSpeedMph))
        let smashes = pos(gs.map(\.smashFactor))
        let launches = pos(gs.map(\.vlaDegrees))
        let signed = gs.compactMap(\.signedHLA)

        var lines: [String] = []

        // stat line
        var stat = "\(club) · \(gs.count) shot\(gs.count == 1 ? "" : "s")"
        if !carries.isEmpty {
            stat += " — \(i(mean(carries))) yd carry avg"
            if !balls.isEmpty { stat += ", \(i(mean(balls))) mph ball" }
            if !smashes.isEmpty { stat += String(format: ", %.2f smash", mean(smashes)) }
        }
        lines.append(stat)

        // direction tendency
        if !signed.isEmpty {
            let m = mean(signed), sd = stdev(signed)
            let side = m >= 0 ? "right" : "left"
            if abs(m) >= 2.5 {
                lines.append(pick([
                    "You're starting it about \(i(abs(m)))° \(side) on average — a steady \(side) miss you can aim off or square up at address.",
                    "Consistent \(i(abs(m)))° \(side) start line — a repeatable pattern, so it's an easy one to play or fix.",
                    "Most of these leak \(i(abs(m)))° \(side). Check alignment first, then face at impact."
                ]))
                priorities.append((abs(m) + 2, "your \(r.label) start line — \(i(abs(m)))° \(side) on average. Alignment-stick drill."))
            } else if sd >= 4 {
                lines.append(pick([
                    "Start line wanders (±\(i(sd))°) — face control at impact is the lever here.",
                    "Direction is scattered (±\(i(sd))°); strike and face angle are moving shot to shot."
                ]))
                priorities.append((sd, "\(r.label) face control — your start line swings ±\(i(sd))°."))
            } else {
                lines.append(pick([
                    "Start line is nicely neutral — nothing to chase there.",
                    "Direction is square and repeatable. Good."
                ]))
            }
        }

        // launch check (gentle, clear deviations only, known club family)
        if !launches.isEmpty, r.label != "club" {
            let m = mean(launches)
            if m < r.launch.lowerBound - 2 {
                lines.append("Launch is low for a \(r.label) (\(i(m))° vs ~\(i(r.launch.lowerBound))°+) — ball may be creeping back in your stance, or you're delofting it.")
                priorities.append((abs(r.launch.lowerBound - m), "\(r.label) launch is low (\(i(m))°) — nudge ball position forward."))
            } else if m > r.launch.upperBound + 2 {
                lines.append("Launch is high for a \(r.label) (\(i(m))° vs ~\(i(r.launch.upperBound))°) — could be adding loft or an early release.")
            } else {
                lines.append("Launch (\(i(m))°) sits right where you want it for a \(r.label).")
            }
        }

        // carry consistency
        if carries.count >= 3 {
            let sd = stdev(carries)
            if sd <= 4 {
                lines.append("Carry is tight (±\(i(sd)) yd) — your strike is repeatable.")
            } else if sd >= 10 {
                lines.append("Carry swings ±\(i(sd)) yd — that's mostly strike quality; center-face contact is the win.")
                priorities.append((sd / 2, "\(r.label) strike — carry varies ±\(i(sd)) yd. Center-face contact drill."))
            }
        }

        // smash tip
        if !smashes.isEmpty {
            let sm = mean(smashes)
            if sm > 0, sm < 1.30, r.label != "wedge" {
                lines.append("Smash is \(String(format: "%.2f", sm)) — off-center strikes are leaving ball speed on the table. Foot-spray / face-tape check.")
                priorities.append((3, "\(r.label) contact — \(String(format: "%.2f", sm)) smash means off-center hits."))
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: single shot

    static func shotReport(_ s: AICoachService.ShotPayload) -> String {
        let r = ref(for: s.clubName)
        var lines: [String] = []

        var head = s.clubName.map { "\($0): " } ?? ""
        if let c = s.carryYards, c > 0 {
            head += "\(i(c)) yd carry"
            if let t = s.totalYards, t > c { head += " (\(i(t)) total)" }
        } else { head += "this one" }
        if let b = s.ballSpeedMph, b > 0 {
            head += ", \(i(b)) mph ball"
            if let sm = s.smashFactor, sm > 0 { head += String(format: ", %.2f smash", sm) }
        }
        lines.append(head + ".")

        if let v = s.vlaDegrees, v > 0 {
            var l = "Launched at \(i(v))°"
            if let sig = s.signedHLA, abs(sig) >= 1 {
                l += ", starting \(i(abs(sig)))° \(sig >= 0 ? "right" : "left")"
            }
            lines.append(l + ".")
        }

        // one standout takeaway
        if let sm = s.smashFactor, sm > 0, sm < 1.28, r.label != "wedge" {
            lines.append(pick([
                "Strike was off-center — that smash says you lost ball speed. Find the middle and this jumps.",
                "A cleaner strike is worth real yards here; the contact wasn't centered."
            ]))
        } else if let v = s.vlaDegrees, v > 0, r.label != "club", v < r.launch.lowerBound - 3 {
            lines.append("Low launch for a \(r.label) — a hair more loft / forward ball position adds carry.")
        } else if let sig = s.signedHLA, abs(sig) >= 4 {
            lines.append("That start line is \(i(abs(sig)))° \(sig >= 0 ? "right" : "left") — worth checking alignment and face at impact.")
        } else if let c = s.carryYards, c > 0 {
            lines.append(pick(["Solid, well-struck ball.", "Clean strike — repeat that one."]))
        }

        return lines.joined(separator: "\n")
    }
}
