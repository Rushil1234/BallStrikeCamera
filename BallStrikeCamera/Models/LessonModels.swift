import Foundation
import CoreGraphics

// MARK: - TrueCarry Coach: lesson + swing models
// Content lives in Resources/Lessons/curriculum.json (versioned, folder-ref so a file swap
// re-ships it); these types are its schema plus the user's progress/swing records.

// MARK: Intake

enum SkillLevel: String, Codable, CaseIterable, Identifiable {
    case newcomer, beginner, improver, intermediate, advanced
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newcomer:     return "Never played"
        case .beginner:     return "Played a few times"
        case .improver:     return "Play occasionally"
        case .intermediate: return "Regular golfer"
        case .advanced:     return "Competitive"
        }
    }
}

enum FocusArea: String, Codable, CaseIterable, Identifiable {
    case startFromZero = "start_zero"
    case slice, hook
    case contact            // topping / chunking / inconsistent strikes
    case distance
    case tempo
    case scoring            // course strategy
    case checkup            // "just analyze my swing"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .startFromZero: return "Start from zero"
        case .slice:         return "I slice it"
        case .hook:          return "I hook it"
        case .contact:       return "Inconsistent contact"
        case .distance:      return "More distance"
        case .tempo:         return "Tempo & rhythm"
        case .scoring:       return "Course scoring"
        case .checkup:       return "Analyze my swing"
        }
    }

    var icon: String {
        switch self {
        case .startFromZero: return "figure.golf"
        case .slice:         return "arrow.up.right"
        case .hook:          return "arrow.up.left"
        case .contact:       return "circle.dotted"
        case .distance:      return "bolt.fill"
        case .tempo:         return "metronome"
        case .scoring:       return "flag.fill"
        case .checkup:       return "waveform.path.ecg"
        }
    }
}

/// The intake questionnaire result (questionnaire-only by design — no baseline capture).
struct LessonProfile: Codable {
    var skillLevel: SkillLevel = .beginner
    var focusAreas: [FocusArea] = []
    var hasClubs = true
    var hasNetOrRange = false
    var hasTripod = false
    var createdAt = Date()
    var updatedAt = Date()
}

// MARK: Curriculum schema (decoded from curriculum.json)

struct LessonCurriculum: Codable {
    var version: Int
    var tracks: [LessonTrack]
}

struct LessonTrack: Codable, Identifiable {
    var id: String                  // "foundations"
    var title: String
    var subtitle: String
    var icon: String
    /// Focus areas this track serves — drives syllabus ordering from the intake.
    var focusAreas: [FocusArea]
    /// Minimum skill level the track assumes (newcomers get foundations first regardless).
    var lessons: [Lesson]
}

struct Lesson: Codable, Identifiable {
    var id: String                  // "foundations.grip"
    var title: String
    var subtitle: String
    var icon: String
    var minutes: Int                // estimated duration shown on the card
    /// Lesson ids that must be mastered first (within or across tracks).
    var prerequisites: [String] = []
    /// Swing metrics this lesson grades (keys into SwingMetricKind) — used by swingCapture steps.
    var focusMetrics: [String] = []
    var steps: [LessonStep]
}

enum LessonStepKind: String, Codable {
    case explainer, video, model3D, check3D, swingCapture, quiz
}

struct LessonStep: Codable, Identifiable {
    var id: String
    var kind: LessonStepKind
    var title: String
    /// Markdown-ish body for explainers; caption elsewhere.
    var body: String = ""
    /// Bullet points rendered under the body (explainer).
    var points: [String] = []
    /// video: catalog id (resolves to a real film later — placeholder art until then).
    var videoId: String? = nil
    /// model3D: USDZ asset name in Resources/Lessons3D (renders diagram fallback when absent).
    var asset3D: String? = nil
    /// model3D/check3D: labelled hotspots / checkpoints the user steps through.
    var checkpoints: [String] = []
    /// swingCapture: swings to record and the metric keys that gate passing.
    var swingCount: Int? = nil
    /// quiz: question set.
    var quiz: [QuizQuestion] = []
}

