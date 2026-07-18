import Foundation
import CoreLocation

// MARK: - ClubDistanceModel (aggressive outlier filter, shared)

/// Robust "what's my NORMAL number with this club" model. The chart's loose 3.5σ filter keeps
/// wild-but-real shots for honesty; this one is deliberately aggressive — a 120 among 180s is
/// a chunk/top and must not drag the club's number, because the caddie and the on-course
/// overlay both answer "what should I expect", not "what has ever happened".
enum ClubDistanceModel {

    /// Indices of `distances` inside the club's normal band:
    /// median ± max(2.2 · robust σ, 10% of median, 12 yd).
    /// Under 4 samples nothing is trimmed — a median of 3 can't call outliers.
    static func keptIndices(distances: [Double]) -> [Int] {
        guard distances.count >= 4 else { return Array(distances.indices) }
        let med = median(distances)
        guard med > 0 else { return Array(distances.indices) }
        let mad = median(distances.map { abs($0 - med) })
        let band = Swift.max(2.2 * 1.4826 * mad, 0.10 * med, 12)
        return distances.indices.filter { abs(distances[$0] - med) <= band }
    }

    /// Trim a club's shot samples on their effective (total, else carry) distance.
    static func trim(_ samples: [CaddieEngine.ShotSample]) -> [CaddieEngine.ShotSample] {
        let keep = Set(keptIndices(distances: samples.map { $0.total ?? $0.carry }))
        return samples.enumerated().filter { keep.contains($0.offset) }.map(\.element)
    }

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
}

// MARK: - CourseManagementEngine

/// Turns the club pick into a course-management plan: go-vs-layup compared on the golfer's own
/// expected strokes, bunker/water carry risk along the aim line, and a punch-out side note when
/// the player is way off the hole's line. Everything is grounded in outlier-filtered per-club
/// distributions plus the golfer's REAL on-course results (verified GPS shots, their putts).
enum CourseManagementEngine {

    // MARK: Approach success (learned from their verified on-course shots)

    /// Empirical "how often do I actually finish on/around the green from X yards" curve,
    /// 25-yd buckets, Laplace-smoothed, blended with the per-club Normal model by sample size.
    struct ApproachSuccessModel {
        /// bucket index (yards/25) → (successes, attempts)
        let buckets: [Int: (hits: Int, n: Int)]

        var totalSamples: Int { buckets.values.reduce(0) { $0 + $1.n } }

        /// Blend the model probability with the golfer's demonstrated rate at this distance.
        /// Real results take over as attempts accumulate (w = n / (n + 5)).
        func blended(modelP: Double, at yds: Double) -> Double {
            let b = Int(yds / 25)
            // Include neighbors so a 130-yd shot benefits from 120- and 140-yd history.
            var hits = 0, n = 0
            for k in (b - 1)...(b + 1) {
                if let v = buckets[k] { hits += v.hits; n += v.n }
            }
            guard n > 0 else { return modelP }
            let empirical = (Double(hits) + 1) / (Double(n) + 2)   // Laplace
            let w = Double(n) / (Double(n) + 5)
            return w * empirical + (1 - w) * modelP
        }
    }

    // MARK: Hazards along the aim line

    struct HazardZone {
        enum Kind { case bunker, water }
        let kind: Kind
        /// Along-line span, yards from the player toward the target.
        let fromYds: Double
        let toYds: Double
        /// Signed lateral extent of the polygon relative to the aim line (+ right).
        let latMinYds: Double
        let latMaxYds: Double
    }

    /// Projects hazard polygons into the player→target frame and keeps the ones that
    /// actually sit in the corridor a shot can plausibly fly (±25 yd of the line).
    static func hazardZones(player: CLLocationCoordinate2D,
                            target: CLLocationCoordinate2D,
                            bunkers: [[CLLocationCoordinate2D]],
                            waters: [[CLLocationCoordinate2D]]) -> [HazardZone] {
        let lineBearing = player.bearing(to: target)
        let distToTarget = player.yards(to: target)

        func zone(_ ring: [CLLocationCoordinate2D], kind: HazardZone.Kind) -> HazardZone? {
            guard ring.count >= 3 else { return nil }
            var alongMin = Double.greatestFiniteMagnitude, alongMax = -Double.greatestFiniteMagnitude
            var latMin = Double.greatestFiniteMagnitude,   latMax = -Double.greatestFiniteMagnitude
            for v in ring {
                let d = player.yards(to: v)
                let theta = (player.bearing(to: v) - lineBearing) * .pi / 180
                let along = d * cos(theta)
                let lat   = d * sin(theta)
                alongMin = Swift.min(alongMin, along); alongMax = Swift.max(alongMax, along)
                latMin   = Swift.min(latMin, lat);     latMax   = Swift.max(latMax, lat)
            }
            // Must be ahead of the player, not past the green surround, and near the line.
            guard alongMax > 8, alongMin < distToTarget + 15,
                  latMin < 25, latMax > -25 else { return nil }
            return HazardZone(kind: kind,
                              fromYds: Swift.max(alongMin, 0), toYds: alongMax,
                              latMinYds: Swift.max(latMin, -25), latMaxYds: Swift.min(latMax, 25))
        }
        return bunkers.compactMap { zone($0, kind: .bunker) }
             + waters.compactMap  { zone($0, kind: .water) }
    }

