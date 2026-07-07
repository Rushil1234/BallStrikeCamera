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

    // MARK: - Geometry DTO (sparse — only fields present in storage files)

    /// Thin Decodable that only declares the fields our geometry files actually contain.
    /// Avoids decode failures from GolfCourse/GolfHole properties that have defaults
    /// in Swift but are absent from the JSON (Swift synthesis calls `decode`, not
    /// `decodeIfPresent`, for properties with default values).
    private struct CatalogGeometry: Decodable {
        let id: String
        let name: String?
        let holes: [CatalogHole]
        let teeBoxes: [CatalogTeeBox]?

        struct CatalogTeeBox: Decodable {
            let id: String
            let name: String?
            let color: String?
            let totalYards: Int?
            let rating: Double?
            let slope: Int?
        }

        struct CatalogHole: Decodable {
            let number: Int
            let par: Int
            let handicap: Int?
            let teeCoordinate: Coordinate?
            let greenCenterCoordinate: Coordinate?
            let greenFrontCoordinate: Coordinate?
            let greenBackCoordinate: Coordinate?
            let pathCoordinates: [Coordinate]?
            let teeYardsByTeeBox: [String: Int]?
            let teeCoordinateByTeeBox: [String: Coordinate]?
            let hazards: [Hazard]?
            let greenPolygon: PolygonRing?
            let fairwayPolygon: PolygonRing?
            let bunkerPolygons: [PolygonRing]?
            let waterPolygons: [PolygonRing]?
        }

        func toGolfCourse(catalogId: String) -> GolfCourse {
            let golfHoles: [GolfHole] = holes.map { h in
                var hole = GolfHole(number: h.number, par: h.par)
                hole.handicap                = h.handicap
                hole.teeCoordinate           = h.teeCoordinate
                hole.greenCenterCoordinate   = h.greenCenterCoordinate
                hole.greenFrontCoordinate    = h.greenFrontCoordinate
                hole.greenBackCoordinate     = h.greenBackCoordinate
                hole.pathCoordinates         = h.pathCoordinates
                hole.teeYardsByTeeBox        = h.teeYardsByTeeBox ?? [:]
                hole.teeCoordinateByTeeBox   = h.teeCoordinateByTeeBox
                hole.hazards                 = h.hazards ?? []
                hole.greenPolygon            = h.greenPolygon
                hole.fairwayPolygon          = h.fairwayPolygon
                hole.bunkerPolygons          = h.bunkerPolygons ?? []
                hole.waterPolygons           = h.waterPolygons ?? []
                return hole
            }

            // Tee boxes: prefer the feed's declared tee_boxes (they carry real names/colors like
            // "Blue", "Black"; the per-hole yardage keys may just be opaque ids). Recompute the
            // total from the per-hole yardages keyed by the tee id so it stays consistent.
            // TRUST CHECK: some blobs carry a declared list from a different course entirely
            // (Berkshire Valley declared Purple/Orange/Teal while its per-hole data held the real
            // Black/Blue/White/Yellow/Red). Declared ids that never key into the per-hole yardage
            // maps can't drive hole yardages anyway — synthesize from the per-hole keys instead.
            var totalsByTee: [String: Int] = [:]
            for h in holes {
                for (name, yards) in (h.teeYardsByTeeBox ?? [:]) where yards > 0 {
                    totalsByTee[name, default: 0] += yards
                }
            }
            let teeBoxes: [TeeBox]
            if let declared = self.teeBoxes, !declared.isEmpty,
               totalsByTee.isEmpty || declared.contains(where: { totalsByTee[$0.id] != nil }) {
                teeBoxes = declared.map { tb in
                    let summed = holes.reduce(0) { $0 + max(0, $1.teeYardsByTeeBox?[tb.id] ?? 0) }
                    return TeeBox(id: tb.id,
                                  name: tb.name ?? tb.id,
                                  color: tb.color ?? (tb.name ?? "white").lowercased(),
                                  totalYards: summed > 0 ? summed : (tb.totalYards ?? 0),
                                  rating: tb.rating,
                                  slope: tb.slope)
                }
            } else {
                // Two per-hole keys with identical 18-hole totals are the same physical markers
                // under two names (Berkshire lists Yellow and Gold both at 5234) — keep one.
                var seenTotals = Set<Int>()
                teeBoxes = totalsByTee
                    .sorted { $0.value > $1.value }   // longest tee first
                    .filter { seenTotals.insert($0.value).inserted }
                    .map { name, total in
                        TeeBox(id: name, name: name, color: name.lowercased(), totalYards: total)
                    }
            }

            var course = GolfCourse(id: catalogId, name: self.name ?? "", holes: golfHoles,
                                    teeBoxes: TeeBox.collapsingSameColorDuplicates(teeBoxes))
            course.source = .merged
            return course
        }
    }

    private static func loadGeometry(courseId: String, config: SupabaseConfig) async -> GolfCourse? {
        let url = config.storageBaseURL
            .appendingPathComponent("object/public")
            .appendingPathComponent(bucket)
            .appendingPathComponent("\(courseId).json.gz")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let json = data.isGzip ? (data.gunzipped() ?? data) : data
            let dto  = try decoder.decode(CatalogGeometry.self, from: json)
            var course = dto.toGolfCourse(catalogId: courseId)
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

    /// Inflate standard gzip data and raw-inflate the DEFLATE stream with COMPRESSION_ZLIB.
    /// The gzip header is variable-length — the optional FEXTRA/FNAME/FCOMMENT/FHCRC fields
    /// (some pipelines embed the original filename) must be skipped per the FLG byte, otherwise
    /// the leftover header bytes corrupt the stream and inflation fails. Returns nil on failure.
    func gunzipped() -> Data? {
        guard count > 18,                                       // header(≥10) + trailer(8)
              self[startIndex] == 0x1f, self[startIndex + 1] == 0x8b else { return nil }
        let flg = self[startIndex + 3]
        var headerLen = 10
        if flg & 0x04 != 0 {                                    // FEXTRA: 2-byte length + payload
            guard startIndex + headerLen + 1 < endIndex else { return nil }
            let xlen = Int(self[startIndex + headerLen]) | (Int(self[startIndex + headerLen + 1]) << 8)
            headerLen += 2 + xlen
        }
        if flg & 0x08 != 0 {                                    // FNAME: null-terminated
            while startIndex + headerLen < endIndex && self[startIndex + headerLen] != 0 { headerLen += 1 }
            headerLen += 1
        }
        if flg & 0x10 != 0 {                                    // FCOMMENT: null-terminated
            while startIndex + headerLen < endIndex && self[startIndex + headerLen] != 0 { headerLen += 1 }
            headerLen += 1
        }
        if flg & 0x02 != 0 { headerLen += 2 }                   // FHCRC: 2-byte header CRC
        guard startIndex + headerLen < endIndex else { return nil }
        let deflate = subdata(in: (startIndex + headerLen)..<endIndex) // skip the full gzip header

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
