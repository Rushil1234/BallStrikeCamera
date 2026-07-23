import Foundation
import CoreML
import Vision
import CoreGraphics
import AVFoundation

// MARK: - ClubheadDetector
//
// Learned per-frame club detector (YOLO11n fine-tuned on the Roboflow
// club-head-tracking dataset, CC BY 4.0 — 11.5k hand-labeled swing frames).
// The model is RAW-output: 640×640 RGB in → [1,7,8400] floats out
// (cx, cy, w, h in 640-letterboxed pixels + shaft/head/grip class scores).
//
// Clubhead rule: the head detection when it's confident; otherwise the shaft box
// corner FARTHEST from the grip — "use the shaft to find the head". Grip falls back
// to the pose hands when the grip class misses.

final class ClubheadDetector {

    struct Detection {
        var shaft: CGRect?
        var shaftConf: Double = 0
        var head: CGPoint?
        var headConf: Double = 0
        var grip: CGPoint?
        var gripConf: Double = 0

        /// Best clubhead estimate in normalized upright coords (y up).
        /// `hands` is the pose-derived grip fallback.
        /// Clubhead + the confidence of whatever produced it (head score, or shaft score
        /// when the far-corner geometry was used). Callers gate on it — weak detections
        /// are where the body lock-ons live.
        func clubheadWithConfidence(hands: CGPoint?) -> (point: CGPoint, conf: Double)? {
            guard let p = clubhead(hands: hands) else { return nil }
            if let head, headConf >= 0.30, abs(p.x - head.x) < 1e-6, abs(p.y - head.y) < 1e-6 {
                return (p, headConf)
            }
            return (p, shaft != nil ? shaftConf : headConf)
        }

        func clubhead(hands: CGPoint?) -> CGPoint? {
            // Sparse-but-right beats dense-but-wrong: the spline bridges gaps smoothly,
            // but junk points drag the line onto the body. A candidate ON the hands is
            // never the clubhead; a tiny shaft box is an arm fragment, not the club.
            func plausible(_ p: CGPoint) -> CGPoint? {
                if let hands, hypot(p.x - hands.x, p.y - hands.y) < 0.06 { return nil }
                return p
            }
            if let head, headConf >= 0.30 { return plausible(head) }
            guard let shaft, shaftConf >= 0.35,
                  hypot(shaft.width, shaft.height) >= 0.07 else {
                return headConf > 0.15 ? head.flatMap(plausible) : nil
            }
            guard let anchor = (gripConf >= 0.25 ? grip : nil) ?? hands else {
                return head.flatMap(plausible)
            }
            // Shaft is a diagonal inside its box; the head end is the corner
            // farthest from the grip.
            let corners = [
                CGPoint(x: shaft.minX, y: shaft.minY), CGPoint(x: shaft.maxX, y: shaft.minY),
                CGPoint(x: shaft.minX, y: shaft.maxY), CGPoint(x: shaft.maxX, y: shaft.maxY),
            ]
            return corners.max {
                hypot($0.x - anchor.x, $0.y - anchor.y) < hypot($1.x - anchor.x, $1.y - anchor.y)
            }.flatMap(plausible)
        }
    }

    private let model: MLModel
    private let vnModel: VNCoreMLModel
    private let inputName: String

    /// App path: Xcode compiles ClubDetector.mlpackage → ClubDetector.mlmodelc in the bundle.
    convenience init?() {
        guard let url = Bundle.main.url(forResource: "ClubDetector", withExtension: "mlmodelc") else {
            return nil
        }
        self.init(compiledURL: url)
    }

