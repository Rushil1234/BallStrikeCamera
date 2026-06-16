import Foundation
import SwiftUI

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
    var brand: String? = nil
    var loftDegrees: Double? = nil
    /// Unique identifier written to the physical NFC sticker attached to this club.
    var nfcTagId: String? = nil
}

// MARK: - NFC Shot

/// A single club tap recorded via NFC during a round, paired with GPS coordinates.
struct NFCShot: Codable, Identifiable {
    var id: UUID = UUID()
    var clubId: UUID
    var clubName: String
    var holeNumber: Int
    var shotNumber: Int = 1
    var latitude: Double
    var longitude: Double
    var distanceToPinYards: Double?
    var tappedAt: Date = Date()
    /// ID of the SavedShot (camera capture) matched to this tap — set when a
    /// camera shot is saved within 3 minutes of this tap on the same hole.
    var linkedShotId: UUID?
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

    var color: Color {
        switch self {
        case .driver:      return Color(red: 0.30, green: 0.55, blue: 0.95)  // blue
        case .fairwayWood: return Color(red: 0.25, green: 0.75, blue: 0.45)  // green
        case .hybrid:      return Color(red: 0.55, green: 0.38, blue: 0.90)  // purple
        case .iron:        return Color(red: 0.90, green: 0.65, blue: 0.20)  // gold
        case .wedge:       return Color(red: 0.95, green: 0.45, blue: 0.25)  // orange
        case .putter:      return Color(red: 0.75, green: 0.25, blue: 0.35)  // red
        }
    }
}

