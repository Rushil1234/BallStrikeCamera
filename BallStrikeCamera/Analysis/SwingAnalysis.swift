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
        // 60Hz pose sampling: half the Vision calls of 120Hz for the SAME phase quality
        // (stored phase times are exact; ±8ms beats waiting twice as long for a score).
        let stride = max(1, Int((nominalFPS / 60.0).rounded()))
        let effectiveFPS = nominalFPS / Double(stride)
        // Camera-roll clips carry a rotation transform (raw buffers are landscape);
        // app-recorded clips are physically portrait (identity). Tell Vision the real
        // orientation so poses come back in upright-image coordinates either way.
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let orientation = Self.orientation(for: transform)

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
            let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: orientation)
            try? handler.perform([request])

            var joints: [VNHumanBodyPoseObservation.JointName: SwingJoint] = [:]
            // Ranges have bystanders: track the LARGEST person in frame (torso span),
            // not whoever Vision happens to list first — a spectator behind the golfer
            // otherwise hijacks the whole analysis.
            func torsoSpan(_ obs: VNHumanBodyPoseObservation) -> CGFloat {
                guard let pts = try? obs.recognizedPoints(.all),
                      let ls = pts[.leftShoulder], let rs = pts[.rightShoulder],
                      let lh = pts[.leftHip], let rh = pts[.rightHip],
                      ls.confidence > 0.1, rs.confidence > 0.1,
                      lh.confidence > 0.1, rh.confidence > 0.1 else { return 0 }
                let sh = CGPoint(x: (ls.location.x + rs.location.x) / 2,
                                 y: (ls.location.y + rs.location.y) / 2)
                let hip = CGPoint(x: (lh.location.x + rh.location.x) / 2,
                                  y: (lh.location.y + rh.location.y) / 2)
                return hypot(sh.x - hip.x, sh.y - hip.y)
            }
            if let obs = request.results?.max(by: { torsoSpan($0) < torsoSpan($1) }),
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

    /// Rotation metadata → the Vision orientation that yields upright-image coordinates.
    static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch Int(round(atan2(transform.b, transform.a) * 180 / .pi)) {
        case 90:        return .right
        case 180, -180: return .down
        case -90:       return .left
        default:        return .up
        }
    }

    /// Zero-phase EMA smoothing per joint (forward pass, then backward pass) — kills
    /// Vision jitter WITHOUT lagging the trace. A causal-only EMA shifts the detected
    /// impact/top a few frames late, which is exactly a "wrong-moment still".
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
        for i in stride(from: out.count - 2, through: 0, by: -1) {
            for (name, joint) in out[i].joints {
                guard let next = out[i + 1].joints[name] else { continue }
                var j = joint
                j.point.x = next.point.x + (joint.point.x - next.point.x) * alpha
                j.point.y = next.point.y + (joint.point.y - next.point.y) * alpha
                out[i].joints[name] = j
            }
        }
        return out
    }
}

// MARK: - Trail quality

/// Smoothness gate for drawn paths. Roughness = mean deviation of each point from its
/// neighbors' midpoint, relative to the local step — a clean arc scores near 0.1-0.3,
/// pose-jitter spaghetti scores far higher. Face-on hand paths above the gate aren't
/// drawn at all: a jerky line teaches nothing.
enum TrailQuality {
    static func roughness(_ pts: [[Double]]) -> Double {
        guard pts.count > 6 else { return 999 }
        var total = 0.0
        var n = 0
        for i in 1..<(pts.count - 1) {
            let a = pts[i - 1], b = pts[i], c = pts[i + 1]
            let dev = hypot(b[0] - (a[0] + c[0]) / 2, b[1] - (a[1] + c[1]) / 2)
            let span = max(hypot(c[0] - a[0], c[1] - a[1]), 1e-4)
            total += dev / span
            n += 1
        }
        return n > 0 ? total / Double(n) : 999
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
        // Backfill leading gaps from the FIRST KNOWN hand — requiring frame 0 to have a
        // wrist aborted whole clips over one bad opening frame.
        guard hand.compactMap({ $0 }).count > frames.count / 2,
              let first = hand.compactMap({ $0 }).first else { return nil }
        let pts = hand.map { $0 ?? first }

        // Speed trace (normalized units/sec).
        var speed = [Double](repeating: 0, count: pts.count)
        for i in 1..<pts.count {
            let d = hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y)
            speed[i] = Double(d) * fps
        }

        // Body scale for thresholds. Shoulder width COLLAPSES in the down-the-line view
        // (shoulders point at the camera), so body height carries the scale there —
        // face-on shoulder width ≈ 0.22 × height, making the two views equivalent.
        let scale = max(motionScale(frames), 0.05)
        let moveThresh = Double(scale) * 0.9        // units/sec ≈ deliberate takeaway motion
        let stillThresh = Double(scale) * 0.45

        // Takeaway: first index where speed stays above moveThresh for ~0.1s — then walk
        // BACK to where motion actually began (the threshold trips a few frames into the
        // backswing; unrefined, the "takeaway" still shows the club already hip-high).
        let holdFrames = max(2, Int(fps * 0.08))
        var takeaway: Int? = nil
        for i in 1..<(speed.count - holdFrames) {
            if (i..<(i + holdFrames)).allSatisfy({ speed[$0] > moveThresh }) {
                takeaway = i; break
            }
        }
        guard var tk = takeaway else { return nil }
        let walkLimit = max(0, tk - Int(fps * 0.5))
        while tk > walkLimit, speed[tk - 1] > Double(scale) * 0.25 { tk -= 1 }
        let address = max(0, tk - max(1, Int(fps * 0.05)))