    /// Shared path (CLI passes a runtime-compiled model URL).
    init?(compiledURL: URL) {
        #if targetEnvironment(simulator)
        // The iOS Simulator's software Metal backend ABORTS on this model — MPSGraph
        // "MLIR pass manager failed" is an uncatchable assert, not a throw, so it can't be
        // guarded with try? or computeUnits. Disable the learned detector in the Simulator
        // entirely: SwingClubTracer falls back to the motion tracker, so analyze-swing runs
        // (with a simpler club trail) instead of crashing. A physical device runs the model
        // for real on the Neural Engine. (macOS CLI is NOT a simulator env → uses the model.)
        return nil
        #else
        let cfg = MLModelConfiguration()
        // .cpuOnly, NOT .all: this detector runs the MOMENT a swing is found (SwingClubTracer),
        // which is exactly Noah's "crashes every time it sees a swing" in Analyze Swing. The crash
        // is "MPSGraph: MLIR pass manager failed" — an UNCATCHABLE assert where the model's Metal
        // graph fails to compile (the ANE is tried first — "numANECores: Unknown" — then the GPU
        // graph aborts). CPU-only skips Metal entirely, so it can't fire. This runs ~30 frames
        // ONCE per analysis (not a live loop), so the CPU cost is a one-time couple of seconds.
        cfg.computeUnits = .cpuOnly
        guard let m = try? MLModel(contentsOf: compiledURL, configuration: cfg),
              let vn = try? VNCoreMLModel(for: m) else { return nil }
        model = m
        vnModel = vn
        inputName = m.modelDescription.inputDescriptionsByName.keys.first ?? "image"
        #endif
    }

    /// Runs one frame. `orientation` maps the buffer to upright exactly like the pose path.
    /// Returns nil when inference fails entirely.
    func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Detection? {
        // Letterbox the UPRIGHT image into 640×640 (Vision's scaleFit — matches training).
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try? handler.perform([request])
        guard let obs = request.results?.first as? VNCoreMLFeatureValueObservation,
              let arr = obs.featureValue.multiArrayValue else { return nil }

        // Upright content size for letterbox unmapping.
        let rawW = CVPixelBufferGetWidth(pixelBuffer)
        let rawH = CVPixelBufferGetHeight(pixelBuffer)
        let rotated = orientation == .left || orientation == .right
        let upW = CGFloat(rotated ? rawH : rawW)
        let upH = CGFloat(rotated ? rawW : rawH)
        let scale = 640 / max(upW, upH)
        let contentW = upW * scale, contentH = upH * scale
        let padX = (640 - contentW) / 2, padY = (640 - contentH) / 2

        let n = 8400
        let ptr = arr.dataPointer.bindMemory(to: Float32.self, capacity: 7 * n)
        // Best anchor per class (shaft=4, head=5, grip=6 score rows).
        var best = [(idx: -1, conf: Float32(0)), (idx: -1, conf: Float32(0)), (idx: -1, conf: Float32(0))]
        for i in 0..<n {
            for c in 0..<3 {
                let s = ptr[(4 + c) * n + i]
                if s > best[c].conf { best[c] = (i, s) }
            }
        }

        func norm(_ i: Int) -> (center: CGPoint, rect: CGRect) {
            let cx = CGFloat(ptr[0 * n + i]), cy = CGFloat(ptr[1 * n + i])
            let w = CGFloat(ptr[2 * n + i]), h = CGFloat(ptr[3 * n + i])
            func nx(_ x: CGFloat) -> CGFloat { min(max((x - padX) / contentW, 0), 1) }
            func ny(_ y: CGFloat) -> CGFloat { 1 - min(max((y - padY) / contentH, 0), 1) }  // y up
            let center = CGPoint(x: nx(cx), y: ny(cy))
            let rect = CGRect(x: nx(cx - w / 2), y: ny(cy + h / 2),
                              width: min(w / contentW, 1), height: min(h / contentH, 1))
            return (center, rect)
        }

        var det = Detection()
        if best[0].idx >= 0, best[0].conf > 0.20 {
            det.shaft = norm(best[0].idx).rect
            det.shaftConf = Double(best[0].conf)
        }
        if best[1].idx >= 0, best[1].conf > 0.15 {
            det.head = norm(best[1].idx).center
            det.headConf = Double(best[1].conf)
        }
        if best[2].idx >= 0, best[2].conf > 0.20 {
            det.grip = norm(best[2].idx).center
            det.gripConf = Double(best[2].conf)
        }
        return (det.shaft != nil || det.head != nil) ? det : nil
    }
}
