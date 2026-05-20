import Foundation
import CoreLocation

// MARK: - Errors

enum OSMGolfError: LocalizedError {
    case missingCoordinate
    case allMirrorsFailed([String])
    case decodeFailed(String)
    case noGreensFound
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingCoordinate:        return "Course has no GPS coordinate to query."
        case .allMirrorsFailed(let r):  return "All Overpass mirrors failed: \(r.joined(separator: "; "))"
        case .decodeFailed(let m):      return "OSM decode failed: \(m)"
        case .noGreensFound:            return "No greens found near this course on OpenStreetMap."
        case .cancelled:                return "OSM enrich request was cancelled."
        }
    }
}

// MARK: - Mirror Configuration

/// Ordered list of Overpass mirrors. Sequential fallback in this exact order.
/// overpass-api.de is the canonical, most reliable instance and goes first. kumi.systems
/// is fast when up but has been flaky/timing out, so it sits last. Timeouts are kept short
/// (12s) so a dead mirror fails fast and we move on instead of hanging ~25s per attempt.
struct OverpassMirror: Equatable {
    let name: String
    let url: URL
    let timeout: TimeInterval

    static let defaults: [OverpassMirror] = [
        .init(name: "overpass-api.de",
              url: URL(string: "https://overpass-api.de/api/interpreter")!,
              timeout: 14),
        .init(name: "openstreetmap.fr",
              url: URL(string: "https://overpass.openstreetmap.fr/api/interpreter")!,
              timeout: 14),
        .init(name: "kumi.systems",
              url: URL(string: "https://overpass.kumi.systems/api/interpreter")!,
              timeout: 12),
    ]
}

// MARK: - Telemetry

/// Lightweight in-memory record of the most recent enrich attempts.
/// Exposed for the DEBUG diagnostics overlay; not persisted.
@MainActor
final class OSMTelemetry: ObservableObject {
    static let shared = OSMTelemetry()

    struct Entry: Identifiable {
        let id = UUID()
        let courseId: String
        let mirror: String?
        let status: Status
        let latencyMs: Int
        let bytes: Int
        let at: Date

        enum Status: String { case success, fail, staleCache, cache }
    }

    @Published private(set) var recent: [Entry] = []
    @Published private(set) var lastEnrichLatencyMs: Int?
    @Published private(set) var lastMirror: String?

    func record(_ e: Entry) {
        recent.insert(e, at: 0)
        if recent.count > 30 { recent.removeLast(recent.count - 30) }
        if e.status == .success || e.status == .cache {
            lastEnrichLatencyMs = e.latencyMs
            lastMirror = e.mirror
        }
    }
}

// MARK: - OSMGolfService

/// Enriches a `GolfCourse` with real geometry pulled from OpenStreetMap via Overpass.
/// Result is cached on disk under `AppStorageManager.globalCourseCacheDir()` keyed by course id.
///
/// Reliability features:
/// - Sequential fallback across multiple Overpass mirrors.
/// - Exponential backoff on transient failures (HTTP 429/504, network errors).
/// - Stale-cache rescue: if every mirror fails but an expired cache exists, return it.
/// - Task de-duplication: concurrent enrich calls for the same course coalesce.
final class OSMGolfService {

    static let shared = OSMGolfService()

    // Tunables
    private let radiusMeters: Double = 1500
    private let cacheTTL:     TimeInterval = 7 * 86400
    private let mirrors:      [OverpassMirror]
    private let session:      URLSession
    private let maxAttemptsPerMirror = 2

    // In-flight task dedup keyed by course id.
    private var inFlight: [String: Task<GolfCourse, Error>] = [:]
    private let inFlightLock = NSLock()

