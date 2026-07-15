import Foundation
import AVFoundation
import Vision
import UIKit

// MARK: - TrueCarry Coach: swing video analysis
//
// Runs AFTER capture on the recorded file (live preview only does coarse pose for framing +
// auto-record). Pipeline: frames → Vision 2D body pose → smoothing → phase segmentation →
// face-on metrics → skill-banded score + fault detection.
//
// Engine is Vision 2D everywhere; on iOS 17+ the recording is tagged for the (Phase 2) 3D
// keyframe upgrade path. 2D face-on is fully sufficient for tempo / sway / slide / tilt /
// balance — the metrics this version ships.

// MARK: In-memory pose types

struct SwingJoint {
    var point: CGPoint          // Vision normalized, origin bottom-left, y up
    var confidence: Double
}

struct SwingPoseFrame {
    var index: Int
    var time: Double
    var joints: [VNHumanBodyPoseObservation.JointName: SwingJoint]

    func joint(_ name: VNHumanBodyPoseObservation.JointName, minConfidence: Double = 0.25) -> CGPoint? {
        guard let j = joints[name], j.confidence >= minConfidence else { return nil }
        return j.point
    }

    /// Midpoint of two joints when both are trusted.
    func mid(_ a: VNHumanBodyPoseObservation.JointName,
             _ b: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        guard let pa = joint(a), let pb = joint(b) else { return nil }
        return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    }
}

// MARK: - Pose extraction

enum SwingPoseExtractor {

    /// Reads the clip and runs 2D body pose on every frame (strided above 120fps so an 8s
    /// 240fps clip stays ~1000 Vision calls). Returns smoothed frames + the effective fps.
    static func extract(videoURL: URL) async throws -> (frames: [SwingPoseFrame], fps: Double) {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "SwingPose", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No video track"])
        }
        let nominalFPS = Double(try await track.load(.nominalFrameRate))
        let stride = max(1, Int((nominalFPS / 120.0).rounded()))
        let effectiveFPS = nominalFPS / Double(stride)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var frames: [SwingPoseFrame] = []
        var rawIndex = 0
        while let sample = output.copyNextSampleBuffer() {
            defer { rawIndex += 1 }
            if rawIndex % stride != 0 { continue }
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds

            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up)
            try? handler.perform([request])

            var joints: [VNHumanBodyPoseObservation.JointName: SwingJoint] = [:]
            if let obs = request.results?.first,
               let recognized = try? obs.recognizedPoints(.all) {
                for (name, pt) in recognized where pt.confidence > 0.1 {
                    joints[name] = SwingJoint(point: pt.location, confidence: Double(pt.confidence))
                }
            }
            frames.append(SwingPoseFrame(index: frames.count, time: time, joints: joints))
        }
        reader.cancelReading()

        return (smooth(frames), effectiveFPS)
    }

    /// Light EMA smoothing per joint — kills Vision jitter without lagging the fast phases.
    private static func smooth(_ frames: [SwingPoseFrame]) -> [SwingPoseFrame] {
        guard frames.count > 2 else { return frames }
        var out = frames
        let alpha = 0.55
        for i in 1..<out.count {
            for (name, joint) in out[i].joints {
                guard let prev = out[i - 1].joints[name] else { continue }
                var j = joint
                j.point.x = prev.point.x + (joint.point.x - prev.point.x) * alpha
                j.point.y = prev.point.y + (joint.point.y - prev.point.y) * alpha
                out[i].joints[name] = j
            }
        }
        return out
    }
}

// MARK: - Phase segmentation

enum SwingPhaseSegmenter {