struct QuizQuestion: Codable, Identifiable {
    var id: String { question }
    var question: String
    var answers: [String]
    var correctIndex: Int
    var why: String = ""
}

// MARK: Progress (local-first; backend sync is a later phase)

enum LessonStatus: String, Codable {
    case locked, available, inProgress, completed, mastered
}

struct LessonProgress: Codable {
    var lessonId: String
    var status: LessonStatus = .available
    var bestScore: Int? = nil          // 0-100 from swingCapture steps, when applicable
    var completedSteps: [String] = []
    var completedAt: Date? = nil
    var attempts: Int = 0
}

/// One sitting of lesson work — the History record.
struct LessonSessionRecord: Codable, Identifiable {
    var id = UUID()
    var userId: UUID
    var lessonId: String
    var lessonTitle: String
    var trackTitle: String
    var startedAt = Date()
    var endedAt: Date? = nil
    var stepsCompleted: Int = 0
    var stepCount: Int = 0
    var swingIds: [UUID] = []          // SwingRecordings captured during the lesson
    var score: Int? = nil
    var notes: String = ""
}

// MARK: Swing Studio records

enum SwingViewAngle: String, Codable {
    case faceOn = "face_on"            // camera on the target-line side, facing the player
    case downTheLine = "down_the_line" // behind the hands, looking at the target

    var displayName: String { self == .faceOn ? "Face-On" : "Down the Line" }
}

enum SwingCameraSource: String, Codable {
    case backGuided   // back camera, voice-guided auto-record (high fps)
    case frontMirror  // front camera, live skeleton on screen
}

/// A recorded + analyzed swing. Video lives on disk; this is the metadata + analysis.
struct SwingRecording: Codable, Identifiable {
    var id = UUID()
    var userId: UUID
    var recordedAt = Date()
    var viewAngle: SwingViewAngle = .faceOn
    var source: SwingCameraSource = .backGuided
    var fps: Double = 60
    var videoPath: String              // relative to the swings dir
    var thumbnailPath: String? = nil
    var lessonId: String? = nil        // captured inside a lesson (nil = free analysis)

    // Analysis results
    var analyzed = false
    var poseEngine: String = "vision2d"    // "vision2d" | "vision3d" (iOS 17 keyframes)
    var phases: SwingPhases? = nil
    var metrics: [SwingMetricValue] = []
    var faults: [String] = []              // FaultLibrary ids
    var overallScore: Int? = nil           // 0-100, skill-banded
    var categoryScores: [String: Int] = [:] // "setup"/"tempo"/"body"/"balance"
    var headline: String = ""              // one win
    var focusPoint: String = ""            // one thing to fix
    /// Skeletons at the 5 phase frames (SwingSkeleton.jointOrder order; [x, y, confidence]
    /// in Vision normalized coords) — powers the replay overlay without storing every frame.
    var keyPoses: [StoredPose] = []
}

struct StoredPose: Codable {
    var frame: Int
    var points: [[Double]]     // SwingSkeleton.jointOrder order: [x, y, confidence]
}

/// Frame indices of each swing phase boundary within the analyzed clip.
struct SwingPhases: Codable {
    var address: Int
    var takeaway: Int
    var top: Int
    var impact: Int
    var finish: Int
    var frameCount: Int
    var frameRate: Double

    var backswingSeconds: Double { Double(top - takeaway) / max(frameRate, 1) }
    var downswingSeconds: Double { Double(impact - top) / max(frameRate, 1) }
    /// Classic tempo ratio (3:1 is the reference).
    var tempoRatio: Double? {
        guard downswingSeconds > 0.01 else { return nil }
        return backswingSeconds / downswingSeconds
    }

    var labelled: [(label: String, frame: Int)] {
        [("Address", address), ("Takeaway", takeaway), ("Top", top),
         ("Impact", impact), ("Finish", finish)]
    }
}

