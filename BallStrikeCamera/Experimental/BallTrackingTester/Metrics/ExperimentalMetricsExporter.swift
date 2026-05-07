#if DEBUG
import Foundation
import CoreGraphics

struct ExperimentalMetricsExporter {
    func export(
        sequence: BallTrackingTestSequence,
        result: BallTrackingTestResult,
        settings: BallTrackingTuningSettings
    ) throws -> URL {
        guard let metrics = result.metrics else {
            throw ExportError.noMetrics
        }

        let destination: URL
        if let sourceURL = sequence.sourceURL {
            destination = sourceURL.appendingPathComponent("experimental_metrics.json")
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            destination = docs.appendingPathComponent("experimental_metrics_\(sequence.sourceName).json")
        }

        let data = try JSONSerialization.data(
            withJSONObject: payload(sequence: sequence, result: result, metrics: metrics, settings: settings),
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: destination)
        print("Exported experimental metrics JSON: \(destination.path)")
        return destination
    }

    enum ExportError: LocalizedError {
        case noMetrics

        var errorDescription: String? {
            switch self {
            case .noMetrics:
                return "Run tracking and metrics before exporting experimental metrics."
            }
        }
    }

    private func payload(
        sequence: BallTrackingTestSequence,
        result: BallTrackingTestResult,
        metrics: ExperimentalShotMetricsResult,
        settings: BallTrackingTuningSettings
    ) -> [String: Any] {
        [
            "schema": "ballstrike.experimental_metrics.v2",
            "sourceName": sequence.sourceName,
            "detectedImpactFrameIndex": metrics.detectedImpactFrameIndex,
            "fallbackImpactFrameIndex": metrics.fallbackImpactFrameIndex,
            "faceFrameIndex": metrics.faceFrameIndex,
            "faceFrameReason": "detectedImpactFrameIndex_plus_one",
            "impactDetectionReason": result.impactDetectionReason,
            "zeroDegreeReferenceAngleDegrees": metrics.zeroDegreeReferenceAngleDegrees,
            "calibration": calibrationJSON(metrics.calibration),
            "metrics": metricsJSON(metrics),
            "warnings": metrics.warnings,
            "settings": settingsJSON(settings),
            "ballTrackingObservations": result.observations.map(ballObservationJSON),
            "ball3DObservations": metrics.ball3DObservations.map(ball3DJSON),
            "clubObservations": metrics.clubObservations.map(clubObservationJSON)
        ]
    }

