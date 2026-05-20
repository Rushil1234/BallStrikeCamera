import Foundation
import CoreLocation

// MARK: - CourseDataAggregator
//
// Multi-source course enrichment. Combines:
//   • GolfCourseAPI  → authoritative scorecard (par, handicap, per-tee yardage, tee boxes
//                       with rating/slope). No geospatial geometry.
//   • OpenStreetMap   → geometry (green/fairway/bunker/water polygons, green center/front/back
//                       coordinates, tee coordinates). Pars/yardages unreliable.
//
// The merge takes the BEST of each: accurate scorecard from GolfCourseAPI laid over real
// geometry from OSM, aligned by hole number. Either source missing degrades gracefully.
//
// Result is cached through `OSMGolfService` so `loadCached` / resume see the merged course.

final class CourseDataAggregator {

    static let shared = CourseDataAggregator()

    private let golfAPI = GolfCourseAPIProvider(userId: UUID())   // userId unused for search/detail
    // Max distance a GolfCourseAPI match may be from the discovered course coordinate.
    private let matchRadiusMeters: Double = 12_000

    // MARK: - Public API

    /// Enrich a discovered (MapKit) course stub with merged scorecard + geometry.
    /// Best-effort: never throws. Returns the richest course it can assemble.
    func enrich(_ course: GolfCourse) async -> GolfCourse {
        // Merged cache hit?
        if let cached = OSMGolfService.shared.loadCached(courseId: course.id) {
            return cached
        }

        // GolfCourseAPI scorecard is the reliable source (par/yardage/handicap) and is the
        // ONLY accurate data for courses OSM hasn't mapped. Run it in a detached task so a
        // spurious SwiftUI `.task` cancellation can't drop it. Geometry is best-effort.
        async let osmTask: GolfCourse = OSMGolfService.shared.enrichBestEffort(course)
        let scorecard = await Task.detached(priority: .userInitiated) { [self] in
            await fetchScorecard(for: course)
        }.value
        let osm = await osmTask

        let merged = merge(base: course, osm: osm, scorecard: scorecard)
        OSMGolfService.shared.cacheMergedCourse(merged)
        return merged
    }

    /// Resolve the user-selected tee (chosen from generic MapKit tees) to the authoritative
    /// tee box on the enriched course, matching by name then color. Falls back sensibly.
    func resolveTeeBox(_ selected: TeeBox, in course: GolfCourse) -> TeeBox {
        guard !course.teeBoxes.isEmpty else { return selected }
        if let byName = course.teeBoxes.first(where: {
            $0.name.caseInsensitiveCompare(selected.name) == .orderedSame
        }) { return byName }
        if let byColor = course.teeBoxes.first(where: {
            $0.color.caseInsensitiveCompare(selected.color) == .orderedSame
        }) { return byColor }
        return course.teeBoxes.first ?? selected
    }

    // MARK: - GolfCourseAPI scorecard

    private func fetchScorecard(for course: GolfCourse) async -> GolfCourse? {
        guard GolfCourseAPIConfig.isConfigured else { return nil }
        do {
            let results = try await golfAPI.searchCourses(query: course.name, near: course.coordinate)
            guard var best = bestMatch(results, to: course) else { return nil }
            // If the search result lacks hole data, pull full detail.
            if best.holes.isEmpty {
                best = (try? await golfAPI.loadCourseDetails(courseId: best.id)) ?? best
            }
            return best.holes.isEmpty ? nil : best
        } catch {
            #if DEBUG
            print("[Aggregator] GolfCourseAPI scorecard failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Pick the closest scorecard course to the discovered coordinate, preferring ones with
    /// hole data and a name that overlaps the search term.
    private func bestMatch(_ results: [GolfCourse], to course: GolfCourse) -> GolfCourse? {
        guard !results.isEmpty else { return nil }
        let target = course.coordinate
        let scored = results.map { candidate -> (GolfCourse, Double) in
            var penalty = 0.0
            if candidate.holes.isEmpty { penalty += 5_000 }              // prefer real scorecards
            if !namesOverlap(candidate.name, course.name) { penalty += 3_000 }
            let dist: Double = {
                guard let t = target, let lat = candidate.latitude, let lon = candidate.longitude
                else { return 8_000 }                                    // unknown distance = mild penalty
                return CLLocation(latitude: t.latitude, longitude: t.longitude)
                    .distance(from: CLLocation(latitude: lat, longitude: lon))
            }()
            return (candidate, dist + penalty)
        }
        // Reject anything implausibly far unless it's the only option.
        let inRange = scored.filter { $0.1 < matchRadiusMeters }
        let pool = inRange.isEmpty ? scored : inRange
        return pool.min(by: { $0.1 < $1.1 })?.0
    }

    private func namesOverlap(_ a: String, _ b: String) -> Bool {
        let norm: (String) -> Set<String> = { s in
            Set(s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !["the", "golf", "club", "course", "links", "country"].contains($0) })
        }
        let sa = norm(a), sb = norm(b)
        return !sa.isDisjoint(with: sb)
    }

    // MARK: - Merge

    private func merge(base: GolfCourse, osm: GolfCourse, scorecard: GolfCourse?) -> GolfCourse {
        var result = osm                          // start from geometry (may equal `base` if OSM failed)

        guard let sc = scorecard, !sc.holes.isEmpty else {
            // No scorecard: keep OSM geometry as-is (or the bare stub).
            result.cachedAt = Date()
            return result
        }

        // Authoritative tee boxes (named, with rating/slope) from GolfCourseAPI.
        if !sc.teeBoxes.isEmpty { result.teeBoxes = sc.teeBoxes }

        // Align by hole number: scorecard is the source of truth for par/handicap/yardage;
        // OSM supplies geometry for that hole number when present.
        let osmByNumber = Dictionary(osm.holes.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
        var mergedHoles: [GolfHole] = []
        for scHole in sc.holes.sorted(by: { $0.number < $1.number }) {
            if var geo = osmByNumber[scHole.number] {
                geo.par              = scHole.par
                geo.handicap         = scHole.handicap ?? geo.handicap
                if !scHole.teeYardsByTeeBox.isEmpty { geo.teeYardsByTeeBox = scHole.teeYardsByTeeBox }
                mergedHoles.append(geo)
            } else {
                // No geometry for this hole — keep the accurate scorecard hole.
                mergedHoles.append(scHole)
            }
        }
        result.holes = mergedHoles
        if result.name.isEmpty { result.name = sc.name }
        result.source = result.hasRealGeometry ? .merged : .golfCourseAPI
        result.cachedAt = Date()
        return result
    }
}
