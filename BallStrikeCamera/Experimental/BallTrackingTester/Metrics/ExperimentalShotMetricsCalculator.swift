#if DEBUG
import Foundation
import UIKit
import simd

enum VLAEstimationMode: String {
    case legacy        = "legacy"
    case pinhole2DSize = "pinhole2DSize"
    case blended       = "blended"
    case groundCalibrated = "groundCalibrated"
    case trainedModel  = "trainedModel"
}

struct ExperimentalShotMetricsCalculator {
    struct Configuration {
        var minimumBallPoints: Int = 2
        var preferredBallPointLimit: Int = 6
        var minimumClubPoints: Int = 2
        var lowConfidenceWarningThreshold: Double = 0.45
        // Part F — metrics point filtering
        var minMetricPointConfidence: Double = 0.35
        var maxMetricDiameterRatioToMedian: Double = 1.75
        var maxMetricPositionResidualNorm: Double = 0.025
        // Part A/D — VLA from apparent diameter growth (updated defaults)
        var useDiameterGrowthForVLA: Bool = true
        var diameterGrowthToVLAScale: Double = 140.0
        var diameterGrowthVLAWeight: Double = 0.75
        var imageYVLAWeight: Double = 0.25
        var maxVLAClampDegrees: Double = 75.0
        // Part A — slow-horizontal VLA boost
        var slowHorizontalProgressBoost: Bool = true
        var slowHorizontalThreshold: Double = 0.035
        var slowHorizontalVLABoostMultiplier: Double = 1.4
        var significantDiamGrowthThreshold: Double = 0.10
        var veryHighLaunchDiamGrowthThreshold: Double = 0.25
        // New VLA model (pinhole2DSize / trainedModel)
        var vlaEstimationMode: VLAEstimationMode = .trainedModel
        var vlaModelFilePath: String? = nil           // path to vla_model.json
        var vlaImageYWeight: Double = 0.45
        var vlaDiameterDepthWeight: Double = 0.55
        var vlaDepthSign: Double = 1.0
        var vlaDepthScale: Double = 1.0
        var useRightwardPerspectiveSizeCorrection: Bool = true
        var rightwardSizeCorrectionStrength: Double = 0.35
        var maxSizeCorrectionRatio: Double = 1.35
        var vlaGrowthBoostDiameterScale: Double = 140.0
        var vlaSignificantGrowthThreshold: Double = 0.10
        var vlaVeryHighGrowthThreshold: Double = 0.25
        var vlaMinFromVeryHighGrowth: Double = 30.0
        var maxVLAPinholeDegrees: Double = 70.0
    }

