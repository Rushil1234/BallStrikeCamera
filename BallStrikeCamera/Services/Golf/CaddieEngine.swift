import Foundation

/// Club-recommendation engine (Pro/Unlimited feature). Given the playing distance (already
/// slope/wind adjusted) and the golfer's own shot history per club, it ranks each club by its
/// chance of finishing on the green and returns the best one, formatted like:
///
///   "7 iron · 145 yds · playing 142 (slope +5, wind −8) · aim 4y left (2 mph L→R)"
///
/// Ranking model: demonstrated results first. For each club we count the tracked shots that would
/// have finished on this green — carried at least to the front edge, didn't roll past the back,
/// and stayed inside the green's width. That empirical rate is blended with a Normal-model
/// estimate (mean = the golfer's average carry, sd = their spread), weighted toward the real
/// results as the sample grows, and the model share is further gated by demonstrated reach — a
/// club that has never carried the distance can't outrank one that has, no matter how close its
/// average sits. The blend keeps small samples honest without letting a club whose *average*
/// merely sits near the number outrank one that has actually held the green. The pick ships with
/// a caddie-style swing note (full swing / stock / take a little off, e.g. "hit 7 iron about
/// 148y"), and a second "tightest grouping" pick surfaces the most repeatable club at this
/// yardage when it differs from the best-odds pick. If nothing clears a small threshold the shot
/// isn't a green-light — the engine falls back to a smart-advance (layup) pick, or nil if there's
/// no data at all.
enum CaddieEngine {

    struct ShotSample {
        let carry: Double
        let lateral: Double
        /// Total distance (carry + roll) when known — nil when the shot only has a carry.
        var total: Double? = nil
    }

    struct ClubStat {
        let name: String
        let carryMean: Double
        let carrySD: Double
        let lateralSD: Double
        let shots: [ShotSample]
        /// Average TOTAL distance (carry + roll) when known — drives layup/advance picks,
        /// where the ball running out matters as much as the carry.
        var totalMean: Double? = nil

        var sampleCount: Int { shots.count }
        var effectiveYards: Double { totalMean ?? carryMean }
    }

    /// The consistency layer: the club with the smallest spread among those whose average
    /// carry sits at this number, shown alongside the best-odds pick when they differ.
    struct TightestPick {
        let clubName: String
        let typicalYards: Int   // the club's average carry
        let spreadYards: Int    // ± one-sd carry spread
        let greenHits: Int      // tracked shots that would have finished on this green
        let greenSamples: Int
        let reached: Int        // shots that carried at least to the front edge
        let shortMisses: Int    // shots that finished short of the front
        let longMisses: Int     // shots that finished past the back
    }

    struct Suggestion {
        let clubName: String
        let typicalYards: Int    // the club's average carry
        let playingYards: Int    // slope + wind adjusted target
        let baseYards: Int       // raw center-of-green yardage
        let slopeDelta: Int      // + uphill (plays longer), − downhill
        let windDelta: Int       // + into wind (plays longer), − downwind
        let onGreenPercent: Int  // best club's blended chance to finish on the green
        let aimAdvice: String    // e.g. "aim 4y left"
        let windSummary: String  // e.g. "2 mph L→R"
        /// Demonstrated results behind onGreenPercent: of `greenSamples` tracked shots with this
        /// club, `greenHits` would have finished on this green.
        var greenHits: Int = 0
        var greenSamples: Int = 0
        /// Caddie-style swing advice for the pick, e.g. "Take a little off — land it about 148y."
        var swingNote: String = ""
        /// Most repeatable club at this yardage, when it isn't the best-odds pick.
        var tightest: TightestPick? = nil
        /// True when no club holds the green — this is the smart-advance pick instead
        /// (longest club that stays short of the trouble around the target).
        var isLayup: Bool = false
        var leavesYards: Int = 0

        /// One-line summary in the format the product spec asked for.
        var headline: String {
            var s: String
            if isLayup {
                s = "\(clubName) · ~\(typicalYards) yds · leaves \(leavesYards) in (playing \(playingYards))"
            } else {
                s = "\(clubName) · \(typicalYards) yds · playing \(playingYards)"
            }
            var adj: [String] = []
            if slopeDelta != 0 { adj.append("slope \(slopeDelta > 0 ? "+" : "")\(slopeDelta)") }
            if windDelta  != 0 { adj.append("wind \(windDelta > 0 ? "+" : "")\(windDelta)") }
            if !adj.isEmpty { s += " (\(adj.joined(separator: ", ")))" }
            if !aimAdvice.isEmpty {
                s += " · \(aimAdvice)"
                if !windSummary.isEmpty { s += " (\(windSummary))" }
            }
            return s
        }
    }

