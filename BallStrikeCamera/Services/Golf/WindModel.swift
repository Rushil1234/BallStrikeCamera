import Foundation
import CoreLocation

/// Quantified wind-effect model for golf shots.
///
/// Coefficients are tuned to well-established launch-monitor / teaching rules of thumb:
///   • A pure 10 mph HEADWIND costs a mid-trajectory ~150 yd shot roughly 12–15 yds of carry.
///   • A pure 10 mph TAILWIND only adds ~6–8 yds — headwind hurts about 2× more than tailwind
///     helps, because a headwind raises effective airspeed (more drag) AND balloons the flight.
///   • A 10 mph pure CROSSWIND drifts that same shot ~8–12 yds laterally.
///   • Higher-launch / higher-spin shots (wedges, high irons) spend longer in the air and are
///     affected substantially more than low, driving shots — captured by `LaunchProfile`.
///
/// Effects scale ~linearly with carry distance (longer = more air time) and with the launch
/// profile. This is an estimate, not a trajectory simulation, but it lands within a yard or two of
/// the accepted rules of thumb across the normal 8–20 mph range.
enum WindModel {

    /// How high/spinny the shot flies — the dominant driver of how much wind matters.
    enum LaunchProfile: Double {
        case low  = 0.70   // long irons, driving/punch shots, knock-downs
        case mid  = 1.00   // mid irons — the reference trajectory
        case high = 1.35   // short irons & wedges (high launch, high spin)

        /// Reasonable default profile for a club category.
        static func forClub(_ category: ShotClub.ClubCategory) -> LaunchProfile {
            switch category {
            case .driver, .wood:      return .low
            case .hybrid:             return .low
            case .iron:               return .mid
            case .wedge:              return .high
            case .putter:             return .mid
            }
        }
    }

    struct Effect {
        /// Distance the shot now "plays like" (headwind → longer, tailwind → shorter).
        let playsLikeYards: Int
        /// Carry yards gained (+, tailwind) or lost (−, headwind) versus a calm day.
        let carryDeltaYards: Int
        /// Headwind component in mph (+ headwind, − tailwind).
        let headwindMph: Double
        /// Crosswind component in mph (+ pushes the ball right of target, − pushes left).
        let crosswindMph: Double
        /// Lateral drift in yards (+ right, − left) the ball will be blown.
        let lateralDriftYards: Int
        /// Suggested aim offset, e.g. "aim 6y left". Empty when negligible.
        let aimAdvice: String
    }

    // Coefficients at the 150 yd / mid-trajectory reference.
    private static let cHead:  Double = 1.30   // yds of carry lost per mph of headwind
    private static let cTail:  Double = 0.70   // yds of carry gained per mph of tailwind
    private static let cCross: Double = 1.00   // yds of lateral drift per mph of crosswind

    /// Compute the wind effect on a shot.
    /// - Parameters:
    ///   - distanceYards: target/carry distance on a calm day.
    ///   - shotBearingDegrees: compass bearing player → target (0 = N, 90 = E).
    ///   - windSpeedMph: sustained wind speed.
    ///   - windFromDegrees: compass direction the wind is blowing FROM (meteorological convention).
    ///   - profile: shot launch profile.
    static func effect(distanceYards: Double,
                       shotBearingDegrees: Double,
                       windSpeedMph: Double,
                       windFromDegrees: Double,
                       profile: LaunchProfile) -> Effect {
        guard distanceYards > 0, windSpeedMph > 0 else {
            return Effect(playsLikeYards: Int(distanceYards.rounded()), carryDeltaYards: 0,
                          headwindMph: 0, crosswindMph: 0, lateralDriftYards: 0, aimAdvice: "")
        }

        // Angle between where the wind is coming FROM and the target line. 0° = wind in your face
        // from the target (pure headwind); 180° = pure tailwind.
        let delta = ((windFromDegrees - shotBearingDegrees) * .pi / 180)
        let head  =  windSpeedMph * cos(delta)   // + headwind (wind from target), − tailwind
        // Wind coming from the LEFT of the line pushes the ball to the RIGHT (+).
        let cross = -windSpeedMph * sin(delta)

        let distScale = distanceYards / 150.0
        let l = profile.rawValue

        let headCoef = head >= 0 ? cHead : cTail
        // Carry lost to a headwind (head>0) or gained from a tailwind (head<0).
        let carryLost = head * headCoef * distScale * l
        let playsLike = distanceYards + carryLost          // headwind makes it play longer
        let carryDelta = -carryLost                        // + means ball flies farther

        let drift = cross * cCross * distScale * l          // + right, − left

        let driftInt = Int(drift.rounded())
        var advice = ""
        if abs(driftInt) >= 2 {
            advice = "aim \(abs(driftInt))y \(driftInt > 0 ? "left" : "right")"
        }

        return Effect(
            playsLikeYards: Int(playsLike.rounded()),
            carryDeltaYards: Int(carryDelta.rounded()),
            headwindMph: head,
            crosswindMph: cross,
            lateralDriftYards: driftInt,
            aimAdvice: advice
        )
    }

    /// Compass abbreviation for a direction the wind blows FROM (e.g. 270 → "W").
    static func cardinal(_ degrees: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        let idx = Int((degrees / 45).rounded()) % 8
        return dirs[(idx + 8) % 8]
    }

    /// Short relative descriptor versus the shot line, e.g. "hurting", "helping", "L→R".
    static func relativeLabel(headwindMph: Double, crosswindMph: Double) -> String {
        let along = abs(headwindMph) >= abs(crosswindMph)
        if along {
            return headwindMph > 0 ? "into" : "downwind"
        } else {
            return crosswindMph > 0 ? "L→R" : "R→L"
        }
    }
}