    let configuration: Configuration
    let distanceEstimator  = ExperimentalDistanceEstimator()
    let spinEstimator      = ExperimentalSpinEstimator()
    let clubPathFaceEstimator = ExperimentalClubPathFaceEstimator()

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func calculate(
        sequence: BallTrackingTestSequence,
        ballResult: BallTrackingTestResult,
        calibrationSettings: CalibrationTuningSettings,
        clubConfiguration: ExperimentalClubTracker.Configuration,
        zeroDegreeAngleDegrees: Double = 0.0,
        carryCorrectionFactor: Double = 0.75
    ) -> ExperimentalShotMetricsResult? {
        print("Experimental metrics calculation started")
        guard let cg = sequence.frames.first?.image.cgImage else {
            print("Experimental metrics skipped: no image dimensions")
            return nil
        }

        let calibration = ExperimentalCameraCalibration.from(
            settings: calibrationSettings,
            imageWidth: cg.width,
            imageHeight: cg.height
        )
        print(String(format: "Experimental calibration: fovX=%.1f fovY=%.1f fx=%.1f fy=%.1f ballDiameter=%.5f",
                     calibration.horizontalFOVDegrees,
                     calibration.verticalFOVDegrees,
                     calibration.focalLengthPixelsX,
                     calibration.focalLengthPixelsY,
                     calibration.realBallDiameterMeters))

        let clubMode = clubConfiguration.useFrameDifference ? "frameDifference" : "dark_only"
        print("Experimental club tracking mode: \(clubMode)")

        let frameMap = Dictionary(uniqueKeysWithValues: sequence.frames.map { ($0.frameIndex, $0) })
        let ball3D = ballResult.observations.compactMap { observation -> ExperimentalBall3DObservation? in
            guard let frame = frameMap[observation.frameIndex] else { return nil }
            return calibration.ballObservation3D(from: observation, frame: frame)
        }

        let clubObservations = ExperimentalClubTracker(configuration: clubConfiguration)
            .track(sequence: sequence, ballResult: ballResult)

        let ballLaunch = calculateBallLaunch(
            ball3DObservations: ball3D,
            impactFrameIndex: ballResult.detectedImpactFrameIndex,
            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
            calibration: calibration
        )

        // Apply trained VLA model if mode is .trainedModel
        var finalBallLaunch = ballLaunch
        if configuration.vlaEstimationMode == .trainedModel {
            let modelData = ExperimentalVLAModelPredictor.autoLoad(
                overridePath: configuration.vlaModelFilePath
            )
            if let model = modelData {
                let featureDict = ExperimentalVLAModelPredictor.extractFeatures(
                    from: ball3D.filter { $0.frameIndex > ballResult.detectedImpactFrameIndex }
                                .sorted { $0.frameIndex < $1.frameIndex }
                                .prefix(configuration.preferredBallPointLimit)
                                .map { $0 },
                    hlaDegrees: ballLaunch.hlaDegrees,
                    ballSpeedMph: ballLaunch.ballSpeedMph,
                    impactFrameIndex: ballResult.detectedImpactFrameIndex,
                    totalFrames: sequence.frames.count
                )
                let (rawPred, clampedPred, featVals, mdlWarns) = ExperimentalVLAModelPredictor.predict(
                    features: featureDict, model: model
                )
                finalBallLaunch.vlaLegacyDegrees       = ballLaunch.vlaDegrees
                finalBallLaunch.vlaPinhole2DSizeDegrees = ballLaunch.vlaDegrees
                finalBallLaunch.vlaTrainedModelDegrees  = clampedPred
                finalBallLaunch.vlaFinalDegrees         = clampedPred
                finalBallLaunch.vlaDegrees              = clampedPred  // override primary
                finalBallLaunch.vlaModelUsed            = "trainedModel"
                finalBallLaunch.vlaModelFile            = model.filePath
                finalBallLaunch.vlaModelFeaturesUsed    = model.featureSearchTopSubset.isEmpty
                    ? model.features : model.featureSearchTopSubset
                finalBallLaunch.vlaModelFeatureValues   = featVals
                finalBallLaunch.vlaModelWarnings        = mdlWarns
                finalBallLaunch.vlaWasClamped           = abs(rawPred - clampedPred) > 0.01
                print(String(format: "[TrainedVLA] prediction=%.1f° (raw=%.1f°) file=%@",
                             clampedPred, rawPred, model.filePath))
            } else {
                finalBallLaunch.vlaModelUsed    = "trainedModel_unavailable_fallback_pinhole2DSize"
                finalBallLaunch.vlaModelWarnings = ["vla_model.json not found — falling back to pinhole2DSize VLA."]
                finalBallLaunch.vlaFinalDegrees  = ballLaunch.vlaDegrees
                finalBallLaunch.vlaLegacyDegrees = ballLaunch.vlaDegrees
            }
        } else {
            finalBallLaunch.vlaLegacyDegrees  = ballLaunch.vlaDegrees
            finalBallLaunch.vlaFinalDegrees   = ballLaunch.vlaDegrees
            finalBallLaunch.vlaModelUsed      = configuration.vlaEstimationMode.rawValue
        }

        let clubMetrics = calculateClubMetrics(
            clubObservations: clubObservations,
            ball3DObservations: ball3D,
            calibration: calibration,
            impactFrameIndex: ballResult.detectedImpactFrameIndex
        )

        let rawSmash: Double?
        if let ballSpeed = finalBallLaunch.ballSpeedMph,
           let clubSpeed = clubMetrics.clubSpeedMph,
           clubSpeed > 0 {
            rawSmash = ballSpeed / clubSpeed
        } else {
            rawSmash = nil
        }
        let smashFactor = rawSmash.map { min(1.50, $0) }
        let smashFactorClamped = rawSmash.map { $0 > 1.50 } ?? false
        let smashClampWarning: String? = smashFactorClamped
            ? String(format: "Smash factor clamped to 1.50 (raw: %.2f).", rawSmash!)
            : nil

        // Club path + face angle
        let clubPath = clubPathFaceEstimator.estimateClubPath(
            clubObservations: clubObservations,
            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
            calibration: calibration,
            impactFrameIndex: ballResult.detectedImpactFrameIndex
        )

        let faceFrameIndex = ballResult.detectedImpactFrameIndex + 1
        print("[ExperimentalMetrics] Clubface detection frame: \(faceFrameIndex)  reason: detectedImpactFrameIndex_plus_one")
        print("[ExperimentalMetrics]   detectedImpactFrameIndex: \(ballResult.detectedImpactFrameIndex)  fallbackImpactFrameIndex: \(ballResult.fallbackImpactFrameIndex)")
        let impactFrame = frameMap[faceFrameIndex]?.image
        let faceAngle = clubPathFaceEstimator.estimateFaceAngle(
            clubObservations: clubObservations,
            impactFrame: impactFrame,
            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
            calibration: calibration,
            impactFrameIndex: faceFrameIndex,
            clubPathDegrees: clubPath.clubPathDegreesSigned,
            ballHLADegrees: finalBallLaunch.hlaDegrees
        )

        // Spin
        var spin = spinEstimator.estimate(
            ballSpeedMph: finalBallLaunch.ballSpeedMph,
            vlaDegrees: finalBallLaunch.vlaDegrees,
            hlaDegrees: finalBallLaunch.hlaDegrees,
            clubPathDegrees: clubPath.clubPathDegreesSigned,
            smashFactor: smashFactor
        )
        spin.spinVLAUsedSource = finalBallLaunch.vlaModelUsed

        // Distance
        var distance = distanceEstimator.estimate(
            ballSpeedMph: finalBallLaunch.ballSpeedMph,
            vlaDegrees: finalBallLaunch.vlaDegrees,
            hlaDegrees: finalBallLaunch.hlaDegrees,
            carryCorrectionFactor: carryCorrectionFactor
        )
        distance.distanceVLAUsedSource = finalBallLaunch.vlaModelUsed

        var warnings = [
            "Experimental FOV calibration is estimated; tune calibration before trusting metrics."
        ]
        if let w = smashClampWarning { warnings.append(w) }
        warnings.append(contentsOf: finalBallLaunch.warnings)
        warnings.append(contentsOf: finalBallLaunch.vlaModelWarnings)
        warnings.append(contentsOf: clubMetrics.warnings)
        warnings.append(contentsOf: distance.warnings)
        warnings.append(contentsOf: spin.warnings)
        warnings.append(contentsOf: clubPath.warnings)
        warnings.append(contentsOf: faceAngle.warnings)
        if smashFactor == nil {
            warnings.append("Smash factor unavailable until ball speed and club speed are both available.")
        }

        let result = ExperimentalShotMetricsResult(
            detectedImpactFrameIndex: ballResult.detectedImpactFrameIndex,
            fallbackImpactFrameIndex: ballResult.fallbackImpactFrameIndex,
            faceFrameIndex: faceFrameIndex,
            calibration: calibration,
            zeroDegreeReferenceAngleDegrees: zeroDegreeAngleDegrees,
            ballLaunch: finalBallLaunch,
            club: clubMetrics,
            smashFactor: smashFactor,
            rawSmashFactor: rawSmash,
            smashFactorClamped: smashFactorClamped,
            distance: distance,
            spin: spin,
            clubPath: clubPath,
            faceAngle: faceAngle,
            ball3DObservations: ball3D,
            clubObservations: clubObservations,
            warnings: Array(Set(warnings)).sorted()
        )

        printSummary(result)
        return result
    }