    private func metricsJSON(_ metrics: ExperimentalShotMetricsResult) -> [String: Any] {
        var d: [String: Any] = [
            // Ball launch
            "ballSpeedMph":          jsonNumber(metrics.ballLaunch.ballSpeedMph),
            "hlaDegrees":            jsonNumber(metrics.ballLaunch.hlaDegrees),
            "hlaDisplay":            metrics.ballLaunch.hlaDisplay,
            "hla3DRawDegrees":       jsonNumber(metrics.ballLaunch.hla3DRawDegrees),
            "hlaReferenceAngle":     metrics.ballLaunch.hlaReferenceAngleDegrees,
            "hlaForwardComponent":   jsonNumber(metrics.ballLaunch.hlaForwardComponent),
            "hlaLateralComponent":   jsonNumber(metrics.ballLaunch.hlaLateralComponent),
            "vlaDegrees":            jsonNumber(metrics.ballLaunch.vlaDegrees),
            "vlaRaw3DDegrees":        jsonNumber(metrics.ballLaunch.vlaRawDegrees),
            "vlaDiameterEstDegrees":  jsonNumber(metrics.ballLaunch.vlaDiameterEstDegrees),
            "diameterGrowthFraction": jsonNumber(metrics.ballLaunch.diameterGrowthFraction),
            // VLA model fields
            "vlaModelUsed":                 metrics.ballLaunch.vlaModelUsed,
            "vlaLegacyDegrees":             jsonNumber(metrics.ballLaunch.vlaLegacyDegrees),
            "vlaPinhole2DSizeDegrees":      jsonNumber(metrics.ballLaunch.vlaPinhole2DSizeDegrees),
            "vlaTrainedModelDegrees":       jsonNumber(metrics.ballLaunch.vlaTrainedModelDegrees),
            "vlaFinalDegrees":              jsonNumber(metrics.ballLaunch.vlaFinalDegrees),
            "vlaModelFile":                 metrics.ballLaunch.vlaModelFile as Any,
            "vlaModelFeaturesUsed":         metrics.ballLaunch.vlaModelFeaturesUsed,
            "vlaModelFeatureValues":        metrics.ballLaunch.vlaModelFeatureValues,
            "vlaModelWarnings":             metrics.ballLaunch.vlaModelWarnings,
            "vlaWasClamped":                metrics.ballLaunch.vlaWasClamped,
            "distanceVLAUsedSource":        metrics.distance.distanceVLAUsedSource,
            "spinVLAUsedSource":            metrics.spin.spinVLAUsedSource,
            "carryYardsUsingFinalVLA":      jsonNumber(metrics.distance.carryYards),
            "rolloutYardsUsingFinalVLA":    jsonNumber(metrics.distance.rolloutYards),
            "totalYardsUsingFinalVLA":      jsonNumber(metrics.distance.totalYards),
            // Club
            "clubSpeedMph":          jsonNumber(metrics.club.clubSpeedMph),
            "smashFactor":           jsonNumber(metrics.smashFactor),
            "rawSmashFactor":        jsonNumber(metrics.rawSmashFactor),
            "smashFactorClamped":    metrics.smashFactorClamped,
            // Distance
            "idealCarryYards":       jsonNumber(metrics.distance.idealCarryYards),
            "carryCorrectionFactor": metrics.distance.carryCorrectionFactor,
            "carryYards":            jsonNumber(metrics.distance.carryYards),
            "rolloutYards":          jsonNumber(metrics.distance.rolloutYards),
            "totalYards":            jsonNumber(metrics.distance.totalYards),
            "rolloutFraction":       jsonNumber(metrics.distance.rolloutFraction),
            "vlaBucket":             metrics.distance.vlaBucket,
            // Spin (all ESTIMATED)
            "estimatedBackspinRpm":           jsonNumber(metrics.spin.estimatedBackspinRpm),
            "estimatedSidespinRpmSigned":     jsonNumber(metrics.spin.estimatedSidespinRpmSigned),
            "estimatedSidespinDisplay":       metrics.spin.estimatedSidespinDisplay,
            "estimatedSpinAxisDegreesSigned": jsonNumber(metrics.spin.estimatedSpinAxisDegreesSigned),
            "estimatedSpinAxisDisplay":       metrics.spin.estimatedSpinAxisDisplay,
            "spinEstimateMethod":             metrics.spin.spinEstimateMethod,
            // Club path
            "clubPathDegreesSigned": jsonNumber(metrics.clubPath.clubPathDegreesSigned),
            "clubPathDisplay":       metrics.clubPath.clubPathDisplay,
            // Face angle (ESTIMATED)
            "estimatedFaceAngleDegreesSigned": jsonNumber(metrics.faceAngle.faceAngleDegreesSigned),
            "estimatedFaceAngleDisplay":       metrics.faceAngle.faceAngleDisplay,
            "faceAngleConfidence":             metrics.faceAngle.confidence,
            "faceToPathDegreesSigned":         jsonNumber(metrics.faceAngle.faceToPathDegreesSigned),
            "faceToPathDisplay":               metrics.faceAngle.faceToPathDisplay,
            // Quality
            "ballPointsUsed":        metrics.ballLaunch.pointsUsed,
            "clubPointsUsed":        metrics.club.pointsUsed,
            "ballQuality":           metrics.ballLaunch.quality,
            "clubQuality":           metrics.club.quality,
            "ballMethod":            metrics.ballLaunch.method,
            "clubMethod":            metrics.club.method,
            "distanceMethod":        metrics.distance.method,
            "clubSpeedFrameIndices": metrics.club.speedFrameIndices
        ]
        if let dx = metrics.ballLaunch.ballMovementDx, let dy = metrics.ballLaunch.ballMovementDy {
            d["ballMovementVector2D"] = ["dx": dx, "dy": dy]
        } else {
            d["ballMovementVector2D"] = NSNull()
        }
        return d
    }

    private func calibrationJSON(_ calibration: ExperimentalCameraCalibration) -> [String: Any] {
        [
            "horizontalFOVDegrees":    calibration.horizontalFOVDegrees,
            "verticalFOVDegrees":      calibration.verticalFOVDegrees,
            "imageWidthPixels":        calibration.imageWidthPixels,
            "imageHeightPixels":       calibration.imageHeightPixels,
            "realBallDiameterMeters":  calibration.realBallDiameterMeters,
            "cameraHeightMeters":      jsonNumber(calibration.cameraHeightMeters),
            "cameraTiltDegrees":       jsonNumber(calibration.cameraTiltDegrees),
            "focalLengthPixelsX":      calibration.focalLengthPixelsX,
            "focalLengthPixelsY":      calibration.focalLengthPixelsY
        ]
    }

    private func ballObservationJSON(_ obs: BallTrackingTestObservation) -> [String: Any] {
        [
            "frameIndex":          obs.frameIndex,
            "detected":            obs.centerX != nil,
            "centerX":             jsonNumber(obs.centerX.map(Double.init)),
            "centerY":             jsonNumber(obs.centerY.map(Double.init)),
            "diameter":            jsonNumber(obs.diameter.map(Double.init)),
            "candidateDiameter":   jsonNumber(obs.candidateDiameter.map(Double.init)),
            "maskRefinedDiameter": jsonNumber(obs.maskRefinedDiameter.map(Double.init)),
            "smoothedDiameter":    jsonNumber(obs.smoothedDiameter.map(Double.init)),
            "confidence":          obs.confidence,
            "debugReason":         obs.debugReason,
            "diameterDebugReason": obs.diameterDebugReason,
            "maskWhitePixelCount": obs.maskWhitePixelCount
        ]
    }