    /// Wrist-kinematics segmentation:
    /// address = last stillness before sustained motion · top = hand-height peak after takeaway
    /// impact = max hand speed after top near address height · finish = speed decays and holds.
    static func segment(frames: [SwingPoseFrame], fps: Double) -> SwingPhases? {
        guard frames.count >= 10, fps > 1 else { return nil }

        // Hand center trace: wrists preferred, elbows as fallback.
        var hand = [CGPoint?](repeating: nil, count: frames.count)
        for (i, f) in frames.enumerated() {
            hand[i] = f.mid(.leftWrist, .rightWrist)
                ?? f.joint(.leftWrist) ?? f.joint(.rightWrist)
                ?? f.mid(.leftElbow, .rightElbow)
        }
        // Fill gaps by carrying last known position.
        var last: CGPoint? = nil
        for i in hand.indices {
            if hand[i] == nil { hand[i] = last } else { last = hand[i] }
        }
        guard hand.compactMap({ $0 }).count > frames.count / 2, let first = hand.first ?? nil else { return nil }
        let pts = hand.map { $0 ?? first }

        // Speed trace (normalized units/sec).
        var speed = [Double](repeating: 0, count: pts.count)
        for i in 1..<pts.count {
            let d = hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y)
            speed[i] = Double(d) * fps
        }

        // Body scale: shoulder width at the start (normalizes thresholds to framing distance).
        let scale = max(shoulderWidth(frames.first!) ?? 0.12, 0.05)
        let moveThresh = Double(scale) * 0.9        // units/sec ≈ deliberate takeaway motion
        let stillThresh = Double(scale) * 0.45

        // Takeaway: first index where speed stays above moveThresh for ~0.1s.
        let holdFrames = max(2, Int(fps * 0.08))
        var takeaway: Int? = nil
        for i in 1..<(speed.count - holdFrames) {
            if (i..<(i + holdFrames)).allSatisfy({ speed[$0] > moveThresh }) {
                takeaway = i; break
            }
        }
        guard let tk = takeaway else { return nil }
        let address = max(0, tk - max(1, Int(fps * 0.05)))

        // Top: hand-height maximum in the window after takeaway (Vision y is up).
        let topSearchEnd = min(pts.count - 2, tk + Int(fps * 2.6))
        guard topSearchEnd > tk + 2 else { return nil }
        var top = tk + 1
        for i in (tk + 1)...topSearchEnd where pts[i].y > pts[top].y { top = i }
        guard top > tk, top < pts.count - 3 else { return nil }

        // Impact: max speed after top while hands are back near/below address height.
        let addressY = pts[address].y
        let impactSearchEnd = min(pts.count - 1, top + Int(fps * 1.2))
        var impact = top + 1
        var bestSpeed = 0.0
        for i in (top + 1)...impactSearchEnd {
            let nearAddressHeight = pts[i].y < addressY + CGFloat(scale) * 0.9
            if nearAddressHeight && speed[i] > bestSpeed { bestSpeed = speed[i]; impact = i }
        }
        guard impact > top else { return nil }

        // Finish: first index after impact where speed stays below stillThresh for ~0.25s,
        // else the last frame.
        let finishHold = max(2, Int(fps * 0.2))
        var finish = pts.count - 1
        if impact + 1 < speed.count - finishHold {
            for i in (impact + 1)..<(speed.count - finishHold) {
                if (i..<(i + finishHold)).allSatisfy({ speed[$0] < stillThresh }) {
                    finish = i; break
                }
            }
        }

        let phases = SwingPhases(address: address, takeaway: tk, top: top,
                                 impact: impact, finish: finish,
                                 frameCount: frames.count, frameRate: fps)
        // Sanity: real swings live inside these envelopes.
        guard phases.backswingSeconds > 0.25, phases.backswingSeconds < 3.5,
              phases.downswingSeconds > 0.08, phases.downswingSeconds < 1.5 else { return nil }
        return phases
    }

    static func shoulderWidth(_ frame: SwingPoseFrame) -> CGFloat? {
        guard let l = frame.joint(.leftShoulder), let r = frame.joint(.rightShoulder) else { return nil }
        return abs(l.x - r.x)
    }
}

// MARK: - Metrics

enum SwingMetricsEngine {

