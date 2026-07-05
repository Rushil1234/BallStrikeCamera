import Foundation
import CoreLocation

// MARK: - Golf Course

struct GolfCourse: Codable, Identifiable {
    var id: String
    var name: String
    var city: String           = ""
    var state: String          = ""
    var country: String        = "US"
    var latitude: Double?
    var longitude: Double?
    var holes: [GolfHole]      = []
    var teeBoxes: [TeeBox]     = []
    var source: CourseSource   = .mock
    var cachedAt: Date?
    var coursePolygon: PolygonRing?  = nil    // outer course boundary if available
    var geometryMetadata: CourseGeometryMetadata? = nil

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var hasRealGeometry: Bool {
        holes.contains(where: {
            $0.greenPolygon != nil ||
            ($0.teeCoordinate != nil && $0.greenCenterCoordinate != nil)
        })
    }

    /// True when geometry is good enough to render as course truth. This prevents
    /// automated drafts from looking like verified GPS data in the round UI.
    var hasTrustedGeometry: Bool {
        guard hasRealGeometry else { return false }
        return geometryMetadata?.isTrusted ?? true
    }

    /// True only when every playable hole has a tee coordinate. Requires geometry to be loaded;
    /// returns false for search stubs (holes: []).
    var hasFullTeeCoords: Bool { hasFullHoleData }

    /// Gold "GPS Map" threshold: every playable hole has a tee, a green, and (for par 4/5) a fairway waypoint.
    var hasFullHoleData: Bool {
        let playable = holes.filter { $0.number > 0 }
        guard !playable.isEmpty else { return false }
        return playable.allSatisfy {
            guard $0.teeCoordinate != nil, $0.greenCenterCoordinate != nil else { return false }
            if $0.par == 3 { return true }
            return !($0.pathCoordinates ?? []).isEmpty
        }
    }

    /// Sage "Partial Map" threshold: at least some holes have a green center but full data is incomplete.
    var hasPartialHoleData: Bool {
        guard !hasFullHoleData else { return false }
        let playable = holes.filter { $0.number > 0 }
        guard !playable.isEmpty else { return false }
        return playable.contains { $0.greenCenterCoordinate != nil }
    }

    // MARK: - Tee yardage

    /// Per-hole yardage for `tee`, matched by tee-box id then by name/color
    /// (mirrors `scorecardYardage` resolution in CourseModeGPSHoleView).
    private func holeYardage(_ hole: GolfHole, for tee: TeeBox) -> Int? {
        if let y = hole.teeYardsByTeeBox[tee.id], y > 0 { return y }
        let key = hole.teeYardsByTeeBox.keys.first {
            $0.caseInsensitiveCompare(tee.name)  == .orderedSame ||
            $0.caseInsensitiveCompare(tee.color) == .orderedSame
        }
        if let key, let y = hole.teeYardsByTeeBox[key], y > 0 { return y }
        return nil
    }

