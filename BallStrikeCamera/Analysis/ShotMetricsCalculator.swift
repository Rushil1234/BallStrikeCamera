import Foundation
import UIKit
import simd

struct BallLaunchMetrics {
    // var: the V2 engine (label-trained, July 2026) may replace this after legacy
    // calculation when its confidence gate passes.
    var ballSpeedMph: Double?
    let hlaDegrees: Double?
    let hlaDisplay: String
    let hla3DRawDegrees: Double?
    var vlaDegrees: Double?
    let hlaReferenceAngleDegrees: Double
    let ballMovementDx: Double?
    let ballMovementDy: Double?
    let hlaForwardComponent: Double?
    let hlaLateralComponent: Double?
    let pointsUsed: Int
    let quality: Double
    let method: String
    let warnings: [String]
    // VLA model fields
    var vlaLegacyDegrees: Double? = nil
    var vlaTrainedModelDegrees: Double? = nil
    var vlaFinalDegrees: Double? = nil
    var vlaModelUsed: String = "physics_3d"
    var vlaModelFile: String? = nil
    var vlaModelFeaturesUsed: [String] = []
    var vlaModelFeatureValues: [String: Double] = [:]
    var vlaModelWarnings: [String] = []
    var vlaWasClamped: Bool = false
}

struct ClubMetrics {
    // var: replaced by the V2 arc-fit head when confident (see calculate()).
    var clubSpeedMph: Double?
    let pointsUsed: Int
    let quality: Double
    var method: String
    let warnings: [String]
    let speedFrameIndices: [Int]
}

struct ShotMetricsResult {
    let detectedImpactFrameIndex: Int
    let fallbackImpactFrameIndex: Int
    let calibration: CameraCalibration
    let zeroDegreeReferenceAngleDegrees: Double
    let ballLaunch: BallLaunchMetrics
    let club: ClubMetrics
    let smashFactor: Double?
    var rawSmashFactor: Double? = nil
    var smashFactorClamped: Bool = false
    var faceFrameIndex: Int = 0
    var faceFrameReason: String = "detectedImpactFrameIndex_plus_one"
    let distance: DistanceEstimate
    let spin: SpinEstimate
    let clubPath: ClubPathEstimate
    let faceAngle: FaceAngleEstimate
    let ball3DObservations: [Ball3DObservation]
    let clubObservations: [ClubObservation]
    let warnings: [String]
    /// Putt-mode readout (ground-plane roll + putter-head pass). Nil for full shots.
    var putt: PuttReadout? = nil
}

struct ShotMetricsCalculator {
    struct Configuration {
        var minimumBallPoints: Int = 2
        var preferredBallPointLimit: Int = 6
        var minimumClubPoints: Int = 2
        var lowConfidenceWarningThreshold: Double = 0.45
        // Below this ball speed the shot is a putt/roll: the ball stays on the ground with no real
        // vertical launch. At these speeds the per-frame horizontal travel is comparable to
        // tracking noise, so the computed VLA becomes unstable and reads spuriously high. Force
        // such shots to 0° VLA.
        var puttBallSpeedThresholdMph: Double = 12.0
    }

    let configuration: Configuration
    let clubTracker: EnsembleBFSClubTracker
    let distanceEstimator: DistanceEstimator
    let spinEstimator: SpinEstimator
    let clubPathFaceEstimator: ClubPathFaceEstimator

    init(
        configuration: Configuration = Configuration(),
        clubTracker: EnsembleBFSClubTracker = EnsembleBFSClubTracker(),
        distanceEstimator: DistanceEstimator = DistanceEstimator(),
        spinEstimator: SpinEstimator = SpinEstimator(),
        clubPathFaceEstimator: ClubPathFaceEstimator = ClubPathFaceEstimator()
    ) {
        self.configuration = configuration
        self.clubTracker = clubTracker
        self.distanceEstimator = distanceEstimator
        self.spinEstimator = spinEstimator
        self.clubPathFaceEstimator = clubPathFaceEstimator
    }

