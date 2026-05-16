import Foundation
import CoreLocation

// MARK: - Provider Protocol

protocol CourseProvider {
    func searchCourses(query: String, near location: CLLocationCoordinate2D?) async throws -> [GolfCourse]
    func loadCourseDetails(courseId: String) async throws -> GolfCourse
}

// MARK: - Provider Factory

enum CourseProviderFactory {
    /// Returns GolfCourseAPIProvider when a key is configured, MockCourseProvider otherwise.
    static func make(userId: UUID) -> CourseProvider {
        if GolfCourseAPIConfig.isConfigured {
            return GolfCourseAPIProvider(userId: userId)
        }
        return MockCourseProvider()
    }
}