// Default starter bag for a right-handed golfer (carry/total in yards)
extension UserClub {
    static func defaultBag(userId: UUID) -> [UserClub] {
        let clubs: [(String, ClubType, Int, Int, Int, Double?)] = [
            ("Driver",   .driver,      235, 255, 0,  10.5),
            ("3 Wood",   .fairwayWood, 210, 228, 1,  15.0),
            ("Hybrid",   .hybrid,      195, 210, 2,  19.0),
            ("4 Iron",   .iron,        185, 198, 3,  22.0),
            ("5 Iron",   .iron,        175, 188, 4,  25.0),
            ("6 Iron",   .iron,        165, 178, 5,  28.0),
            ("7 Iron",   .iron,        155, 167, 6,  32.0),
            ("8 Iron",   .iron,        144, 155, 7,  36.0),
            ("9 Iron",   .iron,        132, 142, 8,  40.0),
            ("PW",       .wedge,       118, 126, 9,  45.0),
            ("50°",      .wedge,       105, 112, 10, 50.0),
            ("54°",      .wedge,       90,  96,  11, 54.0),
            ("58°",      .wedge,       75,  80,  12, 58.0),
            ("Putter",   .putter,      0,   0,   13, nil),
        ]
        return clubs.map { name, type, carry, total, order, loft in
            UserClub(userId: userId, name: name, type: type,
                     expectedCarryYards: carry, expectedTotalYards: total, sortOrder: order,
                     loftDegrees: loft)
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
    var shotLatitude: Double?
    var shotLongitude: Double?
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

extension SavedShotMetrics {
    init(_ metrics: ShotMetricsResult) {
        let hla = metrics.ballLaunch.hlaDegrees ?? 0
        self.init(
            carryYards: metrics.distance.carryYards ?? 0,
            totalYards: metrics.distance.totalYards ?? 0,
            rolloutYards: metrics.distance.rolloutYards ?? 0,
            ballSpeedMph: metrics.ballLaunch.ballSpeedMph ?? 0,
            clubSpeedMph: metrics.club.clubSpeedMph ?? 0,
            smashFactor: metrics.smashFactor ?? 0,
            hlaDegrees: abs(hla),
            hlaDirection: hla < 0 ? "left" : hla > 0 ? "right" : "",
            vlaDegrees: metrics.ballLaunch.vlaDegrees ?? 0,
            backspinRpm: metrics.spin.estimatedBackspinRpm ?? 0,
            sidespinRpm: metrics.spin.estimatedSidespinRpmSigned ?? 0,
            spinAxisDegrees: metrics.spin.estimatedSpinAxisDegreesSigned ?? 0,
            clubPathDegrees: metrics.clubPath.clubPathDegreesSigned ?? 0,
            faceAngleDegrees: metrics.faceAngle.faceAngleDegreesSigned ?? 0,
            faceToPathDegrees: metrics.faceAngle.faceToPathDegreesSigned ?? 0
        )
    }
}

struct SavedShotMedia: Codable {
    var thumbnailPath: String?              = nil
    var compositePath: String?             = nil
    var originalFramesFolderPath: String?  = nil
    var metricsJsonPath: String?           = nil
    var gifPath: String?                   = nil   // animated GIF of original frames
    var frameCount: Int                    = 41
    var saveOriginalFrames: Bool           = false
    /// Replay frames mirrored to cloud storage, so replay works on any device /
    /// after a reinstall (local files only exist on the device that captured them).
    var framesUploaded: Bool               = false
}

// MARK: - Practice Session

struct PracticeSession: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var name: String = ""
    var sessionDescription: String? = nil
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
    var name: String = ""
    var sessionDescription: String? = nil
    var provider: SimProvider = .notConnected
    var startedAt: Date = Date()
    var endedAt: Date?
    var shotIds: [UUID] = []
    var outputLog: [String] = []
    var saveOriginalFrames: Bool = false
    var usedOpenGolfSim: Bool = false
}

enum SimProvider: String, Codable, CaseIterable {
    case gspro = "GSPro"
    case ogs   = "OGS"
    case localJson = "Local JSON"
    case liveSim = "TCSim"
    case notConnected = "Not Connected"
}

/// The app's club is the source of truth: it persists the last club used (set by
/// a manual pick OR an RFID/NFC tag tap) and is what we default to next time and
/// what we send to the sim — "stick with the last club unless the user changes it".
enum ClubPreference {
    private static let idKey   = "lastUsedClubId"
    private static let nameKey = "lastUsedClubName"

    static var lastUsedClubId: UUID? {
        get { UserDefaults.standard.string(forKey: idKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: idKey) }
    }
    static var lastUsedClubName: String? {
        UserDefaults.standard.string(forKey: nameKey)
    }

    /// Record the club the user just selected (manual or RFID).
    static func remember(_ club: UserClub?) {
        guard let club else { return }
        UserDefaults.standard.set(club.id.uuidString, forKey: idKey)
        UserDefaults.standard.set(club.name,          forKey: nameKey)
    }

    /// The club to default to: last used (if still in the bag), else 7 Iron, else first.
    static func preferred(in clubs: [UserClub]) -> UserClub? {
        if let id = lastUsedClubId, let c = clubs.first(where: { $0.id == id }) { return c }
        return clubs.first(where: { $0.name == "7 Iron" }) ?? clubs.first
    }
}

// MARK: - Course Round

struct CourseRound: Codable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID
    var name: String = ""
    var sessionDescription: String? = nil
    var courseId: String
    var courseName: String
    var teeBoxName: String
    var startedAt: Date = Date()
    var endedAt: Date?
    var holes: [RoundHole] = []
    var shotIds: [UUID] = []
    var scoreSummary: RoundScoreSummary = RoundScoreSummary()
    /// NFC-recorded club taps during this round, used for shot location tracking and score inference.
    var nfcShots: [NFCShot] = []
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
    var shotIds: [UUID] = []                       // SavedShot ids (camera captures)
    var trackedShots: [TrackedShot] = []           // on-course GPS shots, in order
}

struct RoundScoreSummary: Codable {
    var totalScore: Int  = 0
    var totalPar: Int    = 0   // 0 until holes are actually scored; avoids showing -72 at round start
    var fairwaysHit: Int = 0
    var greensInReg: Int = 0
    var totalPutts: Int  = 0
}

/// Builds a realistic completed 18-hole round for previewing the saved-history
/// output (as if the user played and tapped an NFC club tag on every shot).
enum SampleRoundFactory {
    static func generate(userId: UUID, clubs: [UserClub]) -> CourseRound {
        let pars  = [4,4,5,3,4,4,3,5,4, 4,3,4,5,4,4,3,4,5]            // par 72
        let yards = [410,395,540,175,430,360,205,560,440, 400,160,420,575,385,415,190,450,525]
        let scoreDeltas = [0,1,0,-1,0,0,1,0,2, 0,-1,0,1,0,0,1,0,1]   // deterministic, human-looking
        let baseLat = 37.6002, baseLon = -122.4908

        func club(_ needles: [String]) -> UserClub? {
            for n in needles { if let c = clubs.first(where: { $0.name.lowercased().contains(n) }) { return c } }
            return clubs.first
        }
        let driver  = club(["driver"])
        let wood    = club(["wood"]) ?? driver
        let midIron = club(["7 iron", "6 iron", "8 iron", "iron"])
        let wedge   = club(["wedge", "pitching", "gap", "sand"]) ?? midIron
        let putter  = club(["putter"])

        var holes: [RoundHole] = []
        var nfc: [NFCShot] = []
        var totalScore = 0, totalPar = 0, fairways = 0, girs = 0, totalPutts = 0

        for i in 0..<18 {
            let par = pars[i], holeNum = i + 1
            let score = max(2, par + scoreDeltas[i])
            let putts = par == 3 ? (scoreDeltas[i] < 0 ? 1 : 2) : min(max(1, 2 + max(0, scoreDeltas[i] - 1)), 3)
            let fairway: Bool? = par == 3 ? nil : (scoreDeltas[i] <= 0)
            let gir = (score - putts) <= (par - 2)
            let penalties = scoreDeltas[i] >= 2 ? 1 : 0

            totalScore += score; totalPar += par; totalPutts += putts
            if fairway == true { fairways += 1 }
            if gir { girs += 1 }

            let fullSwings = max(1, score - putts)
            for s in 0..<fullSwings {
                let chosen: UserClub? = s == 0 ? (par == 3 ? midIron : driver)
                    : (s == fullSwings - 1 ? wedge : (par == 5 && s == 1 ? wood : midIron))
                guard let c = chosen else { continue }
                nfc.append(NFCShot(
                    clubId: c.id, clubName: c.name, holeNumber: holeNum, shotNumber: s + 1,
                    latitude: baseLat + Double(i) * 0.0009 + Double(s) * 0.0001,
                    longitude: baseLon + Double(i) * 0.0006,
                    distanceToPinYards: Double(yards[i]) * (1.0 - Double(s + 1) / Double(fullSwings + 1)),
                    tappedAt: Date().addingTimeInterval(Double(i - 18) * 600 + Double(s) * 45)))
            }
            if let p = putter {
                for k in 0..<putts {
                    nfc.append(NFCShot(
                        clubId: p.id, clubName: p.name, holeNumber: holeNum, shotNumber: fullSwings + k + 1,
                        latitude: baseLat + Double(i) * 0.0009, longitude: baseLon + Double(i) * 0.0006,
                        distanceToPinYards: Double(max(2, 28 - k * 13)),
                        tappedAt: Date().addingTimeInterval(Double(i - 18) * 600 + 240 + Double(k) * 30)))
                }
            }
            holes.append(RoundHole(holeNumber: holeNum, par: par, score: score, putts: putts,
                                   fairwayHit: fairway, greenInRegulation: gir, penalties: penalties))
        }

        var round = CourseRound(userId: userId, courseId: "sample-pine-hollow",
                                courseName: "Pine Hollow National", teeBoxName: "White")
        round.name = "Sample Round (preview)"
        round.startedAt = Date().addingTimeInterval(-18 * 600)
        round.endedAt = Date()
        round.holes = holes
        round.nfcShots = nfc
        round.scoreSummary = RoundScoreSummary(totalScore: totalScore, totalPar: totalPar,
                                               fairwaysHit: fairways, greensInReg: girs, totalPutts: totalPutts)
        return round
    }
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
    var stats: [FeedStat] = []
    var timestamp: Date = Date()
    var likes: Int = 0
    var commentsCount: Int = 0
    var linkedShotId: UUID?
    var linkedSessionId: UUID?
    var linkedRoundId: UUID?
    var activityMetadata: FeedActivityMetadata? = nil
    /// Optional so older stored posts decode cleanly; nil is treated as `.everyone`.
    var visibility: FeedVisibility? = nil
    /// Relative path (under the user's media dir) to an attached photo, if any.
    var photoPath: String? = nil
}

/// One stat column in a feed card (Strava-style: small label over bold value).
struct FeedStat: Codable, Hashable, Identifiable {
    var label: String
    var value: String
    var id: String { label + value }
}

enum FeedPostType: String, Codable {
    case shot, session, round, achievement
}

enum FeedActivityKind: String, Codable, Hashable {
    case round
    case range
    case sim
    case manual
}

struct FeedActivityMetadata: Codable, Hashable {
    var kind: FeedActivityKind
    var courseName: String?
    var clubName: String?
    var providerName: String?
    var totalScore: Int?
    var scoreToPar: Int?
    var fairwaysHit: Int?
    var greensInRegulation: Int?
    var putts: Int?
    var shotCount: Int?
    var averageCarryYards: Int?
    var bestCarryYards: Int?
    var bestTotalYards: Int?
    var averageBallSpeedMph: Int?

