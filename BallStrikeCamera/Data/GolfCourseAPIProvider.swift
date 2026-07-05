import Foundation
import CoreLocation

// MARK: - GolfCourseAPI Live Provider
// Docs: https://api.golfcourseapi.com/docs/api/
// Authorization header: "Key <API_KEY>"

final class GolfCourseAPIProvider: CourseProvider {

    private let userId: UUID
    private let session = URLSession.shared

    private enum Endpoint {
        static let search  = "search"           // GET /v1/search?search_query=<query>
        static let detail  = "courses"          // GET /v1/courses/<id>
    }

    init(userId: UUID) { self.userId = userId }

    // MARK: - Search

    func searchCourses(query: String, near location: CLLocationCoordinate2D?) async throws -> [GolfCourse] {
        var components = URLComponents(string: "\(GolfCourseAPIConfig.baseURL)/\(Endpoint.search)")!
        var queryItems: [URLQueryItem] = []
        if !query.isEmpty {
            queryItems.append(URLQueryItem(name: "search_query", value: query))
        } else if let loc = location {
            // GolfCourseAPI does not expose a coordinate-search endpoint. Use a compact
            // lat/lon search string as a last resort; MapKit handles true nearby search.
            queryItems.append(URLQueryItem(
                name: "search_query",
                value: "\(loc.latitude),\(loc.longitude)"
            ))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let key = GolfCourseAPIConfig.apiKey,
              let url = components.url else {
            throw BackendError.networkError("API not configured")
        }

        var request = URLRequest(url: url)
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        #if DEBUG
        print("[GolfCourseAPI] GET \(url.absoluteString)")
        #endif

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.networkError("No HTTP response") }

        #if DEBUG
        print("[GolfCourseAPI] status \(http.statusCode)")
        #endif

        guard http.statusCode == 200 else {
            throw BackendError.networkError("HTTP \(http.statusCode)")
        }

        let decoded = try decodeSearchResponse(data)
        // Cache results
        decoded.forEach { cacheCoure($0) }
        return decoded
    }

    // MARK: - Detail

    func loadCourseDetails(courseId: String) async throws -> GolfCourse {
        // Check cache first
        if let cached = loadCached(courseId: courseId) { return cached }

        guard let key = GolfCourseAPIConfig.apiKey,
              let url = URL(string: "\(GolfCourseAPIConfig.baseURL)/\(Endpoint.detail)/\(courseId)") else {
            throw BackendError.networkError("API not configured")
        }

        var request = URLRequest(url: url)
        request.setValue("Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        #if DEBUG
        print("[GolfCourseAPI] GET \(url.absoluteString)")
        #endif

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BackendError.networkError("HTTP error loading course \(courseId)")
        }

        let course = try decodeCourseDetail(data)
        cacheCoure(course)
        return course
    }

    // MARK: - Decode helpers

    private func decodeSearchResponse(_ data: Data) throws -> [GolfCourse] {
        do {
            let wrapper = try AppStorageManager.decoder.decode(CourseSearchWrapper.self, from: data)
            #if DEBUG
            print("[GolfCourseAPI] decoded \(wrapper.courses.count) courses from wrapper")
            #endif
            return wrapper.courses.map { mapToCourse($0) }
        } catch {
            #if DEBUG
            print("[GolfCourseAPI] wrapper decode failed: \(error)")
            #endif
            let raw = try AppStorageManager.decoder.decode([RawCourse].self, from: data)
            return raw.map { mapToCourse($0) }
        }
    }

    private func decodeCourseDetail(_ data: Data) throws -> GolfCourse {
        if let wrapper = try? AppStorageManager.decoder.decode(CourseDetailWrapper.self, from: data) {
            return mapToCourse(wrapper.course)
        }
        let raw = try AppStorageManager.decoder.decode(RawCourse.self, from: data)
        return mapToCourse(raw)
    }

    // Raw API response models — adjust field names to match real API.
    private struct CourseSearchWrapper: Codable {
        var courses: [RawCourse]
    }
    private struct CourseDetailWrapper: Codable {
        var course: RawCourse
    }
    private struct RawCourse: Codable {
        var id: Int?
        var club_name: String?
        var course_name: String?
        var location: RawLocation?
        var tees: RawTees?
        var holes: [RawHole]?
    }
    private struct RawLocation: Codable {
        var city: String?
        var state: String?
        var country: String?
        var latitude: Double?
        var longitude: Double?
    }
    private struct RawTees: Codable {
        var female: [RawTeeBox]?
        var male: [RawTeeBox]?
    }
    private struct RawTeeBox: Codable {
        var id: String?
        var tee_name: String?
        var name: String?
        var tee_color: String?
        var total_yards: Int?
        var total_distance: Int?
        var course_rating: Double?
        var bogey_rating: Double?
        var slope_rating: Int?
        var holes: [RawHole]?
    }
    private struct RawHole: Codable {
        var id: String?
        var hole_number: Int?
        var number: Int?
        var par: Int?
        var handicap: Int?
        var yardage: Int?
        var yards: Int?
        var distance: Int?
    }

    private func mapToCourse(_ raw: RawCourse) -> GolfCourse {
        let id   = raw.id.map { String($0) } ?? UUID().uuidString
        let name = raw.club_name ?? raw.course_name ?? "Unknown Course"
        let teeBoxes = buildTeeBoxes(raw: raw, courseId: id)
        let holes    = buildHoles(raw: raw, courseId: id, teeBoxes: teeBoxes)
        return GolfCourse(
            id: id,
            name: name,
            city: raw.location?.city ?? "",
            state: raw.location?.state ?? "",
            country: raw.location?.country ?? "US",
            latitude: raw.location?.latitude,
            longitude: raw.location?.longitude,
            holes: holes,
            teeBoxes: teeBoxes,
            source: .golfCourseAPI,
            cachedAt: Date()
        )
    }