    // MARK: - Ball launch

    private func calculateBallLaunch(
        ball3DObservations: [ExperimentalBall3DObservation],
        impactFrameIndex: Int,
        zeroDegreeAngleDegrees: Double,
        calibration: ExperimentalCameraCalibration
    ) -> ExperimentalBallLaunchMetrics {
        var warnings: [String] = []
        let raw = Array(
            ball3DObservations
                .filter { $0.frameIndex > impactFrameIndex }
                .sorted { $0.frameIndex < $1.frameIndex }
                .prefix(configuration.preferredBallPointLimit)
        )
        // Part F: filter metric points by confidence, diameter, path residual
        let selected = filterMetricPoints(raw, warnings: &warnings)

        guard selected.count >= configuration.minimumBallPoints else {
            warnings.append("Not enough post-impact ball points for speed/HLA/VLA.")
            return ExperimentalBallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil,
                vlaDegrees: nil, vlaRawDegrees: nil, hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: selected.count, quality: 0,
                method: "not_enough_data", warnings: warnings
            )
        }

        let velocity: SIMD3<Double>?
        let method: String
        if selected.count >= 3 {
            velocity = linearFitVelocity(selected.map { ($0.relativeTime, $0.positionMeters) })
            method = "linear_fit_\(selected.count)_points"
        } else {
            let dt = selected[1].relativeTime - selected[0].relativeTime
            velocity = dt > 0 ? (selected[1].positionMeters - selected[0].positionMeters) / dt : nil
            method = "two_point_delta"
            warnings.append("Ball velocity used 2-point fallback.")
        }