enum SwingMetricKind: String, Codable, CaseIterable {
    case tempoRatio       = "tempo_ratio"        // backswing:downswing time
    case headSway         = "head_sway"          // lateral head travel, % of shoulder width
    case hipSlide         = "hip_slide"          // lateral pelvis travel, % of shoulder width
    case spineTiltAddress = "spine_tilt_address" // degrees from vertical at address
    case leadArmAtTop     = "lead_arm_top"       // lead-arm straightness at top (degrees of bend)
    case finishBalance    = "finish_balance"     // ankle jitter over final 0.5s, % shoulder width
    case shoulderTurn     = "shoulder_turn"      // shoulder-line rotation proxy at top, %
    // Down-the-line only (tripod ~6ft behind, camera at hand height):
    case takeawayPath     = "takeaway_path"      // hands vs address plane at hip height going back (− inside / + outside)
    case deliveryPlane    = "delivery_plane"     // hands vs plane at hip height coming down (+ steep / − shallow)
    case earlyExtension   = "early_extension"    // hip drift toward the ball top→impact, % shoulder width

    var displayName: String {
        switch self {
        case .tempoRatio:       return "Tempo"
        case .headSway:         return "Head Sway"
        case .hipSlide:         return "Hip Slide"
        case .spineTiltAddress: return "Spine Tilt"
        case .leadArmAtTop:     return "Lead Arm"
        case .finishBalance:    return "Balance"
        case .shoulderTurn:     return "Shoulder Turn"
        case .takeawayPath:     return "Takeaway Path"
        case .deliveryPlane:    return "Delivery Plane"
        case .earlyExtension:   return "Early Extension"
        }
    }

    var unit: String {
        switch self {
        case .tempoRatio:                       return ":1"
        case .headSway, .hipSlide, .finishBalance, .shoulderTurn,
             .takeawayPath, .deliveryPlane, .earlyExtension: return "%"
        case .spineTiltAddress, .leadArmAtTop:  return "°"
        }
    }

    /// Good/bad verdict chip text (the Golfboy/OnForm-style position call-outs).
    func verdict(for value: SwingMetricValue) -> (label: String, good: Bool) {
        switch self {
        case .takeawayPath:
            if value.inBand { return ("Takeaway On Plane", true) }
            return value.value < value.targetLow ? ("Takeaway Inside", false) : ("Takeaway Outside", false)
        case .deliveryPlane:
            if value.inBand { return ("Club On Plane at Delivery", true) }
            return value.value > value.targetHigh ? ("Club Steep at Delivery", false) : ("Club Shallow at Delivery", false)
        case .earlyExtension:
            return value.inBand ? ("Posture Held", true) : ("Early Extension", false)
        case .tempoRatio:
            if value.inBand { return ("Tour Tempo", true) }
            return value.value < value.targetLow ? ("Quick Transition", false) : ("Slow Drift Back", false)
        case .headSway:
            return value.inBand ? ("Head Centered", true) : ("Head Sway", false)
        case .hipSlide:
            return value.inBand ? ("Hips Rotating", true) : ("Hips Sliding", false)
        case .finishBalance:
            return value.inBand ? ("Balanced Finish", true) : ("Off-Balance Finish", false)
        case .spineTiltAddress:
            return value.inBand ? ("Athletic Posture", true)
                 : (value.value < value.targetLow ? ("Too Upright", false) : ("Hunched Over", false))
        case .leadArmAtTop:
            return value.inBand ? ("Great Width", true) : ("Lead Arm Collapsing", false)
        case .shoulderTurn:
            return value.inBand ? ("Full Turn", true) : ("Short Turn", false)
        }
    }
}

struct SwingMetricValue: Codable, Identifiable {
    var id: String { kind.rawValue }
    var kind: SwingMetricKind
    var value: Double
    /// Target band for the user's skill level at analysis time.
    var targetLow: Double
    var targetHigh: Double
    var confidence: Double            // 0-1: joint-confidence-weighted trust in the number
    var inBand: Bool { value >= targetLow && value <= targetHigh }
}

// MARK: Fault library (decoded from faults.json)

