#if DEBUG
import UIKit
import CoreGraphics

/// Replays a saved frame export through the CURRENT LIVE pipeline — FrameNormalizer,
/// PostImpactBallTracker, ShotMetricsCalculator, and the same validation gates as
/// CameraController.computeAnalysis — then adapts the output to the tester's display models.
///
/// The tracker/normalizer/metrics components ARE the live ones (single source of truth: any
/// tuning done here ships to the live pipeline automatically). Only the orchestration is
/// mirrored, because the live path throws its observations away on a discard while the tester
/// must keep them to show WHY a shot was discarded.
final class LiveParityTestRunner {

    struct Output {
        let result: BallTrackingTestResult
        /// "accepted" | "discarded" | "repositioned" plus reason — same gates as live.
        let verdict: String
        /// The lock the tracker was anchored to (from metadata, or auto-derived).
        let lockedBallRect: CGRect?
        let lockUsedAutoDerive: Bool
    }

    func run(sequence: BallTrackingTestSequence, isPutterMode: Bool = false) -> Output {
        let impactIndex = min(sequence.impactFrameIndex, max(0, sequence.frames.count - 1))

        // ── Timestamps: exports always carry them, but synthesize 240fps spacing if a hand-
        // assembled folder has none — velocity fits divide by these.
        let rawTimes = sequence.frames.map { $0.timestamp }
        let degenerate = Set(rawTimes).count < 2
        if degenerate { print("[Replay] timestamps missing — synthesizing 240fps spacing") }
        // Dual-res reconstruction (July 17): archives written after the 720px migration
        // hold hi-res frames — rebuild the 360 analysis frame from them (all detector
        // thresholds live in 360 space) and keep the original as hiRes for the V2
        // measurement stage. Legacy 360 archives pass through untouched.
        if let cg0 = sequence.frames.first?.image.cgImage {
            print("[Replay] frame0 pixel width=\(cg0.width)")
        }
        let captured: [CapturedFrame] = sequence.frames.enumerated().map { idx, f in
            let ts = degenerate ? Double(idx) / 240.0 : f.timestamp
            guard let cg = f.image.cgImage, cg.width > 400 else {
                return CapturedFrame(image: f.image, timestamp: ts)
            }
            let scale = 360.0 / CGFloat(cg.width)
            let size = CGSize(width: 360, height: CGFloat(cg.height) * scale)
            let fmt = UIGraphicsImageRendererFormat.default()
            fmt.scale = 1
            let lo = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
                f.image.draw(in: CGRect(origin: .zero, size: size))
            }
            return CapturedFrame(image: lo, timestamp: ts, hiRes: f.image)
        }