    // MARK: Probabilities

    private static func phi(_ z: Double) -> Double { 0.5 * (1 + erf(z / 2.0.squareRoot())) }

    /// P(this club finishes on the green) from its outlier-filtered distribution, folded with
    /// the golfer's real on-course success rate at this distance.
    static func pGreen(stat: CaddieEngine.ClubStat, playingYards: Double,
                       halfDepth: Double, halfWidth: Double,
                       approach: ApproachSuccessModel?) -> Double {
        let sd = Swift.max(stat.carrySD, 5), sl = Swift.max(stat.lateralSD, 5)
        let pDist = phi((playingYards + halfDepth - stat.carryMean) / sd)
                  - phi((playingYards - halfDepth - stat.carryMean) / sd)
        let pLat = phi(halfWidth / sl) - phi(-halfWidth / sl)
        let model = Swift.max(0, pDist) * Swift.max(0, pLat)
        guard let approach else { return model }
        return approach.blended(modelP: model, at: playingYards)
    }

    /// Chance this club's shot finds sand / water among the zones (aim assumed on the line).
    static func hazardRisk(stat: CaddieEngine.ClubStat,
                           zones: [HazardZone]) -> (bunker: Double, water: Double) {
        let sd = Swift.max(stat.carrySD, 5), sl = Swift.max(stat.lateralSD, 5)
        let mean = stat.effectiveYards
        var missBunker = 1.0, missWater = 1.0
        for z in zones {
            let pAlong = Swift.max(0, phi((z.toYds - mean) / sd) - phi((z.fromYds - mean) / sd))
            let pLat   = Swift.max(0, phi(z.latMaxYds / sl) - phi(z.latMinYds / sl))
            let p = pAlong * pLat
            switch z.kind {
            case .bunker: missBunker *= (1 - p)
            case .water:  missWater  *= (1 - p)
            }
        }
        return (1 - missBunker, 1 - missWater)
    }

    // MARK: Strategy (go vs lay up, on THEIR expected strokes)

    struct StrategyOption {
        let title: String            // "Go for the green" / "Lay up"
        let clubName: String
        let detail: String
        let successPercent: Int      // on green this shot (go) or with the NEXT shot (layup)
        let hazardPercent: Int       // sand+water risk of THIS shot
        let expectedStrokes: Double  // estimated strokes to hole out from here
    }

    struct Plan {
        var suggestion: CaddieEngine.Suggestion
        var strategy: [StrategyOption] = []      // best first
        var strategyNote: String?                // the verdict sentence
        var hazardNotes: [String] = []
        var positionNote: String?                // off-the-line / punch-out side note
        var basis: String = ""                   // data provenance line
    }

    struct Input {
        var playingYards: Double
        var baseYards: Int
        var slopeDelta: Int
        var windDelta: Int
        var greenDepthYards: Double
        var greenWidthYards: Double
        var aimAdvice: String
        var windSummary: String
        var clubs: [CaddieEngine.ClubStat]
        /// Live player position when on the hole (tee when planning). Drives hazards + position.
        var origin: CLLocationCoordinate2D?
        var green: CLLocationCoordinate2D?
        /// Tee→green centerline (OSM hole path) for the off-line check.
        var centerline: [CLLocationCoordinate2D] = []
        var bunkers: [[CLLocationCoordinate2D]] = []
        var waters: [[CLLocationCoordinate2D]] = []
        var approach: ApproachSuccessModel?
        /// Their real putts per scored hole; nil falls back to 2.0.
        var avgPutts: Double?
        var courseSamples: Int = 0
        var totalSamples: Int = 0
        /// True when origin is a live GPS fix (position note only makes sense then).
        var originIsLive: Bool = false
    }

