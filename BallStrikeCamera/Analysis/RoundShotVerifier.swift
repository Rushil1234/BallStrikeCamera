import Foundation
import CoreLocation
import MapKit

// MARK: - Verified on-course shots

/// A round shot whose start→end journey can be trusted for analytics.
///
/// A hole's shots are "verified" when the player entered a score + putts AND logged exactly
/// (score − putts) non-putt shots. Then shot k necessarily ended where shot k+1 was hit, and
/// the final full swing finished at the green — so distances and lateral deviation computed
/// from GPS points are real, not guesses.
struct VerifiedRoundShot: Identifiable {
    let id: UUID
    let roundId: UUID
    let holeNumber: Int
    let shotIndex: Int
    let clubName: String?
    let clubId: UUID?
    /// Where the shot was hit from.
    let start: CLLocationCoordinate2D
    /// Where it ended: the next shot's location, or the green for the hole-out swing.
    let end: CLLocationCoordinate2D
    /// Total yards the shot travelled (start → end, along the ground).
    let distanceYards: Double
    /// Signed lateral miss in yards off the intended line (negative = left, positive = right).
    /// "Straight" is oriented from the shot's start toward the next fairway marker on the
    /// hole path, or the green center when the path has no marker ahead.
    let lateralYards: Double
    let timestamp: Date
}

enum RoundShotVerifier {

    /// Extracts verified shots from every hole of `round`. `course` supplies hole geometry
    /// (green centers + fairway path) — pass the cached OSM course when available.
    static func verifiedShots(round: CourseRound, course: GolfCourse?) -> [VerifiedRoundShot] {
        var out: [VerifiedRoundShot] = []
        for hole in round.holes {
            out.append(contentsOf: verifiedShots(round: round, hole: hole, course: course))
        }
        return out
    }

    /// True when the hole's logged shots are internally consistent with its score.
    static func isVerified(_ hole: RoundHole) -> Bool {
        guard let score = hole.score, let putts = hole.putts else { return false }
        let swings = fullSwings(hole)
        return !swings.isEmpty && swings.count == score - putts
    }

    static func fullSwings(_ hole: RoundHole) -> [TrackedShot] {
        hole.trackedShots
            .filter { $0.club?.category != .putter }
            .sorted { $0.shotIndex < $1.shotIndex }
    }

    static func verifiedShots(round: CourseRound, hole: RoundHole, course: GolfCourse?) -> [VerifiedRoundShot] {
        guard isVerified(hole) else { return [] }
        let swings = fullSwings(hole)
        let gh = course?.holes.first { $0.number == hole.holeNumber }
        let green = gh?.greenCenterCoordinate?.clCoordinate

        var out: [VerifiedRoundShot] = []
        for (i, shot) in swings.enumerated() {
            let start = shot.startCoordinate.clCoordinate
            let end: CLLocationCoordinate2D? = i + 1 < swings.count
                ? swings[i + 1].startCoordinate.clCoordinate
                : green
            guard let end else { continue }
            let dist = yards(start, end)
            // Junk-fix guard: sub-20yd "shots" are drops/re-logs, 450+ is a GPS jump.
            guard dist >= 20, dist <= 450 else { continue }
            let target = aimTarget(from: start, hole: gh, green: green) ?? end
            out.append(VerifiedRoundShot(
                id: shot.id,
                roundId: round.id,
                holeNumber: hole.holeNumber,
                shotIndex: shot.shotIndex,
                clubName: shot.club?.name,
                clubId: shot.club?.clubId,
                start: start,
                end: end,
                distanceYards: dist,
                lateralYards: lateralOffsetYards(start: start, target: target, landed: end),
                timestamp: shot.timestamp
            ))
        }
        return out
    }

    // MARK: - Geometry

    /// The point that defines "straight" for a shot hit from `start`: the next fairway marker
    /// on the hole path that's meaningfully ahead (≥ 25yd closer to the green than the player),
    /// else the green itself.
    private static func aimTarget(from start: CLLocationCoordinate2D,
                                  hole: GolfHole?,
                                  green: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        guard let green else { return nil }
        let startToGreen = yards(start, green)
        let markersAhead = (hole?.pathCoordinates ?? [])
            .map { $0.clCoordinate }
            .filter { yards($0, green) < startToGreen - 25 && yards(start, $0) > 25 }
        // Nearest marker ahead of the player = the corridor they're aiming down.
        return markersAhead.min { yards(start, $0) < yards(start, $1) } ?? green
    }

    static func yards(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        MKMapPoint(a).distance(to: MKMapPoint(b)) * 1.09361
    }

    /// Signed perpendicular offset (yards) of `landed` from the `start → target` line.
    /// Positive = right of the line (looking from start toward target), negative = left.
    static func lateralOffsetYards(start: CLLocationCoordinate2D,
                                   target: CLLocationCoordinate2D,
                                   landed: CLLocationCoordinate2D) -> Double {
        let kMPerDegLat = 111_320.0
        let cosLat = cos(start.latitude * .pi / 180)
        // Local ENU meters relative to start
        func en(_ c: CLLocationCoordinate2D) -> (e: Double, n: Double) {
            ((c.longitude - start.longitude) * kMPerDegLat * cosLat,
             (c.latitude - start.latitude) * kMPerDegLat)
        }
        let t = en(target), l = en(landed)
        let lineLen = (t.e * t.e + t.n * t.n).squareRoot()
        guard lineLen > 1 else { return 0 }
        // Cross product z-component: positive when landed is LEFT of the line in ENU,
        // so negate for golf convention (right positive).
        let cross = (t.e * l.n - t.n * l.e) / lineLen
        return -cross * 1.09361
    }
}