    func calculate(
        for analysis: ShotAnalysisResult,
        zeroDegreeReferenceAngleDegrees: Double = 0.0,
        carryCorrectionFactor: Double = 0.75,
        isPutterMode: Bool = false
    ) -> ShotMetricsResult? {
        print("Shot metrics calculation started")
        ModelResourceLoader.logBundleCheck()
        let flightModel   = FlightModelPredictor.autoLoad()

        guard let calibration = makeCalibration(from: analysis) else {
            print("Shot metrics skipped: no frame image dimensions")
            return nil
        }

        print(String(format: "Camera calibration: fx=%.1f, fy=%.1f, fovX=%.1f, fovY=%.1f",
                     calibration.focalLengthPixelsX,
                     calibration.focalLengthPixelsY,
                     calibration.horizontalFOVDegrees,
                     calibration.verticalFOVDegrees))
        print(calibration.calibrationWarning)

        let ball3DObservations = makeBall3DObservations(from: analysis, calibration: calibration)
        print("3D ball observations: \(ball3DObservations.count)")

        var ballLaunch = calculateBallLaunch(
            ball3DObservations: ball3DObservations,
            impactFrameIndex: analysis.detectedImpactFrameIndex,
            zeroDegreeAngleDegrees: zeroDegreeReferenceAngleDegrees,
            calibration: calibration,
            isPutterMode: isPutterMode
        )

        // Putter selection forces putt handling deterministically; otherwise fall back to the
        // speed-inferred heuristic (e.g. a chip that dies fast without a putter selected).
        let isPuttShot = isPutterMode || (ballLaunch.ballSpeedMph ?? 0) < configuration.puttBallSpeedThresholdMph
        if isPuttShot {
            // Putt/roll: VLA is already 0 from calculateBallLaunch — never run the model, which
            // would otherwise predict a spurious launch angle for a ball that just rolls.
            ballLaunch.vlaLegacyDegrees       = 0
            ballLaunch.vlaTrainedModelDegrees = nil
            ballLaunch.vlaFinalDegrees        = 0
            ballLaunch.vlaDegrees             = 0
            ballLaunch.vlaModelUsed           = "putt_no_vla"
            ballLaunch.vlaModelWarnings       = [String(format:
                "VLA forced to 0° — ball speed %.1f mph is in the putt/roll range (< %.0f).",
                ballLaunch.ballSpeedMph ?? 0, configuration.puttBallSpeedThresholdMph)]
            print(String(format: "[VLA] putt/roll: ball speed %.1f mph < %.0f → VLA 0° (model skipped)",
                         ballLaunch.ballSpeedMph ?? 0, configuration.puttBallSpeedThresholdMph))
        } else if let growthVLA = diameterGrowthVLA(analysis: analysis) {
            // Physics beats the trained model here: the model was fit on footage from a
            // different tripod height/lighting and reads 45-50° on near-flat shots. The ball's
            // apparent diameter directly encodes height (it grows as the ball rises toward the
            // camera; constant size = flat flight), which needs no training data at all.
            ballLaunch.vlaLegacyDegrees       = ballLaunch.vlaDegrees
            ballLaunch.vlaTrainedModelDegrees = nil
            ballLaunch.vlaFinalDegrees        = growthVLA
            ballLaunch.vlaDegrees             = growthVLA
            ballLaunch.vlaModelUsed           = "diameter_growth_physics"
            ballLaunch.vlaModelWarnings       = ["VLA measured from apparent ball-diameter growth (camera-height geometry); trained model bypassed."]
            print(String(format: "[VLA] diameter-growth physics: %.1f°", growthVLA))
        } else {
            // No usable diameter-growth measurement. Do NOT fall back to the trained model —
            // it was fit on a different rig and reads 45-55° on near-flat shots, and the
            // physics-3D estimate relies on the default FOV calibration (equally untrusted).
            // Reporting no VLA is more honest than reporting a wild one; distance falls back
            // to its low-information paths.
            ballLaunch.vlaLegacyDegrees       = ballLaunch.vlaDegrees
            ballLaunch.vlaTrainedModelDegrees = nil
            ballLaunch.vlaFinalDegrees        = nil
            ballLaunch.vlaDegrees             = nil
            ballLaunch.vlaModelUsed           = "unavailable"
            ballLaunch.vlaModelWarnings       = ["VLA unavailable: too few ball-size samples for diameter-growth measurement (trained model intentionally not used)."]
            print("[VLA] unavailable — insufficient diameter samples; trained model bypassed")
        }

        let ballDepthM = nearestBallDepth(ball3DObservations, impactFrameIndex: analysis.detectedImpactFrameIndex)
        // Club data is only physically meaningful BEFORE impact. At the impact frame itself the
        // clubhead blob merges with/overtakes the ball ("jumped in front of the ball"), and
        // afterward it sweeps through the flight path — both polluted club speed/path fits and
        // drew misleading overlays in the replay. Drop everything from impact onward.
        // Putt/roll shots skip club tracking entirely: the ensemble BFS sweep is the most
        // expensive stage of analysis and putts never produced usable club metrics anyway.
        let clubObservations: [ClubObservation]
        if isPuttShot {
            clubObservations = []
        } else {
            let ebfs = clubTracker.track(analysis: analysis,
                                         ballSpeedMph: ballLaunch.ballSpeedMph,
                                         ballDepthM: ballDepthM)
                .filter { $0.frameIndex < analysis.detectedImpactFrameIndex }
            // V2's GBT club sightings fill the frames EnsembleBFS skipped: EBFS is precise
            // when it fires (4.2px median vs the 758 hand labels) but covered only 29% of
            // labeled approach frames, starving every club path/speed fit down to 1-2
            // points. EBFS keeps priority where both exist (it carries bbox/leading edge).
            var union = ebfs
            if let v2 = analysis.v2Output {
                let have = Set(ebfs.map(\.frameIndex))
                let frameByIdx = Dictionary(uniqueKeysWithValues: analysis.frames.map { ($0.frameIndex, $0) })
                for c in v2.clubObservations
                where !have.contains(c.frameIndex) && c.frameIndex < analysis.detectedImpactFrameIndex {
                    guard let f = frameByIdx[c.frameIndex] else { continue }
                    union.append(ClubObservation(
                        frameIndex: c.frameIndex,
                        timestamp: f.timestamp,
                        relativeTime: f.relativeTime,
                        centerX: CGFloat(c.cxNorm),
                        centerY: CGFloat(c.cyNorm),
                        leadingEdgeX: CGFloat(c.cxNorm),
                        leadingEdgeY: CGFloat(c.cyNorm),
                        clubBoundingBox: nil,
                        confidence: c.confidence,
                        searchROI: nil,
                        ballExclusionCenterX: nil,
                        ballExclusionCenterY: nil,
                        ballExclusionDiameter: nil,
                        debugReason: "v2_club_gbt",
                        detectionMode: "v2_gbt",
                        ballExclusionWasApplied: false,
                        frameDifferenceWasUsed: false
                    ))
                }
                union.sort { $0.frameIndex < $1.frameIndex }
            }
            // (Club gap interpolation was tried July 16 and REMOVED: the head is on a
            // tight ARC at ~26px/frame near impact, so linear fills landed >15px off —
            // off-target 17→29 with zero coverage gain. Ball gap fill is different: a
            // ballistic ball IS linear over 1-2 frames.)
            clubObservations = enforceClubMonotonicity(
                union,
                impactFrameIndex: analysis.detectedImpactFrameIndex,
                ballCenterX: analysis.initialBallCenter?.x ?? analysis.lockedBallRect?.midX
            )
        }
        var clubMetrics = calculateClubMetrics(
            clubObservations: clubObservations,
            ball3DObservations: ball3DObservations,
            calibration: calibration,
            impactFrameIndex: analysis.detectedImpactFrameIndex
        )

        // ── V2 engine (label-trained, Garmin-fit — July 2026). When it produces a
        // confident result its ball speed / VLA / club speed REPLACE the legacy values
        // before smash, distance, and spin derive from them. Legacy numbers stay as
        // the fallback whenever V2 withholds, and everything is tagged in warnings so
        // offline scoring can tell which path produced each shot. Kill switch:
        // UserDefaults "tc_v2_metrics" = false.
        var v2Warnings = [String]()
        let v2Start = CFAbsoluteTimeGetCurrent()
        if !isPutterMode,
           UserDefaults.standard.object(forKey: "tc_v2_metrics") as? Bool ?? true,
           V2Engine.isAvailable,
           // The V2-primary track already ran the engine once per shot — reuse its result
           // instead of repeating the most expensive stage of the whole analysis.
           let v2 = analysis.v2Output ?? V2Engine.run(frames: analysis.frames,
                                                      lockedBallRect: analysis.lockedBallRect,
                                                      impactHint: analysis.fallbackImpactFrameIndex) {
            // Wall-clock visibility: V2's per-frame image work is the slowest stage of the
            // whole pipeline and ~20× slower in unoptimized builds — a multi-second number
            // here means the build is -Onone, not that the tracker is broken.
            print(String(format: "[V2] compute took %.2fs", CFAbsoluteTimeGetCurrent() - v2Start))
            print("[V2] \(v2.notes.joined(separator: " | "))")
            if let speed = v2.ballSpeedMph, v2.confident {
                v2Warnings.append(String(format: "V2 metrics active (confident, %d flight pts): ball %.1f mph%@%@.",
                                         v2.flightPointCount, speed,
                                         v2.vlaDegrees.map { String(format: ", VLA %.1f°", $0) } ?? "",
                                         v2.clubSpeedMph.map { String(format: ", club %.1f mph", $0) } ?? ""))
                ballLaunch.ballSpeedMph = speed
                if let vla = v2.vlaDegrees {
                    ballLaunch.vlaLegacyDegrees = ballLaunch.vlaDegrees
                    ballLaunch.vlaTrainedModelDegrees = vla
                    ballLaunch.vlaFinalDegrees = vla
                    ballLaunch.vlaDegrees = vla
                    ballLaunch.vlaModelUsed = "v2_stacked_head"
                }
                if let cs = v2.clubSpeedMph {
                    clubMetrics.clubSpeedMph = cs
                    clubMetrics.method = "v2_arc_fit_head"
                }
            } else if let speed = v2.ballSpeedMph {
                v2Warnings.append(String(format: "V2 low-confidence (%d pts): measured %.1f mph — legacy values shown.",
                                         v2.flightPointCount, speed))
            } else {
                v2Warnings.append("V2 withheld: " + (v2.notes.last ?? "no usable flight track"))
            }
        }

        // Smash factor with 1.50 cap
        let rawSmashFactor: Double?
        if let ballSpeed = ballLaunch.ballSpeedMph,
           let clubSpeed = clubMetrics.clubSpeedMph,
           clubSpeed > 0 {
            rawSmashFactor = ballSpeed / clubSpeed
        } else {
            rawSmashFactor = nil
        }
        let smashFactorClamped = rawSmashFactor.map { $0 > 1.50 } ?? false
        let smashFactor = rawSmashFactor.map { min($0, 1.50) }
        var smashWarnings = [String]()
        if smashFactorClamped {
            smashWarnings.append(String(format: "Smash factor clamped to 1.50 (raw: %.2f).", rawSmashFactor!))
        }

        let clubPath = clubPathFaceEstimator.estimateClubPath(
            clubObservations: clubObservations,
            zeroDegreeAngleDegrees: zeroDegreeReferenceAngleDegrees,
            calibration: calibration,
            impactFrameIndex: analysis.detectedImpactFrameIndex
        )

        // Face frame = detectedImpactFrameIndex + 1 (no min clamp)
        let faceFrameIndex = analysis.detectedImpactFrameIndex + 1
        print("[ShotMetrics] Clubface detection frame: \(faceFrameIndex)  reason: detectedImpactFrameIndex_plus_one")
        print("[ShotMetrics]   detectedImpactFrameIndex: \(analysis.detectedImpactFrameIndex)  fallbackImpactFrameIndex: \(analysis.fallbackImpactFrameIndex)")
        let impactFrame = analysis.frames
            .first { $0.frameIndex == faceFrameIndex }?
            .originalFrame.image
        let faceAngle = clubPathFaceEstimator.estimateFaceAngle(
            clubObservations: clubObservations,
            impactFrame: impactFrame,
            zeroDegreeAngleDegrees: zeroDegreeReferenceAngleDegrees,
            calibration: calibration,
            impactFrameIndex: faceFrameIndex,
            clubPathDegrees: clubPath.clubPathDegreesSigned,
            ballHLADegrees: ballLaunch.hlaDegrees
        )

        let spin = spinEstimator.estimate(
            ballSpeedMph: ballLaunch.ballSpeedMph,
            vlaDegrees: ballLaunch.vlaDegrees,
            hlaDegrees: ballLaunch.hlaDegrees,
            clubPathDegrees: clubPath.clubPathDegreesSigned,
            smashFactor: smashFactor
        )

        var distance = distanceEstimator.estimate(
            ballSpeedMph: ballLaunch.ballSpeedMph,
            vlaDegrees: ballLaunch.vlaDegrees,
            hlaDegrees: ballLaunch.hlaDegrees,
            carryCorrectionFactor: carryCorrectionFactor,
            flightModel: flightModel,
            backspinRpm: spin.estimatedBackspinRpm
        )

        // ── Putt engine: ground-plane physics replaces the flight machinery. The measured
        // 58×32in footprint mapping is EXACT for a rolling ball, so its speed beats the
        // 3D-projection estimate, roll-out comes from stimp physics instead of the flight
        // model, and the putter-head diff pass fills club speed / path / face that the
        // full-swing club tracker never produced for putts.
        var puttReadout: PuttReadout? = nil
        var clubPathFinal = clubPath
        var faceAngleFinal = faceAngle
        var smashFinal = smashFactor
        var rawSmashFinal = rawSmashFactor
        var smashClampedFinal = smashFactorClamped
        // Explicit putter selection only — a speed-inferred slow chip is on turf, not a green,
        // so stimp roll-out physics would overshoot it badly (that path keeps the old
        // rolling-resistance estimate in DistanceEstimator).
        if isPutterMode {
            let readout = PuttAnalyzer().analyze(analysis: analysis)
            puttReadout = readout

            if let groundSpeed = readout.ballSpeedMph, groundSpeed <= 25 {
                ballLaunch.ballSpeedMph = groundSpeed
            }
            if let rollFeet = readout.rollDistanceFeet {
                let rollYards = rollFeet / 3.0
                distance = DistanceEstimate(
                    idealCarryYards: nil, carryCorrectionFactor: 1.0,
                    carryYards: nil, rolloutYards: rollYards, totalYards: rollYards,
                    rolloutFraction: 1.0, vlaBucket: "putt",
                    method: String(format: "putt_stimp%.0f_physics", readout.stimp),
                    warnings: readout.warnings)
            }
            if let headSpeed = readout.putterSpeedMph {
                clubMetrics.clubSpeedMph = headSpeed
                clubMetrics.method = "putter_head_diff"
                // Putts routinely run smash ~1.6–1.9 off the putter face; the 1.50 full-swing
                // clamp would misreport them, so putt smash stays raw.
                if let bs = ballLaunch.ballSpeedMph, headSpeed > 0 {
                    rawSmashFinal = bs / headSpeed
                    smashFinal = rawSmashFinal
                    smashClampedFinal = false
                }
            }
            if let pathDeg = readout.putterPathDegreesSigned {
                clubPathFinal = ClubPathEstimate(
                    clubPathDegreesSigned: pathDeg,
                    clubPathDisplay: String(format: "%.1f° %@", abs(pathDeg), pathDeg < 0 ? "L" : "R"),
                    confidence: 0.6, method: "putter_head_diff", warnings: [])
            }
            if let faceDeg = readout.faceAngleDegreesSigned {
                let faceToPath = readout.putterPathDegreesSigned.map { faceDeg - $0 }
                faceAngleFinal = FaceAngleEstimate(
                    faceAngleDegreesSigned: faceDeg,
                    faceAngleDisplay: readout.faceDisplay,
                    faceToPathDegreesSigned: faceToPath,
                    faceToPathDisplay: faceToPath.map { String(format: "%.1f°", $0) } ?? "--",
                    confidence: "estimated", method: "putter_silhouette_pca",
                    warnings: [])
            }
        }

        var warnings: [String] = [calibration.calibrationWarning]
        warnings.append(contentsOf: v2Warnings)
        warnings.append(contentsOf: smashWarnings)
        warnings.append(contentsOf: ballLaunch.warnings)
        warnings.append(contentsOf: ballLaunch.vlaModelWarnings)
        warnings.append(contentsOf: clubMetrics.warnings)
        warnings.append(contentsOf: distance.warnings)
        warnings.append(contentsOf: spin.warnings)
        warnings.append(contentsOf: clubPathFinal.warnings)
        warnings.append(contentsOf: faceAngleFinal.warnings)
        if let readout = puttReadout {
            warnings.append(contentsOf: readout.warnings)
        }
        if smashFinal == nil {
            warnings.append("Smash factor unavailable until both ball speed and club speed are available.")
        }

        var result = ShotMetricsResult(
            detectedImpactFrameIndex: analysis.detectedImpactFrameIndex,
            fallbackImpactFrameIndex: analysis.fallbackImpactFrameIndex,
            calibration: calibration,
            zeroDegreeReferenceAngleDegrees: zeroDegreeReferenceAngleDegrees,
            ballLaunch: ballLaunch,
            club: clubMetrics,
            smashFactor: smashFinal,
            distance: distance,
            spin: spin,
            clubPath: clubPathFinal,
            faceAngle: faceAngleFinal,
            ball3DObservations: ball3DObservations,
            clubObservations: clubObservations,
            warnings: Array(Set(warnings)).sorted()
        )
        result.putt = puttReadout
        result.rawSmashFactor    = rawSmashFinal
        result.smashFactorClamped = smashClampedFinal
        result.faceFrameIndex    = faceFrameIndex
        result.faceFrameReason   = "detectedImpactFrameIndex_plus_one"

        printMetricsSummary(result)
        return result
    }