        // ── Normalize exactly like live (darkened-high-contrast is what tracking scans).
        let normalizer = FrameNormalizer()
        var darkened = [UIImage?](repeating: nil, count: captured.count)
        darkened.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: captured.count) { i in
                buf[i] = normalizer.normalizedImage(from: captured[i].image, mode: .darkenedHighContrast)
            }
        }
        let originTimestamp = captured[impactIndex].timestamp
        let prelimFrames: [AnalyzedShotFrame] = captured.enumerated().map { idx, frame in
            AnalyzedShotFrame(
                frameIndex: idx,
                timestamp: frame.timestamp,
                relativeTime: frame.timestamp - originTimestamp,
                originalFrame: frame,
                brightenedImage: nil,
                darkenedHighContrastImage: darkened[idx],
                ballObservation: nil,
                debugInfo: nil
            )
        }

        // ── Lock: prefer the recorded live lock; old exports without one get an auto-derived
        // lock from the pre-impact frames (ball is stationary there by definition).
        var lockAutoDerived = false
        var lockedBallRect = sequence.lockedBallRect
        if lockedBallRect == nil {
            lockedBallRect = Self.autoDeriveLock(darkened: darkened, impactIndex: impactIndex)
            lockAutoDerived = lockedBallRect != nil
            if let r = lockedBallRect {
                print(String(format: "[Replay] AUTO-LOCK (%.3f,%.3f %.3fx%.3f) — export had no locked_ball_rect",
                             r.minX, r.minY, r.width, r.height))
            } else {
                print("[Replay] WARNING: no locked_ball_rect in export and auto-lock failed — tracking cannot anchor")
            }
        }
        // Same 2.5× expansion as CameraController.expandedImpactROI.
        let lockedImpactROI = sequence.lockedImpactROI ?? lockedBallRect.map { r -> CGRect in
            CGRect(x: r.midX - r.width * 1.25, y: r.midY - r.height * 1.25,
                   width: r.width * 2.5, height: r.height * 2.5)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        // ── Track with the live tracker (prints [TrackDebug]/[TrackSummary] itself).
        var observationMap: [Int: ShotBallObservation] = [:]
        var debugInfoMap: [Int: ShotFrameDebugInfo] = [:]
        var effectiveImpactIndex = impactIndex
        var fallbackImpactIndex = impactIndex
        var impactDetectionReason = "no_locked_ball_rect"
        var initialBallCenter: CGPoint? = nil
        var movementThresholdNorm: CGFloat = 0
        if let lockedRect = lockedBallRect {
            let tracker = PostImpactBallTracker(
                configuration: isPutterMode ? .putterPreset : PostImpactBallTracker.Configuration()
            )
            let trackingResult = tracker.track(
                frames: prelimFrames,
                lockedBallRect: lockedRect,
                impactFrameIndex: impactIndex
            )
            effectiveImpactIndex = trackingResult.detectedImpactFrameIndex
            fallbackImpactIndex = trackingResult.fallbackImpactFrameIndex
            impactDetectionReason = trackingResult.impactDetectionReason
            initialBallCenter = trackingResult.initialBallCenter
            movementThresholdNorm = trackingResult.movementThresholdNorm
            for obs in trackingResult.observations { observationMap[obs.frameIndex] = obs }
            for info in trackingResult.debugInfos { debugInfoMap[info.frameIndex] = info }
        }

        // V2-primary track — the SAME shared integration the live pipeline runs, so the
        // sweep measures exactly what ships.
        let v2Primary = V2PrimaryTrack.run(
            prelimFrames: prelimFrames,
            legacyObservations: observationMap,
            lockedBallRect: lockedBallRect,
            legacyImpactIndex: effectiveImpactIndex,
            impactHint: impactIndex,
            isPutterMode: isPutterMode
        )
        if v2Primary.active {
            observationMap = v2Primary.observations
            effectiveImpactIndex = v2Primary.impactFrameIndex
            let v2ImpactNote = v2Primary.v2?.notes.first(where: { $0.hasPrefix("impact=") })
            impactDetectionReason = v2ImpactNote.map { "v2_" + $0 } ?? "v2_ball_motion"
            print("[V2Primary] track active — \(v2Primary.observations.values.filter { $0.centerX != nil }.count) sightings, impact f\(effectiveImpactIndex)")
        }

        // Parity with computeAnalysis: universal ballistic gap fill on the final track.
        observationMap = V2PrimaryTrack.gapFill(observationMap,
                                                impactIndex: effectiveImpactIndex,
                                                frames: prelimFrames)

        let finalFrames: [AnalyzedShotFrame] = prelimFrames.map { frame in
            AnalyzedShotFrame(
                frameIndex: frame.frameIndex,
                timestamp: frame.timestamp,
                relativeTime: frame.relativeTime,
                originalFrame: frame.originalFrame,
                brightenedImage: frame.brightenedImage,
                darkenedHighContrastImage: frame.darkenedHighContrastImage,
                ballObservation: observationMap[frame.frameIndex],
                debugInfo: debugInfoMap[frame.frameIndex]
            )
        }

        let baseResult = ShotAnalysisResult(
            frames: finalFrames,
            impactFrameIndex: effectiveImpactIndex,
            lockedBallRect: lockedBallRect,
            lockedImpactROI: lockedImpactROI,
            createdAt: Date(),
            fallbackImpactFrameIndex: fallbackImpactIndex,
            detectedImpactFrameIndex: effectiveImpactIndex,
            impactDetectionReason: impactDetectionReason,
            initialBallCenter: initialBallCenter,
            movementThresholdNorm: movementThresholdNorm,
            v2Output: v2Primary.v2
        )

        let metrics = ShotMetricsCalculator().calculate(for: baseResult, isPutterMode: isPutterMode)

        // ── Verdict: the exact live gates, but the observations/metrics survive for display.
        var verdict = "accepted"
        if let impactROI = lockedImpactROI {
            let lastTracked: CGPoint? = finalFrames
                .filter { $0.frameIndex > effectiveImpactIndex }
                .compactMap { f -> CGPoint? in
                    guard let o = f.ballObservation, let x = o.centerX, let y = o.centerY else { return nil }
                    return CGPoint(x: x, y: y)
                }
                .last
            if let p = lastTracked, impactROI.contains(p) {
                verdict = "repositioned — ball still inside setup area after capture"
            }
        }
        if verdict == "accepted", let m = metrics {
            let speedOK = m.ballLaunch.ballSpeedMph.map { $0 >= 0.5 && $0 <= 200 } ?? true
            let hlaOK   = m.ballLaunch.hlaDegrees.map { abs($0) <= 75 } ?? true
            let carryOK = m.distance.carryYards.map { $0 >= 0 && $0 <= 375 } ?? true
            if !(speedOK && hlaOK && carryOK) {
                verdict = String(format: "discarded — implausible (speed=%.1f hla=%.1f carry=%.1f)",
                                 m.ballLaunch.ballSpeedMph ?? 0, m.ballLaunch.hlaDegrees ?? 0,
                                 m.distance.carryYards ?? 0)
            } else if !isPutterMode, let speed = m.ballLaunch.ballSpeedMph, speed < 3.0 {
                verdict = String(format: "repositioned — %.1f mph without putter selected", speed)
            }
        } else if verdict == "accepted" && metrics == nil {
            verdict = "discarded — metrics unavailable"
        }
        print("[Replay] live-parity verdict: \(verdict)")

        // ── Adapt to tester display models.
        let testObservations: [BallTrackingTestObservation] = finalFrames.map { f in
            let obs = f.ballObservation
            let dbgInfo = f.debugInfo.map { d in
                BallTrackingFrameDebug(
                    frameIndex: d.frameIndex,
                    searchROI: d.searchROI,
                    searchCenterSource: d.searchCenterSource ?? "",
                    searchScale: d.searchScale ?? 0,
                    candidates: [],
                    selectedCandidate: nil,
                    reason: d.rejectionReason
                )
            }
            return BallTrackingTestObservation(
                frameIndex: f.frameIndex,
                centerX: obs?.centerX,
                centerY: obs?.centerY,
                diameter: obs?.finalDiameter ?? obs?.diameter,
                candidateDiameter: obs?.candidateDiameter,
                maskRefinedDiameter: obs?.refinedDiameter,
                smoothedDiameter: obs?.smoothedDiameter,
                maskBoundsRect: nil,
                maskWhitePixelCount: obs?.maskWhitePixelCount ?? 0,
                diameterDebugReason: obs?.diameterDebugReason ?? "",
                maskPreviewImage: nil,
                maskCropNormRect: nil,
                maskCandidateDiamInCrop: nil,
                maskRefinedDiamInCrop: nil,
                confidence: obs?.confidence ?? 0,
                debugReason: obs?.debugReason ?? "no_pixel_data",
                frameDebug: dbgInfo
            )
        }
        let tracked = testObservations.filter { $0.centerX != nil }
        let avgConf = tracked.isEmpty ? 0 : tracked.map(\.confidence).reduce(0, +) / Double(tracked.count)

        let result = BallTrackingTestResult(
            observations: testObservations,
            trackedCount: tracked.count,
            missingCount: testObservations.count - tracked.count,
            averageConfidence: avgConf,
            detectedImpactFrameIndex: effectiveImpactIndex,
            fallbackImpactFrameIndex: fallbackImpactIndex,
            impactDetectionReason: impactDetectionReason,
            initialBallCenter: initialBallCenter,
            movementThresholdNorm: movementThresholdNorm,
            metrics: metrics.map(Self.mapMetrics)
        )
        dumpReplayJSON(sequence: sequence, result: result, verdict: verdict,
                       lockedBallRect: lockedBallRect, lockedImpactROI: lockedImpactROI,
                       metrics: metrics, lockAutoDerived: lockAutoDerived,
                       v2Notes: v2Primary.v2?.notes ?? [])

        return Output(result: result, verdict: verdict,
                      lockedBallRect: lockedBallRect, lockUsedAutoDerive: lockAutoDerived)
    }

    /// Writes the full replay result to Documents/ReplayResults/<shot>.json so external
    /// viewers (tools/replay_viewer.py) can render frames + overlays without an Apple UI —
    /// the tracking itself always stays in this Swift pipeline (parity with the live app).
    private func dumpReplayJSON(sequence: BallTrackingTestSequence,
                                result: BallTrackingTestResult,
                                verdict: String,
                                lockedBallRect: CGRect?,
                                lockedImpactROI: CGRect?,
                                metrics: ShotMetricsResult?,
                                lockAutoDerived: Bool,
                                v2Notes: [String] = []) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("ReplayResults", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func rect(_ r: CGRect?) -> Any {
            r.map { ["x": Double($0.minX), "y": Double($0.minY), "w": Double($0.width), "h": Double($0.height)] } ?? NSNull()
        }

        let frames: [[String: Any]] = result.observations.map { o in
            var d: [String: Any] = ["i": o.frameIndex, "reason": o.debugReason]
            if let x = o.centerX, let y = o.centerY {
                d["cx"] = Double(x); d["cy"] = Double(y)
                d["d"] = Double(o.diameter ?? 0)
                d["conf"] = o.confidence
            }
            if let fd = o.frameDebug {
                d["roi"] = rect(fd.searchROI)
                if let r = fd.reason { d["rej"] = r }
            }
            return d
        }
        let clubs: [[String: Any]] = (metrics?.clubObservations ?? []).compactMap { c in
            guard c.centerX != nil || c.clubBoundingBox != nil else { return nil }
            var d: [String: Any] = ["i": c.frameIndex, "conf": c.confidence, "mode": c.detectionMode]
            if let x = c.centerX, let y = c.centerY { d["cx"] = Double(x); d["cy"] = Double(y) }
            if let x = c.leadingEdgeX, let y = c.leadingEdgeY { d["lex"] = Double(x); d["ley"] = Double(y) }
            d["box"] = rect(c.clubBoundingBox)
            return d
        }
        var m: [String: Any] = [:]
        if let mm = metrics {
            m["ballSpeedMph"] = mm.ballLaunch.ballSpeedMph ?? NSNull()
            m["hlaDisplay"]   = mm.ballLaunch.hlaDisplay
            m["vlaDegrees"]   = mm.ballLaunch.vlaDegrees ?? NSNull()
            m["ballPoints"]   = mm.ballLaunch.pointsUsed
            m["carryYards"]   = mm.distance.carryYards ?? NSNull()
            m["totalYards"]   = mm.distance.totalYards ?? NSNull()
            m["clubSpeedMph"] = mm.club.clubSpeedMph ?? NSNull()
            m["warnings"]     = mm.warnings
        }
        let payload: [String: Any] = [
            "source": sequence.sourceName,
            "verdict": verdict,
            "lockAutoDerived": lockAutoDerived,
            "impactDetected": result.detectedImpactFrameIndex,
            "impactFallback": result.fallbackImpactFrameIndex,
            "impactReason": result.impactDetectionReason,
            "lockedBallRect": rect(lockedBallRect),
            "lockedImpactROI": rect(lockedImpactROI),
            "frames": frames,
            "club": clubs,
            "metrics": m,
            "v2Notes": v2Notes
        ]
        let url = dir.appendingPathComponent("\(sequence.sourceName).json")
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            print("[Replay] wrote \(url.lastPathComponent) → \(dir.path)")
        }
    }

    // MARK: - Auto-lock (exports saved before metadata.json carried locked_ball_rect)

    /// Finds the stationary white ball in the pre-impact frames using the live white-ball
    /// criterion (bright + channel spread ≤ 72). The blob must appear at the same spot in two
    /// pre-impact frames to qualify — glare flickers, the ball doesn't.
    private static func autoDeriveLock(darkened: [UIImage?], impactIndex: Int) -> CGRect? {
        let firstIdx = 0
        let secondIdx = max(0, min(impactIndex - 2, 5))
        guard let first = darkened[safe: firstIdx].flatMap({ $0 }),
              let second = darkened[safe: secondIdx].flatMap({ $0 }),
              let a = brightestBallBlob(in: first),
              let b = brightestBallBlob(in: second) else { return nil }
        let drift = hypot(a.midX - b.midX, a.midY - b.midY)
        guard drift < 0.03 else {
            print(String(format: "[Replay] auto-lock rejected: candidate moved %.3f between pre frames", drift))
            return nil
        }
        // Live locked rects are the detector's 1.35×-padded box — match that so the tracker's
        // diameter expectations line up.
        let side = max(a.width, a.height) * 1.35
        return CGRect(x: a.midX - side / 2, y: a.midY - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Brightest compact white blob of plausible ball size in the frame (normalized rect).
    private static func brightestBallBlob(in image: UIImage) -> CGRect? {
        guard let pd = pixelBytes(from: image) else { return nil }
        let (bytes, width, height) = pd
        let stride = 2
        let cols = width / stride, rows = height / stride
        var bright = [Bool](repeating: false, count: cols * rows)
        for row in 0..<rows {
            let base = row * stride * width * 4
            for col in 0..<cols {
                let i = base + col * stride * 4
                let r = Int(bytes[i]); let g = Int(bytes[i + 1]); let b = Int(bytes[i + 2])
                let brightness = (r + g + b) / 3
                let spread = max(r, max(g, b)) - min(r, min(g, b))
                // White criterion, plus the lime range-ball signature (collapsed blue).
                bright[row * cols + col] = (brightness >= 125 && spread <= 72)
                    || (brightness >= 130 && g - b >= 110 && r < g && r * 2 > g)
            }
        }
        var visited = [Bool](repeating: false, count: cols * rows)
        var best: (rect: CGRect, score: Int)? = nil
        for start in 0..<(cols * rows) {
            guard bright[start], !visited[start] else { continue }
            var queue = [start]; var head = 0
            visited[start] = true
            var minC = cols, maxC = 0, minR = rows, maxR = 0, count = 0
            while head < queue.count {
                let idx = queue[head]; head += 1
                let c = idx % cols, r = idx / cols
                count += 1
                minC = min(minC, c); maxC = max(maxC, c)
                minR = min(minR, r); maxR = max(maxR, r)
                for (dc, dr) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nc = c + dc, nr = r + dr
                    guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
                    let ni = nr * cols + nc
                    if bright[ni], !visited[ni] { visited[ni] = true; queue.append(ni) }
                }
            }
            guard count >= 12 else { continue }
            let w = CGFloat((maxC - minC + 1) * stride) / CGFloat(width)
            let h = CGFloat((maxR - minR + 1) * stride) / CGFloat(height)
            let aspect = w / max(h, 1e-6)
            guard w >= 0.015, w <= 0.11, h >= 0.015, h <= 0.16, aspect >= 0.45, aspect <= 2.0 else { continue }
            let rect = CGRect(x: CGFloat(minC * stride) / CGFloat(width),
                              y: CGFloat(minR * stride) / CGFloat(height),
                              width: w, height: h)
            if best == nil || count > best!.score { best = (rect, count) }
        }
        return best?.rect
    }

    private static func pixelBytes(from image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return (bytes, width, height)
    }

    // MARK: - Live → Experimental metrics mapping (shapes are 1:1; live is the source of truth)

    private static func mapMetrics(_ m: ShotMetricsResult) -> ExperimentalShotMetricsResult {
        ExperimentalShotMetricsResult(
            detectedImpactFrameIndex: m.detectedImpactFrameIndex,
            fallbackImpactFrameIndex: m.fallbackImpactFrameIndex,
            faceFrameIndex: m.faceFrameIndex,
            calibration: ExperimentalCameraCalibration(
                horizontalFOVDegrees: m.calibration.horizontalFOVDegrees,
                verticalFOVDegrees: m.calibration.verticalFOVDegrees,
                imageWidthPixels: m.calibration.imageWidthPixels,
                imageHeightPixels: m.calibration.imageHeightPixels,
                realBallDiameterMeters: m.calibration.realBallDiameterMeters,
                cameraHeightMeters: m.calibration.cameraHeightMeters,
                cameraTiltDegrees: m.calibration.cameraTiltDegrees
            ),
            zeroDegreeReferenceAngleDegrees: m.zeroDegreeReferenceAngleDegrees,
            ballLaunch: ExperimentalBallLaunchMetrics(
                ballSpeedMph: m.ballLaunch.ballSpeedMph,
                hlaDegrees: m.ballLaunch.hlaDegrees,
                hlaDisplay: m.ballLaunch.hlaDisplay,
                hla3DRawDegrees: m.ballLaunch.hla3DRawDegrees,
                vlaDegrees: m.ballLaunch.vlaDegrees,
                vlaRawDegrees: nil,
                hlaReferenceAngleDegrees: m.ballLaunch.hlaReferenceAngleDegrees,
                ballMovementDx: m.ballLaunch.ballMovementDx,
                ballMovementDy: m.ballLaunch.ballMovementDy,
                hlaForwardComponent: m.ballLaunch.hlaForwardComponent,
                hlaLateralComponent: m.ballLaunch.hlaLateralComponent,
                pointsUsed: m.ballLaunch.pointsUsed,
                quality: m.ballLaunch.quality,
                method: m.ballLaunch.method,
                warnings: m.ballLaunch.warnings
            ),
            club: ExperimentalClubMetrics(
                clubSpeedMph: m.club.clubSpeedMph,
                pointsUsed: m.club.pointsUsed,
                quality: m.club.quality,
                method: m.club.method,
                warnings: m.club.warnings,
                speedFrameIndices: m.club.speedFrameIndices
            ),
            smashFactor: m.smashFactor,
            rawSmashFactor: m.rawSmashFactor,
            smashFactorClamped: m.smashFactorClamped,
            distance: ExperimentalDistanceEstimate(
                idealCarryYards: m.distance.idealCarryYards,
                carryCorrectionFactor: m.distance.carryCorrectionFactor,
                carryYards: m.distance.carryYards,
                rolloutYards: m.distance.rolloutYards,
                totalYards: m.distance.totalYards,
                rolloutFraction: m.distance.rolloutFraction,
                vlaBucket: m.distance.vlaBucket,
                method: m.distance.method,
                warnings: m.distance.warnings
            ),
            spin: ExperimentalSpinEstimate(
                estimatedBackspinRpm: m.spin.estimatedBackspinRpm,
                estimatedSidespinRpmSigned: m.spin.estimatedSidespinRpmSigned,
                estimatedSidespinDisplay: m.spin.estimatedSidespinDisplay,
                estimatedSpinAxisDegreesSigned: m.spin.estimatedSpinAxisDegreesSigned,
                estimatedSpinAxisDisplay: m.spin.estimatedSpinAxisDisplay,
                spinEstimateMethod: m.spin.spinEstimateMethod,
                warnings: m.spin.warnings
            ),
            clubPath: ExperimentalClubPathEstimate(
                clubPathDegreesSigned: m.clubPath.clubPathDegreesSigned,
                clubPathDisplay: m.clubPath.clubPathDisplay,
                confidence: m.clubPath.confidence,
                method: m.clubPath.method,
                warnings: m.clubPath.warnings
            ),
            faceAngle: ExperimentalFaceAngleEstimate(
                faceAngleDegreesSigned: m.faceAngle.faceAngleDegreesSigned,
                faceAngleDisplay: m.faceAngle.faceAngleDisplay,
                faceToPathDegreesSigned: m.faceAngle.faceToPathDegreesSigned,
                faceToPathDisplay: m.faceAngle.faceToPathDisplay,
                confidence: m.faceAngle.confidence,
                method: m.faceAngle.method,
                warnings: m.faceAngle.warnings
            ),
            ball3DObservations: m.ball3DObservations.map {
                ExperimentalBall3DObservation(
                    frameIndex: $0.frameIndex, timestamp: $0.timestamp, relativeTime: $0.relativeTime,
                    imageX: $0.imageX, imageY: $0.imageY, diameterNorm: $0.diameterNorm,
                    diameterPixels: $0.diameterPixels, positionMeters: $0.positionMeters,
                    confidence: $0.confidence
                )
            },
            clubObservations: m.clubObservations.map {
                ExperimentalClubObservation(
                    frameIndex: $0.frameIndex, timestamp: $0.timestamp, relativeTime: $0.relativeTime,
                    centerX: $0.centerX, centerY: $0.centerY,
                    leadingEdgeX: $0.leadingEdgeX, leadingEdgeY: $0.leadingEdgeY,
                    clubBoundingBox: $0.clubBoundingBox, confidence: $0.confidence,
                    searchROI: $0.searchROI,
                    ballExclusionCenterX: $0.ballExclusionCenterX,
                    ballExclusionCenterY: $0.ballExclusionCenterY,
                    ballExclusionDiameter: $0.ballExclusionDiameter,
                    debugReason: $0.debugReason, detectionMode: $0.detectionMode,
                    ballExclusionWasApplied: $0.ballExclusionWasApplied,
                    frameDifferenceWasUsed: $0.frameDifferenceWasUsed
                )
            },
            warnings: m.warnings
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