    private func ball3DJSON(_ obs: ExperimentalBall3DObservation) -> [String: Any] {
        [
            "frameIndex":     obs.frameIndex,
            "timestamp":      obs.timestamp,
            "relativeTime":   obs.relativeTime,
            "imageX":         Double(obs.imageX),
            "imageY":         Double(obs.imageY),
            "diameterNorm":   Double(obs.diameterNorm),
            "diameterPixels": obs.diameterPixels,
            "positionMeters": ["x": obs.positionMeters.x, "y": obs.positionMeters.y, "z": obs.positionMeters.z],
            "confidence":     obs.confidence
        ]
    }

    private func clubObservationJSON(_ obs: ExperimentalClubObservation) -> [String: Any] {
        [
            "frameIndex":              obs.frameIndex,
            "timestamp":               obs.timestamp,
            "relativeTime":            obs.relativeTime,
            "centerX":                 jsonNumber(obs.centerX.map(Double.init)),
            "centerY":                 jsonNumber(obs.centerY.map(Double.init)),
            "leadingEdgeX":            jsonNumber(obs.leadingEdgeX.map(Double.init)),
            "leadingEdgeY":            jsonNumber(obs.leadingEdgeY.map(Double.init)),
            "clubBoundingBox":         rectJSON(obs.clubBoundingBox),
            "confidence":              obs.confidence,
            "searchROI":               rectJSON(obs.searchROI),
            "ballExclusionCenterX":    jsonNumber(obs.ballExclusionCenterX.map(Double.init)),
            "ballExclusionCenterY":    jsonNumber(obs.ballExclusionCenterY.map(Double.init)),
            "ballExclusionDiameter":   jsonNumber(obs.ballExclusionDiameter.map(Double.init)),
            "debugReason":             obs.debugReason,
            "detectionMode":           obs.detectionMode,
            "ballExclusionWasApplied": obs.ballExclusionWasApplied,
            "frameDifferenceWasUsed":  obs.frameDifferenceWasUsed
        ]
    }

    private func settingsJSON(_ settings: BallTrackingTuningSettings) -> [String: Any] {
        [
            "tracking": [
                "sampleStride":           settings.sampleStride,
                "trackingMode":           settings.trackingMode.rawValue,
                "preBrightnessThreshold": settings.preBrightnessThreshold,
                "postBrightnessThreshold": settings.postBrightnessThreshold,
                "preImpactSearchScale":   settings.preImpactSearchScale,
                "impactSearchScale":      settings.impactSearchScale,
                "postImpactBaseScale":    settings.postImpactBaseScale,
                "postImpactScaleGrowth":  settings.postImpactScaleGrowth,
                "postImpactMaxScale":     settings.postImpactMaxScale,
                "zeroDegreeAngleDeg":     settings.zeroDegreeAngleDeg
            ],
            "calibration": [
                "horizontalFOVDegrees":   settings.calibration.horizontalFOVDegrees,
                "verticalFOVDegrees":     settings.calibration.verticalFOVDegrees,
                "realBallDiameterMeters": settings.calibration.realBallDiameterMeters,
                "useCameraHeight":        settings.calibration.useCameraHeight,
                "cameraHeightMeters":     settings.calibration.cameraHeightMeters,
                "useCameraTilt":          settings.calibration.useCameraTilt,
                "cameraTiltDegrees":      settings.calibration.cameraTiltDegrees
            ],
            "distanceModel": [
                "carryCorrectionFactor": settings.carryCorrectionFactor
            ],
            "club": [
                "enabled":                        settings.club.enabled,
                "searchBehindBallEnabled":         settings.club.searchBehindBallEnabled,
                "clubTrackingMode":                settings.club.useFrameDifference ? "frameDifference" : "dark_only",
                "ballExclusionRadiusScale":        settings.club.ballExclusionRadiusScale,
                "clubSearchROIScaleX":             settings.club.clubSearchROIScaleX,
                "clubSearchROIScaleY":             settings.club.clubSearchROIScaleY,
                "useFrameDifference":              settings.club.useFrameDifference,
                "frameDifferenceThreshold":        settings.club.frameDifferenceThreshold,
                "minClubBlobArea":                 settings.club.minClubBlobArea,
                "maxClubBlobArea":                 settings.club.maxClubBlobArea,
                "minClubConfidence":               settings.club.minClubConfidence,
                "minClubDarknessOrEdgeThreshold":  settings.club.minClubDarknessOrEdgeThreshold,
                "debugLoggingEnabled":             settings.club.debugLoggingEnabled
            ]
        ]
    }

    private func rectJSON(_ rect: CGRect?) -> Any {
        guard let rect else { return NSNull() }
        return [
            "x":      Double(rect.minX),
            "y":      Double(rect.minY),
            "width":  Double(rect.width),
            "height": Double(rect.height)
        ]
    }

    private func jsonNumber(_ value: Double?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return value
    }
}
#endif