    /// Trusted total yardage for a tee box, or `nil` when the per-hole data can't be trusted.
    ///
    /// Two corruption patterns are common in the feed and both yield nonsensical tee yardages:
    ///   • Duplicated holes (e.g. 18 holes repeated 4×) inflate the stored total to ~24,000 yds.
    ///   • Partial coverage (e.g. only holes 1–9 carry the White/Yellow/Red tees) makes those
    ///     totals ~half of the real value next to a full-18 "Blue" tee.
    ///
    /// We rebuild the total from one per-hole yardage per *distinct hole number* (de-duplicating),
    /// and only trust the result when every distinct hole has a yardage for this tee. A tee that
    /// is missing any hole returns `nil` so the UI can show "GPS estimate" rather than a misleading
    /// half-length number.
    /// De-duplicated per-distinct-hole total, but only when this tee carries a yardage for every
    /// hole. Does NOT apply the orphan/implausibility check — that is layered on in `trustedYards`.
    private func fullyCoveredYards(for tee: TeeBox) -> Int? {
        let playable = holes.filter { $0.number > 0 }
        guard !playable.isEmpty else { return tee.totalYards > 0 ? tee.totalYards : nil }
        var yardageByHole: [Int: Int] = [:]
        for hole in playable where yardageByHole[hole.number] == nil {
            if let y = holeYardage(hole, for: tee) { yardageByHole[hole.number] = y }
        }
        let distinctHoles = Set(playable.map { $0.number }).count
        guard yardageByHole.count == distinctHoles else { return nil }
        let sum = yardageByHole.values.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    /// Longest fully-covered tee on the course — the reference for spotting orphan short tees.
    private var longestCoveredYards: Int {
        teeBoxes.compactMap { fullyCoveredYards(for: $0) }.max() ?? 0
    }

    func trustedYards(for tee: TeeBox) -> Int? {
        guard let yards = fullyCoveredYards(for: tee) else { return nil }
        let distinctHoles = max(1, Set(holes.filter { $0.number > 0 }.map { $0.number }).count)
        let perHole = Double(yards) / Double(distinctHoles)
        let longest = longestCoveredYards
        // Drop an "orphan" tee that is both far shorter than the course's real tees (<50% of the
        // longest fully-covered tee) and implausibly short per hole (<170 yd) — these are corrupted
        // or mislabeled sets, not a graduated forward tee. Consistently short courses (all tees
        // near each other, e.g. par-3 layouts) are kept because no tee is <50% of the longest.
        if longest > 0, Double(yards) < 0.5 * Double(longest), perHole < 170 { return nil }
        return yards
    }

    /// Display yardage for a tee box: the trusted total, or 0 when the data is incomplete /
    /// duplicated / an implausible orphan. Callers treat 0 as "show GPS estimate, not a number".
    func displayYards(for tee: TeeBox) -> Int { trustedYards(for: trustedTee(near: tee)) ?? 0 }

    /// Nearest tee at or below `tee`'s length that has trusted (real, full-course) yardage data.
    /// GPS-estimate tees have no reliable per-hole numbers of their own, so total and per-hole
    /// yardage should both read from the closest shorter tee that does, rather than guessing.
    /// Returns `tee` unchanged if it's already trusted, or if no shorter tee is trusted either.
    func trustedTee(near tee: TeeBox) -> TeeBox {
        if trustedYards(for: tee) != nil { return tee }
        let byLength = teeBoxes.sorted { $0.totalYards > $1.totalYards }
        guard let idx = byLength.firstIndex(where: { $0.id == tee.id }) else { return tee }
        return byLength[idx...].first { trustedYards(for: $0) != nil } ?? tee
    }

    /// Per-hole yardage for `tee`, falling back to `trustedTee(near:)` when `tee` itself is a
    /// GPS estimate, so a hole's number always comes from the same tee used for the total.
    func resolvedHoleYardage(_ hole: GolfHole, for tee: TeeBox) -> Int? {
        if let y = holeYardage(hole, for: tee) { return y }
        let fallback = trustedTee(near: tee)
        return fallback.id == tee.id ? nil : holeYardage(hole, for: fallback)
    }
}

enum CourseSource: String, Codable {
    case mock, golfCourseAPI, bundled, manual, mapKit, openStreetMap, merged, autoBackfill
}

enum CourseGeometryState: String, Codable {
    case unknown
    case autoDraft = "auto_draft"
    case accepted
    case rejected
}

struct CourseGeometryMetadata: Codable, Hashable {
    var state: CourseGeometryState = .unknown
    var confidence: Double? = nil
    var source: String = "unknown"
    var schemaVersion: Int = 1
    var generatedBy: String? = nil
    var validationErrors: [String] = []
    var imagerySource: String? = nil
    var updatedAt: Date? = nil

    var isTrusted: Bool {
        switch state {
        case .accepted:
            return validationErrors.isEmpty
        case .autoDraft, .rejected, .unknown:
            return false
        }
    }
}

/// Drives which tee rating/slope a round uses for handicap calculation (see
/// `TeeBox.resolvedRating(for:)`/`resolvedSlope(for:)`) — not a gameplay setting.
enum Gender: String, Codable, CaseIterable {
    case male   = "Male"
    case female = "Female"
}

// MARK: - Tee Box

struct TeeBox: Codable, Identifiable {
    var id: String
    var name: String
    var color: String
    var totalYards: Int
    var rating: Double?
    var slope: Int?
    /// Women's course rating/slope for this SAME physical tee, when the data source reports one
    /// distinct from `rating`/`slope` (e.g. GolfCourseAPI's male/female arrays describing the same
    /// markers). Not a separate playable tee — `resolvedRating(for:)`/`resolvedSlope(for:)` pick
    /// whichever pair to use for handicap purposes based on the golfer's profile.
    var womensRating: Double? = nil
    var womensSlope: Int? = nil