    init(mirrors: [OverpassMirror] = OverpassMirror.defaults) {
        self.mirrors = mirrors
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Public API

    /// Enrich a course with real OSM geometry. Returns the enriched course or throws.
    /// - If the course already has real geometry, it is returned as-is.
    /// - Cached results are reused for `cacheTTL` seconds.
    /// - Concurrent calls for the same `courseId` coalesce into one network round-trip.
    func enrich(_ course: GolfCourse) async throws -> GolfCourse {
        if course.hasRealGeometry { return course }
        if let fresh = loadCached(courseId: course.id) {
            await OSMTelemetry.shared.record(.init(
                courseId: course.id, mirror: nil, status: .cache,
                latencyMs: 0, bytes: 0, at: Date()))
            return fresh
        }
        return try await dedupe(course.id) {
            try await self.enrichOnce(course)
        }
    }

    /// Best-effort variant — swallows errors and falls back to unenriched course.
    func enrichBestEffort(_ course: GolfCourse) async -> GolfCourse {
        do { return try await enrich(course) }
        catch {
            #if DEBUG
            print("[OSMGolf] enrich failed: \(error.localizedDescription)")
            #endif
            return course
        }
    }

    /// Prewarm a course in the background. Honors cancellation; does not throw.
    func prewarm(_ course: GolfCourse, priority: TaskPriority = .background) {
        Task(priority: priority) { [weak self] in
            _ = await self?.enrichBestEffort(course)
        }
    }

    // MARK: - Dedup

    private func dedupe(_ courseId: String,
                        _ work: @escaping () async throws -> GolfCourse) async throws -> GolfCourse {
        inFlightLock.lock()
        if let existing = inFlight[courseId] {
            inFlightLock.unlock()
            return try await existing.value
        }
        let task = Task { try await work() }
        inFlight[courseId] = task
        inFlightLock.unlock()

        defer {
            inFlightLock.lock()
            inFlight[courseId] = nil
            inFlightLock.unlock()
        }
        return try await task.value
    }

    // MARK: - Single enrich attempt across mirrors

    private func enrichOnce(_ course: GolfCourse) async throws -> GolfCourse {
        guard let coord = course.coordinate else { throw OSMGolfError.missingCoordinate }

        let started = Date()
        var failures: [String] = []
        for mirror in mirrors {
            try Task.checkCancellation()
            do {
                let raw = try await fetchOverpass(near: coord, via: mirror)
                let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                let enriched = try assembleCourse(course, elements: raw)
                await OSMTelemetry.shared.record(.init(
                    courseId: course.id, mirror: mirror.name, status: .success,
                    latencyMs: elapsedMs, bytes: 0, at: Date()))
                save(enriched)
                return enriched
            } catch is CancellationError {
                throw OSMGolfError.cancelled
            } catch OSMGolfError.noGreensFound {
                // A mirror answered successfully but OSM simply has no golf geometry here.
                // Every mirror queries the same OSM dataset, so trying the others is pointless
                // (and wastes time hanging on the slow/dead mirror). Fail fast.
                #if DEBUG
                print("[OSMGolf] \(mirror.name): no golf geometry in OSM for this course — not a mirror fault, stopping")
                #endif
                throw OSMGolfError.noGreensFound
            } catch {
                let msg = "\(mirror.name): \(error.localizedDescription)"
                failures.append(msg)
                #if DEBUG
                print("[OSMGolf] \(msg) — trying next mirror")
                #endif
                await OSMTelemetry.shared.record(.init(
                    courseId: course.id, mirror: mirror.name, status: .fail,
                    latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                    bytes: 0, at: Date()))
            }
        }

        // All mirrors failed — try expired cache as last resort.
        if let stale = loadCached(courseId: course.id, allowExpired: true) {
            await OSMTelemetry.shared.record(.init(
                courseId: course.id, mirror: nil, status: .staleCache,
                latencyMs: 0, bytes: 0, at: Date()))
            #if DEBUG
            print("[OSMGolf] all mirrors failed — serving stale cache for \(course.id)")
            #endif
            return stale
        }
        throw OSMGolfError.allMirrorsFailed(failures)
    }

    // MARK: - Overpass fetch with retry/backoff

    private func fetchOverpass(near coord: CLLocationCoordinate2D,
                                via mirror: OverpassMirror) async throws -> [OSMElement] {
        var attempt = 0
        var lastError: Error = OSMGolfError.allMirrorsFailed([])
        while attempt < maxAttemptsPerMirror {
            try Task.checkCancellation()
            attempt += 1
            do {
                return try await performRequest(coord: coord, mirror: mirror)
            } catch let urlErr as URLError where urlErr.code == .cancelled {
                throw OSMGolfError.cancelled
            } catch {
                lastError = error
                if attempt >= maxAttemptsPerMirror { break }
                // Exponential backoff: 600ms, 1.8s, 5.4s …
                let delayMs = UInt64(600 * pow(3.0, Double(attempt - 1)))
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }
        throw lastError
    }

    private func performRequest(coord: CLLocationCoordinate2D,
                                 mirror: OverpassMirror) async throws -> [OSMElement] {
        let query = Self.overpassQuery(lat: coord.latitude, lon: coord.longitude, radius: radiusMeters)
        var req = URLRequest(url: mirror.url)
        req.httpMethod = "POST"
        req.timeoutInterval = mirror.timeout
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("TrueCarry-iOS",
                     forHTTPHeaderField: "User-Agent")
        req.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            .data(using: .utf8)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 429 || http.statusCode == 504 || http.statusCode == 503 {
            throw URLError(.init(rawValue: http.statusCode))
        }
        guard http.statusCode == 200 else {
            throw URLError(.init(rawValue: http.statusCode))
        }
        do {
            return try JSONDecoder().decode(OSMResponse.self, from: data).elements
        } catch {
            throw OSMGolfError.decodeFailed(String(describing: error))
        }
    }

    /// Overpass QL — pulls golf features and their nodes in one request.
    private static func overpassQuery(lat: Double, lon: Double, radius: Double) -> String {
        let r = Int(radius)
        return """
        [out:json][timeout:25];
        (
          way["golf"="green"](around:\(r),\(lat),\(lon));
          way["golf"="fairway"](around:\(r),\(lat),\(lon));
          way["golf"="tee"](around:\(r),\(lat),\(lon));
          way["golf"="bunker"](around:\(r),\(lat),\(lon));
          way["natural"="water"](around:\(r),\(lat),\(lon));
          way["natural"="wetland"](around:\(r),\(lat),\(lon));
          way["golf"="hole"](around:\(r),\(lat),\(lon));
        );
        out body;
        >;
        out skel qt;
        """
    }

    // MARK: - Assemble enriched course

    private func assembleCourse(_ course: GolfCourse, elements: [OSMElement]) throws -> GolfCourse {
        let classified = classify(elements)
        guard !classified.greens.isEmpty else { throw OSMGolfError.noGreensFound }

        let rawHoles = HoleInference.infer(
            classified:    classified,
            courseId:      course.id,
            startingTees:  course.teeBoxes
        )
        // Simplify polygons once before caching so every later render is cheap.
        let holes = rawHoles.map { GeometrySimplifier.simplify($0) }

        var enriched = course
        enriched.holes    = holes
        enriched.source   = .openStreetMap
        enriched.cachedAt = Date()
        if enriched.latitude == nil || enriched.longitude == nil,
           let center = centroidOfAll(classified.greens) {
            enriched.latitude  = center.latitude
            enriched.longitude = center.longitude
        }
        return enriched
    }

    private func classify(_ elements: [OSMElement]) -> OSMClassified {
        var nodeMap: [Int64: Coordinate] = [:]
        nodeMap.reserveCapacity(elements.count)
        for e in elements where e.type == .node {
            if let lat = e.lat, let lon = e.lon {
                nodeMap[e.id] = Coordinate(latitude: lat, longitude: lon)
            }
        }
        var result = OSMClassified()
        for e in elements where e.type == .way {
            guard let nodeRefs = e.nodes, let tags = e.tags else { continue }
            let coords = nodeRefs.compactMap { nodeMap[$0] }
            guard coords.count >= 2 else { continue }
            let geom = OSMWayGeometry(id: e.id, coordinates: coords, tags: tags)
            if let g = tags["golf"] {
                switch g {
                case "green":    result.greens.append(geom)
                case "fairway":  result.fairways.append(geom)
                case "tee":      result.tees.append(geom)
                case "bunker":   result.bunkers.append(geom)
                case "hole":     result.holeWays.append(geom)
                default: break
                }
            }
            if tags["natural"] == "water" || tags["natural"] == "wetland" {
                result.water.append(geom)
            }
        }
        return result
    }

    private func centroidOfAll(_ ways: [OSMWayGeometry]) -> Coordinate? {
        let all = ways.compactMap { $0.centroid }
        guard !all.isEmpty else { return nil }
        let lat = all.map(\.latitude).reduce(0, +) / Double(all.count)
        let lon = all.map(\.longitude).reduce(0, +) / Double(all.count)
        return Coordinate(latitude: lat, longitude: lon)
    }

    // MARK: - Cache

    private func cacheURL(for courseId: String) -> URL {
        let safeId = courseId.replacingOccurrences(of: "/", with: "_")
        let dir    = AppStorageManager.globalCourseCacheDir()
        AppStorageManager.ensureDirectory(dir)
        return dir.appendingPathComponent("osm-\(safeId).json")
    }

    private func save(_ course: GolfCourse) {
        try? AppStorageManager.save(course, to: cacheURL(for: course.id))
    }

    /// Public passthrough so the multi-source aggregator can persist a merged course
    /// (OSM geometry + GolfCourseAPI scorecard) into the same cache `loadCached` reads.
    func cacheMergedCourse(_ course: GolfCourse) {
        var c = course
        c.cachedAt = Date()
        save(c)
    }

    /// Load cached enrichment.
    /// - Parameter allowExpired: when `true`, ignores `cacheTTL` for stale-cache rescue.
    func loadCached(courseId: String, allowExpired: Bool = false) -> GolfCourse? {
        let url = cacheURL(for: courseId)
        guard let course = try? AppStorageManager.load(GolfCourse.self, from: url) else { return nil }
        if !allowExpired,
           let at = course.cachedAt,
           Date().timeIntervalSince(at) > cacheTTL { return nil }
        return course
    }

    func clearCache(courseId: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: courseId))
    }
}