    static func plan(_ input: Input,
                     provider: ExpectedStrokesProvider = .stub) -> Plan? {
        guard let suggestion = CaddieEngine.suggest(
            playingYards: input.playingYards, baseYards: input.baseYards,
            slopeDelta: input.slopeDelta, windDelta: input.windDelta,
            greenDepthYards: input.greenDepthYards, greenWidthYards: input.greenWidthYards,
            aimAdvice: input.aimAdvice, windSummary: input.windSummary,
            clubs: input.clubs) else { return nil }

        var plan = Plan(suggestion: suggestion)
        let putts = input.avgPutts ?? 2.0
        let halfDepth = Swift.max(input.greenDepthYards / 2, 4)
        let halfWidth = Swift.max(input.greenWidthYards / 2, 6)

        // Hazards along the actual line (player → green).
        var zones: [HazardZone] = []
        if let origin = input.origin, let green = input.green {
            zones = hazardZones(player: origin, target: green,
                                bunkers: input.bunkers, waters: input.waters)
        }

        // ── GO option: the suggested club, judged on their own numbers ────────────────
        let goStat = input.clubs.first { $0.name == suggestion.clubName }
        if let goStat, !suggestion.isLayup {
            let pG = pGreen(stat: goStat, playingYards: input.playingYards,
                            halfDepth: halfDepth, halfWidth: halfWidth, approach: input.approach)
            let (pB, pW) = hazardRisk(stat: goStat, zones: zones)
            // A ball on the green isn't also in the sand — allocate what's left of pG first.
            let pWx = pW * (1 - pG)
            let pBx = pB * Swift.max(0, 1 - pG - pWx)
            let pMiss = Swift.max(0, 1 - pG - pWx - pBx)
            let missLeave = Swift.max(18, goStat.carrySD)
            let eGo = 1 + pG * putts
                        + pWx * (1 + provider.expected(distanceYds: 30, lie: .rough))
                        + pBx * provider.expected(distanceYds: Swift.max(12, halfDepth), lie: .sand)
                        + pMiss * provider.expected(distanceYds: missLeave, lie: .rough)
            plan.strategy.append(StrategyOption(
                title: "Go for the green",
                clubName: goStat.name,
                detail: "Hit \(goStat.name) at the number.",
                successPercent: Int((pG * 100).rounded()),
                hazardPercent: Int(((pWx + pBx) * 100).rounded()),
                expectedStrokes: eGo))
        }

        // ── LAY UP option: longest safe club, then their best wedge number in ─────────
        if input.playingYards > 120 {
            let layupCandidates = input.clubs
                .filter { $0.effectiveYards <= input.playingYards - 25 && $0.sampleCount >= 3 }
                .sorted { $0.effectiveYards > $1.effectiveYards }
            var layupPick: (stat: CaddieEngine.ClubStat, risk: Double)?
            for c in layupCandidates {
                let (b, w) = hazardRisk(stat: c, zones: zones)
                if b + w < 0.15 { layupPick = (c, b + w); break }
            }
            if layupPick == nil, let safest = layupCandidates
                .map({ (stat: $0, risk: { let r = hazardRisk(stat: $0, zones: zones); return r.bunker + r.water }($0)) })
                .min(by: { $0.risk < $1.risk }) {
                layupPick = safest
            }
            if let (lay, layRisk) = layupPick {
                let leaves = Swift.max(20, input.playingYards - lay.effectiveYards)
                let (apName, apP) = bestApproach(clubs: input.clubs, at: leaves,
                                                 approach: input.approach)
                let eLay = 1 + layRisk * 0.4
                             + 1 + apP * putts
                             + (1 - apP) * provider.expected(distanceYds: 15, lie: .rough)
                plan.strategy.append(StrategyOption(
                    title: "Lay up",
                    clubName: lay.name,
                    detail: "\(lay.name) to ~\(Int(leaves.rounded())) yds, then \(apName) in.",
                    successPercent: Int((apP * 100).rounded()),
                    hazardPercent: Int((layRisk * 100).rounded()),
                    expectedStrokes: eLay))
            }
        }

        plan.strategy.sort { $0.expectedStrokes < $1.expectedStrokes }
        if plan.strategy.count >= 2 {
            let bestOpt = plan.strategy[0], alt = plan.strategy[1]
            let diff = alt.expectedStrokes - bestOpt.expectedStrokes
            if diff < 0.12 {
                plan.strategyNote = "Dead even on strokes (\(fmt(bestOpt.expectedStrokes)) vs \(fmt(alt.expectedStrokes))) — take the shot you trust today."
            } else if bestOpt.title.hasPrefix("Go") {
                plan.strategyNote = "Green light: going costs you \(fmt(bestOpt.expectedStrokes)) strokes on average vs \(fmt(alt.expectedStrokes)) laying up."
            } else {
                plan.strategyNote = "Position play: laying up averages \(fmt(bestOpt.expectedStrokes)) strokes vs \(fmt(alt.expectedStrokes)) going for it — protect the card."
            }
        }

        // ── Hazard notes for the suggested club ───────────────────────────────────────
        if let goStat {
            for z in zones {
                let kind = z.kind == .bunker ? "bunker" : "water"
                let sd = Swift.max(goStat.carrySD, 5)
                let pClear = 1 - phi((z.toYds - goStat.effectiveYards) / sd)
                let clearPct = Int((pClear * 100).rounded())
                if z.toYds > input.playingYards - halfDepth { continue }  // greenside, covered by pick
                if pClear >= 0.75 {
                    plan.hazardNotes.append(
                        "Carries the \(kind) at \(Int(z.toYds.rounded())) — your \(goStat.name) clears it \(clearPct)% of the time.")
                } else if pClear <= 0.35 {
                    plan.hazardNotes.append(
                        "The \(kind) at \(Int(z.fromYds.rounded()))–\(Int(z.toYds.rounded())) is in play — only \(clearPct)% of your \(goStat.name) shots clear it. Lay up short or take more club.")
                } else {
                    plan.hazardNotes.append(
                        "Coin flip over the \(kind) at \(Int(z.toYds.rounded())) (\(clearPct)% clear) — commit or club up.")
                }
            }
        }

        // ── Off-the-line / punch-out side note ────────────────────────────────────────
        if input.originIsLive, let origin = input.origin, let green = input.green,
           input.centerline.count >= 2 {
            plan.positionNote = positionNote(player: origin, green: green,
                                             centerline: input.centerline,
                                             clubs: input.clubs, approach: input.approach)
        }

        let courseBit = input.courseSamples > 0 ? " (\(input.courseSamples) hit on-course)" : ""
        plan.basis = "Outlier-filtered: built from \(input.totalSamples) of your shots\(courseBit)"
            + (input.avgPutts != nil ? " and your real putting." : ".")
        return plan
    }