    /// Skill-banded target windows (low, high) per metric.
    static func targetBand(_ kind: SwingMetricKind, skill: SkillLevel) -> (Double, Double) {
        let loose = skill == .newcomer || skill == .beginner
        switch kind {
        case .tempoRatio:       return loose ? (2.2, 4.0) : (2.6, 3.4)
        case .headSway:         return loose ? (0, 40)    : (0, 25)      // % shoulder width
        case .hipSlide:         return loose ? (0, 55)    : (0, 35)
        case .spineTiltAddress: return (25, 45)                          // degrees
        case .leadArmAtTop:     return loose ? (0, 35)    : (0, 20)      // degrees of bend
        case .finishBalance:    return loose ? (0, 12)    : (0, 7)       // % jitter
        case .shoulderTurn:     return (55, 100)
        case .takeawayPath:     return loose ? (-35, 35)  : (-22, 22)    // % shoulder width off plane
        case .deliveryPlane:    return loose ? (-35, 35)  : (-22, 22)
        case .earlyExtension:   return loose ? (0, 35)    : (0, 22)
        }
    }

    static func compute(frames: [SwingPoseFrame], phases: SwingPhases,
                        skill: SkillLevel, isLefty: Bool,
                        viewAngle: SwingViewAngle = .faceOn) -> [SwingMetricValue] {
        viewAngle == .downTheLine
            ? computeDownTheLine(frames: frames, phases: phases, skill: skill)
            : computeFaceOn(frames: frames, phases: phases, skill: skill, isLefty: isLefty)
    }

    /// Down-the-line (tripod ~6ft behind, looking at the target): swing-plane proxies.
    /// The plane reference is the ADDRESS hand position; inside/outside/steep/shallow are the
    /// hands' horizontal offset from that reference when they pass hip height — the same visual
    /// call the plane-line apps draw, measured instead of eyeballed.
    private static func computeDownTheLine(frames: [SwingPoseFrame], phases: SwingPhases,
                                           skill: SkillLevel) -> [SwingMetricValue] {
        var out: [SwingMetricValue] = []
        let addr = frames[phases.address]
        let scale = Double(SwingPhaseSegmenter.shoulderWidth(addr) ?? 0.10)
        guard scale > 0.015 else { return out }

        func add(_ kind: SwingMetricKind, _ value: Double, confidence: Double) {
            let band = targetBand(kind, skill: skill)
            out.append(SwingMetricValue(kind: kind, value: value,
                                        targetLow: band.0, targetHigh: band.1,
                                        confidence: confidence))
        }

        if let ratio = phases.tempoRatio {
            add(.tempoRatio, (ratio * 10).rounded() / 10, confidence: 0.95)
        }

        func hands(_ f: SwingPoseFrame) -> CGPoint? {
            f.mid(.leftWrist, .rightWrist) ?? f.joint(.leftWrist) ?? f.joint(.rightWrist)
        }
        guard let addrHands = hands(addr),
              let addrHips = addr.mid(.leftHip, .rightHip) else { return out }
        let hipHeight = addrHips.y
        // Ball side: in DTL the ball (and hands at address) sit toward one screen edge
        // relative to the body — positive = toward the ball line = outside/steep.
        let ballSign: Double = addrHands.x >= addrHips.x ? 1 : -1

        /// Hands' offset from the address hand position (% shoulder width, +toward ball)
        /// at the frame nearest hip height inside a window.
        func planeOffset(in range: ClosedRange<Int>) -> Double? {
            var best: (dy: CGFloat, dx: Double)? = nil
            for i in range where i >= 0 && i < frames.count {
                guard let h = hands(frames[i]) else { continue }
                let dy = abs(h.y - hipHeight)
                if best == nil || dy < best!.dy {
                    best = (dy, Double(h.x - addrHands.x) * ballSign)
                }
            }
            guard let best, best.dy < 0.12 else { return nil }
            return (best.dx / scale * 100).rounded()
        }

        if phases.top > phases.takeaway,
           let back = planeOffset(in: phases.takeaway...phases.top) {
            add(.takeawayPath, back, confidence: 0.6)
        }
        if phases.impact > phases.top,
           let down = planeOffset(in: phases.top...phases.impact) {
            add(.deliveryPlane, down, confidence: 0.6)
        }

        // Early extension: pelvis drifting toward the ball line between top and impact.
        var maxDrift = 0.0
        for i in phases.top...min(phases.impact, frames.count - 1) {
            guard let hips = frames[i].mid(.leftHip, .rightHip) else { continue }
            maxDrift = max(maxDrift, Double(hips.x - addrHips.x) * ballSign)
        }
        add(.earlyExtension, (maxDrift / scale * 100).rounded(), confidence: 0.55)

        // Balance reads the same from any angle.
        let tail = frames.suffix(max(3, Int(phases.frameRate * 0.5)))
        let anklePts: [CGPoint] = tail.compactMap { $0.mid(.leftAnkle, .rightAnkle) }
        if anklePts.count > 3 {
            let mx = anklePts.map { Double($0.x) }.reduce(0, +) / Double(anklePts.count)
            let my = anklePts.map { Double($0.y) }.reduce(0, +) / Double(anklePts.count)
            let jitter = anklePts.map { hypot(Double($0.x) - mx, Double($0.y) - my) }
                .reduce(0, +) / Double(anklePts.count)
            add(.finishBalance, (jitter / scale * 100 * 10).rounded() / 10, confidence: 0.7)
        }
        return out
    }

