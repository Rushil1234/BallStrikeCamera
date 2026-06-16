import Foundation

// MARK: - Outbound

struct OpenGolfSimShotMessage: Encodable {
    let type: String = "shot"
    let shot: OpenGolfSimShot
}

struct OpenGolfSimShot: Codable {
    let ballSpeed: Double              // mph
    let verticalLaunchAngle: Double    // degrees
    let horizontalLaunchAngle: Double  // degrees (+ right, - left)
    let spinSpeed: Double              // rpm
    let spinAxis: Double               // degrees (+ draw, - fade)
    let club: String?                  // selected club (the app is source of truth)

    static func from(metrics: SavedShotMetrics, club: String? = nil) -> OpenGolfSimShot {
        let totalSpin = sqrt(pow(metrics.backspinRpm, 2) + pow(metrics.sidespinRpm, 2))
        return OpenGolfSimShot(
            ballSpeed:            metrics.ballSpeedMph,
            verticalLaunchAngle:  metrics.vlaDegrees,
            horizontalLaunchAngle: metrics.hlaDegrees,
            spinSpeed:            max(totalSpin, 0),
            spinAxis:             metrics.spinAxisDegrees,
            club:                 club
        )
    }

    static let testShot = OpenGolfSimShot(
        ballSpeed:            145.0,
        verticalLaunchAngle:  13.0,
        horizontalLaunchAngle: 0.5,
        spinSpeed:            2600.0,
        spinAxis:             -1.0,
        club:                 nil
    )
}

// MARK: - Inbound

struct OpenGolfSimGenericMessage: Decodable {
    let type: String?
}

struct OpenGolfSimShotResult: Decodable {
    let type: String?
    let carry: Double?
    let height: Double?
    let roll: Double?
    let total: Double?
    let lateral: Double?
    let club: String?
    let shot: OpenGolfSimShot?
}

// MARK: - Connection State

enum OGSConnectionState: Equatable {
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

// MARK: - Errors

enum OGSError: LocalizedError {
    case notConnected
    var errorDescription: String? { "Shot not sent — simulator is disconnected." }
}
