import Foundation

// MARK: - App User

struct AppUser: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var createdAt: Date = Date()
    var subscriptionStatus: SubscriptionStatus = .free
    var isGuest: Bool = false
    var rememberedLogin: Bool = true
}

enum SubscriptionStatus: String, Codable {
    case free, pro, admin
}

// MARK: - User Profile

struct UserProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var displayName: String
    var handedness: Handedness = .right
    var distanceUnit: DistanceUnit = .yards
    var speedUnit: SpeedUnit = .mph
    var homeCourseName: String = ""
    var profileImagePath: String? = nil
}

enum Handedness: String, Codable, CaseIterable {
    case right = "Right-handed"
    case left  = "Left-handed"
    var short: String { self == .right ? "RH" : "LH" }
}

enum DistanceUnit: String, Codable, CaseIterable {
    case yards = "Yards"
    case meters = "Meters"
}

enum SpeedUnit: String, Codable, CaseIterable {
    case mph = "mph"
    case kmh = "km/h"
}

// MARK: - Club

struct UserClub: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var name: String
    var type: ClubType
    var expectedCarryYards: Int
    var expectedTotalYards: Int
    var isActive: Bool = true
    var createdAt: Date = Date()
    var shotCount: Int = 0
    var sortOrder: Int = 0
}

enum ClubType: String, Codable, CaseIterable {
    case driver = "Driver"
    case fairwayWood = "Fairway Wood"
    case hybrid = "Hybrid"
    case iron = "Iron"
    case wedge = "Wedge"
    case putter = "Putter"

    var icon: String {
        switch self {
        case .driver:      return "figure.golf"
        case .fairwayWood: return "figure.golf"
        case .hybrid:      return "figure.golf"
        case .iron:        return "figure.golf"
        case .wedge:       return "figure.golf"
        case .putter:      return "circle.fill"
        }
    }
}

// Default starter bag for a right-handed golfer (carry/total in yards)
extension UserClub {
    static func defaultBag(userId: UUID) -> [UserClub] {
        let clubs: [(String, ClubType, Int, Int, Int)] = [
            ("Driver",   .driver,      235, 255, 0),
            ("3 Wood",   .fairwayWood, 210, 228, 1),
            ("Hybrid",   .hybrid,      195, 210, 2),
            ("4 Iron",   .iron,        185, 198, 3),
            ("5 Iron",   .iron,        175, 188, 4),
            ("6 Iron",   .iron,        165, 178, 5),
            ("7 Iron",   .iron,        155, 167, 6),
            ("8 Iron",   .iron,        144, 155, 7),
            ("9 Iron",   .iron,        132, 142, 8),
            ("PW",       .wedge,       118, 126, 9),
            ("50°",      .wedge,       105, 112, 10),
            ("54°",      .wedge,       90,  96,  11),
            ("58°",      .wedge,       75,  80,  12),
            ("Putter",   .putter,      0,   0,   13),
        ]
        return clubs.map { name, type, carry, total, order in
            UserClub(userId: userId, name: name, type: type,
                     expectedCarryYards: carry, expectedTotalYards: total, sortOrder: order)
        }
    }
}

// MARK: - Saved Shot

struct SavedShot: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var source: ShotSource = .live
    var mode: ShotMode = .quick
    var clubId: UUID?
    var clubName: String?
    var timestamp: Date = Date()
    var metrics: SavedShotMetrics
    var media: SavedShotMedia = SavedShotMedia()
    var isBadShot: Bool = false
    var badShotReason: String?
    var notes: String?
    var sessionId: UUID?
    var roundId: UUID?
    var holeNumber: Int?
}

enum ShotSource: String, Codable {
    case live, simulated, manual
}

enum ShotMode: String, Codable {
    case quick, range, sim, course
}

struct SavedShotMetrics: Codable {
    var carryYards: Double      = 0
    var totalYards: Double      = 0
    var rolloutYards: Double    = 0
    var ballSpeedMph: Double    = 0
    var clubSpeedMph: Double    = 0
    var smashFactor: Double     = 0
    var hlaDegrees: Double      = 0
    var hlaDirection: String    = ""
    var vlaDegrees: Double      = 0
    var backspinRpm: Double     = 0
    var sidespinRpm: Double     = 0
    var spinAxisDegrees: Double = 0
    var clubPathDegrees: Double = 0
    var faceAngleDegrees: Double = 0
    var faceToPathDegrees: Double = 0
}

struct SavedShotMedia: Codable {
    var thumbnailPath: String?              = nil
    var compositePath: String?             = nil
    var originalFramesFolderPath: String?  = nil
    var metricsJsonPath: String?           = nil
    var frameCount: Int                    = 41
    var saveOriginalFrames: Bool           = false
}

// MARK: - Practice Session

struct PracticeSession: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var startedAt: Date = Date()
    var endedAt: Date?
    var selectedClubId: UUID?
    var selectedClubName: String?
    var shotIds: [UUID] = []
    var saveOriginalFrames: Bool = false
    var summary: SessionSummary = SessionSummary()
}

struct SessionSummary: Codable {
    var shotCount: Int    = 0
    var avgCarry: Double  = 0
    var avgTotal: Double  = 0
    var avgBallSpeed: Double = 0
    var bestCarry: Double = 0
    var hlaDispersion: Double = 0
}

// MARK: - Sim Session

struct SimSession: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var provider: SimProvider = .notConnected
    var startedAt: Date = Date()
    var endedAt: Date?
    var shotIds: [UUID] = []
    var outputLog: [String] = []
    var saveOriginalFrames: Bool = false
}

enum SimProvider: String, Codable, CaseIterable {
    case gspro = "GSPro"
    case ogs   = "OGS"
    case localJson = "Local JSON"
    case notConnected = "Not Connected"
}

// MARK: - Course Round

struct CourseRound: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var courseId: String
    var courseName: String
    var teeBoxName: String
    var startedAt: Date = Date()
    var endedAt: Date?
    var holes: [RoundHole] = []
    var shotIds: [UUID] = []
    var scoreSummary: RoundScoreSummary = RoundScoreSummary()
}

struct RoundHole: Codable, Identifiable {
    var id: UUID = UUID()
    var holeNumber: Int
    var par: Int
    var score: Int?
    var putts: Int?
    var fairwayHit: Bool?
    var greenInRegulation: Bool?
    var penalties: Int = 0
    var shotIds: [UUID] = []
}

struct RoundScoreSummary: Codable {
    var totalScore: Int  = 0
    var totalPar: Int    = 72
    var fairwaysHit: Int = 0
    var greensInReg: Int = 0
    var totalPutts: Int  = 0
}

// MARK: - Feed Post

struct FeedPost: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var authorName: String
    var type: FeedPostType
    var title: String
    var subtitle: String
    var metricHighlight: String
    var timestamp: Date = Date()
    var likes: Int = 0
    var commentsCount: Int = 0
    var linkedShotId: UUID?
    var linkedSessionId: UUID?
    var linkedRoundId: UUID?
}

enum FeedPostType: String, Codable {
    case shot, session, round, achievement
}