    private static func computeFaceOn(frames: [SwingPoseFrame], phases: SwingPhases,
                                      skill: SkillLevel, isLefty: Bool) -> [SwingMetricValue] {
        var out: [SwingMetricValue] = []
        let scale = Double(SwingPhaseSegmenter.shoulderWidth(frames[phases.address]) ?? 0.12)
        guard scale > 0.02 else { return out }

        func add(_ kind: SwingMetricKind, _ value: Double, confidence: Double) {
            let band = targetBand(kind, skill: skill)
            out.append(SwingMetricValue(kind: kind, value: value,
                                        targetLow: band.0, targetHigh: band.1,
                                        confidence: confidence))
        }

        // Tempo — the most trustworthy number we have (pure timing).
        if let ratio = phases.tempoRatio {
            add(.tempoRatio, (ratio * 10).rounded() / 10, confidence: 0.95)
        }

        // Head sway: lateral travel of the head (nose/ears) address→impact, % shoulder width.
        let headTrace: [CGPoint] = frames[phases.address...min(phases.impact, frames.count - 1)].compactMap {
            $0.joint(.nose) ?? $0.mid(.leftEar, .rightEar)
        }
        if headTrace.count > 5, let start = headTrace.first {
            let maxDx = headTrace.map { abs(Double($0.x - start.x)) }.max() ?? 0
            add(.headSway, (maxDx / scale * 100).rounded(),
                confidence: Double(headTrace.count) / Double(phases.impact - phases.address + 1))
        }

        // Hip slide: pelvis lateral travel address→impact, % shoulder width.
        let hipTrace: [CGPoint] = frames[phases.address...min(phases.impact, frames.count - 1)].compactMap {
            $0.mid(.leftHip, .rightHip) ?? $0.joint(.root)
        }
        if hipTrace.count > 5, let start = hipTrace.first {
            let maxDx = hipTrace.map { abs(Double($0.x - start.x)) }.max() ?? 0
            add(.hipSlide, (maxDx / scale * 100).rounded(),
                confidence: Double(hipTrace.count) / Double(phases.impact - phases.address + 1))
        }

        // Spine tilt at address: angle of hip-mid → shoulder-mid line from vertical.
        let addr = frames[phases.address]
        if let hip = addr.mid(.leftHip, .rightHip),
           let sh  = addr.mid(.leftShoulder, .rightShoulder) {
            let dx = Double(sh.x - hip.x), dy = Double(sh.y - hip.y)
            if dy > 0.01 {
                let tilt = abs(atan2(dx, dy) * 180 / .pi)
                add(.spineTiltAddress, tilt.rounded(), confidence: 0.75)
            }
        }

        // Lead-arm bend at the top (degrees short of straight). Lead arm = left for righties.
        let topFrame = frames[phases.top]
        let (shJ, elJ, wrJ): (VNHumanBodyPoseObservation.JointName,
                              VNHumanBodyPoseObservation.JointName,
                              VNHumanBodyPoseObservation.JointName) =
            isLefty ? (.rightShoulder, .rightElbow, .rightWrist)
                    : (.leftShoulder, .leftElbow, .leftWrist)
        if let s = topFrame.joint(shJ), let e = topFrame.joint(elJ), let w = topFrame.joint(wrJ) {
            let v1 = CGPoint(x: s.x - e.x, y: s.y - e.y)
            let v2 = CGPoint(x: w.x - e.x, y: w.y - e.y)
            let dot = Double(v1.x * v2.x + v1.y * v2.y)
            let mag = Double(hypot(v1.x, v1.y) * hypot(v2.x, v2.y))
            if mag > 0.0001 {
                let elbowAngle = acos(max(-1, min(1, dot / mag))) * 180 / .pi
                add(.leadArmAtTop, max(0, 180 - elbowAngle).rounded(), confidence: 0.6)
            }
        }

        // Finish balance: ankle-midpoint jitter over the final ~0.5s, % shoulder width.
        let tail = frames.suffix(max(3, Int(phases.frameRate * 0.5)))
        let anklePts: [CGPoint] = tail.compactMap { $0.mid(.leftAnkle, .rightAnkle) }
        if anklePts.count > 3 {
            let mx = anklePts.map { Double($0.x) }.reduce(0, +) / Double(anklePts.count)
            let my = anklePts.map { Double($0.y) }.reduce(0, +) / Double(anklePts.count)
            let jitter = anklePts.map { hypot(Double($0.x) - mx, Double($0.y) - my) }
                .reduce(0, +) / Double(anklePts.count)
            add(.finishBalance, (jitter / scale * 100 * 10).rounded() / 10, confidence: 0.7)
        }

        return out
    }
}