    var primaryValue: String {
        switch kind {
        case .round:
            if let totalScore { return "\(totalScore)" }
            return scoreToPar.map { $0 == 0 ? "E" : $0 > 0 ? "+\($0)" : "\($0)" } ?? "--"
        case .range:
            return bestCarryYards.map { "\($0)" } ?? averageCarryYards.map { "\($0)" } ?? "\(shotCount ?? 0)"
        case .sim:
            return "\(shotCount ?? 0)"
        case .manual:
            return bestCarryYards.map { "\($0)" } ?? "--"
        }
    }

    var primaryUnit: String {
        switch kind {
        case .round: return "score"
        case .range: return bestCarryYards != nil || averageCarryYards != nil ? "yd" : "shots"
        case .sim: return "shots"
        case .manual: return bestCarryYards != nil ? "yd" : ""
        }
    }
}

struct FeedHomeSummary: Codable, Hashable {
    var weeklyRounds: Int = 0
    var weeklyShots: Int = 0
    var bestCarryYards: Int = 0
    var activeStreakDays: Int = 0
    var friendsCount: Int = 0
    var gimmesReceived: Int = 0

    static let empty = FeedHomeSummary()
}

struct FeedPage: Codable {
    var posts: [FeedPost]
    var nextCursor: Date?
    var hasMore: Bool
}

struct FeedEngagementSummary: Codable, Hashable {
    var gimmeCounts: [UUID: Int] = [:]
    var gimmedByMe: Set<UUID> = []
    var commentCounts: [UUID: Int] = [:]
}

enum FeedLeaderboardPeriod: String, Codable, Hashable {
    case week
    case month
}

enum FeedLeaderboardMetric: String, Codable, Hashable {
    case longestDrive
    case bestScore
    case practiceShots