        // Anchor on the SPEED PEAK first — hands move fastest in the downswing, in every
        // view. A max-height-only "top" search lands on the FINISH down-the-line, where
        // the wrapped finish carries the hands higher than the top of the backswing.
        let peakSearchEnd = min(pts.count - 1, tk + Int(fps * 4.5))
        guard peakSearchEnd > tk + 3 else { return nil }
        var speedPeak = tk + 1
        for i in (tk + 1)...peakSearchEnd where speed[i] > speed[speedPeak] { speedPeak = i }
        guard speedPeak > tk + 2 else { return nil }

        // Top: highest hands between takeaway and the downswing's speed peak.
        var top = tk + 1
        for i in (tk + 1)..<speedPeak where pts[i].y > pts[top].y { top = i }
        guard top > tk, top < pts.count - 3 else { return nil }

        // Impact: the hands return to address height at the strike — the first descent
        // through it after the top is the impact moment. Max hand speed alone lands a
        // frame or two LATE (peak speed is the release). Fall back to height-gated max
        // speed, then the raw speed peak — never a garbage top+1 "impact".
        let addressY = pts[address].y
        let impactSearchEnd = min(pts.count - 1, max(speedPeak + Int(fps * 0.25), top + 1))
        var impact = 0
        for i in (top + 1)...impactSearchEnd where pts[i].y <= addressY + CGFloat(scale) * 0.4 {
            impact = i; break
        }
        if impact == 0 {
            var bestSpeed = 0.0
            impact = speedPeak
            for i in (top + 1)...impactSearchEnd {
                let nearAddressHeight = pts[i].y < addressY + CGFloat(scale) * 0.9
                if nearAddressHeight && speed[i] > bestSpeed { bestSpeed = speed[i]; impact = i }
            }
        }
        guard impact > top else { return nil }
        // A real downswing drops the hands well below the top by impact. Without this,
        // a backswing-only demo (lift to the top, hold) reads as a swing whose "impact"
        // is the fastest moment of the LIFT.
        guard pts[impact].y < pts[top].y - CGFloat(scale) * 0.5 else { return nil }

        // Finish: first index after impact where speed stays below stillThresh for ~0.25s,
        // else the last frame.
        let finishHold = max(2, Int(fps * 0.2))
        // Cap the search: the held finish lives within ~1.2s of impact — searching past
        // that finds the relaxed walk-away, not the pose.
        var finish = min(pts.count - 1, impact + Int(fps * 1.2))
        if impact + 1 < speed.count - finishHold {
            for i in (impact + 1)..<min(speed.count - finishHold, impact + Int(fps * 1.2)) {
                if (i..<(i + finishHold)).allSatisfy({ speed[$0] < stillThresh }) {
                    finish = i; break
                }
            }
        }

        var phases = SwingPhases(address: address, takeaway: tk, top: top,
                                 impact: impact, finish: finish,
                                 frameCount: frames.count, frameRate: fps)
        // Exact video timestamps — replay seeks land on the real moment, not index ÷ fps.
        phases.times = [address, tk, top, impact, finish].map {
            frames[min($0, frames.count - 1)].time
        }
        // Sanity: real swings live inside these envelopes. Wide enough for deliberate
        // practice/rehearsal swings — learners copy demonstrations slowly.
        guard phases.backswingSeconds > 0.25, phases.backswingSeconds < 4.0,
              phases.downswingSeconds > 0.08, phases.downswingSeconds < 2.0 else { return nil }
        return phases
    }

    static func shoulderWidth(_ frame: SwingPoseFrame) -> CGFloat? {
        guard let l = frame.joint(.leftShoulder), let r = frame.joint(.rightShoulder) else { return nil }
        return abs(l.x - r.x)
    }

    /// View-invariant body scale: shoulder width where it's real (face-on), body height
    /// × 0.22 where it isn't (down-the-line). Scans the first second for a usable frame.
    static func motionScale(_ frames: [SwingPoseFrame]) -> CGFloat {
        var best: CGFloat = 0
        for frame in frames.prefix(40) {
            if let w = shoulderWidth(frame) { best = max(best, w) }
            if let head = frame.joint(.nose) ?? frame.mid(.leftEar, .rightEar) ?? frame.joint(.neck),
               let ankles = frame.mid(.leftAnkle, .rightAnkle) {
                best = max(best, abs(head.y - ankles.y) * 0.22)
            }
            if best > 0.08 { break }
        }
        return best > 0 ? best : 0.12
    }
}

// MARK: - Metrics

enum SwingMetricsEngine {

    /// Skill-banded target windows (low, high) per metric. `limitedMobility` relaxes
    /// turn/posture demands — a real coach asks about the body before demanding 90°.
    static func targetBand(_ kind: SwingMetricKind, skill: SkillLevel,
                           limitedMobility: Bool = false) -> (Double, Double) {
        if limitedMobility {
            switch kind {
            case .shoulderTurn:     return (40, 100)
            case .spineTiltAddress: return (20, 48)
            case .leadArmAtTop:     return (0, 45)
            default: break
            }
        }
        let loose = skill == .newcomer || skill == .beginner
        switch kind {
        case .tempoRatio:       return loose ? (2.2, 4.0) : (2.5, 3.7)   // real-time pro measured 3.6:1
        case .headSway:         return loose ? (0, 40)    : (0, 25)      // % shoulder width
        case .hipSlide:         return loose ? (0, 55)    : (0, 35)
        case .spineTiltAddress: return (25, 45)                          // degrees
        case .leadArmAtTop:     return loose ? (0, 35)    : (0, 20)      // degrees of bend
        case .finishBalance:    return loose ? (0, 12)    : (0, 7)       // % jitter
        case .shoulderTurn:     return (55, 100)
        // Ankle centers sit ~a foot-width outside the "insides under the shoulders"
        // checkpoint, so the target band lives above 100% of shoulder width.
        case .stanceWidth:      return loose ? (85, 170)  : (95, 155)
        case .weightShift:      return loose ? (40, 125)  : (55, 115)    // % toward the lead foot
        case .transitionSeq:    return loose ? (-80, 380) : (0, 360)     // ms hips lead arms (pro measured 320)
        case .takeawayPath:     return loose ? (-35, 35)  : (-22, 22)    // % shoulder width off plane
        case .deliveryPlane:    return loose ? (-35, 35)  : (-22, 22)
        case .earlyExtension:   return loose ? (0, 65)    : (0, 50)    // reference-calibrated: Rory measures 41 on this scale
        // Reference-calibrated: Rory holds spine angle within ~4° address→impact; a
        // 25-handicap reference collapsed 21°. Aspect cancels in the DIFFERENCE.
        case .postureRetention: return loose ? (0, 14)    : (0, 8)
        }
    }

