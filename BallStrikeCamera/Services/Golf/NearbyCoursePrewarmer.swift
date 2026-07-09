import Foundation
import CoreLocation

/// Background warmer that pulls the nearest GPS-ready courses from OUR catalog
/// and seeds the local geometry cache so a round can start instantly.
///
/// Database-only by design: course mode never touches MapKit/OSM/GolfCourseAPI —
/// if the catalog is unreachable, warming silently does nothing and the round
/// flow surfaces its own error at start time.
///
/// Usage:
///   let warmer = NearbyCoursePrewarmer()
///   warmer.warm(near: userLoc)
///   // …later, on view dismiss / mode change:
///   warmer.cancel()
@MainActor
final class NearbyCoursePrewarmer: ObservableObject {

    @Published private(set) var warmedCount = 0
    @Published private(set) var isWarming   = false

    private var task: Task<Void, Never>?
    private var alreadyWarmed: Set<String> = []
    private let maxCandidates: Int

    init(maxCandidates: Int = 3) {
        self.maxCandidates = maxCandidates
    }

    deinit { task?.cancel() }

    func cancel() {
        task?.cancel()
        task = nil
        isWarming = false
    }

    /// Kick off prewarming. Idempotent — if a warm is already running it is left alone.
    /// Honors `Task.cancelled` throughout the chain. Best-effort: no errors propagate.
    func warm(near location: CLLocationCoordinate2D, radiusMeters: Double = 60_000) {
        guard task?.isCancelled != false else { return }   // already running
        isWarming  = true
        warmedCount = 0
        task = Task(priority: .background) { [weak self] in
            guard let self else { return }
            // Nearest gps_ready catalog courses only — same source as the Nearby list.
            let candidates = await CourseCatalog.search(query: "", near: location,
                                                        limit: self.maxCandidates * 2,
                                                        onlyGeometry: true)
            if Task.isCancelled { return }
            for course in candidates.prefix(self.maxCandidates) {
                if Task.isCancelled { break }
                if self.alreadyWarmed.contains(course.id) { continue }
                self.alreadyWarmed.insert(course.id)
                // Skip when fresh cache already exists.
                if OSMGolfService.shared.loadCached(courseId: course.id) != nil {
                    self.warmedCount += 1
                    continue
                }
                if let geo = await CourseCatalog.geometry(for: course), geo.hasTrustedGeometry {
                    OSMGolfService.shared.cacheMergedCourse(geo)
                }
                if Task.isCancelled { break }
                self.warmedCount += 1
            }
            self.isWarming = false
        }
    }
}
