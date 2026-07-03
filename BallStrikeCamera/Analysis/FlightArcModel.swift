import Foundation
import simd

/// Point-mass golf ball flight integrator ported from the web sim's physics
/// (TrueCarry_Sim/js/physics.js: drag crisis + Magnus lift + spin decay) so
/// app-drawn arcs share one aerodynamic model with the sim.
enum FlightArcModel {
    struct Sample {
        let downrangeYd: Double
        let offlineYd: Double   // positive = right of target line
        let heightFt: Double
    }

    private static let g = 9.81
    private static let ballR = 0.0214          // regulation ball radius, m
    private static let aero = 0.0192           // 0.5 * rho * A / m
    private static let clSlope = 2.2           // lift coeff vs spin ratio, saturating
    private static let clMax = 0.32
    private static let cdBase = 0.255
    private static let spinDecay = 10.0        // s

    /// Integrates launch conditions to landing. Empty when speed is unusable.
    static func trajectory(ballSpeedMph: Double,
                           vlaDeg: Double,
                           hlaDeg: Double,
                           backspinRpm: Double,
                           sidespinRpm: Double) -> [Sample] {
        let speed = ballSpeedMph * 0.44704
        guard speed > 2, vlaDeg > 0.1 else { return [] }
        let vla = vlaDeg * .pi / 180
        let hla = hlaDeg * .pi / 180

        // Launch frame: +z downrange, +x right, +y up.
        let dir = SIMD3<Double>(sin(hla), 0, cos(hla))
        var vel = dir * (speed * cos(vla)) + SIMD3<Double>(0, speed * sin(vla), 0)
        var pos = SIMD3<Double>(0, 0.02, 0)
        let rpmToRad = Double.pi * 2 / 60
        // Backspin about the horizontal axis perpendicular to flight (dir × up,
        // matching the sim — this order gives upward Magnus); sidespin about vertical.
        let backAxis = simd_normalize(simd_cross(dir, SIMD3<Double>(0, 1, 0)))
        var omega = backAxis * (backspinRpm * rpmToRad) + SIMD3<Double>(0, sidespinRpm * rpmToRad, 0)

        var samples = [Sample(downrangeYd: 0, offlineYd: 0, heightFt: 0)]
        let dt = 1.0 / 120.0
        var step = 0
        while pos.y > 0, step < 3000 {
            let vmag = simd_length(vel)
            var acc = SIMD3<Double>(0, -g, 0)
            if vmag > 0.01 {
                let spinRate = simd_length(omega)
                let s = spinRate * ballR / vmag
                let cl = min(clMax, clSlope * s)
                let hi = min(max((vmag - 30) / 25, 0), 1)   // drag crisis ramp
                let cd = cdBase - 0.055 * hi + 0.30 * cl
                acc += vel * (-aero * cd * vmag)
                if spinRate > 1 {
                    let liftDir = simd_normalize(simd_cross(omega / spinRate, vel / vmag))
                    acc += liftDir * (aero * cl * vmag * vmag)
                }
            }
            vel += acc * dt
            pos += vel * dt
            omega *= exp(-dt / spinDecay)
            step += 1
            if step % 6 == 0 || pos.y <= 0 {
                samples.append(Sample(
                    downrangeYd: pos.z * 1.09361,
                    offlineYd: pos.x * 1.09361,
                    heightFt: max(0, pos.y) * 3.28084
                ))
            }
        }
        return samples
    }
}
