import Foundation

/// Club-recommendation engine (Pro/Unlimited feature). Given the playing distance (already
/// slope/wind adjusted) and the golfer's own shot history per club, it estimates each club's
/// probability of finishing on the green and returns the best one, formatted like:
///
///   "7 iron · 145 yds · playing 142 (slope +5, wind −8) · aim 4y left (2 mph L→R)"
///
/// Probability model: a club's carry is treated as Normal(mean = the golfer's average carry with
/// that club, sd = their spread). We integrate that distribution over the green's depth window
/// (centered on the playing distance) and multiply by the chance the lateral miss stays inside the
/// green's width. Only clubs with enough samples are considered. If nothing clears a small
/// threshold the shot isn't a green-light — the engine returns nil so the UI can say so.
enum CaddieEngine {

    struct ClubStat {
        let name: String
        let carryMean: Double
        let carrySD: Double
        let lateralSD: Double
        let sampleCount: Int
    }

    struct Suggestion {
        let clubName: String
        let typicalYards: Int    // the club's average carry
        let playingYards: Int    // slope + wind adjusted target
        let baseYards: Int       // raw center-of-green yardage
        let slopeDelta: Int      // + uphill (plays longer), − downhill
        let windDelta: Int       // + into wind (plays longer), − downwind
        let onGreenPercent: Int  // best club's estimated chance to hold the green
        let aimAdvice: String    // e.g. "aim 4y left"
        let windSummary: String  // e.g. "2 mph L→R"

        /// One-line summary in the format the product spec asked for.
        var headline: String {
            var s = "\(clubName) · \(typicalYards) yds · playing \(playingYards)"
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

        var best: (ClubStat, Double)?
        for c in clubs where c.sampleCount >= 3 {
            // Floor the spreads so a handful of tightly-grouped shots don't read as near-certainty.
            let carrySD = max(c.carrySD, 4)
            let latSD   = max(c.lateralSD, 4)
            let pDist = phi((playingYards + halfDepth - c.carryMean) / carrySD)
                      - phi((playingYards - halfDepth - c.carryMean) / carrySD)
            let pLat  = phi(halfWidth / latSD) - phi(-halfWidth / latSD)
            let p = max(0, pDist) * max(0, pLat)
            if best == nil || p > best!.1 { best = (c, p) }
        }
        guard let (club, p) = best, p > 0.02 else { return nil }

        return Suggestion(
            clubName: club.name,
            typicalYards: Int(club.carryMean.rounded()),
            playingYards: Int(playingYards.rounded()),
            baseYards: baseYards,
            slopeDelta: slopeDelta,
            windDelta: windDelta,
            onGreenPercent: Int((p * 100).rounded()),
            aimAdvice: aimAdvice,
            windSummary: windSummary
        )
    }

    /// Build a ClubStat from a set of (carry, lateral) samples.
    static func stat(name: String, samples: [(carry: Double, lateral: Double)]) -> ClubStat? {
        guard samples.count >= 3 else { return nil }
        let carries = samples.map(\.carry)
        let laterals = samples.map(\.lateral)
        let carryMean = carries.reduce(0, +) / Double(carries.count)
        let carrySD = standardDeviation(carries, mean: carryMean)
        let latMean = laterals.reduce(0, +) / Double(laterals.count)
        let latSD = standardDeviation(laterals, mean: latMean)
        return ClubStat(name: name, carryMean: carryMean, carrySD: carrySD,
                        lateralSD: latSD, sampleCount: samples.count)
    }

    private static func standardDeviation(_ xs: [Double], mean: Double) -> Double {
        guard xs.count > 1 else { return 0 }
        let variance = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(xs.count - 1)
        return variance.squareRoot()
    }
}