    /// Standard normal CDF.
    private static func phi(_ z: Double) -> Double { 0.5 * (1 + erf(z / 2.0.squareRoot())) }

    static func suggest(playingYards: Double,
                        baseYards: Int,
                        slopeDelta: Int,
                        windDelta: Int,
                        greenDepthYards: Double,
                        greenWidthYards: Double,
                        aimAdvice: String,
                        windSummary: String,
                        clubs: [ClubStat]) -> Suggestion? {
        guard playingYards > 0 else { return nil }
        let halfDepth = max(greenDepthYards / 2, 4)
        let halfWidth = max(greenWidthYards / 2, 6)
        let front = playingYards - halfDepth
        let back  = playingYards + halfDepth

        struct Ranked {
            let stat: ClubStat
            let score: Double
            let hits: Int         // finished on the green
            let reached: Int      // carried at least to the front edge — proved the distance
            let cleared: Int      // carried past the back — flew the green
            let shortMisses: Int  // finished short of the front
            let longMisses: Int   // finished past the back
        }
        var ranked: [Ranked] = []
        for c in clubs where c.sampleCount >= 3 {
            // Floor the spreads so a handful of tightly-grouped shots don't read as near-certainty.
            let carrySD = max(c.carrySD, 4)
            let latSD   = max(c.lateralSD, 4)
            let pDist = phi((back - c.carryMean) / carrySD)
                      - phi((front - c.carryMean) / carrySD)
            let pLat  = phi(halfWidth / latSD) - phi(-halfWidth / latSD)
            let model = max(0, pDist) * max(0, pLat)

            // Demonstrated results. A hit carried to the front, didn't run off the back, and
            // stayed inside the width; a shot with no measured total is judged on carry alone.
            var hits = 0, reached = 0, cleared = 0, short = 0, long = 0
            for s in c.shots {
                let finish = s.total ?? s.carry
                if s.carry >= front { reached += 1 }
                if s.carry > back { cleared += 1 }
                if finish < front { short += 1 }
                if s.carry > back || finish > back { long += 1 }
                if s.carry >= front && finish <= back && abs(s.lateral) <= halfWidth { hits += 1 }
            }
            let n = Double(c.sampleCount)
            let empirical = Double(hits) / n

            // Lean on real results as the sample grows; the Normal model fills in thin history.
            let w = n / (n + 6)
            // A club that has never carried this far shouldn't ride its bell curve onto the
            // green: the model share is credited by demonstrated reach, with full credit once
            // about a quarter of its shots have gotten there. Flying the green counts as reach —
            // clearing it proves the distance, and the depth window already punishes going long.
            let reachCred = min(1, (Double(reached) + 0.5) / (0.25 * n + 0.5))
            let score = w * empirical + (1 - w) * model * reachCred
            ranked.append(Ranked(stat: c, score: score, hits: hits, reached: reached,
                                 cleared: cleared, shortMisses: short, longMisses: long))
        }

        let best = ranked.max(by: { $0.score < $1.score })

        // No green-light club → smart advance: the longest club (by TOTAL when known)
        // that stays comfortably short of the target, i.e. closest to the center of the
        // fairway/approach zone without running through it. Wind + slope are already in
        // playingYards, so the pick inherits them.
        guard let best, best.score > 0.02 else {
            let candidates = clubs.filter { $0.sampleCount >= 3 }
            let buffer = 12.0
            let pick = candidates
                .filter { $0.effectiveYards <= playingYards - buffer }
                .max(by: { $0.effectiveYards < $1.effectiveYards })
                ?? candidates.min(by: {
                    abs($0.effectiveYards - playingYards) < abs($1.effectiveYards - playingYards)
                })
            guard let layup = pick else { return nil }
            return Suggestion(
                clubName: layup.name,
                typicalYards: Int(layup.effectiveYards.rounded()),
                playingYards: Int(playingYards.rounded()),
                baseYards: baseYards,
                slopeDelta: slopeDelta,
                windDelta: windDelta,
                onGreenPercent: 0,
                aimAdvice: aimAdvice,
                windSummary: windSummary,
                isLayup: true,
                leavesYards: max(0, Int((playingYards - layup.effectiveYards).rounded()))
            )
        }

        // Consistency layer: among clubs whose average carry sits near this number, the one with
        // the smallest combined spread — a different answer than "best odds" when a steady club
        // keeps missing the green in the same spot. The window runs a touch past the green edges
        // so a steady club that consistently finishes just short/long still gets named (with an
        // honest note about why it isn't the pick).
        let window = max(halfDepth, 10) + 5
        let tightest: TightestPick? = ranked
            .filter { abs($0.stat.carryMean - playingYards) <= window }
            .min(by: { spread($0.stat) < spread($1.stat) })
            .flatMap { t in
                guard t.stat.name != best.stat.name else { return nil }
                return TightestPick(
                    clubName: t.stat.name,
                    typicalYards: Int(t.stat.carryMean.rounded()),
                    spreadYards: Int(max(t.stat.carrySD, 4).rounded()),
                    greenHits: t.hits,
                    greenSamples: t.stat.sampleCount,
                    reached: t.reached,
                    shortMisses: t.shortMisses,
                    longMisses: t.longMisses
                )
            }

        return Suggestion(
            clubName: best.stat.name,
            typicalYards: Int(best.stat.carryMean.rounded()),
            playingYards: Int(playingYards.rounded()),
            baseYards: baseYards,
            slopeDelta: slopeDelta,
            windDelta: windDelta,
            onGreenPercent: Int((best.score * 100).rounded()),
            aimAdvice: aimAdvice,
            windSummary: windSummary,
            greenHits: best.hits,
            greenSamples: best.stat.sampleCount,
            swingNote: swingNote(for: best.stat, reached: best.reached, cleared: best.cleared,
                                 playingYards: playingYards),
            tightest: tightest
        )
    }