    var title: String {
        switch self {
        case .longestDrive: return "Longest Drive"
        case .bestScore: return "Best Score"
        case .practiceShots: return "Practice Shots"
        }
    }

    var unit: String {
        switch self {
        case .longestDrive: return "yd"
        case .bestScore: return ""
        case .practiceShots: return "shots"
        }
    }
}

struct FeedLeaderboardEntry: Identifiable, Codable, Hashable {
    var id: String { "\(metric.rawValue)-\(userId.uuidString)" }
    var userId: UUID
    var displayName: String
    var metric: FeedLeaderboardMetric
    var value: Int
    var subtitle: String
}

struct FeedChallengePreview: Identifiable, Codable, Hashable {
    var id: String { title }
    var title: String
    var subtitle: String
    var progress: Double
    var icon: String
}

// MARK: - Backward-compatible decoders
// Fields added after the initial app release may be absent from rows already stored in Supabase.
// Using decodeIfPresent + default for those fields prevents a hard DecodingError.keyNotFound crash
// that would otherwise show "Load Error: The data couldn't be read because it is missing."

extension SavedShotMedia {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thumbnailPath            = try c.decodeIfPresent(String.self, forKey: .thumbnailPath)
        compositePath            = try c.decodeIfPresent(String.self, forKey: .compositePath)
        originalFramesFolderPath = try c.decodeIfPresent(String.self, forKey: .originalFramesFolderPath)
        metricsJsonPath          = try c.decodeIfPresent(String.self, forKey: .metricsJsonPath)
        gifPath                  = try c.decodeIfPresent(String.self, forKey: .gifPath)
        frameCount               = try c.decodeIfPresent(Int.self,    forKey: .frameCount) ?? 41
        saveOriginalFrames       = try c.decodeIfPresent(Bool.self,   forKey: .saveOriginalFrames) ?? false
    }
}

