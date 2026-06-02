import Foundation
import CoreLocation

// MARK: - Golf Course

struct GolfCourse: Codable, Identifiable {
    var id: String
    var name: String
    var city: String
    var state: String
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

// MARK: - Tee Box

struct TeeBox: Codable, Identifiable {
    var id: String
    var name: String
    var color: String
    var totalYards: Int
    var rating: Double?
    var slope: Int?
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