    private func buildTeeBoxes(raw: RawCourse, courseId: String) -> [TeeBox] {
        let rawTees = allRawTees(raw)
        guard !rawTees.isEmpty else {
            return [TeeBox(id: "\(courseId)-default", name: "Standard", color: "White", totalYards: 0)]
        }
        let all = rawTees.enumerated().map { idx, entry -> (tee: TeeBox, isFemale: Bool) in
            let t = entry.tee
            let tee = TeeBox(
                id: t.id ?? "\(courseId)-tee-\(idx)",
                name: t.tee_name ?? t.name ?? "Tee \(idx+1)",
                color: inferredTeeColor(explicit: t.tee_color,
                                        name: t.tee_name ?? t.name),
                totalYards: t.total_yards ?? t.total_distance ?? 0,
                rating: t.course_rating,
                slope: t.slope_rating
            )
            return (tee, entry.isFemale)
        }
        return TeeBox.mergingGenderedDuplicates(all)
    }

    private func inferredTeeColor(explicit: String?, name: String?) -> String {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        let lower = (name ?? "").lowercased()
        if lower.contains("championship") || lower.contains("black") { return "Black" }
        if lower.contains("blue") { return "Blue" }
        if lower.contains("white") { return "White" }
        if lower.contains("green") { return "Green" }
        if lower.contains("gold") || lower.contains("yellow") { return "Gold" }
        if lower.contains("red") || lower.contains("forward") { return "Red" }
        if lower.contains("silver") || lower.contains("fairway") { return "Silver" }
        return "Gray"
    }

    private func buildHoles(raw: RawCourse, courseId: String, teeBoxes: [TeeBox]) -> [GolfHole] {
        // GolfCourseAPI holes are ordered arrays and usually do not include a hole_number.
        // Treat the array index as the canonical hole number.
        var holesMap: [Int: GolfHole] = [:]
        let rawEntries = allRawTees(raw)
        let maleColors = Set(rawEntries.filter { !$0.isFemale }.map {
            inferredTeeColor(explicit: $0.tee.tee_color, name: $0.tee.tee_name ?? $0.tee.name)
        })

        for (tee, isFemale) in rawEntries {
            let rawName = tee.tee_name ?? tee.name ?? ""
            let rawColor = inferredTeeColor(explicit: tee.tee_color, name: rawName)
            // A women's tee whose color matches a men's tee was merged into that men's TeeBox for
            // display (TeeBox.mergingGenderedDuplicates) — the merged tee plays the men's yardage
            // entirely (only rating/slope carried over), so its own per-hole yardage doesn't apply.
            if isFemale && maleColors.contains(rawColor) { continue }
            // Match by name (not position) since teeBoxes is the post-merge/dedup array and can be
            // shorter than the raw male+female list; fall back to color for a standalone tee whose
            // exact name text doesn't match (e.g. GolfCourseAPI text variations).
            guard let teeBox = teeBoxes.first(where: { $0.name.caseInsensitiveCompare(rawName) == .orderedSame })
                ?? teeBoxes.first(where: { $0.color.caseInsensitiveCompare(rawColor) == .orderedSame })
            else { continue }
            for (idx, rawHole) in (tee.holes ?? []).enumerated() {
                let num = rawHole.hole_number ?? rawHole.number ?? idx + 1
                guard num > 0 else { continue }
                var hole = holesMap[num] ?? GolfHole(
                    id: "\(courseId)-hole-\(num)",
                    courseId: courseId,
                    number: num,
                    par: rawHole.par ?? 4,
                    handicap: rawHole.handicap
                )
                if let par = rawHole.par {
                    hole.par = par
                }
                if let handicap = rawHole.handicap {
                    hole.handicap = handicap
                }
                let yds = rawHole.yardage ?? rawHole.yards ?? rawHole.distance ?? 0
                if yds > 0 {
                    hole.teeYardsByTeeBox[teeBox.id] = yds
                }
                holesMap[num] = hole
            }
        }
        // Fallback to top-level holes
        for (idx, rawHole) in (raw.holes ?? []).enumerated() {
            let num = rawHole.hole_number ?? rawHole.number ?? idx + 1
            guard num > 0 else { continue }
            if holesMap[num] == nil {
                holesMap[num] = GolfHole(
                    id: "\(courseId)-hole-\(num)",
                    courseId: courseId,
                    number: num,
                    par: rawHole.par ?? 4,
                    handicap: rawHole.handicap
                )
            }
        }
        return holesMap.values.sorted { $0.number < $1.number }
    }

    private func allRawTees(_ raw: RawCourse) -> [(tee: RawTeeBox, isFemale: Bool)] {
        (raw.tees?.male ?? []).map { ($0, false) } + (raw.tees?.female ?? []).map { ($0, true) }
    }

    // MARK: - Cache

    private func cacheCoure(_ course: GolfCourse) {
        let dir  = AppStorageManager.globalCourseCacheDir()
        AppStorageManager.ensureDirectory(dir)
        try? AppStorageManager.save(course, to: dir.appendingPathComponent("\(course.id).json"))
    }

    private func loadCached(courseId: String) -> GolfCourse? {
        let url = AppStorageManager.globalCourseCacheDir().appendingPathComponent("\(courseId).json")
        guard let course = try? AppStorageManager.load(GolfCourse.self, from: url) else { return nil }
        // Invalidate cache after 7 days
        if let cached = course.cachedAt, Date().timeIntervalSince(cached) > 7 * 86400 { return nil }
        return course
    }
}
