import Foundation

struct DistanceEstimate {
    let idealCarryYards: Double?
    let carryCorrectionFactor: Double
    let carryYards: Double?
    let rolloutYards: Double?
    let totalYards: Double?
    let rolloutFraction: Double?
    let vlaBucket: String
    let method: String
    let warnings: [String]
}

struct DistanceEstimator {
    // Below this ball speed the shot is a putt/roll; bypass the full-swing flight model.
    private let puttSpeedCutoffMph: Double = 12.0
    // Rolling resistance of a golf ball on turf (~0.08 fast green … ~0.20 rough); middle estimate.
    private let rollingResistance: Double = 0.12
    // The trained flight model is fit to full shots; below this ball speed it just emits its bias
    // (~35 yd) regardless of input, so chips/pitches use speed-scaled physics instead.
    private let flightModelMinSpeedMph: Double = 50.0

    func estimate(
        ballSpeedMph: Double?,
        vlaDegrees: Double?,
        hlaDegrees: Double?,
        carryCorrectionFactor: Double = 0.75,
        flightModel: FlightModelPredictor? = nil,
        backspinRpm: Double? = nil
    ) -> DistanceEstimate {
        var warnings = [String]()

        guard let ballSpeedMph, ballSpeedMph > 0 else {
            warnings.append("Distance estimate skipped: missing ball speed.")
            return DistanceEstimate(
                idealCarryYards: nil, carryCorrectionFactor: carryCorrectionFactor,
                carryYards: nil, rolloutYards: nil, totalYards: nil,
                rolloutFraction: nil, vlaBucket: "unknown",
                method: "unavailable", warnings: warnings)
        }
        guard let vlaDegrees, vlaDegrees.isFinite else {
            warnings.append("Distance estimate skipped: missing VLA.")
            return DistanceEstimate(
                idealCarryYards: nil, carryCorrectionFactor: carryCorrectionFactor,
                carryYards: nil, rolloutYards: nil, totalYards: nil,
                rolloutFraction: nil, vlaBucket: "unknown",
                method: "unavailable", warnings: warnings)
        }

        if hlaDegrees == nil {
            warnings.append("HLA unavailable; distance model ignores lateral curve.")
        }

        // Putt / slow roll: the trained flight model is fit to full shots and extrapolates a
        // bogus 30+ yd rollout at putt speeds (its bias term dominates when inputs ≈ 0). A ball
        // this slow doesn't fly — it rolls. Estimate the roll distance from kinetic energy vs
        // rolling resistance (d = v² / (2·μ·g)) instead of consulting the flight model.
        if ballSpeedMph < puttSpeedCutoffMph {
            let speedMps  = ballSpeedMph / 2.23694
            let rollMeters = (speedMps * speedMps) / (2.0 * rollingResistance * 9.80665)
            let rollYards  = rollMeters * 1.09361
            warnings.append(String(format: "Putt/roll: %.1f mph → %.1f yd roll (flight model bypassed).",
                                   ballSpeedMph, rollYards))
            return DistanceEstimate(
                idealCarryYards: nil, carryCorrectionFactor: 1.0,
                carryYards: nil, rolloutYards: rollYards > 0 ? rollYards : nil,
                totalYards: rollYards > 0 ? rollYards : nil,
                rolloutFraction: 1.0, vlaBucket: "putt_roll",
                method: "putt_rolling_physics", warnings: warnings)
        }

        let clampedVLA = min(max(vlaDegrees, 0.5), 65)
        if clampedVLA != vlaDegrees {
            warnings.append(String(format: "VLA %.1f° clamped to %.1f° for distance estimate.", vlaDegrees, clampedVLA))
        }

        let speedMps = ballSpeedMph / 2.23694
        let vlaRad   = clampedVLA * .pi / 180.0
        let idealCarryMeters = (speedMps * speedMps * sin(2.0 * vlaRad)) / 9.80665
        let idealCarryYards  = idealCarryMeters * 1.09361

        // Hard physical ceiling: a ball launched at this speed cannot travel farther than its
        // optimal-launch (45°) vacuum range — even with roll — by more than a small margin. This
        // is a sanity cap so no path can ever report a physically impossible distance.
        let physicalMaxYards = ((speedMps * speedMps) / 9.80665) * 1.09361 * 1.25

        // Flight model path (trained ridge regression) — only trusted at full-shot speeds.
        if let fm = flightModel, ballSpeedMph >= flightModelMinSpeedMph {
            let carry      = clamp(fm.predictCarry(ballSpeedMph: ballSpeedMph,
                                                   vlaDegrees: clampedVLA,
                                                   idealCarryYards: idealCarryYards), 0, 450)
            let rollout    = clamp(fm.predictRollout(ballSpeedMph: ballSpeedMph,
                                                     vlaDegrees: clampedVLA,
                                                     idealCarryYards: idealCarryYards,
                                                     carryYards: carry,
                                                     backspinRpm: backspinRpm), 0, 150)
            let total      = min(carry + rollout, 400, physicalMaxYards)
            let rollFrac   = carry > 0 ? rollout / carry : 0
            if total > 350 {
                warnings.append("Total distance estimate >350 yd — verify calibration and FOV settings.")
            }
            warnings.append(String(format: "FlightModel: carry=%.0f yd  rollout=%.0f yd  total=%.0f yd",
                                   carry, rollout, total))
            return DistanceEstimate(
                idealCarryYards: idealCarryYards > 0 ? idealCarryYards : nil,
                carryCorrectionFactor: 1.0,
                carryYards: carry > 0 ? carry : nil,
                rolloutYards: rollout > 0 ? rollout : nil,
                totalYards: total > 0 ? total : nil,
                rolloutFraction: rollFrac,
                vlaBucket: "flightModel",
                method: "flightModel_ridge",
                warnings: warnings
            )
        }

        // Physics fallback
        let correctionFactor = clamp(carryCorrectionFactor, 0.40, 1.20)
        let carry = clamp(idealCarryYards * correctionFactor, 0, 450)

        let baseRollout: Double
        let vlaBucket: String
        if clampedVLA < 1 {
            baseRollout = 0.85; vlaBucket = "vla<1°"
        } else if clampedVLA < 3 {
            baseRollout = 0.65; vlaBucket = "1°≤vla<3°"
        } else if clampedVLA < 6 {
            baseRollout = 0.45; vlaBucket = "3°≤vla<6°"
        } else if clampedVLA < 10 {
            baseRollout = 0.30; vlaBucket = "6°≤vla<10°"
        } else if clampedVLA < 15 {
            baseRollout = 0.20; vlaBucket = "10°≤vla<15°"
        } else if clampedVLA < 22 {
            baseRollout = 0.12; vlaBucket = "15°≤vla<22°"
        } else if clampedVLA < 30 {
            baseRollout = 0.07; vlaBucket = "22°≤vla<30°"
        } else if clampedVLA < 40 {
            baseRollout = 0.04; vlaBucket = "30°≤vla<40°"
        } else if clampedVLA < 50 {
            baseRollout = 0.03; vlaBucket = "40°≤vla<50°"
        } else {
            baseRollout = 0.01; vlaBucket = "vla≥50°"
        }

        let speedAdjust: Double
        if ballSpeedMph < 40        { speedAdjust = 0.45 }
        else if ballSpeedMph < 80   { speedAdjust = 0.75 }
        else if ballSpeedMph >= 130 { speedAdjust = 1.10 }
        else                        { speedAdjust = 1.00 }

        let rolloutFraction = clamp(baseRollout * speedAdjust, 0.02, 0.90)
        let rolloutYards    = carry * rolloutFraction
        let total           = min(carry + rolloutYards, 400, physicalMaxYards)

        if total > 350 {
            warnings.append("Total distance estimate >350 yd — verify calibration and FOV settings.")
        }
        warnings.append("Total = carry + VLA-based rollout. Spin and ground conditions unknown.")
        warnings.append(String(format: "Carry: idealCarry=%.0f yd × correctionFactor=%.2f = %.0f yd",
                               idealCarryYards, correctionFactor, carry))
        warnings.append(String(format: "Rollout: %.0f%% of carry (VLA bucket: %@)", rolloutFraction * 100, vlaBucket))

        return DistanceEstimate(
            idealCarryYards: idealCarryYards > 0 ? idealCarryYards : nil,
            carryCorrectionFactor: correctionFactor,
            carryYards: carry > 0 ? carry : nil,
            rolloutYards: rolloutYards > 0 ? rolloutYards : nil,
            totalYards: total > 0 ? total : nil,
            rolloutFraction: rolloutFraction,
            vlaBucket: vlaBucket,
            method: String(format: "physics_carry_cf%.2f_rollout%.0fpct_%@",
                           correctionFactor, rolloutFraction * 100, vlaBucket),
            warnings: warnings
        )
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