// MARK: - Scoring + faults

enum SwingScorer {

    struct Result {
        var overall: Int
        var categories: [String: Int]
        var faultIds: [String]
        var headline: String
        var focusPoint: String
    }

    private static let categoryMap: [SwingMetricKind: String] = [
        .spineTiltAddress: "setup",
        .tempoRatio: "tempo",
        .headSway: "body", .hipSlide: "body", .leadArmAtTop: "body",
        .finishBalance: "balance",
        .takeawayPath: "plane", .deliveryPlane: "plane", .earlyExtension: "plane"
    ]

    static func score(metrics: [SwingMetricValue], faults: [SwingFault]) -> Result {
        // Per-metric subscore: 100 in band, decaying with distance beyond it (in band-widths).
        func subscore(_ m: SwingMetricValue) -> Double {
            let width = max(m.targetHigh - m.targetLow, 0.001)
            let over = m.value > m.targetHigh ? (m.value - m.targetHigh) / width
                     : m.value < m.targetLow  ? (m.targetLow - m.value) / width
                     : 0
            return max(30, 100 - over * 45)
        }

        var catTotals: [String: (sum: Double, weight: Double)] = [:]
        for m in metrics {
            let cat = categoryMap[m.kind] ?? "body"
            let w = max(m.confidence, 0.2)
            var t = catTotals[cat] ?? (0, 0)
            t.sum += subscore(m) * w
            t.weight += w
            catTotals[cat] = t
        }
        var categories: [String: Int] = [:]
        for (cat, t) in catTotals where t.weight > 0 {
            categories[cat] = Int((t.sum / t.weight).rounded())
        }
        let overall = categories.isEmpty ? 0
            : Int((Double(categories.values.reduce(0, +)) / Double(categories.count)).rounded())

        // Faults: metric out of band in the rule's direction (confidence-gated).
        var faultIds: [String] = []
        for fault in faults {
            guard let m = metrics.first(where: { $0.kind.rawValue == fault.metric }),
                  m.confidence >= 0.35 else { continue }
            let hit = fault.direction == "above" ? m.value > m.targetHigh
                                                 : m.value < m.targetLow
            if hit { faultIds.append(fault.id) }
        }

        // 1 win + 1 focus — never a wall of criticism.
        let best = metrics.filter(\.inBand).max { $0.confidence < $1.confidence }
        let headline: String
        if let best {
            headline = "\(best.kind.displayName) is on the money — \(format(best))."
        } else if overall > 0 {
            headline = "You made a full, committed swing — that's the hard part."
        } else {
            headline = "Swing captured."
        }
        let focusPoint: String
        if let firstFault = faultIds.first, let f = faults.first(where: { $0.id == firstFault }) {
            focusPoint = f.explanation
        } else if overall >= 85 {
            focusPoint = "Keep stacking reps — consistency is the next skill."
        } else {
            focusPoint = "Smooth tempo and a held finish will lift everything else."
        }

        return Result(overall: overall, categories: categories, faultIds: faultIds,
                      headline: headline, focusPoint: focusPoint)
    }

