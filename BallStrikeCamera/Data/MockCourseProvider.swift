import Foundation
import CoreLocation

// MARK: - Mock Course Provider (always available, no API key required)

final class MockCourseProvider: CourseProvider {

    func searchCourses(query: String, near location: CLLocationCoordinate2D?) async throws -> [GolfCourse] {
        let all = Self.allMockCourses
        if query.isEmpty { return all }
        let q = query.lowercased()
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.city.lowercased().contains(q) ||
            $0.state.lowercased().contains(q)
        }
    }

    func loadCourseDetails(courseId: String) async throws -> GolfCourse {
        guard let course = Self.allMockCourses.first(where: { $0.id == courseId }) else {
            throw BackendError.loadFailed("Course \(courseId) not found in mock data")
        }
        return course
    }

    // MARK: - Mock Data

    static let allMockCourses: [GolfCourse] = [
        pennStateBlue(),
        eagleRidgeGC(),
        par3Practice(),
    ]

    // MARK: Penn State Blue Course

    static func pennStateBlue() -> GolfCourse {
        let tees: [TeeBox] = [
            TeeBox(id: "psb-blue",  name: "Blue",  color: "Blue",  totalYards: 6508, rating: 71.8, slope: 125),
            TeeBox(id: "psb-white", name: "White", color: "White", totalYards: 6104, rating: 69.5, slope: 120),
            TeeBox(id: "psb-red",   name: "Red",   color: "Red",   totalYards: 5284, rating: 70.2, slope: 118),
        ]
        let holeData: [(Int, Int, Int, Int, Int, Int)] = [
            // (number, par, hcp, blue, white, red)
            (1,  4, 11, 382, 356, 308),
            (2,  4,  5, 401, 378, 327),
            (3,  3, 17, 168, 152, 132),
            (4,  5,  1, 523, 495, 451),
            (5,  4,  9, 388, 362, 315),
            (6,  3, 15, 142, 128, 118),
            (7,  5,  3, 541, 510, 468),
            (8,  4, 13, 375, 348, 299),
            (9,  4,  7, 418, 392, 342),
            (10, 4,  8, 403, 375, 326),
            (11, 4,  4, 391, 366, 318),
            (12, 3, 16, 155, 138, 122),
            (13, 5,  2, 538, 508, 462),
            (14, 4, 12, 370, 345, 296),
            (15, 3, 18, 148, 134, 116),
            (16, 5,  6, 517, 488, 441),
            (17, 4, 10, 385, 356, 308),
            (18, 4, 14, 363, 338, 290),
        ]
        let holes = holeData.map { num, par, hcp, blue, white, red -> GolfHole in
            GolfHole(
                id: "psb-hole-\(num)",
                courseId: "penn-state-blue",
                number: num,
                par: par,
                handicap: hcp,
                teeYardsByTeeBox: ["psb-blue": blue, "psb-white": white, "psb-red": red]
            )
        }
        return GolfCourse(
            id: "penn-state-blue",
            name: "Penn State Blue Course",
            city: "University Park",
            state: "PA",
            latitude: 40.7934,
            longitude: -77.8600,
            holes: holes,
            teeBoxes: tees,
            source: .mock
        )
    }

    // MARK: Eagle Ridge GC

    static func eagleRidgeGC() -> GolfCourse {
        let tees: [TeeBox] = [
            TeeBox(id: "er-black", name: "Black", color: "Black", totalYards: 7124, rating: 74.2, slope: 135),
            TeeBox(id: "er-blue",  name: "Blue",  color: "Blue",  totalYards: 6640, rating: 71.6, slope: 128),
            TeeBox(id: "er-white", name: "White", color: "White", totalYards: 6215, rating: 69.8, slope: 122),
        ]
        let pars    = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4]
        let yBlack  = [418, 556, 192, 425, 388, 165, 538, 401, 392, 410, 178, 542, 398, 412, 155, 551, 388, 415]
        let yBlue   = [390, 518, 172, 396, 362, 148, 503, 375, 365, 382, 158, 510, 371, 385, 138, 516, 361, 390]
        let yWhite  = [366, 486, 155, 370, 338, 132, 470, 349, 341, 355, 142, 478, 346, 360, 122, 484, 336, 364]
        let holes = (1...18).map { num -> GolfHole in
            let i = num - 1
            return GolfHole(
                id: "er-hole-\(num)",
                courseId: "eagle-ridge-gc",
                number: num,
                par: pars[i],
                teeYardsByTeeBox: ["er-black": yBlack[i], "er-blue": yBlue[i], "er-white": yWhite[i]]
            )
        }
        return GolfCourse(
            id: "eagle-ridge-gc",
            name: "Eagle Ridge Golf Club",
            city: "Springfield",
            state: "IL",
            holes: holes,
            teeBoxes: tees,
            source: .mock
        )
    }

    // MARK: Par-3 Practice Course

    static func par3Practice() -> GolfCourse {
        let tees = [TeeBox(id: "p3-tee", name: "Standard", color: "White", totalYards: 1240)]
        let yardages = [95, 115, 88, 132, 102, 78, 142, 108, 118, 155, 92, 128, 86, 108, 118, 98, 138, 145]
        let holes = (1...18).map { num -> GolfHole in
            GolfHole(
                id: "p3-hole-\(num)",
                courseId: "par3-practice",
                number: num,
                par: 3,
                teeYardsByTeeBox: ["p3-tee": yardages[num - 1]]
            )
        }
        return GolfCourse(
            id: "par3-practice",
            name: "Greenway Par-3 Course",
            city: "Local",
            state: "—",
            holes: holes,
            teeBoxes: tees,
            source: .mock
        )
    }
}
