import Foundation
import CoreLocation

// MARK: - TrackedShot
//
// GPS-derived on-course shot. Parallel to (and intentionally separate from) `SavedShot`,
// which models a launch-monitor capture. A `TrackedShot` is anchored in a round + hole,
// with start/end coordinates, club, lie, and result.
//
// `linkedSavedShotId` is an optional bridge to a launch-monitor capture taken during
// the same swing. This lets future flows merge launch data with on-course outcomes.

struct TrackedShot: Codable, Identifiable, Hashable {
    var id: UUID                       = UUID()
    var roundId: UUID
    var holeNumber: Int
    var shotIndex: Int                 // 1-based ordering within the hole
    var userId: UUID

    var startCoordinate: Coordinate
    var endCoordinate:   Coordinate

    var club: ShotClub?
    var lie:  ShotLie                  = .unknown
    var result: ShotResult             = .inPlay

    var timestamp: Date                = Date()

    // Derived; persisted for convenience (avoid recomputing on every view).
    var distanceYards: Double          = 0
    var carryYards:    Double?         = nil          // only if user enters

    // Bridge to a launch-monitor capture, if any.
    var linkedSavedShotId: UUID?       = nil

    // Strokes-gained scaffold — populated by future engine.
    var strokesGained: Double?         = nil
    var expectedStrokes: Double?       = nil

    // MARK: - Helpers

    /// Recomputes `distanceYards` from start/end. Call on construction or after edit.
    mutating func recomputeDistance() {
        let a = CLLocation(latitude: startCoordinate.latitude, longitude: startCoordinate.longitude)
        let b = CLLocation(latitude: endCoordinate.latitude,   longitude: endCoordinate.longitude)
        distanceYards = a.distance(from: b) * 1.09361
    }
}

// MARK: - ShotClub

/// Lightweight club reference. Resolved against `UserClub` when available; falls back to
/// the embedded name + category so analytics still work offline / for guest users.
struct ShotClub: Codable, Hashable {
    var clubId: UUID?
    var name:   String
    var category: ClubCategory

    enum ClubCategory: String, Codable, CaseIterable {
        case driver, wood, hybrid, iron, wedge, putter

        var displayName: String {
            switch self {
            case .driver: return "Driver"
            case .wood:   return "Wood"
            case .hybrid: return "Hybrid"
            case .iron:   return "Iron"
            case .wedge:  return "Wedge"
            case .putter: return "Putter"
            }
        }
    }

}

// ShotClub(userClub:) bridge lives in AppModels.swift next to UserClub — this file
// must stay dependency-free for the swiftc logic-test harness (tools/ios-logic-tests.sh).

// MARK: - Lie

/// Where the ball is lying before the shot. Mapped to OSM polygon classifications
/// when shots are placed; user can override.
enum ShotLie: String, Codable, CaseIterable {
    case tee, fairway, rough, sand, water, recovery, fringe, green, unknown

    var displayName: String {
        switch self {
        case .tee:      return "Tee"
        case .fairway:  return "Fairway"
        case .rough:    return "Rough"
        case .sand:     return "Bunker"
        case .water:    return "Water"
        case .recovery: return "Recovery"
        case .fringe:   return "Fringe"
        case .green:    return "Green"
        case .unknown:  return "Unknown"
        }
    }

    /// Used by the strokes-gained scaffold to pick a baseline table.
    var sgCategory: String {
        switch self {
        case .tee, .fairway:      return "fairway"
        case .rough, .recovery:   return "rough"
        case .sand:               return "sand"
        case .green, .fringe:     return "green"
        case .water:              return "water"   // penalty handling done elsewhere
        case .unknown:            return "fairway" // optimistic default
        }
    }
}

// MARK: - Result

/// Outcome the user (or the engine) attributes to the shot. Used for analytics
/// (filter out penalties from carry averages, etc.).
enum ShotResult: String, Codable, CaseIterable {
    case inPlay, fairwayHit, missedLeft, missedRight, short, long
    case greenInReg, holed, penalty, mishit

    var isMeaningfulForCarry: Bool {
        switch self {
        case .penalty, .mishit: return false
        default: return true
        }
    }

    var displayName: String {
        switch self {
        case .inPlay:       return "In Play"
        case .fairwayHit:   return "Fairway"
        case .missedLeft:   return "Miss Left"
        case .missedRight:  return "Miss Right"
        case .short:        return "Short"
        case .long:         return "Long"
        case .greenInReg:   return "GIR"
        case .holed:        return "Holed"
        case .penalty:      return "Penalty"
        case .mishit:       return "Mishit"
        }
    }
}
