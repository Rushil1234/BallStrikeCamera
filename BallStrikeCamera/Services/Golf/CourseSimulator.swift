#if targetEnvironment(simulator)
import Foundation
import CoreLocation

/// In-simulator GPS walkthrough — feeds coordinates directly to LocationService,
/// bypassing Xcode's unreliable GPX playback entirely.
@MainActor
final class CourseSimulator: ObservableObject {
    static let shared = CourseSimulator()

    @Published private(set) var isRunning = false

    private var waypoints: [CLLocationCoordinate2D] = []
    private var index = 0
    private var timer: Timer?

    func start(waypoints: [CLLocationCoordinate2D],
               location: LocationService,
               interval: TimeInterval = 1.2) {
        guard !waypoints.isEmpty else { return }
        stop()
        self.waypoints = waypoints
        self.index = 0
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.index < self.waypoints.count else {
                    self?.stop(); return
                }
                location.currentLocation = self.waypoints[self.index]
                self.index += 1
            }
        }
        // Deliver first point immediately
        location.currentLocation = waypoints[0]
        index = 1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}
#endif
