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

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

enum CourseSource: String, Codable {
    case mock, golfCourseAPI, bundled, manual
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
    var id: String
    var courseId: String
    var number: Int
    var par: Int
    var handicap: Int?
    var teeYardsByTeeBox: [String: Int]     = [:]
    var greenFrontCoordinate: Coordinate?
    var greenCenterCoordinate: Coordinate?
    var greenBackCoordinate: Coordinate?
    var teeCoordinateByTeeBox: [String: Coordinate]? = nil
    var hazards: [Hazard]                   = []
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

struct Coordinate: Codable {
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
