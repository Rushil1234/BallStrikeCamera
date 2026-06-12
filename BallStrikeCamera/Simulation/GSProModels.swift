import Foundation

// MARK: - Outbound: Shot message

struct GSProShotMessage: Encodable {
    let deviceID: String
    let units: String
    let shotNumber: Int
    let apiVersion: String
    let ballData: GSProBallData?
    let shotDataOptions: GSProShotDataOptions

    enum CodingKeys: String, CodingKey {
        case deviceID          = "DeviceID"
        case units             = "Units"
        case shotNumber        = "ShotNumber"
        case apiVersion        = "APIversion"
        case ballData          = "BallData"
        case shotDataOptions   = "ShotDataOptions"
    }

    static func shot(number: Int, metrics: SavedShotMetrics) -> GSProShotMessage {
        let totalSpin = sqrt(pow(metrics.backspinRpm, 2) + pow(metrics.sidespinRpm, 2))
        return GSProShotMessage(
            deviceID: "TrueCarry",
            units: "Yards",
            shotNumber: number,
            apiVersion: "1",
            ballData: GSProBallData(
                speed:         metrics.ballSpeedMph,
                spinAxis:      metrics.spinAxisDegrees,
                totalSpin:     max(totalSpin, 0),
                backSpin:      max(metrics.backspinRpm, 0),
                sideSpin:      metrics.sidespinRpm,
                hla:           metrics.hlaDegrees,
                vla:           metrics.vlaDegrees,
                carryDistance: metrics.carryYards
            ),
            shotDataOptions: GSProShotDataOptions(
                containsBallData: true,
                launchMonitorBallDetected: true,
                isHeartBeat: false
            )
        )
    }

    /// Sent immediately on connection — tells GSPro the launch monitor is ready so the
    /// range screen finishes loading (otherwise it stalls at ~90% waiting for this signal).
    static func ready(number: Int) -> GSProShotMessage {
        GSProShotMessage(
            deviceID: "TrueCarry",
            units: "Yards",
            shotNumber: number,
            apiVersion: "1",
            ballData: nil,
            shotDataOptions: GSProShotDataOptions(
                containsBallData: false,
                launchMonitorBallDetected: false,
                isHeartBeat: false
            )
        )
    }

    static func heartbeat(number: Int) -> GSProShotMessage {
        GSProShotMessage(
            deviceID: "TrueCarry",
            units: "Yards",
            shotNumber: number,
            apiVersion: "1",
            ballData: nil,
            shotDataOptions: GSProShotDataOptions(
                containsBallData: false,
                launchMonitorBallDetected: false,
                isHeartBeat: true
            )
        )
    }

    static func testShot(number: Int) -> GSProShotMessage {
        let test = SavedShotMetrics()
        var m = test
        m.ballSpeedMph    = 147.5
        m.vlaDegrees      = 14.3
        m.hlaDegrees      = 2.3
        m.backspinRpm     = 2500
        m.sidespinRpm     = -800
        m.spinAxisDegrees = -13.2
        m.carryYards      = 256.5
        return .shot(number: number, metrics: m)
    }
}

struct GSProBallData: Encodable {
    let speed: Double
    let spinAxis: Double
    let totalSpin: Double
    let backSpin: Double
    let sideSpin: Double
    let hla: Double
    let vla: Double
    let carryDistance: Double

    enum CodingKeys: String, CodingKey {
        case speed         = "Speed"
        case spinAxis      = "SpinAxis"
        case totalSpin     = "TotalSpin"
        case backSpin      = "BackSpin"
        case sideSpin      = "SideSpin"
        case hla           = "HLA"
        case vla           = "VLA"
        case carryDistance = "CarryDistance"
    }
}

struct GSProShotDataOptions: Encodable {
    let containsBallData: Bool
    let containsClubData: Bool = false
    let launchMonitorIsReady: Bool = true
    let launchMonitorBallDetected: Bool
    let isHeartBeat: Bool

    enum CodingKeys: String, CodingKey {
        case containsBallData          = "ContainsBallData"
        case containsClubData          = "ContainsClubData"
        case launchMonitorIsReady      = "LaunchMonitorIsReady"
        case launchMonitorBallDetected = "LaunchMonitorBallDetected"
        case isHeartBeat               = "IsHeartBeat"
    }
}

// MARK: - Inbound: GSPro response

struct GSProResponse: Decodable {
    let code: Int?
    let message: String?
    let player: GSProPlayerInfo?

    enum CodingKeys: String, CodingKey {
        case code    = "Code"
        case message = "Message"
        case player  = "Player"
    }
}

struct GSProPlayerInfo: Decodable, Equatable {
    let handed: String?  // "RH" or "LH"
    let club: String?    // "DR", "3W", "5W", "2H"…"9H", "PW", "GW", "SW", "LW", "PT"

    enum CodingKeys: String, CodingKey {
        case handed = "Handed"
        case club   = "Club"
    }

    var clubDisplayName: String? {
        guard let club else { return nil }
        let map: [String: String] = [
            "DR": "Driver", "1W": "Driver",
            "3W": "3 Wood", "5W": "5 Wood", "7W": "7 Wood",
            "2H": "2 Hybrid", "3H": "3 Hybrid", "4H": "4 Hybrid", "5H": "5 Hybrid",
            "1I": "1 Iron", "2I": "2 Iron", "3I": "3 Iron", "4I": "4 Iron",
            "5I": "5 Iron", "6I": "6 Iron", "7I": "7 Iron", "8I": "8 Iron", "9I": "9 Iron",
            "PW": "Pitching Wedge", "GW": "Gap Wedge", "SW": "Sand Wedge", "LW": "Lob Wedge",
            "PT": "Putter",
        ]
        return map[club] ?? club
    }
}

// MARK: - Connection state

enum GSProConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected:      return "Disconnected"
        case .connecting:        return "Connecting…"
        case .connected:         return "Connected"
        case .failed(let msg):   return msg
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

enum GSProError: LocalizedError {
    case notConnected
    var errorDescription: String? { "Shot not sent — GSPro is disconnected." }
}
