import Foundation
import CoreLocation
import Compression

// MARK: - Course Catalog (Supabase)
//
// The app's course database lives in Supabase:
//   • `courses` table  — 40k+ course catalog, searched via the `search_courses` RPC
//     (trigram name match + proximity ranking).
//   • Storage bucket `course-geometry/<course_uuid>.json.gz` — the full GolfCourse geometry,
//     gzipped, fetched on demand when a course is opened.
//
// Flow: search_courses(name, lat, lon, only_geometry) → best row's `id` → fetch + gunzip its
// geometry file → decode GolfCourse. No paid data; OSM-derived, attribution required.

enum CourseCatalog {
    private static let bucket = "course-geometry"

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // Lenient ISO-8601: handles timestamps WITH or WITHOUT fractional seconds (the feed emits
        // millis, which the stock .iso8601 strategy rejects — that silently broke every decode).
        let withFrac = ISO8601DateFormatter(); withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let noFrac = ISO8601DateFormatter(); noFrac.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            return withFrac.date(from: s) ?? noFrac.date(from: s) ?? Date()
        }
        return d
    }()

    /// A lightweight catalog match returned by the search RPC.
    struct Match: Decodable {
        let id: String
        let name: String
        let city: String?
        let state: String?
        let latitude: Double?
        let longitude: Double?
        let dataTier: String?

        var hasGeometry: Bool { dataTier == "gps_ready" }
    }

    /// Search the full 42k-course catalog for the search screen. Returns ALL matching courses
    /// (with or without geometry) as lightweight stubs — so users always see a course exists,
    /// even when we don't have its map yet.
    static func search(query: String, near: CLLocationCoordinate2D?, limit: Int = 25) async -> [GolfCourse] {
        guard let config = SupabaseConfig.load() else { return [] }
        let matches = await runSearch(q: query, coordinate: near, onlyGeometry: false, limit: limit, config: config)
        return matches.map { m in
            GolfCourse(
                id: m.id, name: m.name,
                city: m.city ?? "", state: m.state ?? "", country: "US",
                latitude: m.latitude, longitude: m.longitude,
                holes: [],
                teeBoxes: [TeeBox(id: "\(m.id)-gps", name: "Course GPS", color: "Gray", totalYards: 0)],
                source: m.hasGeometry ? .merged : .mapKit
            )
        }
    }

    /// Load a course's geometry: by catalog id directly when we have it, else by name+proximity.
    /// Returns nil when there's no geometry-bearing match (caller falls back to live OSM).
    static func geometry(for course: GolfCourse) async -> GolfCourse? {
        guard let config = SupabaseConfig.load() else { return nil }
        if isUUID(course.id), let g = await loadGeometry(courseId: course.id, config: config) { return g }
        guard let match = await runSearch(q: course.name, coordinate: course.coordinate, onlyGeometry: true, limit: 1, config: config).first
        else { return nil }
        return await loadGeometry(courseId: match.id, config: config)
    }

    private static func isUUID(_ s: String) -> Bool {
        s.count == 36 && s.filter { $0 == "-" }.count == 4
    }

    // MARK: - Search RPC

    private static func runSearch(q: String,
                                  coordinate: CLLocationCoordinate2D?,
                                  onlyGeometry: Bool,
                                  limit: Int,
                                  config: SupabaseConfig) async -> [Match] {
        let url = config.rpcBaseURL.appendingPathComponent("search_courses")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12
        var body: [String: Any] = ["q": q, "only_geometry": onlyGeometry, "lim": limit]
        if let c = coordinate { body["lat"] = c.latitude; body["lon"] = c.longitude }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return (try? decoder.decode([Match].self, from: data)) ?? []
        } catch {
            #if DEBUG
            print("[CourseCatalog] search failed: \(error.localizedDescription)")
            #endif
            return []
        }
    }

    // MARK: - Geometry fetch from Storage

    private static func loadGeometry(courseId: String, config: SupabaseConfig) async -> GolfCourse? {
        let url = config.storageBaseURL
            .appendingPathComponent("object/public")
            .appendingPathComponent(bucket)
            .appendingPathComponent("\(courseId).json.gz")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let json = data.isGzip ? (data.gunzipped() ?? data) : data
            var course = try decoder.decode(GolfCourse.self, from: json)
            course.cachedAt = Date()
            return course.hasRealGeometry ? course : nil
        } catch {
            print("[CourseCatalog] geometry fetch failed (\(courseId)): \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Gzip inflate (Apple Compression framework)

extension Data {
    var isGzip: Bool { count >= 2 && self[startIndex] == 0x1f && self[startIndex + 1] == 0x8b }

    /// Inflate standard gzip data. Strips the 10-byte gzip header and raw-inflates the DEFLATE
    /// stream with COMPRESSION_ZLIB. Returns nil on failure.
    func gunzipped() -> Data? {
        guard count > 18 else { return nil }                    // header(10) + trailer(8)
        let deflate = subdata(in: (startIndex + 10)..<endIndex) // skip gzip header

        let bufferSize = 1 << 16
        var output = Data()
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        guard compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPtr) }

        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        return deflate.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return nil }
            streamPtr.pointee.src_ptr = srcBase
            streamPtr.pointee.src_size = deflate.count
            streamPtr.pointee.dst_ptr = dst
            streamPtr.pointee.dst_size = bufferSize
            while true {
                let status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - streamPtr.pointee.dst_size
                    if produced > 0 { output.append(dst, count: produced) }
                    streamPtr.pointee.dst_ptr = dst
                    streamPtr.pointee.dst_size = bufferSize
                    if status == COMPRESSION_STATUS_END { return output }
                default:
                    return nil
                }
            }
        }
    }
}