    /// Caddie-style sentence for the pick: full swing, stock swing, or take something off —
    /// grounded in what the club has actually shown at this distance.
    private static func swingNote(for c: ClubStat, reached: Int, cleared: Int,
                                  playingYards: Double) -> String {
        let playing = Int(playingYards.rounded())
        let stock = Int(c.carryMean.rounded())
        let delta = c.carryMean - playingYards
        if delta >= 6 {
            if cleared > 0 {
                return "Take a little off — you've flown this distance \(cleared) time\(cleared == 1 ? "" : "s"). Hit \(c.name) about \(playing)y, not your stock \(stock)y."
            }
            return "Take a little off — hit \(c.name) about \(playing)y instead of your stock \(stock)y."
        }
        if delta <= -6 {
            guard reached > 0 else {
                return "A reach — none of your tracked \(c.name) shots have carried this far. Favor the safe side."
            }
            return "Needs your good one — you've carried it this far \(reached) of \(c.sampleCount) times. Commit to a full swing."
        }
        return "Stock number — a normal \(c.name) swing covers this."
    }

    private static func spread(_ c: ClubStat) -> Double {
        (max(c.carrySD, 4) * max(c.carrySD, 4) + max(c.lateralSD, 4) * max(c.lateralSD, 4)).squareRoot()
    }

    /// Build a ClubStat from per-shot samples.
    static func stat(name: String, shots: [ShotSample]) -> ClubStat? {
        guard shots.count >= 3 else { return nil }
        let carries = shots.map(\.carry)
        let laterals = shots.map(\.lateral)
        let carryMean = carries.reduce(0, +) / Double(carries.count)
        let carrySD = standardDeviation(carries, mean: carryMean)
        let latMean = laterals.reduce(0, +) / Double(laterals.count)
        let latSD = standardDeviation(laterals, mean: latMean)
        let totals = shots.compactMap(\.total)
        let totalMean = totals.isEmpty ? nil : totals.reduce(0, +) / Double(totals.count)
        return ClubStat(name: name, carryMean: carryMean, carrySD: carrySD,
                        lateralSD: latSD, shots: shots, totalMean: totalMean)
    }

    private static func standardDeviation(_ xs: [Double], mean: Double) -> Double {
        guard xs.count > 1 else { return 0 }
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count - 1)
        return variance.squareRoot()
    }
}