    /// The rating to use for handicap calculation for a golfer of the given gender — falls back to
    /// the primary rating if no women's-specific figure was captured for this tee.
    func resolvedRating(for gender: Gender) -> Double? {
        gender == .female ? (womensRating ?? rating) : rating
    }

    /// The slope to use for handicap calculation for a golfer of the given gender — falls back to
    /// the primary slope if no women's-specific figure was captured for this tee.
    func resolvedSlope(for gender: Gender) -> Int? {
        gender == .female ? (womensSlope ?? slope) : slope
    }

    /// Merges duplicate entries that share a name (male + female raw tee lists can produce the
    /// same name twice) — keeps the longer-yardage entry as the surviving tee, but preserves
    /// either side's women's rating/slope rather than discarding it when the shorter one is dropped.
    static func collapsingSameNameDuplicates(_ tees: [TeeBox]) -> [TeeBox] {
        var seen: [String: TeeBox] = [:]
        for tee in tees {
            let key = tee.name.lowercased()
            guard let existing = seen[key] else { seen[key] = tee; continue }
            var winner = tee.totalYards >= existing.totalYards ? tee : existing
            let loser  = tee.totalYards >= existing.totalYards ? existing : tee
            if winner.womensRating == nil { winner.womensRating = loser.womensRating }
            if winner.womensSlope  == nil { winner.womensSlope  = loser.womensSlope }
            seen[key] = winner
        }
        return seen.values.sorted { $0.totalYards > $1.totalYards }
    }

    /// Collapses male/female raw-tee pairs that share the same COLOR (e.g. "White" + "White (W)",
    /// or any name variant that infers to the same color) into ONE visible TeeBox — yardage is
    /// NOT required to match, since a men's/women's marker of the "same" tee can legitimately play
    /// a different length. The male entry's identity (name/color/id/yardage) wins; the female
    /// entry's rating/slope is attached as `womensRating`/`womensSlope` rather than shown as a
    /// separate selectable tee. A female tee whose color has no matching male entry (a genuinely
    /// distinct forward-tee-only set) is kept as its own visible tee.
    static func mergingGenderedDuplicates(_ entries: [(tee: TeeBox, isFemale: Bool)]) -> [TeeBox] {
        let maleTees = entries.filter { !$0.isFemale }.map(\.tee)
        var femaleTees = entries.filter { $0.isFemale }.map(\.tee)

        var merged: [TeeBox] = []
        for male in maleTees {
            var tee = male
            if let idx = femaleTees.firstIndex(where: { $0.color.caseInsensitiveCompare(male.color) == .orderedSame }) {
                let female = femaleTees.remove(at: idx)
                tee.womensRating = female.rating
                tee.womensSlope  = female.slope
            }
            merged.append(tee)
        }
        // Leftover female-only tees have no matching men's color — real, distinct, visible tees.
        merged.append(contentsOf: femaleTees)

        return collapsingSameNameDuplicates(merged)
    }

    /// Collapses tee boxes that share the same (alias-normalized) color into one visible tee.
    /// Unlike `mergingGenderedDuplicates`, this doesn't know which entries are male/female up
    /// front — it's for cached catalog blobs (Supabase `course-geometry` Storage) built by a
    /// backend pipeline that could still emit a men's/women's pair as two separate tees (some
    /// literally suffixed "<name> (W)") instead of merging them server-side. Masks already-cached
    /// duplicates on the client so the fix shows up immediately, without waiting on every course's
    /// blob to be regenerated. The longer-yardage entry wins as the visible tee (women's tees are
    /// essentially always the shorter of a same-color pair); the other's rating/slope folds into
    /// womensRating/womensSlope, and any leftover gender-suffix text is stripped from its name.
    static func collapsingSameColorDuplicates(_ tees: [TeeBox]) -> [TeeBox] {
        var groups: [String: [TeeBox]] = [:]
        var order: [String] = []
        for tee in tees {
            let key = canonicalColor(tee.color)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(tee)
        }
        var result: [TeeBox] = []
        for key in order {
            let group = groups[key]!.sorted { $0.totalYards > $1.totalYards }
            var primary = group[0]
            primary.name = strippingGenderSuffix(primary.name)
            for extra in group.dropFirst() {
                if primary.womensRating == nil { primary.womensRating = extra.rating }
                if primary.womensSlope  == nil { primary.womensSlope  = extra.slope }
            }
            result.append(primary)
        }
        return result.sorted { $0.totalYards > $1.totalYards }
    }