        guard let velocity else {
            warnings.append("Ball velocity calculation failed due to invalid time span.")
            return ExperimentalBallLaunchMetrics(
                ballSpeedMph: nil, hlaDegrees: nil, hlaDisplay: "—",
                hla3DRawDegrees: nil,
                vlaDegrees: nil, vlaRawDegrees: nil, hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
                ballMovementDx: nil, ballMovementDy: nil,
                hlaForwardComponent: nil, hlaLateralComponent: nil,
                pointsUsed: selected.count, quality: 0,
                method: method, warnings: warnings
            )
        }

        let speed = vectorLength(velocity)
        let ballSpeedMph = speed * 2.23694
        let hla3D = atan2(velocity.x, velocity.z) * 180 / .pi
        let horizontal = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
        // Part E: VLA clamped to ≥ 0 (ball cannot launch downward)
        let vlaRaw = atan2(velocity.y, horizontal) * 180 / .pi
        let vla3D = max(0.0, vlaRaw)
        if vlaRaw < 0 {
            warnings.append(String(format: "VLA was negative (%.1f°); clamped to 0.", vlaRaw))
        }

        // Part A/D: VLA from apparent diameter growth with slow-horizontal boost
        var vlaDiamEst: Double? = nil
        var diamGrowth: Double? = nil
        if configuration.useDiameterGrowthForVLA && selected.count >= 2 {
            let diaFirst = Double(selected.first!.diameterNorm)
            let diaLast  = Double(selected.last!.diameterNorm)
            if diaFirst > 1e-6 {
                let growth = (diaLast - diaFirst) / diaFirst
                diamGrowth = growth
                var est = max(0.0, min(configuration.maxVLAClampDegrees,
                                      growth * configuration.diameterGrowthToVLAScale))
                // Part A: slow-horizontal boost — if ball moved little horizontally, it went more upward
                if configuration.slowHorizontalProgressBoost && growth > 0 {
                    let cx0 = Double(selected.first!.imageX)
                    let cy0 = Double(selected.first!.imageY)
                    let cx1 = Double(selected.last!.imageX)
                    let cy1 = Double(selected.last!.imageY)
                    let dxPx = (cx1 - cx0) * Double(calibration.imageWidthPixels)
                    let dyPx = (cy1 - cy0) * Double(calibration.imageHeightPixels)
                    let horizProg = sqrt(dxPx * dxPx + dyPx * dyPx) /
                                    Double(max(calibration.imageWidthPixels, calibration.imageHeightPixels))
                    if horizProg < configuration.slowHorizontalThreshold {
                        est = min(configuration.maxVLAClampDegrees, est * configuration.slowHorizontalVLABoostMultiplier)
                    }
                }
                // Part A: VLA floor for significant diameter growth
                let sigThresh = configuration.significantDiamGrowthThreshold
                let vhThresh  = configuration.veryHighLaunchDiamGrowthThreshold
                if growth > vhThresh {
                    let floor = min(configuration.maxVLAClampDegrees, vhThresh * configuration.diameterGrowthToVLAScale * 0.8)
                    est = max(est, floor)
                } else if growth > sigThresh {
                    let floor = min(configuration.maxVLAClampDegrees, sigThresh * configuration.diameterGrowthToVLAScale * 0.8)
                    est = max(est, floor)
                }
                if est > 0 { vlaDiamEst = est }
            }
        }
        let vla: Double
        switch configuration.vlaEstimationMode {
        case .pinhole2DSize, .groundCalibrated, .trainedModel:
            // For trainedModel, pinhole2DSize is used here as the pre-model base;
            // the trained model override is applied in calculate() after this returns.
            let pinhole = calculatePinhole2DVla(
                selected: selected, calibration: calibration, warnings: &warnings)
            if let p = pinhole {
                vla = max(0.0, min(configuration.maxVLAPinholeDegrees, p))
            } else {
                vla = vla3D  // fallback
            }
        case .blended:
            let pinhole = calculatePinhole2DVla(
                selected: selected, calibration: calibration, warnings: &warnings)
            if let est = vlaDiamEst, let p = pinhole {
                vla = max(0.0, min(configuration.maxVLAPinholeDegrees, (est + p) / 2.0))
            } else if let p = pinhole {
                vla = max(0.0, min(configuration.maxVLAPinholeDegrees, p))
            } else if let est = vlaDiamEst {
                let wDiam = configuration.diameterGrowthVLAWeight
                let w3D   = configuration.imageYVLAWeight
                if vla3D < 5.0 && est > 10.0 {
                    let combined = est * wDiam + vla3D * w3D
                    warnings.append(String(format: "VLA: 3D=%.1f° near zero; diameter growth → combined=%.1f°.", vla3D, combined))
                    vla = max(0.0, min(configuration.maxVLAClampDegrees, combined))
                } else {
                    vla = max(0.0, min(configuration.maxVLAClampDegrees, max(vla3D, est * wDiam)))
                }
            } else {
                vla = vla3D
            }
        case .legacy:
            if let est = vlaDiamEst {
                let wDiam = configuration.diameterGrowthVLAWeight
                let w3D   = configuration.imageYVLAWeight
                if vla3D < 5.0 && est > 10.0 {
                    let combined = est * wDiam + vla3D * w3D
                    warnings.append(String(format: "VLA: 3D=%.1f° near zero; diameter growth → combined=%.1f°.", vla3D, combined))
                    vla = max(0.0, min(configuration.maxVLAClampDegrees, combined))
                } else {
                    vla = max(0.0, min(configuration.maxVLAClampDegrees, max(vla3D, est * wDiam)))
                }
            } else {
                vla = vla3D
            }
        }