extension SavedShot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(UUID.self,           forKey: .id) ?? UUID()
        userId        = try c.decode(UUID.self,                    forKey: .userId)
        source        = try c.decodeIfPresent(ShotSource.self,     forKey: .source) ?? .live
        mode          = try c.decodeIfPresent(ShotMode.self,       forKey: .mode) ?? .quick
        clubId        = try c.decodeIfPresent(UUID.self,           forKey: .clubId)
        clubName      = try c.decodeIfPresent(String.self,         forKey: .clubName)
        timestamp     = try c.decodeIfPresent(Date.self,           forKey: .timestamp) ?? Date()
        metrics       = try c.decode(SavedShotMetrics.self,        forKey: .metrics)
        media         = try c.decodeIfPresent(SavedShotMedia.self, forKey: .media) ?? SavedShotMedia()
        isBadShot     = try c.decodeIfPresent(Bool.self,           forKey: .isBadShot) ?? false
        badShotReason = try c.decodeIfPresent(String.self,         forKey: .badShotReason)
        notes         = try c.decodeIfPresent(String.self,         forKey: .notes)
        sessionId     = try c.decodeIfPresent(UUID.self,           forKey: .sessionId)
        roundId       = try c.decodeIfPresent(UUID.self,           forKey: .roundId)
        holeNumber    = try c.decodeIfPresent(Int.self,            forKey: .holeNumber)
        shotLatitude  = try c.decodeIfPresent(Double.self,         forKey: .shotLatitude)
        shotLongitude = try c.decodeIfPresent(Double.self,         forKey: .shotLongitude)
    }
}

extension SavedShotMetrics {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        carryYards        = try c.decodeIfPresent(Double.self, forKey: .carryYards) ?? 0
        totalYards        = try c.decodeIfPresent(Double.self, forKey: .totalYards) ?? 0
        rolloutYards      = try c.decodeIfPresent(Double.self, forKey: .rolloutYards) ?? 0
        ballSpeedMph      = try c.decodeIfPresent(Double.self, forKey: .ballSpeedMph) ?? 0
        clubSpeedMph      = try c.decodeIfPresent(Double.self, forKey: .clubSpeedMph) ?? 0
        smashFactor       = try c.decodeIfPresent(Double.self, forKey: .smashFactor) ?? 0
        hlaDegrees        = try c.decodeIfPresent(Double.self, forKey: .hlaDegrees) ?? 0
        hlaDirection      = try c.decodeIfPresent(String.self, forKey: .hlaDirection) ?? ""
        vlaDegrees        = try c.decodeIfPresent(Double.self, forKey: .vlaDegrees) ?? 0
        backspinRpm       = try c.decodeIfPresent(Double.self, forKey: .backspinRpm) ?? 0
        sidespinRpm       = try c.decodeIfPresent(Double.self, forKey: .sidespinRpm) ?? 0
        spinAxisDegrees   = try c.decodeIfPresent(Double.self, forKey: .spinAxisDegrees) ?? 0
        clubPathDegrees   = try c.decodeIfPresent(Double.self, forKey: .clubPathDegrees) ?? 0
        faceAngleDegrees  = try c.decodeIfPresent(Double.self, forKey: .faceAngleDegrees) ?? 0
        faceToPathDegrees = try c.decodeIfPresent(Double.self, forKey: .faceToPathDegrees) ?? 0
    }
}

extension SessionSummary {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shotCount     = try c.decodeIfPresent(Int.self,    forKey: .shotCount) ?? 0
        avgCarry      = try c.decodeIfPresent(Double.self, forKey: .avgCarry) ?? 0
        avgTotal      = try c.decodeIfPresent(Double.self, forKey: .avgTotal) ?? 0
        avgBallSpeed  = try c.decodeIfPresent(Double.self, forKey: .avgBallSpeed) ?? 0
        bestCarry     = try c.decodeIfPresent(Double.self, forKey: .bestCarry) ?? 0
        hlaDispersion = try c.decodeIfPresent(Double.self, forKey: .hlaDispersion) ?? 0
    }
}

extension PracticeSession {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decodeIfPresent(UUID.self,            forKey: .id) ?? UUID()
        userId             = try c.decode(UUID.self,                     forKey: .userId)
        name               = try c.decodeIfPresent(String.self,          forKey: .name) ?? ""
        sessionDescription = try c.decodeIfPresent(String.self,          forKey: .sessionDescription)
        startedAt          = try c.decodeIfPresent(Date.self,            forKey: .startedAt) ?? Date()
        endedAt            = try c.decodeIfPresent(Date.self,            forKey: .endedAt)
        selectedClubId     = try c.decodeIfPresent(UUID.self,            forKey: .selectedClubId)
        selectedClubName   = try c.decodeIfPresent(String.self,          forKey: .selectedClubName)
        shotIds            = try c.decodeIfPresent([UUID].self,          forKey: .shotIds) ?? []
        saveOriginalFrames = try c.decodeIfPresent(Bool.self,            forKey: .saveOriginalFrames) ?? false
        summary            = try c.decodeIfPresent(SessionSummary.self,  forKey: .summary) ?? SessionSummary()
    }
}