    private func makeCalibration(from analysis: ShotAnalysisResult) -> CameraCalibration? {
        guard let firstImage = analysis.frames.first?.originalFrame.image.cgImage else { return nil }
        return CameraCalibration.defaultForImage(width: firstImage.width, height: firstImage.height)
    }

    private func makeBall3DObservations(
        from analysis: ShotAnalysisResult,
        calibration: CameraCalibration
    ) -> [Ball3DObservation] {
        analysis.frames.compactMap { frame in
            guard let observation = frame.ballObservation else { return nil }
            return calibration.ballObservation3D(from: observation)
        }
    }

    // MARK: - Ball launch

    private func calculateBallLaunch(
        ball3DObservations: [Ball3DObservation],
        impactFrameIndex: Int,
        zeroDegreeAngleDegrees: Double,
        calibration: CameraCalibration,
        isPutterMode: Bool = false
    ) -> BallLaunchMetrics {
        var warnings: [String] = []
        let postImpact = ball3DObservations
            .filter { $0.frameIndex > impactFrameIndex }
            .sorted { $0.frameIndex < $1.frameIndex }
        var selected = Array(postImpact.prefix(configuration.preferredBallPointLimit))

        // Single flight point: anchor it to the resting ball at the detected impact frame.
        // The ball's rest position and the impact frame's timestamp are both KNOWN, so one
        // tracked flight point still yields displacement over a known interval. The launch
        // actually happened somewhere inside the impact→next-frame gap, so this reads as a
        // floor — but a floored measurement beats "unavailable" (frequent at driver speed
        // with dropped frames, where the ball survives only 1-2 stored frames).
        var anchoredToImpact = false
        if selected.count == 1,
           let anchor = ball3DObservations
               .filter({ $0.frameIndex <= impactFrameIndex })
               .max(by: { $0.frameIndex < $1.frameIndex }) {
            selected.insert(anchor, at: 0)
            anchoredToImpact = true
            warnings.append("Ball speed estimated from the resting ball at impact plus one flight point — treat as a floor.")
        }

        guard selected.count >= configuration.minimumBallPoints else {
            warnings.append("Too few post-impact ball points for ball speed/HLA/VLA.")
            return BallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil, vlaDegrees: nil,
                hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: selected.count, quality: 0,
                method: "unavailable", warnings: warnings
            )
        }

