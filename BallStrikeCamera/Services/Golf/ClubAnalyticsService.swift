import Foundation
import CoreLocation

// MARK: - Output models

struct ClubAnalytics {
    let category: ShotClub.ClubCategory
    let sampleCount: Int
    let avgCarryYds: Double
    let avgTotalYds: Double
    /// One-sigma lateral dispersion in yards (left/right of intended line).
    /// nil until intended-line capture exists — TrackedShot has no aim vector,
    /// so lateral spread is not computable yet (a 0 would read as "perfect").
    let lateralStdDevYds: Double?
    /// One-sigma longitudinal dispersion in yards (short/long of average).
    let longitudinalStdDevYds: Double
    /// Miss tendency: signed yards (negative = left, positive = right).
    /// nil until intended-line capture exists (see lateralStdDevYds).
    let missBiasYds: Double?
    /// Confidence in [0, 1] based on sample size and outlier ratio.
    let confidence: Double
}

// MARK: - Service

/// Aggregates `TrackedShot` data into per-club analytics suitable for the bag stats screen
/// and the upcoming AI caddie. Pure functions; no I/O.
enum ClubAnalyticsService {

    /// Lower bound on samples needed before a club is considered statistically meaningful.
    private static let minSamples = 4

    /// Outlier rejection threshold in robust (MAD-scaled) deviations. Mean/σ
    /// rejection masks single big outliers in small samples — a 400yd mishit
    /// inflates σ enough to save itself — so we use median ± k·MAD instead.
    private static let madCutoff = 3.0

    /// Compute per-club analytics from a flat list of tracked shots.
    /// Filters:
    /// - Penalties and mishits excluded.
    /// - Clubs with fewer than `minSamples` shots return `nil` for that category.
    /// - Outliers ≥ `outlierZScore` σ from the mean are dropped on a second pass.
    static func aggregate(_ shots: [TrackedShot]) -> [ShotClub.ClubCategory: ClubAnalytics] {
        var byCategory: [ShotClub.ClubCategory: [TrackedShot]] = [:]
        for s in shots where s.result.isMeaningfulForCarry && s.club != nil {
            byCategory[s.club!.category, default: []].append(s)
        }
        var out: [ShotClub.ClubCategory: ClubAnalytics] = [:]
        for (cat, group) in byCategory where group.count >= minSamples {
            if let analytics = analytics(for: cat, shots: group) {
                out[cat] = analytics
            }
        }
        return out
    }

    private static func analytics(for cat: ShotClub.ClubCategory,
                                   shots: [TrackedShot]) -> ClubAnalytics? {
        // Robust outlier rejection: median ± madCutoff · (1.4826 · MAD).
        let firstDistances = shots.map { $0.distanceYards }
        let med = median(firstDistances)
        let mad = median(firstDistances.map { abs($0 - med) })
        let spread = max(1.4826 * mad, 2)   // floor so identical distances don't reject everything
        let kept = shots.filter { abs($0.distanceYards - med) <= madCutoff * spread }
        guard kept.count >= minSamples else { return nil }

        let carryVals = kept.compactMap { $0.carryYards ?? $0.distanceYards }
        let totalVals = kept.map { $0.distanceYards }
        let avgCarry  = carryVals.reduce(0, +) / Double(carryVals.count)
        let avgTotal  = totalVals.reduce(0, +) / Double(totalVals.count)

        let longitudinalStd = stdDev(totalVals, mean: avgTotal)

        // Confidence: scales with sample size and the inverse of outlier ratio.
        let droppedRatio = 1.0 - Double(kept.count) / Double(shots.count)
        let sampleFactor = min(1.0, Double(kept.count) / 30.0)
        let confidence   = max(0.0, min(1.0, sampleFactor * (1 - droppedRatio)))

        return ClubAnalytics(
            category: cat,
            sampleCount:           kept.count,
            avgCarryYds:           avgCarry,
            avgTotalYds:           avgTotal,
            lateralStdDevYds:      nil,   // needs intended-line capture
            longitudinalStdDevYds: longitudinalStd,
            missBiasYds:           nil,    // needs intended-line capture
            confidence:            confidence
        )
    }

    // MARK: - Math helpers

    private static func stdDev(_ xs: [Double], mean: Double) -> Double {
        guard xs.count > 1 else { return 0 }
        let sq = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        return sqrt(sq / Double(xs.count - 1))
    }

    private static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let sorted = xs.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

}