    private static func canonicalColor(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("championship") || lower.contains("black") { return "black" }
        if lower.contains("blue") { return "blue" }
        if lower.contains("white") { return "white" }
        if lower.contains("green") { return "green" }
        if lower.contains("gold") || lower.contains("yellow") { return "gold" }
        if lower.contains("red") || lower.contains("forward") { return "red" }
        if lower.contains("silver") || lower.contains("fairway") { return "silver" }
        return lower
    }

    private static func strippingGenderSuffix(_ name: String) -> String {
        var s = name
        for pattern in ["(W)", "(w)", "(F)", "(f)"] {
            s = s.replacingOccurrences(of: " \(pattern)", with: "")
            s = s.replacingOccurrences(of: pattern, with: "")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Golf Hole

struct GolfHole: Codable, Identifiable {
    var id: String       = ""
    var courseId: String = ""
    var number: Int
    var par: Int
    var handicap: Int?
    var teeYardsByTeeBox: [String: Int]     = [:]
    var greenFrontCoordinate: Coordinate?
    var greenCenterCoordinate: Coordinate?
    var greenBackCoordinate: Coordinate?
    var teeCoordinateByTeeBox: [String: Coordinate]? = nil
    /// Preferred tee-to-green route/centerline for map rendering. Comes from OSM
    /// `golf=hole` when available, otherwise a best-effort tee/fairway/green path.
    var pathCoordinates: [Coordinate]? = nil
    var hazards: [Hazard]                   = []

    // MARK: - Geometry (OpenStreetMap derived)

    /// Primary tee coordinate (centroid of the matched OSM tee polygon)
    var teeCoordinate: Coordinate?          = nil
    /// Green polygon (outer ring)
    var greenPolygon: PolygonRing?          = nil
    /// Fairway polygon (outer ring)
    var fairwayPolygon: PolygonRing?        = nil
    /// All bunker polygons matched to this hole
    var bunkerPolygons: [PolygonRing]       = []
    /// All water polygons matched to this hole
    var waterPolygons: [PolygonRing]        = []

    /// Tee-to-green straight-line yardage when both coordinates exist.
    var measuredYardage: Int? {
        guard let tee = teeCoordinate, let g = greenCenterCoordinate else { return nil }
        let a = CLLocation(latitude: tee.latitude, longitude: tee.longitude)
        let b = CLLocation(latitude: g.latitude,   longitude: g.longitude)
        return Int((a.distance(from: b) * 1.09361).rounded())
    }
}

// MARK: - Hazard

struct Hazard: Codable, Identifiable {
    var id: String
    var type: HazardType
    var name: String?
    var coordinate: Coordinate?
    var frontCoordinate: Coordinate?
    var carryCoordinate: Coordinate?
}

enum HazardType: String, Codable {
    case bunker, water, trees, other
}

// MARK: - Coordinate (Codable wrapper for CLLocationCoordinate2D)

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coord: CLLocationCoordinate2D) {
        latitude = coord.latitude; longitude = coord.longitude
    }
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude; self.longitude = longitude
    }
}

// MARK: - GPS Yardages

struct GreenDistances {
    var front: Int?
    var center: Int?
    var back: Int?

    var isAvailable: Bool { front != nil || center != nil || back != nil }
}

// MARK: - Polygon Ring (Codable wrapper for a ring of coordinates)

struct PolygonRing: Codable, Hashable {
    var coordinates: [Coordinate]

    init(coordinates: [Coordinate]) { self.coordinates = coordinates }
    init(_ coords: [CLLocationCoordinate2D]) {
        self.coordinates = coords.map { Coordinate($0) }
    }

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { $0.clCoordinate }
    }

    /// Geographic centroid (arithmetic mean of vertices). Adequate for small polygons.
    var centroid: Coordinate? {
        guard !coordinates.isEmpty else { return nil }
        let lat = coordinates.map { $0.latitude  }.reduce(0, +) / Double(coordinates.count)
        let lng = coordinates.map { $0.longitude }.reduce(0, +) / Double(coordinates.count)
        return Coordinate(latitude: lat, longitude: lng)
    }

    /// Axis-aligned bounding box in (minLat, maxLat, minLng, maxLng).
    var bounds: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for c in coordinates.dropFirst() {
            minLat = Swift.min(minLat, c.latitude);  maxLat = Swift.max(maxLat, c.latitude)
            minLng = Swift.min(minLng, c.longitude); maxLng = Swift.max(maxLng, c.longitude)
        }
        return (minLat, maxLat, minLng, maxLng)
    }
}
