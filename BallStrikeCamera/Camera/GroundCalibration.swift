import ARKit
import Combine
import simd

/// Result of a pre-shot ground calibration, handed to the capture pipeline so
/// the ball detector can work in real-world scale.
struct CalibrationResult: Equatable {
    var heightMeters: Double   // camera / tripod height above the ground
    var groundY: Float         // world-space Y of the ground plane
}

/// Measures the tripod height above the ground and the ground plane using ARKit
/// horizontal-plane detection.
///
/// IMPORTANT: this is a brief PRE-SHOT phase. ARKit's `ARSession` cannot share
/// the camera with the app's 240 fps `AVCaptureSession`, so call `stop()` before
/// starting capture. See `AR_GROUND_CALIBRATION_PLAN.md`.
///
/// Threading: ARSession delegate callbacks arrive on a single serial queue, so
/// the `dq*` fields are mutated only there; `@Published` values are pushed to the
/// main queue for SwiftUI.
final class GroundCalibration: NSObject, ObservableObject {
    @Published private(set) var heightCm: Int?
    @Published private(set) var groundY: Float?
    @Published private(set) var hasGround = false
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Point the camera at the ground next to the ball…"

    let session = ARSession()

    /// Mutated only on the ARSession delegate (serial) queue.
    private var dqGroundY: Float?

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            statusText = "This device doesn't support AR calibration."
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.worldAlignment = .gravity
        // LiDAR devices: a denser ground/scene depth for a better ground map.
        if type(of: config).supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        session.pause()
        isRunning = false
    }

    /// The current best calibration, or nil until the ground has been found.
    var result: CalibrationResult? {
        guard let g = groundY, let cm = heightCm, cm > 0 else { return nil }
        return CalibrationResult(heightMeters: Double(cm) / 100.0, groundY: g)
    }

    private func publish(_ apply: @escaping (GroundCalibration) -> Void) {
        DispatchQueue.main.async { apply(self) }
    }
}

extension GroundCalibration: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor])    { handlePlanes(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { handlePlanes(anchors) }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let g = dqGroundY else { return }
        let h = frame.camera.transform.columns.3.y - g
        guard h > 0 else { return }
        let cm = Int((h * 100).rounded())
        publish { me in
            me.heightCm = cm
            me.statusText = "Tripod height: \(cm) cm — aim at the ball, then confirm."
        }
    }

    private func handlePlanes(_ anchors: [ARAnchor]) {
        let ys = anchors
            .compactMap { $0 as? ARPlaneAnchor }
            .filter { $0.alignment == .horizontal }
            .map { $0.transform.columns.3.y }
        guard let lowest = ys.min() else { return }
        // Ground = the lowest horizontal plane observed so far.
        let g = min(dqGroundY ?? lowest, lowest)
        dqGroundY = g
        publish { me in
            me.groundY = g
            me.hasGround = true
        }
    }
}