struct SwingFault: Codable, Identifiable {
    var id: String                    // "sway", "quick_tempo", ...
    var title: String
    var explanation: String           // plain-English "what + why it matters"
    var drill: String                 // one drill, plain text
    var lessonId: String? = nil       // deep link into the curriculum
    var videoId: String? = nil        // future filmed content
    /// Detection rule: metric + out-of-band direction ("above" | "below").
    var metric: String
    var direction: String
}

// MARK: Player model (rolling weaknesses; local-first)

struct PlayerSwingModel: Codable {
    var swingCount = 0
    var lastScores: [Int] = []                   // most recent 20 overall scores
    var metricAverages: [String: Double] = [:]   // EMA per metric kind
    var activeFaults: [String: Int] = [:]        // fault id → consecutive detections
    var bestSwingId: UUID? = nil
    var updatedAt = Date()

    mutating func absorb(_ swing: SwingRecording) {
        swingCount += 1
        if let s = swing.overallScore {
            lastScores.append(s)
            if lastScores.count > 20 { lastScores.removeFirst(lastScores.count - 20) }
        }
        for m in swing.metrics {
            let prev = metricAverages[m.kind.rawValue] ?? m.value
            metricAverages[m.kind.rawValue] = prev * 0.7 + m.value * 0.3
        }
        // Faults must persist across a few swings before they're "active"; one clean
        // swing starts clearing them.
        for f in swing.faults { activeFaults[f, default: 0] += 1 }
        for k in activeFaults.keys where !swing.faults.contains(k) {
            activeFaults[k]! -= 1
            if activeFaults[k]! <= 0 { activeFaults.removeValue(forKey: k) }
        }
        updatedAt = Date()
    }

    /// Faults seen on 2+ recent swings, most persistent first.
    var persistentFaults: [String] {
        activeFaults.filter { $0.value >= 2 }.sorted { $0.value > $1.value }.map(\.key)
    }
}

// MARK: - Lenient curriculum decoding
//
// The synthesized Decodable REQUIRES every key, but curriculum steps only carry the fields
// their kind uses (a quiz has no asset3D; an explainer has no swingCount). The silent decode
// failure of one missing key emptied the entire curriculum — these initializers make every
// optional-ish field genuinely optional.

extension LessonStep {
    private enum K: String, CodingKey {
        case id, kind, title, body, points, videoId, asset3D, checkpoints, swingCount, quiz
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id          = try c.decode(String.self, forKey: .id)
        kind        = try c.decode(LessonStepKind.self, forKey: .kind)
        title       = try c.decode(String.self, forKey: .title)
        body        = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        points      = try c.decodeIfPresent([String].self, forKey: .points) ?? []
        videoId     = try c.decodeIfPresent(String.self, forKey: .videoId)
        asset3D     = try c.decodeIfPresent(String.self, forKey: .asset3D)
        checkpoints = try c.decodeIfPresent([String].self, forKey: .checkpoints) ?? []
        swingCount  = try c.decodeIfPresent(Int.self, forKey: .swingCount)
        quiz        = try c.decodeIfPresent([QuizQuestion].self, forKey: .quiz) ?? []
    }
}

extension Lesson {
    private enum K: String, CodingKey {
        case id, title, subtitle, icon, minutes, prerequisites, focusMetrics, steps
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id            = try c.decode(String.self, forKey: .id)
        title         = try c.decode(String.self, forKey: .title)
        subtitle      = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        icon          = try c.decodeIfPresent(String.self, forKey: .icon) ?? "figure.golf"
        minutes       = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 10
        prerequisites = try c.decodeIfPresent([String].self, forKey: .prerequisites) ?? []
        focusMetrics  = try c.decodeIfPresent([String].self, forKey: .focusMetrics) ?? []
        steps         = try c.decode([LessonStep].self, forKey: .steps)
    }
}

extension QuizQuestion {
    private enum K: String, CodingKey { case question, answers, correctIndex, why }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        question     = try c.decode(String.self, forKey: .question)
        answers      = try c.decode([String].self, forKey: .answers)
        correctIndex = try c.decode(Int.self, forKey: .correctIndex)
        why          = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
    }
}