        let velocity: SIMD3<Double>?
        let method: String
        if anchoredToImpact {
            velocity = deltaVelocity(first: selected[0], last: selected[1])
            method = "impact_anchor_single_point"
        } else if selected.count >= 3 {
            velocity = linearFitVelocity(selected.map { ($0.relativeTime, $0.positionMeters) })
            method = "linear_fit_\(selected.count)_points"
        } else {
            velocity = deltaVelocity(first: selected[0], last: selected[1])
            method = "two_point_delta"
            warnings.append("Ball velocity used 2-point fallback.")
        }

        guard let velocity else {
            warnings.append("Ball velocity fit failed because time span was too small.")
            return BallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil, vlaDegrees: nil,
                hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: selected.count, quality: 0,
                method: method, warnings: warnings
            )
        }

        let speedMetersPerSecond = vectorLength(velocity)
        let ballSpeedMph = speedMetersPerSecond * 2.23694

        // The impact-anchored single-point estimate is only as good as its one flight point;
        // a junk pick reads as hundreds of mph (observed 719). Outside the range a golf ball
        // can physically fly, withhold rather than report — and rather than letting the
        // implausibility gate discard the whole shot.
        if anchoredToImpact, !(3.0...230.0).contains(ballSpeedMph) {
            warnings.append(String(format: "Single-point speed estimate implausible (%.0f mph) — withheld.", ballSpeedMph))
            return BallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil, vlaDegrees: nil,
                hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: 1, quality: 0,
                method: "impact_anchor_rejected", warnings: warnings
            )
        }
        // Reversed mount flips world-x; keep downrange (z) forward so HLA sign stays golf-correct.
        let hla3D = atan2(HitDirection.sign * velocity.x, velocity.z) * 180 / .pi
        let horizontalSpeed = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
        // Putt/roll: as soon as we know the ball speed is in the putt range, do NOT compute a VLA
        // — a slow roll has no vertical launch, and atan2 is dominated by tracking noise at low
        // horizontal speed (reads spuriously high). Force it to 0 at the source.
        let isPutt = isPutterMode || ballSpeedMph < configuration.puttBallSpeedThresholdMph
        let vlaDegrees = isPutt ? 0.0 : atan2(velocity.y, horizontalSpeed) * 180 / .pi

        let imageHLA = computeImageSpaceHLA(
            observations: selected,
            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
            calibration: calibration
        )
        warnings.append(contentsOf: imageHLA.warnings)

        let hlaDisplay = imageHLA.hla.map { DirectionalFormat.angleLR($0) } ?? "—"

        let avgConfidence = selected.map(\.confidence).reduce(0, +) / Double(selected.count)
        if avgConfidence < configuration.lowConfidenceWarningThreshold {
            warnings.append("Average post-impact ball tracking confidence is low.")
        }
        if selected.count < 3 {
            warnings.append("Ball launch is less stable with fewer than 3 post-impact points.")
        }

        let quality = min(1.0, Double(selected.count) / Double(configuration.preferredBallPointLimit)) * avgConfidence
        return BallLaunchMetrics(
            ballSpeedMph: ballSpeedMph,
            hlaDegrees: imageHLA.hla,
            hlaDisplay: hlaDisplay,
            hla3DRawDegrees: hla3D,
            vlaDegrees: vlaDegrees,
            hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
            ballMovementDx: imageHLA.dx,
            ballMovementDy: imageHLA.dy,
            hlaForwardComponent: imageHLA.forward,
            hlaLateralComponent: imageHLA.lateral,
            pointsUsed: selected.count,
            quality: quality,
            method: method,
            warnings: warnings
        )
    }

    // VLA from apparent-diameter growth: d ∝ 1/(cameraHeight − ballHeight), so per-frame height
    // is h·(1 − d₀/d) against the pre-impact on-ground diameter. Uses the measured 41" camera
    // height via GroundPlaneMetricsCalculator. Returns nil when there aren't enough diameter
    // samples, letting the caller fall through to the older paths.
    private func diameterGrowthVLA(analysis: ShotAnalysisResult) -> Double? {
        let result = GroundPlaneMetricsCalculator().calculate(
            observations: analysis.frames.compactMap { $0.ballObservation },
            impactFrameIndex: analysis.detectedImpactFrameIndex,
            groundCalibration: GroundCalibration.shared
        )
        guard let vla = result.vlaDegrees, result.usedDiameterVLA else { return nil }
        // Floor at 0 (negative fitted vz on an airborne shot is size noise); cap at 65 —
        // the physical ceiling for an extreme flop shot.
        return min(max(vla, 0), 65)
    }

    // MARK: - Image-space HLA

    private struct ImageSpaceHLAResult {
        let hla: Double?
        let dx: Double?
        let dy: Double?
        let forward: Double?
        let lateral: Double?
        let warnings: [String]
    }

    private func computeImageSpaceHLA(
        observations: [Ball3DObservation],
        zeroDegreeAngleDegrees: Double,
        calibration: CameraCalibration
    ) -> ImageSpaceHLAResult {
        var warnings: [String] = []
        guard observations.count >= 2 else {
            return ImageSpaceHLAResult(hla: nil, dx: nil, dy: nil, forward: nil, lateral: nil,
                                       warnings: ["Not enough points for image-space HLA."])
        }

        let times = observations.map { $0.relativeTime }
        let xs    = observations.map { Double($0.imageX) }
        let ys    = observations.map { Double($0.imageY) }

        let meanT = times.reduce(0.0, +) / Double(times.count)
        let denom = times.map { ($0 - meanT) * ($0 - meanT) }.reduce(0.0, +)

        guard denom > 0 else {
            return ImageSpaceHLAResult(hla: nil, dx: nil, dy: nil, forward: nil, lateral: nil,
                                       warnings: ["Invalid time span for image-space HLA."])
        }

        let dxdt = zip(times, xs).map { ($0 - meanT) * $1 }.reduce(0.0, +) / denom
        let dydt = zip(times, ys).map { ($0 - meanT) * $1 }.reduce(0.0, +) / denom

        let W = Double(calibration.imageWidthPixels)
        let H = Double(calibration.imageHeightPixels)
        // The reversed mount is a 180° physical rotation, which flips BOTH image axes.
        // Flipping only x (the previous code) is a mirror, and mirrors invert handedness —
        // that's why HLA read "7° R" for a shot that went left. Apply the sign to y as well
        // so the transform is a rotation and L/R semantics survive.
        let dxPx = HitDirection.sign * dxdt * W
        let dyPx = HitDirection.sign * dydt * H

        let movLen = sqrt(dxPx * dxPx + dyPx * dyPx)
        if movLen < 1e-6 {
            warnings.append("Ball 2D movement vector is near zero; HLA unreliable.")
            return ImageSpaceHLAResult(hla: nil, dx: dxdt, dy: dydt, forward: nil, lateral: nil,
                                       warnings: warnings)
        }

        let theta = zeroDegreeAngleDegrees * .pi / 180.0
        let refX  =  cos(theta)
        let refY  = -sin(theta)
        let perpX =  sin(theta)
        let perpY =  cos(theta)

        let forward = dxPx * refX + dyPx * refY
        let lateral = dxPx * perpX + dyPx * perpY

        if abs(forward) < 0.001 * movLen {
            warnings.append("Ball moving nearly perpendicular to 0° reference; HLA near ±90°.")
        }

        let hla = atan2(lateral, forward) * 180.0 / .pi
        return ImageSpaceHLAResult(hla: hla, dx: dxdt, dy: dydt,
                                   forward: forward, lateral: lateral, warnings: warnings)
    }

    // Same physics the ball tracker enforces, applied to the club: during the downswing the
    // clubhead only advances toward impact (monotonic progress along the travel direction),
    // and it can never be AHEAD of the ball before contact. Detections violating either rule
    // are glare/shaft misreads that made the overlay "bounce around" pre-impact.
    private func enforceClubMonotonicity(
        _ observations: [ClubObservation],
        impactFrameIndex: Int,
        ballCenterX: CGFloat?
    ) -> [ClubObservation] {
        let s = CGFloat(HitDirection.sign)   // s·x increases toward impact
        let allowance: CGFloat = 0.015
        var lastProgress: CGFloat = -.greatestFiniteMagnitude
        var kept: [ClubObservation] = []
        var dropped = 0
        for obs in observations.sorted(by: { $0.frameIndex < $1.frameIndex }) {
            guard let cx = obs.centerX else { kept.append(obs); continue }
            let progress = s * cx
            if obs.frameIndex < impactFrameIndex, let bx = ballCenterX, progress > s * bx + allowance {
                dropped += 1
                continue   // clubhead "ahead of the ball" before impact — impossible
            }
            if progress < lastProgress - allowance {
                dropped += 1
                continue   // clubhead moving backward mid-downswing — misdetection
            }
            lastProgress = max(lastProgress, progress)
            kept.append(obs)
        }
        if dropped > 0 {
            print("[ClubTrack] monotonicity dropped \(dropped)/\(observations.count) club observations")
        }
        return kept
    }

    // MARK: - Club metrics

    private func calculateClubMetrics(
        clubObservations: [ClubObservation],
        ball3DObservations: [Ball3DObservation],
        calibration: CameraCalibration,
        impactFrameIndex: Int
    ) -> ClubMetrics {
        var warnings = ["Club speed is approximate because club depth is assumed from ball depth near impact."]

        guard let assumedDepth = nearestBallDepth(ball3DObservations, impactFrameIndex: impactFrameIndex) else {
            warnings.append("Club speed skipped: no ball depth near impact.")
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: 0, quality: 0,
                               method: "unavailable", warnings: warnings, speedFrameIndices: [])
        }

        let points = clubObservations
            .filter { $0.frameIndex <= impactFrameIndex && $0.confidence > 0 }
            .compactMap { observation -> (frameIndex: Int, time: Double, position: SIMD3<Double>, confidence: Double)? in
                guard let x = observation.centerX ?? observation.leadingEdgeX,
                      let y = observation.centerY ?? observation.leadingEdgeY,
                      let position = calibration.positionMeters(centerX: x, centerY: y, depthMeters: assumedDepth) else {
                    return nil
                }
                return (observation.frameIndex, observation.relativeTime, position, observation.confidence)
            }
            .sorted { $0.frameIndex < $1.frameIndex }

        guard points.count >= configuration.minimumClubPoints else {
            warnings.append("Too few club points for club speed.")
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: points.count, quality: 0,
                               method: "unavailable", warnings: warnings,
                               speedFrameIndices: points.map(\.frameIndex))
        }

        let velocity: SIMD3<Double>?
        let method: String
        if points.count >= 3 {
            velocity = linearFitVelocity(points.map { ($0.time, $0.position) })
            method = "linear_fit_\(points.count)_points_assumed_ball_depth"
        } else {
            let first = points[0]
            let last = points[1]
            let dt = last.time - first.time
            velocity = dt > 0 ? (last.position - first.position) / dt : nil
            method = "two_point_delta_assumed_ball_depth"
            warnings.append("Club velocity used 2-point fallback.")
        }

        guard let velocity else {
            warnings.append("Club velocity fit failed because time span was too small.")
            return ClubMetrics(clubSpeedMph: nil, pointsUsed: points.count, quality: 0,
                               method: method, warnings: warnings,
                               speedFrameIndices: points.map(\.frameIndex))
        }

        let avgConfidence = points.map(\.confidence).reduce(0, +) / Double(points.count)
        let clubSpeedMph = vectorLength(velocity) * 2.23694
        let quality = min(1.0, Double(points.count) / 6.0) * avgConfidence * 0.65

        return ClubMetrics(
            clubSpeedMph: clubSpeedMph,
            pointsUsed: points.count,
            quality: quality,
            method: method,
            warnings: warnings,
            speedFrameIndices: points.map(\.frameIndex)
        )
    }

    // MARK: - Helpers

    private func nearestBallDepth(_ observations: [Ball3DObservation], impactFrameIndex: Int) -> Double? {
        observations
            .filter { $0.frameIndex >= impactFrameIndex - 1 }
            .min { abs($0.frameIndex - impactFrameIndex) < abs($1.frameIndex - impactFrameIndex) }?
            .positionMeters.z
    }

    private func deltaVelocity(first: Ball3DObservation, last: Ball3DObservation) -> SIMD3<Double>? {
        let dt = last.relativeTime - first.relativeTime
        guard dt > 0 else { return nil }
        return (last.positionMeters - first.positionMeters) / dt
    }

    private func linearFitVelocity(_ points: [(time: Double, position: SIMD3<Double>)]) -> SIMD3<Double>? {
        guard points.count >= 2 else { return nil }
        let meanT = points.map(\.time).reduce(0, +) / Double(points.count)
        let denominator = points.map { pow($0.time - meanT, 2) }.reduce(0, +)
        guard denominator > 0 else { return nil }

        func slope(_ component: KeyPath<SIMD3<Double>, Double>) -> Double {
            points.map { ($0.time - meanT) * $0.position[keyPath: component] }.reduce(0, +) / denominator
        }

        return SIMD3<Double>(slope(\.x), slope(\.y), slope(\.z))
    }

    private func vectorLength(_ vector: SIMD3<Double>) -> Double {
        sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    }

    private func printMetricsSummary(_ result: ShotMetricsResult) {
        print(result.ballLaunch.ballSpeedMph.map { String(format: "Ball speed: %.1f mph", $0) } ?? "Ball speed: unavailable")
        print(result.ballLaunch.hlaDegrees.map { _ in "HLA: \(result.ballLaunch.hlaDisplay)" } ?? "HLA: unavailable")
        print(result.ballLaunch.hla3DRawDegrees.map { String(format: "HLA (3D raw): %.1f°", $0) } ?? "HLA 3D: unavailable")
        print(result.ballLaunch.vlaDegrees.map { String(format: "VLA: %.1f°", $0) } ?? "VLA: unavailable")
        print(result.club.clubSpeedMph.map { String(format: "Club speed: %.1f mph", $0) } ?? "Club speed: unavailable")
        print(result.smashFactor.map { String(format: "Smash factor: %.2f%@", $0, result.smashFactorClamped ? " (clamped)" : "") } ?? "Smash factor: unavailable")
        print(result.ballLaunch.vlaModelUsed == "trainedModel"
            ? String(format: "VLA (trained model): %.1f°", result.ballLaunch.vlaDegrees ?? 0)
            : "VLA model: not used")
        print(result.distance.carryYards.map { String(format: "Est. carry: %.0f yd (ideal: %.0f yd × cf=%.2f)", $0, result.distance.idealCarryYards ?? 0, result.distance.carryCorrectionFactor) } ?? "Est. carry: unavailable")
        print(result.distance.totalYards.map { String(format: "Est. total: %.0f yd (rollout %.0f%%)", $0, (result.distance.rolloutFraction ?? 0) * 100) } ?? "Est. total: unavailable")
        print(result.spin.estimatedBackspinRpm.map { String(format: "Est. backspin: %.0f rpm", $0) } ?? "Backspin: unavailable")
        print("Club path: \(result.clubPath.clubPathDisplay)  Face: \(result.faceAngle.faceAngleDisplay)  F-to-P: \(result.faceAngle.faceToPathDisplay)")
        if !result.warnings.isEmpty {
            print("Metrics warnings: \(result.warnings.joined(separator: " | "))")
        }
    }
}