    /// Best club for a plain approach from `yds` out (generic green), with its success odds.
    static func bestApproach(clubs: [CaddieEngine.ClubStat], at yds: Double,
                             approach: ApproachSuccessModel?) -> (name: String, p: Double) {
        var best: (String, Double) = ("wedge", 0.3)
        for c in clubs where c.sampleCount >= 3 && abs(c.carryMean - yds) <= 25 {
            let p = pGreen(stat: c, playingYards: yds, halfDepth: 9, halfWidth: 10,
                           approach: approach)
            if p > best.1 { best = (c.name, p) }
        }
        return best
    }

    /// "You're 35 yds right of the hole's line — punch out, then X from ~120 (64% for you)."
    /// Only meaningful with a live fix; nil when the player is basically on the line.
    static func positionNote(player: CLLocationCoordinate2D,
                             green: CLLocationCoordinate2D,
                             centerline: [CLLocationCoordinate2D],
                             clubs: [CaddieEngine.ClubStat],
                             approach: ApproachSuccessModel?) -> String? {
        guard let (nearest, lineBearing) = nearestOnPolyline(player, centerline) else { return nil }
        let offset = player.yards(to: nearest)
        guard offset >= 28 else { return nil }
        // Which side: bearing from the line point to the player vs the line's direction.
        let rel = (nearest.bearing(to: player) - lineBearing + 540)
            .truncatingRemainder(dividingBy: 360) - 180
        let side = rel >= 0 ? "right" : "left"

        // Punch-out: back to the line, ball advances a touch — approach from ~the same number.
        let backOnLine = Swift.max(40, nearest.yards(to: green) - 12)
        let (apName, apP) = bestApproach(clubs: clubs, at: backOnLine, approach: approach)
        let pct = Int((apP * 100).rounded())
        return "You're ~\(Int(offset.rounded())) yds \(side) of the hole's line. If trees or trouble block the green, take your medicine: punch back to the fairway, then \(apName) from ~\(Int(backOnLine.rounded())) — you put that on or around the green \(pct)% of the time. One safe shot beats a heroic double."
    }

    /// Nearest point on the polyline + the direction of its segment at that point.
    private static func nearestOnPolyline(_ p: CLLocationCoordinate2D,
                                          _ line: [CLLocationCoordinate2D])
        -> (point: CLLocationCoordinate2D, segmentBearing: Double)? {
        guard line.count >= 2 else { return nil }
        var best: (CLLocationCoordinate2D, Double, Double)?   // point, bearing, distance
        for i in 0..<(line.count - 1) {
            let a = line[i], b = line[i + 1]
            let segLen = a.yards(to: b)
            guard segLen > 1 else { continue }
            let segBearing = a.bearing(to: b)
            let d = a.yards(to: p)
            let theta = (a.bearing(to: p) - segBearing) * .pi / 180
            let t = Swift.max(0, Swift.min(segLen, d * cos(theta)))
            let proj = a.projected(yardsForward: t, yardsRight: 0, bearingDeg: segBearing)
            let dist = p.yards(to: proj)
            if best == nil || dist < best!.2 { best = (proj, segBearing, dist) }
        }
        return best.map { ($0.0, $0.1) }
    }

    private static func fmt(_ x: Double) -> String { String(format: "%.1f", x) }
}