    static func compute(frames: [SwingPoseFrame], phases: SwingPhases,
                        skill: SkillLevel, isLefty: Bool,
                        viewAngle: SwingViewAngle = .faceOn,
                        limitedMobility: Bool = false) -> [SwingMetricValue] {
        viewAngle == .downTheLine
            ? computeDownTheLine(frames: frames, phases: phases, skill: skill,
                                 limitedMobility: limitedMobility)
            : computeFaceOn(frames: frames, phases: phases, skill: skill, isLefty: isLefty,
                            limitedMobility: limitedMobility)
    }

    /// Down-the-line (tripod ~6ft behind, looking at the target): swing-plane proxies.
    /// The plane reference is the ADDRESS hand position; inside/outside/steep/shallow are the
    /// hands' horizontal offset from that reference when they pass hip height — the same visual
    /// call the plane-line apps draw, measured instead of eyeballed.
    private static func computeDownTheLine(frames: [SwingPoseFrame], phases: SwingPhases,
                                           skill: SkillLevel,
                                           limitedMobility: Bool = false) -> [SwingMetricValue] {
        var out: [SwingMetricValue] = []
        let addr = frames[phases.address]
        // Shoulder width FORESHORTENS to near-zero from behind — normalizing by it
        // inflated every DTL percentage ~3x (and the tiny-scale guard zeroed whole
        // clips). motionScale falls back to body height exactly like the segmenter.
        let scale = Double(max(SwingPhaseSegmenter.motionScale(frames), 0.05))

        func add(_ kind: SwingMetricKind, _ value: Double, confidence: Double) {
            let band = targetBand(kind, skill: skill, limitedMobility: limitedMobility)
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

        // Posture retention: spine-from-vertical change address→impact. THE amateur
        // tell (standing up through the ball) — hands-based plane proxies miss it
        // completely; the reference amateur read Δ21° where Rory reads Δ<4°.
        func spineAngle(_ f: SwingPoseFrame) -> Double? {
            guard let hip = f.mid(.leftHip, .rightHip),
                  let sh = f.mid(.leftShoulder, .rightShoulder) else { return nil }
            return atan2(Double(sh.x - hip.x), Double(sh.y - hip.y)) * 180 / .pi
        }
        if phases.impact < frames.count,
           let a = spineAngle(addr), let i = spineAngle(frames[phases.impact]) {
            add(.postureRetention, (abs(abs(a) - abs(i))).rounded(), confidence: 0.7)
        }

        // Balance reads the same from any angle — but only when the clip actually
        // CONTAINS the finish: on a clip cut at impact the "tail" is the release, and
        // pros were scoring 30 for a metric that measured nothing.
        let tailLen = max(3, Int(phases.frameRate * 0.5))
        guard frames.count - phases.finish >= tailLen / 2 else { return out }
        let tail = frames.suffix(from: max(phases.finish, frames.count - tailLen))
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
                                      skill: SkillLevel, isLefty: Bool,
                                      limitedMobility: Bool = false) -> [SwingMetricValue] {
        var out: [SwingMetricValue] = []
        let scale = Double(SwingPhaseSegmenter.shoulderWidth(frames[phases.address]) ?? 0.12)
        guard scale > 0.02 else { return out }

        func add(_ kind: SwingMetricKind, _ value: Double, confidence: Double) {
            let band = targetBand(kind, skill: skill, limitedMobility: limitedMobility)
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

        // Stance width at address: ankle spread vs shoulder width ("inside of the feet
        // the same width as your shoulders" — the video's balance/speed/stability base).
        let addrFrame = frames[phases.address]
        if let la = addrFrame.joint(.leftAnkle), let ra = addrFrame.joint(.rightAnkle) {
            let spread = Double(abs(la.x - ra.x))
            add(.stanceWidth, (spread / scale * 100).rounded(), confidence: 0.7)
        }

        // Weight shift at the finish: how far the pelvis moved from stance-center toward
        // a foot (mirror-proof — measured against the nearer ankle). 0% = still centered,
        // 100% = hips stacked over the lead foot, the "twist AND push" finish.
        let finFrame = frames[min(phases.finish, frames.count - 1)]
        if let hips = finFrame.mid(.leftHip, .rightHip),
           let fla = finFrame.joint(.leftAnkle), let fra = finFrame.joint(.rightAnkle) {
            let spread = abs(fla.x - fra.x)
            if spread > 0.02 {
                let center = (fla.x + fra.x) / 2
                let t = abs(Double(hips.x - center)) / (Double(spread) / 2)
                add(.weightShift, min(t * 100, 140).rounded(), confidence: 0.65)
            }
        }

        // Transition sequence: the pros' downswing starts from the ground up — the
        // pelvis reverses toward the target BEFORE the arms leave the top. Positive ms
        // = hips first (good); negative = arms first (the over-the-top precursor).
        if let topTime = phases.times?[2] ?? Optional(Double(phases.top) / max(phases.frameRate, 1)) {
            let hipXs: [(t: Double, x: CGFloat)] = frames.compactMap { f in
                guard let h = f.mid(.leftHip, .rightHip) else { return nil }
                return (f.time, h.x)
            }
            // Hip direction during the late backswing, then the first sustained reversal.
            let pre = hipXs.filter { $0.t > topTime - 0.45 && $0.t < topTime - 0.1 }
            let win = hipXs.filter { $0.t > topTime - 0.35 && $0.t < topTime + 0.35 }
            if pre.count >= 4, win.count >= 6, let first = pre.first, let last = pre.last {
                let backDir: CGFloat = last.x >= first.x ? 1 : -1   // hips drift this way going back
                var reversal: Double? = nil
                for i in 1..<(win.count - 1) {
                    let v1 = (win[i].x - win[i - 1].x) * backDir
                    let v2 = (win[i + 1].x - win[i].x) * backDir
                    if v1 < 0 && v2 < 0 { reversal = win[i].t; break }   // sustained turn-around
                }
                if let reversal {
                    add(.transitionSeq, ((topTime - reversal) * 1000).rounded(), confidence: 0.5)
                }
            }
        }

        // Spine tilt at address: angle of hip-mid → shoulder-mid line from vertical.
        let addr = frames[phases.address]
        if let hip = addr.mid(.leftHip, .rightHip),
           let sh  = addr.mid(.leftShoulder, .rightShoulder) {
            let dx = Double(sh.x - hip.x), dy = Double(sh.y - hip.y)
            if dy > 0.01 {
                // Face-on this measures FRONTAL lean (pros ≈ 0-8°, our reference: 0.7°),
                // not the DTL forward bend the default 25-45° band describes — that band
                // flagged every face-on golfer ever. Band overridden to the frontal read.
                let tilt = abs(atan2(dx, dy) * 180 / .pi)
                out.append(SwingMetricValue(kind: .spineTiltAddress, value: tilt.rounded(),
                                            targetLow: 0, targetHigh: 12, confidence: 0.75))
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
        .spineTiltAddress: "setup", .stanceWidth: "setup",
        .tempoRatio: "tempo",
        .headSway: "body", .hipSlide: "body", .leadArmAtTop: "body", .weightShift: "body",
        .transitionSeq: "tempo",
        .finishBalance: "balance",
        .takeawayPath: "plane", .deliveryPlane: "plane", .earlyExtension: "plane",
        .postureRetention: "posture"
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

    // MARK: Live pose angles (face-on overlays)

    struct PoseAngles {
        var shoulderTilt: Double?    // shoulder line vs horizontal, degrees
        var hipTilt: Double?         // hip line vs horizontal, degrees
        var headLean: Double?        // neck→nose vs vertical, degrees
    }

    /// Angles from a stored pose (jointOrder indices; Vision coords, y up). Tilts are
    /// only returned when the joint pair is spread enough on screen to be measurable —
    /// down-the-line, the shoulder/hip lines point at the camera and the number is noise.
    static func angles(from pose: StoredPose) -> PoseAngles {
        func pt(_ i: Int) -> CGPoint? {
            guard i < pose.points.count, pose.points[i][2] > 0.25 else { return nil }
            return CGPoint(x: pose.points[i][0], y: pose.points[i][1])
        }
        // Spread gates are RELATIVE to torso length so a golfer small in a wide frame
        // still gets gauges, while true down-the-line stays suppressed.
        var torso: CGFloat = 0.2
        if let sl = pt(2), let sr = pt(3), let hl = pt(8), let hr = pt(9) {
            torso = max(0.05, hypot((sl.x + sr.x) / 2 - (hl.x + hr.x) / 2,
                                    (sl.y + sr.y) / 2 - (hl.y + hr.y) / 2))
        }
        func lineTilt(_ a: CGPoint, _ b: CGPoint, minSpread: CGFloat) -> Double? {
            let dx = b.x - a.x, dy = b.y - a.y
            guard abs(dx) > minSpread else { return nil }
            var deg = atan2(Double(dy), Double(dx)) * 180 / .pi
            if deg > 90 { deg -= 180 }
            if deg < -90 { deg += 180 }
            return deg
        }
        var out = PoseAngles()
        if let l = pt(2), let r = pt(3) { out.shoulderTilt = lineTilt(r, l, minSpread: torso * 0.35) }
        if let l = pt(8), let r = pt(9) { out.hipTilt = lineTilt(r, l, minSpread: torso * 0.22) }
        if let nose = pt(0), let neck = pt(1), let sl = pt(2), let sr = pt(3),
           abs(sl.x - sr.x) > torso * 0.35 {   // face-on only — head lean is noise down-the-line
            let dx = Double(nose.x - neck.x), dy = Double(nose.y - neck.y)
            if abs(dy) > 0.01 { out.headLean = atan2(dx, dy) * 180 / .pi }
        }
        return out
    }
}

// MARK: - Clubhead tracer (down-the-line)

/// Traces the CLUBHEAD through takeaway → impact for down-the-line clips. Hands occlude
/// each other in DTL, so a hand trail reads as noise there — the clubhead is the line the
/// takeaway lesson actually teaches.
///
/// Detection runs on a THREE-FRAME MOTION map (min of |cur−prev| and |next−cur| — the
/// classic double-difference that isolates the object at the CURRENT frame): static
/// clutter like grass texture vanishes entirely, and the fast thin shaft is the
/// strongest ridge radiating from the hands. Rays from the hand center score each
/// direction; the best ray's far end is the clubhead. The trace stops when motion blur
/// or occlusion erases the ridge (expected right around impact).
enum SwingClubTracer {

    struct UprightPlane {
        var data: [UInt8]
        let w: Int
        let h: Int
    }

    /// Learned detector source. The app default loads the bundled CoreML model; the macOS
    /// CLI overrides this with a runtime-compiled model. Nil → motion-ridge fallback.
    static var detectorProvider: () -> ClubheadDetector? = { ClubheadDetector() }
    private static var cachedDetector: ClubheadDetector??

    static func trace(videoURL: URL, frames: [SwingPoseFrame], phases: SwingPhases) async -> [[Double]]? {
        guard let times = phases.times, times.count == 5 else { return nil }
        let tStart = max(0, times[0] - 0.1)
        let tEnd = times[3] + 0.2      // through impact; follow-through extension is future work

        let asset = AVURLAsset(url: videoURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let orientation = SwingPoseExtractor.orientation(for: transform)
        let nominalFPS = Double((try? await track.load(.nominalFrameRate)) ?? 30)
        // 240fps capture → 120Hz clubhead samples: smooth slow-motion trail, and the
        // 3-frame motion difference stays crisp (tiny per-frame displacement).
        let frameStride = max(1, Int((nominalFPS / 120.0).rounded()))

        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: tStart, preferredTimescale: 600),
            end: CMTime(seconds: tEnd, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        let handSamples: [(t: Double, p: CGPoint)] = frames.compactMap { f in
            guard let h = f.mid(.leftWrist, .rightWrist)
                    ?? f.joint(.leftWrist) ?? f.joint(.rightWrist) else { return nil }
            return (f.time, h)
        }
        guard handSamples.count > 4 else { return nil }
        func hands(at t: Double) -> CGPoint? {
            var best: (dt: Double, p: CGPoint)? = nil
            for s in handSamples {
                let dt = abs(s.t - t)
                if best == nil || dt < best!.dt { best = (dt, s.p) }
            }
            guard let best, best.dt < 0.2 else { return nil }
            return best.p
        }

        // Motion baseline stays ~1/30s regardless of capture rate: at 120Hz sampling the
        // club moves sub-pixel between ADJACENT samples and the difference signal dies —
        // so difference against frames `baseline` samples away while still emitting a
        // point per sample (smooth slow-motion trail).
        let sampleFPS = nominalFPS / Double(frameStride)
        let baseline = max(1, Int((sampleFPS / 30.0).rounded()))
        let windowSize = 2 * baseline + 1

        // ── Learned path: per-frame YOLO detections, clubhead from head-or-shaft-end. ──
        // The detector generalizes where motion differencing can't (blur, busy backgrounds,
        // re-timed footage). Falls back to the motion tracker when the model is unavailable.
        if cachedDetector == nil { cachedDetector = detectorProvider() }
        if let detector = cachedDetector ?? nil {
            var trail: [[Double]] = []
            var rawIndex = 0
            var ballAnchor: CGPoint? = nil
            while let sample = output.copyNextSampleBuffer() {
                defer { rawIndex += 1 }
                if rawIndex % frameStride != 0 { continue }
                guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
                let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let hp = hands(at: t)
                if ballAnchor == nil, let hp {
                    // One-time ball fix from the first (address) frame.
                    ballAnchor = Self.findBall(
                        plane: Self.uprightPlane(from: pb, orientation: orientation),
                        handsUpright: hp)
                }
                if let det = detector.detect(pixelBuffer: pb, orientation: orientation),
                   let hit = det.clubheadWithConfidence(hands: hp),
                   // Strict before the top (body lock-ons live in the slow backswing);
                   // relaxed after it — downswing blur naturally lowers confidence, and
                   // dropping those anchors decouples the trail's TIMING from the club.
                   hit.conf >= (t < times[2] ? 0.45 : 0.25) {
                    let head = hit.point
                    // Mid/late backswing the clubhead is ABOVE the hands — hip-height
                    // detections there are body false-positives (the club is often half
                    // out of frame at the top and the detector hallucinates low).
                    let midBackswing = t > times[1] + 0.25 && t < times[3] - 0.15
                    if midBackswing, let hp, Double(head.y) < Double(hp.y) - 0.05 {
                        // skip — geometrically impossible
                    } else {
                        trail.append([Double(head.x), Double(head.y), t])
                    }
                }
            }
            reader.cancelReading()
            guard trail.count >= 6 else { return nil }
            return polish(trail, impactTime: times[3],
                          ball: ballAnchor.map { [Double($0.x), Double($0.y)] })
        }

        var window: [(t: Double, plane: UprightPlane)] = []
        var trail: [[Double]] = []
        var lastDir: Double? = nil
        var lastHead: CGPoint? = nil
        var prevHead: CGPoint? = nil
        var missStreak = 0
        var rawIndex = 0

        while let sample = output.copyNextSampleBuffer() {
            defer { rawIndex += 1 }
            if rawIndex % frameStride != 0 { continue }
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            window.append((t, Self.uprightPlane(from: pb, orientation: orientation)))
            if window.count < windowSize { continue }
            if window.count > windowSize { window.removeFirst() }
            let tCur = window[baseline].t
            guard let hp = hands(at: tCur) else { continue }

            if let hit = Self.rayClubhead(prev: window[0].plane, cur: window[baseline].plane,
                                          next: window[2 * baseline].plane, handsUpright: hp,
                                          preferDir: lastDir), hit.score > 300 {
                // Continuity gate: within a club-speed-scaled jump of the last point.
                // (A tight constant-velocity prediction gate REJECTS real fast motion —
                // at 30fps the head legitimately moves 0.25+/sample mid-swing.)
                let accept = lastHead.map {
                    hypot(Double(hit.head.x - $0.x), Double(hit.head.y - $0.y)) < 0.35
                } ?? true
                if accept {
                    trail.append([Double(hit.head.x), Double(hit.head.y), tCur])
                    prevHead = lastHead
                    lastHead = hit.head
                    lastDir = hit.dir
                    missStreak = 0
                } else {
                    missStreak += 1
                }
            } else {
                missStreak += 1
            }
            // Keep hunting through impact blur — the club reappears in the
            // follow-through and the spline bridges the gap. Bail only when it's
            // been gone a long time past the strike.
            if missStreak > 8, !trail.isEmpty, tCur > times[2] { break }
        }
        reader.cancelReading()
        guard trail.count >= 6 else { return nil }
        return polish(trail, impactTime: times[3])
    }

    /// Broadcast-tracer finish: reject outliers against neighbor continuity, inject the
    /// one point physics guarantees (the clubhead is AT THE BALL at impact — bridging
    /// the motion-blur gap with truth instead of a chord), then resample through a
    /// Catmull-Rom spline. The drawn line should read as a swing plane, not a seismograph.
    private static func polish(_ raw: [[Double]], impactTime: Double,
                               ball: [Double]? = nil) -> [[Double]] {
        var pts = raw.sorted { $0[2] < $1[2] }

        // Whole-clip swing selection (Noah's rule), anchored on the TRUE ball position:
        // waggles and pre-swing club adjustments hover near the ball; the real backswing
        // is the FINAL departure from it. Without a ball fix this is skipped entirely —
        // four heuristic versions without an anchor all traded one clip for another.
        if let ball, pts.count > 14 {
            var topIdx = 0
            var topDist = 0.0
            for (i, p) in pts.enumerated() {
                let d = hypot(p[0] - ball[0], p[1] - ball[1])
                if d > topDist { topDist = d; topIdx = i }
            }
            if topIdx > 3, topDist > 0.25 {
                var start = 0
                for j in 0..<topIdx where hypot(pts[j][0] - ball[0], pts[j][1] - ball[1]) < 0.07 {
                    start = j
                }
                if start > 0, pts[start][2] - pts[0][2] > 0.3 {
                    pts.removeFirst(start)
                }
            }
        }

        // The trace ends AT impact — follow-through points only smear the line the
        // player reads. The segmenter's impact TIME can run early, but the ball doesn't
        // move: truncate at the downswing's closest approach to the address clubhead
        // position (= the ball). Time-trim only as a loose backstop.
        pts.removeAll { $0[2] > impactTime + 0.25 }
        if let ball = pts.first, pts.count > 8 {
            var bestI = pts.count - 1
            var bestD = Double.infinity
            for i in (pts.count / 2)..<pts.count {
                let d = hypot(pts[i][0] - ball[0], pts[i][1] - ball[1])
                if d < bestD { bestD = d; bestI = i }
            }
            if bestD < 0.15 { pts = Array(pts[0...bestI]) }
        }

        // Robust outlier pass: a detection that jerks off the line its NEIGHBORS agree on
        // is a misfire, not the club. Each interior point is predicted from the midpoint of
        // its neighbors; deviations far beyond the local step get dropped. The allowance is
        // span-relative, so dense sampling through the top keeps its real curvature.
        for _ in 0..<2 {
            guard pts.count > 6 else { break }
            var keep = [pts[0]]
            for i in 1..<(pts.count - 1) {
                let a = pts[i - 1], b = pts[i], c = pts[i + 1]
                // Predict b by TIME-weighted interpolation between its neighbors — a plain
                // midpoint assumes uniform sampling and flags real points whenever the club
                // is fast and a frame was missed (exactly the impact zone).
                let dt = c[2] - a[2]
                let u = dt > 1e-6 ? (b[2] - a[2]) / dt : 0.5
                let ex = a[0] + (c[0] - a[0]) * u
                let ey = a[1] + (c[1] - a[1]) * u
                let dev = hypot(b[0] - ex, b[1] - ey)
                let span = hypot(c[0] - a[0], c[1] - a[1])
                // Only flagrant jerks die: big absolute deviation AND well beyond what the
                // local step justifies. Anything softer belongs to the spline.
                if dev < max(span * 0.9, 0.028) { keep.append(b) }
            }
            keep.append(pts[pts.count - 1])
            pts = keep
        }
        // Wider-window pass: a run of 2-4 consecutive false points agrees with itself and
        // slips past the ±1 test — but against neighbors THREE steps out it reads as the
        // excursion it is (the hip-height body lock-on). Time-weighted, both directions.
        if pts.count > 8 {
            var keep = Array(pts[0..<3])
            for i in 3..<(pts.count - 3) {
                let a = pts[i - 3], b = pts[i], c = pts[i + 3]
                let dt = c[2] - a[2]
                let u = dt > 1e-6 ? (b[2] - a[2]) / dt : 0.5
                let ex = a[0] + (c[0] - a[0]) * u
                let ey = a[1] + (c[1] - a[1]) * u
                let dev = hypot(b[0] - ex, b[1] - ey)
                let span = hypot(c[0] - a[0], c[1] - a[1])
                if dev < max(span * 0.6, 0.05) { keep.append(b) }
            }
            keep.append(contentsOf: pts[(pts.count - 3)...])
            pts = keep
        }

        // Impact anchor: the address clubhead position ≈ the ball. Only inject when the
        // tracker has nothing near impact (blur gap).
        if let ball = pts.first, !pts.contains(where: { abs($0[2] - impactTime) < 0.08 }) {
            let anchor = [ball[0], ball[1], impactTime]
            let idx = pts.firstIndex(where: { $0[2] > impactTime }) ?? pts.count
            if idx > 0, idx < pts.count { pts.insert(anchor, at: idx) }
        }

        // Spike rejection (two passes): drop a point only when the path goes far OUT
        // AND BACK through it (detour ≫ chord). A chord-deviation test would also kill
        // legitimate sharp curvature — i.e., the top of the swing.
        for _ in 0..<2 {
            guard pts.count > 4 else { break }
            var keep = [pts[0]]
            for i in 1..<(pts.count - 1) {
                let a = pts[i - 1], b = pts[i], c = pts[i + 1]
                let detour = hypot(b[0] - a[0], b[1] - a[1]) + hypot(c[0] - b[0], c[1] - b[1])
                let chord = hypot(c[0] - a[0], c[1] - a[1])
                if detour < max(chord * 2.2, 0.06) { keep.append(b) }
            }
            keep.append(pts[pts.count - 1])
            pts = keep
        }
        guard pts.count >= 4 else { return pts }

        // Catmull-Rom resample (6 samples per segment) — the smooth broadcast line.
        func cr(_ p0: [Double], _ p1: [Double], _ p2: [Double], _ p3: [Double],
                _ t: Double) -> [Double] {
            let t2 = t * t, t3 = t2 * t
            func comp(_ i: Int) -> Double {
                0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t
                       + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
                       + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3)
            }
            return [comp(0), comp(1), comp(2)]
        }
        var out: [[Double]] = []
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i]
            let p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            // Sample each segment at uniform TIME, not uniform parameter: the cubic eases
            // t near anchors, which makes the growing tip DWELL at the last detection and
            // then jump — the "lagged" downswing. Solve u for each target time by bisection
            // (t is monotone along the segment).
            for k in 0..<6 {
                let tk = p1[2] + (p2[2] - p1[2]) * Double(k) / 6
                var lo = 0.0, hi = 1.0
                for _ in 0..<10 {
                    let mid = (lo + hi) / 2
                    if cr(p0, p1, p2, p3, mid)[2] < tk { lo = mid } else { hi = mid }
                }
                out.append(cr(p0, p1, p2, p3, (lo + hi) / 2))
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    /// True BALL anchor: brightest compact blob below the hands at address. The ball
    /// is a small white circle on grass — the one scene object we can find without the
    /// trail (whose own first points may be pre-swing junk). Normalized upright, y-up.
    static func findBall(plane: UprightPlane, handsUpright: CGPoint) -> CGPoint? {
        let w = plane.w, h = plane.h
        let hx = Int(Double(handsUpright.x) * Double(w))
        let hy = Int((1 - Double(handsUpright.y)) * Double(h))   // raster y-down
        let r = max(2, h / 240)                                   // ~ball radius
        var best: (score: Double, x: Int, y: Int)? = nil
        let y0 = min(h - 1, hy + h / 20), y1 = min(h - 1, hy + h / 2)
        let x0 = max(0, hx - w / 4), x1 = min(w - 1, hx + w / 4)
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let c = Double(plane.data[y * w + x])
                guard c > 150 else { x += 2; continue }
                // Bright center, darker ring at 3r — compact blob, not a stripe.
                var ring = 0.0
                var n = 0
                for (dx, dy) in [(3 * r, 0), (-3 * r, 0), (0, 3 * r), (0, -3 * r)] {
                    let rx = x + dx, ry = y + dy
                    guard rx >= 0, ry >= 0, rx < w, ry < h else { continue }
                    ring += Double(plane.data[ry * w + rx])
                    n += 1
                }
                guard n > 2 else { x += 2; continue }
                let contrast = c - ring / Double(n)
                if contrast > 28, contrast > (best?.score ?? 0) {
                    best = (contrast, x, y)
                }
                x += 2
            }
            y += 2
        }
        guard let best else { return nil }
        return CGPoint(x: Double(best.x) / Double(w), y: 1 - Double(best.y) / Double(h))
    }

    /// Rotate + 2× downsample the Y plane into upright raster space.
    static func uprightPlane(from pb: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> UprightPlane {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let rawW = CVPixelBufferGetWidthOfPlane(pb, 0)
        let rawH = CVPixelBufferGetHeightOfPlane(pb, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let buf = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)

        // FULL resolution: a 2-3px shaft downsampled 2× smears below a pixel and its
        // motion signal dies while thick arm edges survive — exactly the wrong bias.
        let rotated = orientation == .left || orientation == .right
        let ds = 1
        let w = (rotated ? rawH : rawW) / ds
        let h = (rotated ? rawW : rawH) / ds
        var data = [UInt8](repeating: 0, count: w * h)
        for py in 0..<h {
            for px in 0..<w {
                let ux = px * ds, uy = py * ds
                let rx: Int, ry: Int
                switch orientation {
                case .right: rx = uy;             ry = rawH - 1 - ux
                case .left:  rx = rawW - 1 - uy;  ry = ux
                case .down:  rx = rawW - 1 - ux;  ry = rawH - 1 - uy
                default:     rx = ux;             ry = uy
                }
                data[py * w + px] = buf[ry * stride + rx]
            }
        }
        return UprightPlane(data: data, w: w, h: h)
    }

    /// One frame: strongest thin MOTION ridge radiating from the hands; far end = head.
    static func rayClubhead(prev: UprightPlane, cur: UprightPlane, next: UprightPlane,
                            handsUpright: CGPoint, preferDir: Double?) -> (head: CGPoint, dir: Double, score: Double)? {
        let w = cur.w, h = cur.h
        guard prev.w == w, next.w == w else { return nil }
        func motion(_ x: Int, _ y: Int) -> Double {
            guard x >= 0, y >= 0, x < w, y < h else { return -1 }
            let i = y * w + x
            let a = abs(Int(cur.data[i]) - Int(prev.data[i]))
            let b = abs(Int(next.data[i]) - Int(cur.data[i]))
            return Double(min(a, b))
        }

        let hx = Double(handsUpright.x) * Double(w)
        let hy = (1 - Double(handsUpright.y)) * Double(h)

        let step = max(2.0, Double(h) / 480)
        let rStart = Double(h) * 0.04
        let rMax = Double(h) * 0.6
        let side = max(4.0, Double(h) / 200)
        let minRidge = 12.0
        let maxGap = 5

        var best: (score: Double, end: Double, dir: Double, firstHit: Double)? = nil
        var theta = 0.0
        while theta < 2 * .pi {
            defer { theta += .pi / 60 }
            let dx = cos(theta), dy = sin(theta)
            let px = -dy, py = dx
            var score = 0.0
            var run = 0
            var gap = 0
            var end = 0.0
            var firstHit = -1.0
            var s = rStart
            while s < rMax {
                let cx = hx + dx * s, cy = hy + dy * s
                let c = motion(Int(cx), Int(cy))
                if c < 0 { break }
                let s1 = motion(Int(cx + px * side), Int(cy + py * side))
                let s2 = motion(Int(cx - px * side), Int(cy - py * side))
                // Thin moving object: hot center, cool sides. A moving torso is hot
                // across all three and cancels out.
                // Thin moving object: hot center, cool sides. A moving torso is hot
                // across all three and cancels out.
                let ridge = c - 0.7 * max(s1, s2)
                if ridge > minRidge {
                    score += ridge
                    run += 1
                    end = s
                    gap = 0
                    if firstHit < 0 { firstHit = s }
                } else if run > 0 {
                    // Only gap-break once the run has started: the hands are the
                    // rotation center, so the shaft is nearly STATIC at the grip and
                    // motion grows toward the head — the ridge starts mid-shaft.
                    gap += 1
                    if gap > maxGap { break }
                }
                s += step
            }
            guard run >= 6, firstHit < rMax * 0.7 else { continue }
            if let preferDir {
                let dd = abs(atan2(sin(theta - preferDir), cos(theta - preferDir)))
                score *= (dd < 0.6 ? 1.35 : (dd > 2.4 ? 0.7 : 1.0))
            }
            if best == nil || score > best!.score { best = (score, end, theta, firstHit) }
        }
        guard let best else { return nil }

        // Refinement: re-walk the winning direction with LATERAL RE-CENTERING — at each
        // step snap to the strongest motion pixel within ±6px perpendicular. A straight
        // 3°-quantized ray drifts off the thin shaft midway and undershoots the head;
        // the snake follows the real line to its tip.
        let dx = cos(best.dir), dy = sin(best.dir)
        let px = -dy, py = dx
        var lat = 0.0
        var head = CGPoint(x: hx + dx * best.end, y: hy + dy * best.end)
        var misses = 0
        var s2 = max(rStart, best.firstHit - 2 * step)
        let latWindow = 6
        while s2 < rMax {
            var bestOff = 0
            var bestVal = -1.0
            for off in -latWindow...latWindow {
                let ox = hx + dx * s2 + px * (lat + Double(off))
                let oy = hy + dy * s2 + py * (lat + Double(off))
                let v = motion(Int(ox), Int(oy))
                if v > bestVal { bestVal = v; bestOff = off }
            }
            if bestVal > minRidge * 0.8 {
                lat += Double(bestOff) * 0.6            // ease toward the line, don't jump
                lat = max(-Double(h) * 0.08, min(Double(h) * 0.08, lat))
                head = CGPoint(x: hx + dx * s2 + px * lat, y: hy + dy * s2 + py * lat)
                misses = 0
            } else {
                misses += 1
                if misses > maxGap { break }
            }
            s2 += step
        }
        let headX = Double(head.x) / Double(w)
        let headY = 1 - Double(head.y) / Double(h)
        return (CGPoint(x: headX, y: headY), best.dir, best.score)
    }
}

// MARK: - Orchestrator

enum SwingAnalyzer {

    /// Full pipeline over a recorded clip. Returns the recording with analysis filled in
    /// (analyzed stays false when no swing could be segmented — UI shows a retake prompt).
    static func analyze(recording: SwingRecording, videoURL: URL,
                        skill: SkillLevel, isLefty: Bool,
                        faults: [SwingFault], limitedMobility: Bool = false) async -> SwingRecording {
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
                                                     viewAngle: rec.viewAngle,
                                                     limitedMobility: limitedMobility)
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
            // Head trail address→impact — powers the drawn-on-video sway box.
            let headRange = phases.address...min(phases.impact, frames.count - 1)
            rec.headTrail = headRange.compactMap { i -> [Double]? in
                guard let h = frames[i].joint(.nose) ?? frames[i].mid(.leftEar, .rightEar)
                else { return nil }
                return [Double(h.x), Double(h.y)]
            }
            // Hand trail: address→finish, downsampled to ≤150 points for the replay ribbon.
            let trailRange = phases.address...min(phases.finish, frames.count - 1)
            let trailStride = max(1, trailRange.count / 150)
            rec.handTrail = trailRange.compactMap { i -> [Double]? in
                guard i % trailStride == 0,
                      let h = frames[i].mid(.leftWrist, .rightWrist)
                          ?? frames[i].joint(.leftWrist) ?? frames[i].joint(.rightWrist)
                else { return nil }
                return [Double(h.x), Double(h.y)]
            }
            // Clubhead trace for BOTH views: down-the-line it IS the ribbon (hands
            // occlude each other); face-on it's the optional second view next to the
            // hand path — the replay lets the player flip between them.
            rec.clubTrail = await SwingClubTracer.trace(videoURL: videoURL,
                                                        frames: frames, phases: phases)
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
