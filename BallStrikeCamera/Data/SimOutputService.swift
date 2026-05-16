import Foundation

// MARK: - Sim Output Service

/// Generates and exports shot data in formats compatible with sim providers.
final class SimOutputService {

    // MARK: - GSPro / OGS OpenAPI format

    struct SimShotPacket: Codable {
        var DeviceID:          String = "BallStrike"
        var Units:             String = "Yards"
        var ShotNumber:        Int    = 1
        var APIversion:        String = "1"
        var BallData: BallData
        var ClubData: ClubData
        var ShotDataOptions: ShotDataOptions

        struct BallData: Codable {
            var Speed:          Double  // mph
            var SpinAxis:       Double  // degrees (+ = draw, - = fade)
            var TotalSpin:      Double  // rpm
            var BackSpin:       Double  // rpm
            var SideSpin:       Double  // rpm
            var HLA:            Double  // horizontal launch angle degrees
            var VLA:            Double  // vertical launch angle degrees
            var CarryDistance:  Double  // yards
        }
        struct ClubData: Codable {
            var Speed:          Double  // mph
            var AngleOfAttack:  Double  // degrees
            var FaceToTarget:   Double  // degrees
            var Lie:            Double = 0
            var Loft:           Double = 0
            var Path:           Double  // degrees
            var SpeedAtImpact:  Double  // mph
            var VerticalFaceImpact: Double = 0
            var HorizontalFaceImpact: Double = 0
            var ClosureRate:    Double = 0
        }
        struct ShotDataOptions: Codable {
            var ContainsBallData:  Bool = true
            var ContainsClubData:  Bool = true
            var LaunchMonitorIsReady:  Bool = true
            var LaunchMonitorBallDetected: Bool = true
            var IsHeartBeat:       Bool = false
        }
    }

    // MARK: - Build packet from SavedShotMetrics

    func buildGSProPacket(metrics: SavedShotMetrics, shotNumber: Int = 1) -> SimShotPacket {
        SimShotPacket(
            ShotNumber: shotNumber,
            BallData: SimShotPacket.BallData(
                Speed:         metrics.ballSpeedMph,
                SpinAxis:      metrics.spinAxisDegrees,
                TotalSpin:     sqrt(pow(metrics.backspinRpm, 2) + pow(metrics.sidespinRpm, 2)),
                BackSpin:      metrics.backspinRpm,
                SideSpin:      metrics.sidespinRpm,
                HLA:           metrics.hlaDegrees,
                VLA:           metrics.vlaDegrees,
                CarryDistance: metrics.carryYards
            ),
            ClubData: SimShotPacket.ClubData(
                Speed:          metrics.clubSpeedMph,
                AngleOfAttack:  metrics.vlaDegrees,
                FaceToTarget:   metrics.faceAngleDegrees,
                Path:           metrics.clubPathDegrees,
                SpeedAtImpact:  metrics.clubSpeedMph
            ),
            ShotDataOptions: SimShotPacket.ShotDataOptions()
        )
    }

    // MARK: - Local JSON export

    /// Returns a pretty-printed JSON string of the shot packet.
    func jsonString(metrics: SavedShotMetrics, shotNumber: Int = 1) -> String {
        let packet = buildGSProPacket(metrics: metrics, shotNumber: shotNumber)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(packet),
              let str  = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    /// Writes the shot JSON to a file and returns the URL.
    func exportToFile(metrics: SavedShotMetrics,
                      userId: UUID,
                      shotId: UUID,
                      shotNumber: Int = 1) throws -> URL {
        let dir = AppStorageManager.shotFramesDir(userId: userId, shotId: shotId)
        AppStorageManager.ensureDirectory(dir)
        let url = dir.appendingPathComponent("sim_output.json")
        let packet = buildGSProPacket(metrics: metrics, shotNumber: shotNumber)
        try AppStorageManager.save(packet, to: url)
        return url
    }

    // MARK: - Simple flat format (for "Local JSON" export to Files app)

    struct FlatShotExport: Codable {
        var timestamp:          String
        var clubName:           String?
        var ballSpeedMph:       Double
        var launchAngleDeg:     Double
        var horizontalAngleDeg: Double
        var spinRatePrm:        Double
        var carryYards:         Double
        var totalYards:         Double
        var smashFactor:        Double
        var clubSpeedMph:       Double
        var clubPathDeg:        Double
        var faceAngleDeg:       Double
    }

    func flatExport(shot: SavedShot) -> FlatShotExport {
        let m = shot.metrics
        let fmt = ISO8601DateFormatter()
        return FlatShotExport(
            timestamp:          fmt.string(from: shot.timestamp),
            clubName:           shot.clubName,
            ballSpeedMph:       m.ballSpeedMph,
            launchAngleDeg:     m.vlaDegrees,
            horizontalAngleDeg: m.hlaDegrees,
            spinRatePrm:        m.backspinRpm,
            carryYards:         m.carryYards,
            totalYards:         m.totalYards,
            smashFactor:        m.smashFactor,
            clubSpeedMph:       m.clubSpeedMph,
            clubPathDeg:        m.clubPathDegrees,
            faceAngleDeg:       m.faceAngleDegrees
        )
    }
}
