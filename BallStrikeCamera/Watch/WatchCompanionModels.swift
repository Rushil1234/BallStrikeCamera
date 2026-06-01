import Foundation

enum WatchCompanionMode: String, Codable, Hashable {
    case none
    case round
    case range
}

struct WatchAppState: Codable, Hashable {
    var currentMode: WatchCompanionMode = .none
    var round: WatchCompanionRoundSnapshot?
    var range: WatchCompanionRangeSnapshot?
    var latestShot: WatchCompanionShotSnapshot?
    var lastUpdated: Date = Date()

    static let empty = WatchAppState()
}

struct WatchCompanionRoundSnapshot: Codable, Hashable {
    var courseName: String
    var holeNumber: Int
    var holeCount: Int
    var par: Int
    var score: Int?
    var scoreToPar: Int
    var totalScore: Int
    var frontYards: Int
    var centerYards: Int
    var backYards: Int
    var canGoPrevious: Bool
    var canGoNext: Bool
}

struct WatchCompanionRangeSnapshot: Codable, Hashable {
    var isActive: Bool
    var selectedClubName: String?
    var shotCount: Int
    var averageCarryYards: Int
    var bestCarryYards: Int
    var averageBallSpeedMph: Int
}

struct WatchCompanionShotSnapshot: Codable, Hashable {
    var clubName: String?
    var carryYards: Int
    var totalYards: Int
    var ballSpeedMph: Int
    var smashFactor: Double
    var timestamp: Date
}

enum WatchCommandKind: String, Codable, Hashable {
    case refresh
    case roundNextHole
    case roundPreviousHole
    case roundSetScore
    case rangeStart
    case rangeEnd
    case rangeRefresh
}

struct WatchCommand: Codable, Hashable {
    var kind: WatchCommandKind
    var holeNumber: Int?
    var score: Int?
}

struct WatchCommandResult: Codable, Hashable {
    var accepted: Bool
    var message: String?

    static func success(_ message: String? = nil) -> WatchCommandResult {
        WatchCommandResult(accepted: true, message: message)
    }

    static func failure(_ message: String) -> WatchCommandResult {
        WatchCommandResult(accepted: false, message: message)
    }
}

enum WatchPayload {
    static let stateKey = "watchAppState"
    static let commandKey = "watchCommand"
    static let resultKey = "watchCommandResult"
}