extension SimSession {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decodeIfPresent(UUID.self,         forKey: .id) ?? UUID()
        userId             = try c.decode(UUID.self,                  forKey: .userId)
        name               = try c.decodeIfPresent(String.self,       forKey: .name) ?? ""
        sessionDescription = try c.decodeIfPresent(String.self,       forKey: .sessionDescription)
        provider           = try c.decodeIfPresent(SimProvider.self,  forKey: .provider) ?? .notConnected
        startedAt          = try c.decodeIfPresent(Date.self,         forKey: .startedAt) ?? Date()
        endedAt            = try c.decodeIfPresent(Date.self,         forKey: .endedAt)
        shotIds            = try c.decodeIfPresent([UUID].self,       forKey: .shotIds) ?? []
        outputLog          = try c.decodeIfPresent([String].self,     forKey: .outputLog) ?? []
        saveOriginalFrames = try c.decodeIfPresent(Bool.self,         forKey: .saveOriginalFrames) ?? false
        usedOpenGolfSim    = try c.decodeIfPresent(Bool.self,         forKey: .usedOpenGolfSim) ?? false
    }
}

extension RoundScoreSummary {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalScore  = try c.decodeIfPresent(Int.self, forKey: .totalScore) ?? 0
        totalPar    = try c.decodeIfPresent(Int.self, forKey: .totalPar) ?? 0
        fairwaysHit = try c.decodeIfPresent(Int.self, forKey: .fairwaysHit) ?? 0
        greensInReg = try c.decodeIfPresent(Int.self, forKey: .greensInReg) ?? 0
        totalPutts  = try c.decodeIfPresent(Int.self, forKey: .totalPutts) ?? 0
    }
}

extension RoundHole {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decodeIfPresent(UUID.self,           forKey: .id) ?? UUID()
        holeNumber        = try c.decode(Int.self,                     forKey: .holeNumber)
        par               = try c.decode(Int.self,                     forKey: .par)
        score             = try c.decodeIfPresent(Int.self,            forKey: .score)
        putts             = try c.decodeIfPresent(Int.self,            forKey: .putts)
        fairwayHit        = try c.decodeIfPresent(Bool.self,           forKey: .fairwayHit)
        greenInRegulation = try c.decodeIfPresent(Bool.self,           forKey: .greenInRegulation)
        penalties         = try c.decodeIfPresent(Int.self,            forKey: .penalties) ?? 0
        shotIds           = try c.decodeIfPresent([UUID].self,         forKey: .shotIds) ?? []
        trackedShots      = try c.decodeIfPresent([TrackedShot].self,  forKey: .trackedShots) ?? []
    }
}

extension CourseRound {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decodeIfPresent(UUID.self,               forKey: .id) ?? UUID()
        userId             = try c.decode(UUID.self,                        forKey: .userId)
        name               = try c.decodeIfPresent(String.self,             forKey: .name) ?? ""
        sessionDescription = try c.decodeIfPresent(String.self,             forKey: .sessionDescription)
        courseId           = try c.decode(String.self,                      forKey: .courseId)
        courseName         = try c.decode(String.self,                      forKey: .courseName)
        teeBoxName         = try c.decode(String.self,                      forKey: .teeBoxName)
        startedAt          = try c.decodeIfPresent(Date.self,               forKey: .startedAt) ?? Date()
        endedAt            = try c.decodeIfPresent(Date.self,               forKey: .endedAt)
        holes              = try c.decodeIfPresent([RoundHole].self,        forKey: .holes) ?? []
        shotIds            = try c.decodeIfPresent([UUID].self,             forKey: .shotIds) ?? []
        scoreSummary       = try c.decodeIfPresent(RoundScoreSummary.self,  forKey: .scoreSummary) ?? RoundScoreSummary()
        nfcShots           = try c.decodeIfPresent([NFCShot].self,          forKey: .nfcShots) ?? []
    }
}
