import CoreML
import UIKit
import Vision

/// Clubless club speed from the hosel point (Noah's shaft-head-junction idea).
///
/// ClubDetectorV2 is a yolov8n fine-tuned on 3,221 hand-labeled frames across five
/// sessions (classes: 0 head, 1 hosel, 2 ball; raw [1,7,8400] output at 640px
/// letterbox). July 20 validation, jul16+17 vs TopTracer (n=113):
///   - hosel localization 0.7 px median vs Noah's labels
///   - speed 3.0-3.4 mph median — AT the truth floor: TT and Garmin disagree with
///     each other by 5.4 mph median on the same swings, and this measurement agrees
///     with each unit better than they agree with each other (k=1.028 vs TT,
///     0.980 vs Garmin).
/// Measured dead ends (do not revisit without new data): head point 3.9 mph (blade
/// rotation pollutes it), head+hosel midpoint worse, ball-motion px ruler 2x worse,
/// post-impact extra point blocked (detector trained only on impact-3..+1 poses).
final class HoselSpeedEstimator {

    static let shared = HoselSpeedEstimator()

    private let vnModel: VNCoreMLModel?

    private init() {
        var vn: VNCoreMLModel? = nil
        if let url = Bundle.main.url(forResource: "ClubDetectorV2", withExtension: "mlmodelc") {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            if let m = try? MLModel(contentsOf: url, configuration: cfg) {
                vn = try? VNCoreMLModel(for: m)
            }
        }
        vnModel = vn
        if vnModel == nil {
            print("[Hosel] ClubDetectorV2.mlmodelc not loadable — hosel club speed disabled")
        }
    }

    /// Best hosel detection in ORIGINAL image pixel coords (conf >= 0.25), undoing
    /// Vision's scaleFit letterbox — same mapping the offline eval validated.
    func hoselPoint(in cg: CGImage) -> (x: Double, y: Double, conf: Double)? {
        guard let vnModel else { return nil }
        let W = Double(cg.width), H = Double(cg.height)
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFit
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        guard let obs = request.results?.first as? VNCoreMLFeatureValueObservation,
              let arr = obs.featureValue.multiArrayValue,
              arr.shape.count == 3, arr.shape[1].intValue == 7 else { return nil }
        let n = arr.shape[2].intValue
        let scale = 640.0 / max(W, H)
        let padX = (640.0 - W * scale) / 2, padY = (640.0 - H * scale) / 2
        let p = arr.dataPointer.bindMemory(to: Float.self, capacity: 7 * n)
        var best: (x: Double, y: Double, conf: Double)? = nil
        for i in 0..<n {
            let conf = Double(p[5 * n + i])          // row 5 = hosel class score
            guard conf >= 0.25, conf > (best?.conf ?? 0) else { continue }
            best = ((Double(p[i]) - padX) / scale,
                    (Double(p[n + i]) - padY) / scale, conf)
        }
        return best
    }

    /// Mean-of-window hosel speed. Window = impact-3 ... impact+1; intervals must
    /// span <= 3 frames and END by impact+1 (the interval INTO the impact frame is
    /// fine; anything later is follow-through the detector never trained on, and the
    /// single last interval alone reads ~18% low from contact blur — hence the mean).
    /// `r0` is the HYBRID rest-ball radius: (this shot's r0 + session median) / 2 —
    /// averaging out per-shot radius quantization cut the error tail p90 12.7 -> 10.1.
    func clubSpeedMph(frames: [AnalyzedShotFrame], impactIndex: Int,
                      r0: Double) -> (mph: Double, intervals: Int)? {
        guard vnModel != nil, r0 > 1 else { return nil }
        var pts: [(fi: Int, t: Double, x: Double, y: Double)] = []
        for f in frames where f.frameIndex >= impactIndex - 3 && f.frameIndex <= impactIndex + 1 {
            guard let cg = f.originalFrame.image.cgImage else { continue }
            if let h = hoselPoint(in: cg) {
                pts.append((f.frameIndex, f.timestamp, h.x, h.y))
            }
        }
        pts.sort { $0.fi < $1.fi }
        var mphs: [Double] = []
        for (a, b) in zip(pts, pts.dropFirst()) {
            guard b.fi - a.fi <= 3, b.t > a.t else { continue }
            let vPx = hypot(b.x - a.x, b.y - a.y) / (b.t - a.t)
            mphs.append(vPx * 0.021335 / r0 * 2.23694)   // ball radius = 21.335 mm
        }
        guard !mphs.isEmpty else { return nil }
        return (mphs.reduce(0, +) / Double(mphs.count), mphs.count)
    }
}
