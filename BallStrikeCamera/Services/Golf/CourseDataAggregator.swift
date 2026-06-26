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
    /// Loads course geometry from Supabase. Falls back to disk cache if offline.
    func enrich(_ course: GolfCourse, backend: AppBackend? = nil) async -> GolfCourse {
        // Primary source: Supabase catalog (geometry storage bucket).
        // All tee, green, and path data lives here — no third-party API calls needed.
        if let catalog = await CourseCatalog.geometry(for: course),
           catalog.hasTrustedGeometry {
            var result = catalog
            result.id = course.id
            result = await mergeScorecardTees(into: result)
            OSMGolfService.shared.cacheMergedCourse(result)
            return result
        }

        // Offline fallback: use whatever is on disk if the network is unavailable.
        if let cached = OSMGolfService.shared.loadCached(courseId: course.id),
           cached.hasTrustedGeometry {
            return cached
        }

        // Nothing available — return the original stub so the round can still start.
        return course
    }

    /// When the GPS geometry carries only a single tee (common for traced courses where only one
    /// tee box was digitized), pull the full tee set + per-hole yardages from the GolfCourse
    /// scorecard API and merge in the tees we're missing. Best-effort and non-blocking — any
    /// failure (API off, no confident name match, no extra tees) returns the geometry unchanged,
    /// so it never blocks or slows a course that already has a full tee set.
    private func mergeScorecardTees(into geo: GolfCourse) async -> GolfCourse {
        guard geo.teeBoxes.count <= 1, !geo.name.isEmpty,
              GolfCourseAPIConfig.isConfigured else { return geo }
        let matches = (try? await golfAPI.searchCourses(query: geo.name, near: geo.coordinate)) ?? []
        guard var scorecard = matches.first(where: { Self.courseNamesMatch($0.name, geo.name) }) else { return geo }
        // Search results can be summary-only; fetch full detail if per-hole yardages are missing.
        if scorecard.holes.allSatisfy({ $0.teeYardsByTeeBox.isEmpty }),
           let detail = try? await golfAPI.loadCourseDetails(courseId: scorecard.id) {
            scorecard = detail
        }
        let existing = Set(geo.teeBoxes.map { $0.name.lowercased() })
        let newTees = scorecard.teeBoxes.filter { $0.totalYards > 0 && !existing.contains($0.name.lowercased()) }
        guard !newTees.isEmpty else { return geo }

        var result = geo
        result.teeBoxes.append(contentsOf: newTees)
        let newIds = Set(newTees.map { $0.id })
        // Align scorecard holes to the geometry by par + true tee→green distance, NOT by hole
        // number. Composite / re-routed courses (e.g. a "Blue/White" 18 stitched from two nines)
        // can have the scorecard's hole order differ from the geometry's, which would otherwise
        // graft a par-3's yardage onto a par-5, etc. Greedy 1-to-1 on (par, nearest distance).
        var availableSC = Array(scorecard.holes.indices)
        for i in result.holes.indices {
            let gh = result.holes[i]
            let geomYards = Double(gh.measuredYardage ?? 0)
            var bestK: Int?; var bestDiff = Double.greatestFiniteMagnitude
            for k in availableSC where scorecard.holes[k].par == gh.par {
                let scYards = Double(scorecard.holes[k].teeYardsByTeeBox.values.max() ?? 0)
                let diff = geomYards > 0 ? abs(scYards - geomYards) : 0
                if diff < bestDiff { bestDiff = diff; bestK = k }
            }
            guard let k = bestK else { continue }
            availableSC.removeAll { $0 == k }
            for (teeId, yards) in scorecard.holes[k].teeYardsByTeeBox where yards > 0 && newIds.contains(teeId) {
                result.holes[i].teeYardsByTeeBox[teeId] = yards
            }
        }
        #if DEBUG
        print("[Aggregator] merged \(newTees.count) scorecard tee(s) into \(geo.name)")
        #endif
        return result
    }

    /// Confident match between a GPS course name and a scorecard course name, ignoring punctuation
    /// and spacing (e.g. "… ~ Blue/White" vs "… - Blue/White"). Requires substantial overlap so we
    /// don't graft a different course's tees onto this one.
    static func courseNamesMatch(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            String(String.UnicodeScalarView(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
        }
        let na = norm(a), nb = norm(b)
        guard na.count >= 8, nb.count >= 8 else { return na == nb }
        return na == nb || na.contains(nb) || nb.contains(na)
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

    func queueBackfill(_ course: GolfCourse,
                       backend: AppBackend?,
                       reason: String = "missing_geometry") async {
        guard isUsableCachedCourse(course) else { return }
        try? await sharedGeometryBackend(preferred: backend)?
            .requestCourseGeometryBackfill(course, reason: reason)
    }

    private func isUsableCachedCourse(_ course: GolfCourse) -> Bool {
        if course.hasTrustedGeometry { return true }
        let validHoleNumbers = course.holes.filter { $0.number > 0 }.count
        let hasScorecard = validHoleNumbers >= 9 && course.teeBoxes.contains { $0.totalYards > 0 }
        return hasScorecard
    }

    private func loadSharedGeometry(courseId: String, backend: AppBackend?) async -> GolfCourse? {
        guard let backend = sharedGeometryBackend(preferred: backend) else { return nil }
        do {
            let course = try await backend.loadCourseGeometry(courseId: courseId)
            return course?.hasTrustedGeometry == true ? course : nil
        } catch {
            #if DEBUG
            print("[Aggregator] shared course geometry failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Fuzzy fallback when the exact id misses — the bulk OSM pre-bake can't always reproduce the
    /// MapKit synthetic id, so we match the shared geometry by name + proximity instead.
    private func loadSharedGeometryFuzzy(_ course: GolfCourse, backend: AppBackend?) async -> GolfCourse? {
        guard let backend = sharedGeometryBackend(preferred: backend) else { return nil }
        do {
            let match = try await backend.findCourseGeometryNear(name: course.name,
                                                                 coordinate: course.coordinate)
            return match?.hasTrustedGeometry == true ? match : nil
        } catch {
            #if DEBUG
            print("[Aggregator] fuzzy shared geometry failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Public course geometry should still use Supabase when the signed-in/session backend is
    /// local guest storage because Supabase anonymous auth is disabled. These course endpoints
    /// are RLS-safe with the publishable key and do not require a user session.
    private func sharedGeometryBackend(preferred backend: AppBackend?) -> AppBackend? {
        if let backend, backend is SupabaseBackendService {
            return backend
        }
        if let config = SupabaseConfig.load() {
            return SupabaseBackendService(config: config)
        }
        return backend
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
        // Deduplicate by name (male+female can produce same name) and sort longest first.
        if !sc.teeBoxes.isEmpty {
            var seen: [String: TeeBox] = [:]
            for tee in sc.teeBoxes {
                let key = tee.name.lowercased()
                if let existing = seen[key] {
                    if tee.totalYards > existing.totalYards { seen[key] = tee }
                } else {
                    seen[key] = tee
                }
            }
            result.teeBoxes = seen.values.sorted { $0.totalYards > $1.totalYards }
        }

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
        if result.hasRealGeometry {
            if result.geometryMetadata == nil || result.geometryMetadata?.state == .unknown {
                result.geometryMetadata = CourseGeometryMetadata(
                    state: .accepted,
                    confidence: 1.0,
                    source: osm.source.rawValue,
                    schemaVersion: 1,
                    generatedBy: osm.source == .openStreetMap ? "osm_overpass" : "shared_geometry",
                    validationErrors: [],
                    imagerySource: nil,
                    updatedAt: Date()
                )
            }
            result.source = .merged
        } else {
            result.source = .golfCourseAPI
        }
        result.cachedAt = Date()
        return result
    }
}

// MARK: - Course Mode Availability

struct CourseAvailabilityReport: Identifiable, Equatable {
    let id = UUID()
    let courseId: String
    let courseName: String
    let city: String
    let state: String
    let country: String
    let reasonCode: String
    let message: String
    let missingHoleNumbers: [Int]
    let scorecardHoleCount: Int
    let geometryHoleCount: Int
    let csvURL: URL
    let createdAt: Date

    var locationLabel: String {
        [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// How fully a course can be played, best tier first. The app no longer blocks a round just
/// because OSM lacks hand-traced geometry for every hole — it starts in the richest tier the
/// free data (GolfCourseAPI scorecard + OSM greens) supports and keeps queueing backfill so
/// coverage improves over time.
enum CourseModeTier {
    /// Verified tee + green polygon + route for every hole, scorecard yardages validated.
    case fullGPS
    /// Scorecard + a green-center point on most holes — distance-to-green works. Green polygon /
    /// front / back are synthesized from the center where OSM didn't trace them.
    case rangefinder
    /// A usable scorecard but not enough geometry for live distances — score tracking only.
    case scorecardOnly
    /// Nothing playable (no holes, no geometry).
    case unavailable

    var isPlayable: Bool { self != .unavailable }
    var hasLiveDistances: Bool { self == .fullGPS || self == .rangefinder }
}

struct CourseModeReadiness {
    let tier: CourseModeTier
    /// Diagnostic detail. Always present for `.unavailable`; present for degraded tiers so the
    /// app can show a banner and log the course for geometry backfill.
    let report: CourseAvailabilityReport?
}

enum CourseAvailability {
    private static let minimumHoleCount = 9

    static var unavailableCSVURL: URL {
        AppStorageManager.globalRoot
            .appendingPathComponent("courseAvailability")
            .appendingPathComponent("unavailable_courses.csv")
    }

    /// Classify how fully a course can be played. Never blocks unless the course is genuinely empty.
    static func evaluateReadiness(course: GolfCourse,
                                  teeBox: TeeBox?) -> CourseModeReadiness {
        let playable = course.holes.filter { $0.number > 0 }
        let expectedCount = expectedPlayableHoleCount(for: playable)
        let geometryHoles = playable.filter(isHoleGeometryPlayable)
        let centerHoles = playable.filter { $0.hasGreenCenter }

        // Genuinely empty — nothing to score or range.
        guard !playable.isEmpty, playable.count >= minimumHoleCount || !centerHoles.isEmpty else {
            return CourseModeReadiness(
                tier: .unavailable,
                report: report(
                    course: course,
                    reasonCode: "missing_scorecard",
                    message: "This course does not have a scorecard or map data yet, so True Carry can't start a round.",
                    missing: Array(1...18),
                    scorecardHoleCount: playable.count,
                    geometryHoleCount: geometryHoles.count
                )
            )
        }

        // Full verified GPS: complete, trusted geometry (tee + green + outline) on every hole.
        // Licensed pro data is authoritative, so we do NOT second-guess it with route-vs-scorecard
        // yardage heuristics (those were for rough OSM geometry and wrongly demoted good courses).
        let fullGeomCount = (1...expectedCount).filter { number in
            playable.first(where: { $0.number == number }).map(isHoleGeometryPlayable) ?? false
        }.count
        if fullGeomCount == expectedCount, course.hasTrustedGeometry {
            return CourseModeReadiness(tier: .fullGPS, report: nil)
        }

        // Rangefinder: enough green centers to give distance-to-green. We synthesize polygon /
        // front / back from the centers at round start.
        let rangefinderThreshold = max(minimumHoleCount, Int((Double(expectedCount) * 0.5).rounded()))
        if centerHoles.count >= rangefinderThreshold {
            return CourseModeReadiness(
                tier: .rangefinder,
                report: report(
                    course: course,
                    reasonCode: "rangefinder_partial_geometry",
                    message: "Live GPS active · course visuals improving",
                    missing: (1...expectedCount).filter { number in
                        !(playable.first(where: { $0.number == number })?.hasGreenCenter ?? false)
                    },
                    scorecardHoleCount: playable.count,
                    geometryHoleCount: centerHoles.count
                )
            )
        }

        // Scorecard only: track score and see par/yardage, no live distances.
        return CourseModeReadiness(
            tier: .scorecardOnly,
            report: report(
                course: course,
                reasonCode: "scorecard_only",
                message: "Scorecard mode · live distances limited here",
                missing: [],
                scorecardHoleCount: playable.count,
                geometryHoleCount: centerHoles.count
            )
        )
    }

    /// Returns a course copy where holes that have a green center but no traced green polygon get a
    /// synthesized polygon + front/back, so the round map can render distance-to-green everywhere.
    static func makePlayReady(_ course: GolfCourse) -> GolfCourse {
        var result = course
        result.holes = course.holes.map { hole in
            var h = hole
            h.fillSyntheticGreenIfNeeded()
            return h
        }
        return result
    }

    static func recordUnavailable(_ report: CourseAvailabilityReport,
                                  teeBox: TeeBox?) {
        let url = unavailableCSVURL
        AppStorageManager.ensureDirectory(url.deletingLastPathComponent())
        let header = "timestamp,course_id,course_name,city,state,country,tee_name,tee_yards,reason,missing_holes,scorecard_holes,geometry_holes\n"
        let line = [
            csvDate(report.createdAt),
            report.courseId,
            report.courseName,
            report.city,
            report.state,
            report.country,
            teeBox?.name ?? "",
            teeBox?.totalYards.description ?? "",
            report.reasonCode,
            report.missingHoleNumbers.map(String.init).joined(separator: "|"),
            String(report.scorecardHoleCount),
            String(report.geometryHoleCount)
        ].map(csvEscape).joined(separator: ",") + "\n"

        if !FileManager.default.fileExists(atPath: url.path) {
            try? (header + line).data(using: .utf8)?.write(to: url, options: .atomic)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }

    private static func expectedPlayableHoleCount(for holes: [GolfHole]) -> Int {
        if holes.count >= 18 { return 18 }
        if holes.count >= 9 { return 9 }
        return 18
    }

    private static func isHoleGeometryPlayable(_ hole: GolfHole) -> Bool {
        hole.number > 0 &&
        hole.teeCoordinate != nil &&
        hole.greenCenterCoordinate != nil
    }

    private static func hasAuthoritativeScorecard(_ holes: [GolfHole],
                                                  teeBox: TeeBox?,
                                                  expectedCount: Int) -> Bool {
        guard let teeBox, teeBox.totalYards > 0 else { return false }
        let yardageCount = (1...expectedCount).filter { number in
            guard let hole = holes.first(where: { $0.number == number }) else { return false }
            return (hole.teeYardsByTeeBox[teeBox.id] ?? 0) > 0
        }.count
        return yardageCount == expectedCount
    }

    private static func yardageMismatch(for hole: GolfHole,
                                        teeBox: TeeBox?) -> String? {
        let geometryYards = routeYards(for: hole) ?? hole.measuredYardage
        guard let geometryYards, geometryYards > 0 else { return nil }

        let hasSelectedTeeGeometry = teeBox.flatMap { hole.teeCoordinateByTeeBox?[$0.id] } != nil
        let candidates: [(label: String, yards: Int)]
        if hasSelectedTeeGeometry,
           let teeBox,
           let selectedYards = hole.teeYardsByTeeBox[teeBox.id],
           selectedYards > 0 {
            candidates = [(teeBox.name, selectedYards)]
        } else {
            // OSM usually stores one `golf=hole` route, not a separate centerline per tee box.
            // Validate that the route matches at least one official tee yardage so forward
            // tees do not falsely block an otherwise verified course map.
            candidates = hole.teeYardsByTeeBox
                .compactMap { key, yards in yards > 0 ? (key, yards) : nil }
        }

        guard let closest = candidates.min(by: {
            abs($0.yards - geometryYards) < abs($1.yards - geometryYards)
        }) else { return nil }

        let tolerance = max(25, Int((Double(closest.yards) * 0.08).rounded()))
        let delta = abs(closest.yards - geometryYards)
        guard delta > tolerance else { return nil }
        return "hole_\(hole.number)_yardage_mismatch_\(geometryYards)_vs_nearest_scorecard_\(closest.yards)"
    }

    private static func routeYards(for hole: GolfHole) -> Int? {
        guard let path = hole.pathCoordinates, path.count >= 2 else { return nil }
        let meters = zip(path, path.dropFirst()).reduce(0.0) { partial, pair in
            let a = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let b = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return partial + a.distance(from: b)
        }
        return Int((meters * 1.09361).rounded())
    }

    private static func report(course: GolfCourse,
                               reasonCode: String,
                               message: String,
                               missing: [Int],
                               scorecardHoleCount: Int,
                               geometryHoleCount: Int) -> CourseAvailabilityReport {
        CourseAvailabilityReport(
            courseId: course.id,
            courseName: course.name,
            city: course.city,
            state: course.state,
            country: course.country,
            reasonCode: reasonCode,
            message: message,
            missingHoleNumbers: missing,
            scorecardHoleCount: scorecardHoleCount,
            geometryHoleCount: geometryHoleCount,
            csvURL: unavailableCSVURL,
            createdAt: Date()
        )
    }

    private static func csvDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