    private static func format(_ m: SwingMetricValue) -> String {
        m.kind == .tempoRatio ? String(format: "%.1f:1", m.value)
                              : "\(Int(m.value))\(m.kind.unit)"
    }
}

// MARK: - Skeleton (drawing order shared by analysis + replay overlay)

enum SwingSkeleton {
    static let jointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .neck,
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
        .leftHip, .rightHip,
        .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle
    ]

    /// Bones as index pairs into jointOrder.
    static let bones: [(Int, Int)] = [
        (0, 1),                 // head-neck
        (1, 2), (1, 3),         // neck-shoulders
        (2, 4), (4, 6),         // left arm
        (3, 5), (5, 7),         // right arm
        (2, 8), (3, 9),         // torso sides
        (8, 9),                 // pelvis
        (8, 10), (10, 12),      // left leg
        (9, 11), (11, 13)       // right leg
    ]

    static func stored(from frame: SwingPoseFrame, at index: Int) -> StoredPose {
        StoredPose(frame: index, points: jointOrder.map { name in
            if let j = frame.joints[name] {
                return [Double(j.point.x), Double(j.point.y), j.confidence]
            }
            return [0, 0, 0]
        })
    }
}

// MARK: - Orchestrator

enum SwingAnalyzer {

    /// Full pipeline over a recorded clip. Returns the recording with analysis filled in
    /// (analyzed stays false when no swing could be segmented — UI shows a retake prompt).
    static func analyze(recording: SwingRecording, videoURL: URL,
                        skill: SkillLevel, isLefty: Bool,
                        faults: [SwingFault]) async -> SwingRecording {
        var rec = recording
        do {
            let (frames, fps) = try await SwingPoseExtractor.extract(videoURL: videoURL)
            guard let phases = SwingPhaseSegmenter.segment(frames: frames, fps: fps) else {
                rec.analyzed = false
                rec.headline = "Couldn't find a swing in that clip."
                rec.focusPoint = "Make sure your whole body is in frame and take one full swing."
                return rec
            }
            let metrics = SwingMetricsEngine.compute(frames: frames, phases: phases,
                                                     skill: skill, isLefty: isLefty,
                                                     viewAngle: rec.viewAngle)
            let result = SwingScorer.score(metrics: metrics, faults: faults)
            rec.analyzed = true
            rec.fps = fps
            rec.phases = phases
            rec.metrics = metrics
            rec.faults = result.faultIds
            rec.overallScore = result.overall
            rec.categoryScores = result.categories
            rec.headline = result.headline
            rec.focusPoint = result.focusPoint
            rec.keyPoses = phases.labelled.map { _, frameIdx in
                SwingSkeleton.stored(from: frames[min(frameIdx, frames.count - 1)], at: frameIdx)
            }
            if #available(iOS 17.0, *) { rec.poseEngine = "vision2d+3dready" }
        } catch {
            rec.analyzed = false
            rec.headline = "Analysis failed."
            rec.focusPoint = error.localizedDescription
        }
        return rec
    }

    /// First-frame thumbnail for history cards.
    static func makeThumbnail(videoURL: URL, to destination: URL) {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 400, height: 400)
        if let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil),
           let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) {
            try? data.write(to: destination)
        }
    }
}
