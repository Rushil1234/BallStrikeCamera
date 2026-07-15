import Foundation

struct SpinEstimate {
    let estimatedBackspinRpm: Double?
    let estimatedSidespinRpmSigned: Double?
    let estimatedSidespinDisplay: String
    let estimatedSpinAxisDegreesSigned: Double?
    let estimatedSpinAxisDisplay: String
    let spinEstimateMethod: String
    let warnings: [String]
}

struct SpinEstimator {
    func estimate(
        ballSpeedMph: Double?,
        vlaDegrees: Double?,
        hlaDegrees: Double?,
        clubPathDegrees: Double?,
        smashFactor: Double? = nil
    ) -> SpinEstimate {
        var warnings: [String] = [
            "Backspin is ESTIMATED from a speed/VLA model fit to TopTracer range data. Not measured.",
            "Sidespin is ESTIMATED from HLA/path angle difference. Not measured."
        ]

        guard let ballSpeedMph, ballSpeedMph > 0 else {
            warnings.append("Spin estimate unavailable: missing ball speed.")
            return SpinEstimate(
                estimatedBackspinRpm: nil,
                estimatedSidespinRpmSigned: nil, estimatedSidespinDisplay: "—",
                estimatedSpinAxisDegreesSigned: nil, estimatedSpinAxisDisplay: "—",
                spinEstimateMethod: "unavailable", warnings: warnings
            )
        }

        let vla = vlaDegrees ?? 15.0
        if vlaDegrees == nil {
            warnings.append("VLA unavailable — backspin estimate uses default VLA=15°.")
        }

        let backspinRpm = min(max(Self.fittedBackspin(ballSpeedMph: ballSpeedMph, vla: vla), 1200), 11500)

        let sidespinRpmSigned: Double?
        let spinAxisDegreesSigned: Double?
        let method: String

        if let hla = hlaDegrees, let path = clubPathDegrees {
            let faceToPath  = hla - path
            let speedFactor = ballSpeedMph / 100.0
            let sidespin    = min(max(faceToPath * 200.0 * speedFactor, -4000), 4000)
            sidespinRpmSigned     = sidespin
            spinAxisDegreesSigned = atan2(sidespin, backspinRpm) * 180.0 / .pi
            method = "vla_speed_smash_piecewise_sidespin_hla_minus_path"
        } else if let hla = hlaDegrees {
            let speedFactor = ballSpeedMph / 100.0
            let sidespin    = min(max(hla * 150.0 * speedFactor, -4000), 4000)
            sidespinRpmSigned     = sidespin
            spinAxisDegreesSigned = atan2(sidespin, backspinRpm) * 180.0 / .pi
            warnings.append("Club path unavailable — sidespin estimated from HLA only (lower accuracy).")
            method = "vla_speed_smash_piecewise_sidespin_hla_only"
        } else {
            sidespinRpmSigned     = nil
            spinAxisDegreesSigned = nil
            warnings.append("HLA unavailable — sidespin and spin axis unavailable.")
            method = "vla_speed_smash_piecewise_sidespin_unavailable"
        }

        let sidespinDisplay = sidespinRpmSigned.map    { DirectionalFormat.spinLR($0) } ?? "—"
        let spinAxisDisplay = spinAxisDegreesSigned.map { DirectionalFormat.angleLR($0) } ?? "—"

        return SpinEstimate(
            estimatedBackspinRpm: backspinRpm,
            estimatedSidespinRpmSigned: sidespinRpmSigned,
            estimatedSidespinDisplay: sidespinDisplay,
            estimatedSpinAxisDegreesSigned: spinAxisDegreesSigned,
            estimatedSpinAxisDisplay: spinAxisDisplay,
            spinEstimateMethod: method,
            warnings: warnings
        )
    }

    /// Ridge fit on 116 TopTracer-measured spins (swingsync-2026-07-12, range balls, full
    /// bag; 5-fold CV MAE 1045 rpm vs 1264 for the old hand-written table). Features
    /// standardized as (x−μ)/σ; trained via tools — retrain with
    /// scratchpad/train_flight_model.py's sibling when new labeled sessions land.
    private static func fittedBackspin(ballSpeedMph bs: Double, vla: Double) -> Double {
        let x: [Double]  = [vla, bs, vla * bs, vla * vla]
        let w: [Double]  = [1613.938, 391.840, -440.579, -545.295]
        let mu: [Double] = [17.284, 98.544, 1623.959, 340.809]
        let sd: [Double] = [6.486, 23.693, 456.117, 291.919]
        var spin = 2810.33
        for i in 0..<4 { spin += w[i] * (x[i] - mu[i]) / sd[i] }
        return spin
    }
}