        let imageHLA = computeImageSpaceHLA(observations: selected,
                                            zeroDegreeAngleDegrees: zeroDegreeAngleDegrees,
                                            calibration: calibration)
        warnings.append(contentsOf: imageHLA.warnings)

        let hlaDisplay: String
        if let hla = imageHLA.hla {
            hlaDisplay = ExperimentalDirectionalFormat.angleLR(hla)
        } else {
            hlaDisplay = "—"
        }

        let avgConfidence = selected.map(\.confidence).reduce(0, +) / Double(selected.count)
        if avgConfidence < configuration.lowConfidenceWarningThreshold {
            warnings.append("Average ball tracking confidence is low.")
        }

        return ExperimentalBallLaunchMetrics(
            ballSpeedMph: ballSpeedMph,
            hlaDegrees: imageHLA.hla,
            hlaDisplay: hlaDisplay,
            hla3DRawDegrees: hla3D,
            vlaDegrees: vla,
            vlaRawDegrees: vlaRaw < 0 ? vlaRaw : nil,
            vlaDiameterEstDegrees: vlaDiamEst,
            diameterGrowthFraction: diamGrowth,
            hlaReferenceAngleDegrees: zeroDegreeAngleDegrees,
            ballMovementDx: imageHLA.dx,
            ballMovementDy: imageHLA.dy,
            hlaForwardComponent: imageHLA.forward,
            hlaLateralComponent: imageHLA.lateral,
            pointsUsed: selected.count,
            quality: min(1.0, Double(selected.count) / Double(configuration.preferredBallPointLimit)) * avgConfidence,
            method: method,
            warnings: warnings
        )
    }

    // MARK: - Part F: Metrics point filtering

    private func filterMetricPoints(
        _ input: [ExperimentalBall3DObservation],
        warnings: inout [String]
    ) -> [ExperimentalBall3DObservation] {
        let minPts = configuration.minimumBallPoints
        guard input.count >= minPts else { return input }
        var filtered = input

        // Step 1: confidence filter
        let confStep = filtered.filter { $0.confidence >= configuration.minMetricPointConfidence }
        if confStep.count >= minPts {
            if confStep.count < filtered.count {
                warnings.append("Filtered \(filtered.count - confStep.count) low-confidence metric points.")
            }
            filtered = confStep
        }

        // Step 2: diameter outlier filter
        let sortedDiam = filtered.map(\.diameterNorm).sorted()
        let medDiam = sortedDiam[sortedDiam.count / 2]
        let maxDiam = medDiam * CGFloat(configuration.maxMetricDiameterRatioToMedian)
        let diamStep = filtered.filter { $0.diameterNorm <= maxDiam }
        if diamStep.count >= minPts {
            if diamStep.count < filtered.count {
                warnings.append("Filtered \(filtered.count - diamStep.count) outlier-diameter metric points.")
            }
            filtered = diamStep
        }

        // Step 3: perpendicular path-residual filter (requires ≥3 points to fit a line)
        guard filtered.count >= 3 else { return filtered }
        let times = filtered.map(\.relativeTime)
        let xs    = filtered.map { Double($0.imageX) }
        let ys    = filtered.map { Double($0.imageY) }
        let meanT = times.reduce(0, +) / Double(times.count)
        let cx0   = xs.reduce(0, +) / Double(xs.count)
        let cy0   = ys.reduce(0, +) / Double(ys.count)
        let denom = times.map { pow($0 - meanT, 2) }.reduce(0, +)
        guard denom > 0 else { return filtered }
        let dx = zip(times, xs).map { ($0 - meanT) * $1 }.reduce(0, +) / denom
        let dy = zip(times, ys).map { ($0 - meanT) * $1 }.reduce(0, +) / denom
        let dirLen = sqrt(dx * dx + dy * dy)
        guard dirLen > 1e-6 else { return filtered }
        let ndx = dx / dirLen, ndy = dy / dirLen
        let residStep = filtered.filter { obs in
            let ox = Double(obs.imageX) - cx0
            let oy = Double(obs.imageY) - cy0
            return abs(ox * ndy - oy * ndx) <= configuration.maxMetricPositionResidualNorm
        }
        if residStep.count >= minPts {
            if residStep.count < filtered.count {
                warnings.append("Filtered \(filtered.count - residStep.count) path-outlier metric points.")
            }
            filtered = residStep
        }

        return filtered
    }

    // MARK: - Pinhole2DSize VLA

    /// New VLA model: use image coordinates + apparent diameter (pinhole depth) to estimate VLA.
    /// Returns nil if insufficient data.
    private func calculatePinhole2DVla(
        selected: [ExperimentalBall3DObservation],
        calibration: ExperimentalCameraCalibration,
        warnings: inout [String]
    ) -> Double? {
        let W = Double(calibration.imageWidthPixels)
        let H = Double(calibration.imageHeightPixels)
        let fovXRad = calibration.horizontalFOVDegrees * .pi / 180.0
        let fovYRad = calibration.verticalFOVDegrees * .pi / 180.0
        let fx = W / (2.0 * tan(fovXRad / 2.0))
        let fy = H / (2.0 * tan(fovYRad / 2.0))
        let fAvg = (fx + fy) / 2.0
        let ballDiamM = calibration.realBallDiameterMeters

        let valid = selected.filter { $0.diameterNorm > 0 }
        guard valid.count >= 2 else {
            warnings.append("Pinhole2DSize VLA: fewer than 2 valid diameter points.")
            return nil
        }
        let pts = Array(valid.prefix(6))

        let initCx = Double(pts[0].imageX)
        let usePersp = configuration.useRightwardPerspectiveSizeCorrection
        let strength = configuration.rightwardSizeCorrectionStrength
        let maxCorr  = configuration.maxSizeCorrectionRatio

        func correctedDia(_ obs: ExperimentalBall3DObservation) -> Double {
            let dia = Double(obs.diameterNorm)
            guard usePersp else { return dia }
            let dxNorm = Double(obs.imageX) - initCx
            let scale = 1.0 / max(1e-6, 1.0 + strength * max(0.0, dxNorm))
            let corrected = dia / scale
            return min(corrected, dia * maxCorr)
        }

        struct EnrichedPoint {
            let obs: ExperimentalBall3DObservation
            let cDia: Double
            let Z: Double
        }

        var enriched: [EnrichedPoint] = []
        for o in pts {
            let cDia = correctedDia(o)
            let diaPx = cDia * W
            guard diaPx > 0 else { continue }
            let Z = ballDiamM * fAvg / diaPx
            enriched.append(EnrichedPoint(obs: o, cDia: cDia, Z: Z))
        }

        guard enriched.count >= 2 else {
            warnings.append("Pinhole2DSize VLA: not enough points after perspective correction.")
            return nil
        }

        let first = enriched.first!
        let last  = enriched.last!

        let dxPx = (Double(last.obs.imageX) - Double(first.obs.imageX)) * W
        let dyPx = (Double(last.obs.imageY) - Double(first.obs.imageY)) * H
        let dz   = last.Z - first.Z
        let avgZ = (first.Z + last.Z) / 2.0

        let dXm =  dxPx * avgZ / max(fx, 1e-6)
        let dYm = -dyPx * avgZ / max(fy, 1e-6)
        let dZm =  dz

        let imgYW   = configuration.vlaImageYWeight
        let diaDW   = configuration.vlaDiameterDepthWeight
        let depthSgn = configuration.vlaDepthSign
        let depthScl = configuration.vlaDepthScale

        let vertFromImageY = dYm
        let vertFromDepth  = -dZm * depthSgn * depthScl
        let vertCombined   = imgYW * vertFromImageY + diaDW * vertFromDepth
        let horizComponent = max(abs(dXm), 1e-6)

        let rawVLA = atan2(max(0.0, vertCombined), horizComponent) * 180.0 / .pi

        // Diameter growth boost
        let obsGrowth  = (Double(last.obs.diameterNorm) - Double(first.obs.diameterNorm)) / max(Double(first.obs.diameterNorm), 1e-6)
        let corrGrowth = (last.cDia - first.cDia) / max(first.cDia, 1e-6)

        let sigThresh   = configuration.vlaSignificantGrowthThreshold
        let vhThresh    = configuration.vlaVeryHighGrowthThreshold
        let minVLAVH    = configuration.vlaMinFromVeryHighGrowth
        let growthScale = configuration.vlaGrowthBoostDiameterScale

        var boostedVLA = rawVLA
        if corrGrowth > sigThresh {
            let growthVLA = corrGrowth * growthScale
            boostedVLA = max(rawVLA, growthVLA)
        }
        if corrGrowth > vhThresh {
            boostedVLA = max(boostedVLA, minVLAVH)
        }

        let finalVLA = max(0.0, min(configuration.maxVLAPinholeDegrees, boostedVLA))

        if rawVLA < 0 {
            warnings.append(String(format: "Pinhole2DSize VLA raw=%.1f° (negative clamped to 0)", rawVLA))
        }
        if corrGrowth < obsGrowth - 0.01 {
            warnings.append(String(format: "Perspective correction applied: obs_growth=%+.3f corrected_growth=%+.3f", obsGrowth, corrGrowth))
        }
        return finalVLA
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

    /// Computes HLA relative to the user-defined 0° reference direction in image space.
    ///
    /// Velocities are scaled to pixel space before projection so the computed angle
    /// matches the visual angle between the drawn 0° ref line and the drawn ball path.
    private func computeImageSpaceHLA(
        observations: [ExperimentalBall3DObservation],
        zeroDegreeAngleDegrees: Double,
        calibration: ExperimentalCameraCalibration
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

        // Scale to pixel space: the 0° ref line is drawn in pixels, so both vectors
        // must be in the same space for the angle to match the display.
        let W = Double(calibration.imageWidthPixels)
        let H = Double(calibration.imageHeightPixels)
        let dxPx = dxdt * W
        let dyPx = dydt * H

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

    // MARK: - Club metrics

    private func calculateClubMetrics(
        clubObservations: [ExperimentalClubObservation],
        ball3DObservations: [ExperimentalBall3DObservation],
        calibration: ExperimentalCameraCalibration,
        impactFrameIndex: Int
    ) -> ExperimentalClubMetrics {
        var warnings = ["Club speed is approximate because club depth is assumed from ball depth near impact."]
        guard let assumedDepth = nearestBallDepth(ball3DObservations, impactFrameIndex: impactFrameIndex) else {
            warnings.append("No ball depth near impact for club speed.")
            return ExperimentalClubMetrics(
                clubSpeedMph: nil, pointsUsed: 0, quality: 0,
                method: "not_enough_data", warnings: warnings, speedFrameIndices: []
            )
        }

        let points = clubObservations
            .filter { $0.frameIndex <= impactFrameIndex && $0.confidence > 0 }
            .compactMap { obs -> (frameIndex: Int, time: Double, position: SIMD3<Double>, confidence: Double)? in
                guard let x = obs.leadingEdgeX ?? obs.centerX,
                      let y = obs.leadingEdgeY ?? obs.centerY,
                      let position = calibration.positionMeters(centerX: x, centerY: y, depthMeters: assumedDepth) else {
                    return nil
                }
                return (obs.frameIndex, obs.relativeTime, position, obs.confidence)
            }
            .sorted { $0.frameIndex < $1.frameIndex }

        guard points.count >= configuration.minimumClubPoints else {
            warnings.append("Not enough club points for club speed.")
            return ExperimentalClubMetrics(
                clubSpeedMph: nil, pointsUsed: points.count, quality: 0,
                method: "not_enough_data", warnings: warnings,
                speedFrameIndices: points.map(\.frameIndex)
            )
        }

        let velocity: SIMD3<Double>?
        let method: String
        if points.count >= 3 {
            velocity = linearFitVelocity(points.map { ($0.time, $0.position) })
            method = "linear_fit_\(points.count)_points_assumed_ball_depth"
        } else {
            let dt = points[1].time - points[0].time
            velocity = dt > 0 ? (points[1].position - points[0].position) / dt : nil
            method = "two_point_delta_assumed_ball_depth"
            warnings.append("Club velocity used 2-point fallback.")
        }

        guard let velocity else {
            warnings.append("Club velocity calculation failed due to invalid time span.")
            return ExperimentalClubMetrics(
                clubSpeedMph: nil, pointsUsed: points.count, quality: 0,
                method: method, warnings: warnings, speedFrameIndices: points.map(\.frameIndex)
            )
        }

        let avgConfidence = points.map(\.confidence).reduce(0, +) / Double(points.count)
        let speedMph = vectorLength(velocity) * 2.23694
        print("Club speed points used: \(points.count)")
        print(String(format: "Club speed: %.1f mph", speedMph))

        return ExperimentalClubMetrics(
            clubSpeedMph: speedMph,
            pointsUsed: points.count,
            quality: min(1.0, Double(points.count) / 6.0) * avgConfidence * 0.65,
            method: method,
            warnings: warnings,
            speedFrameIndices: points.map(\.frameIndex)
        )
    }

    // MARK: - Helpers

    private func nearestBallDepth(_ observations: [ExperimentalBall3DObservation], impactFrameIndex: Int) -> Double? {
        observations
            .filter { $0.frameIndex >= impactFrameIndex - 1 }
            .min { abs($0.frameIndex - impactFrameIndex) < abs($1.frameIndex - impactFrameIndex) }?
            .positionMeters.z
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

    private func printSummary(_ result: ExperimentalShotMetricsResult) {
        print("Experimental metrics complete")
        print(result.ballLaunch.ballSpeedMph.map { String(format: "Ball speed: %.1f mph", $0) } ?? "Ball speed: not enough data")
        print(result.ballLaunch.hlaDegrees.map { String(format: "HLA (image-ref): %.1f° (%@)", $0, result.ballLaunch.hlaDisplay) } ?? "HLA: not enough data")
        print(result.ballLaunch.hla3DRawDegrees.map { String(format: "HLA (3D raw): %.1f°", $0) } ?? "HLA 3D: not enough data")
        print(result.ballLaunch.vlaDegrees.map { String(format: "VLA: %.1f°", $0) } ?? "VLA: not enough data")
        print(result.club.clubSpeedMph.map { String(format: "Club speed: %.1f mph", $0) } ?? "Club speed: not enough data")
        print(result.smashFactor.map { String(format: "Smash factor: %.2f", $0) } ?? "Smash factor: not enough data")
        print(result.distance.carryYards.map { String(format: "Estimated carry: %.0f yd (ideal: %.0f yd × cf=%.2f)", $0, result.distance.idealCarryYards ?? 0, result.distance.carryCorrectionFactor) } ?? "Estimated carry: not enough data")
        print(result.distance.totalYards.map { String(format: "Estimated total: %.0f yd (rollout %.0f%%)", $0, (result.distance.rolloutFraction ?? 0) * 100) } ?? "Estimated total: not enough data")
        print(result.spin.estimatedBackspinRpm.map { String(format: "Est. backspin: %.0f rpm", $0) } ?? "Backspin: not enough data")
        print("Club path: \(result.clubPath.clubPathDisplay)  Face: \(result.faceAngle.faceAngleDisplay)  F-to-P: \(result.faceAngle.faceToPathDisplay)")
        print("Experimental metric warnings: \(result.warnings.joined(separator: " | "))")
    }
}
#endif
