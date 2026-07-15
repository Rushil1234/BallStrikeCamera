import Foundation
import SwiftUI

// MARK: - TrueCarry Coach: curriculum engine + local-first persistence
//
// Content loads from Resources/Lessons/curriculum.json + faults.json. All user state
// (intake profile, per-lesson progress, swing records, player model) persists as JSON files
// under AppStorageManager's user root — same local-first pattern the rest of the app uses.
// Backend sync is a later phase (see LESSONS_PLAN.md).

@MainActor
final class LessonLibrary: ObservableObject {

    static let shared = LessonLibrary()

    @Published private(set) var curriculum: LessonCurriculum = LessonCurriculum(version: 0, tracks: [])
    @Published private(set) var faults: [SwingFault] = []
    @Published private(set) var profile: LessonProfile? = nil
    @Published private(set) var progress: [String: LessonProgress] = [:]   // lessonId → progress
    @Published private(set) var swings: [SwingRecording] = []
    @Published private(set) var lessonSessions: [LessonSessionRecord] = []
    @Published private(set) var playerModel = PlayerSwingModel()

    private var userId: UUID?

    private init() {
        loadContent()
    }

    // MARK: Content loading

    private func loadContent() {
        if let url = Bundle.main.url(forResource: "curriculum", withExtension: "json", subdirectory: "Lessons")
                  ?? Bundle.main.url(forResource: "curriculum", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            do {
                curriculum = try JSONDecoder().decode(LessonCurriculum.self, from: data)
                print("[Lessons] curriculum loaded: \(curriculum.tracks.count) tracks")
            } catch {
                // A decode failure here erased the whole roadmap once - never fail silently.
                print("[Lessons] curriculum DECODE FAILED: \(error)")
                assertionFailure("curriculum.json decode failed: \(error)")
            }
        } else {
            print("[Lessons] curriculum.json missing from bundle")
        }
        if let url = Bundle.main.url(forResource: "faults", withExtension: "json", subdirectory: "Lessons")
                  ?? Bundle.main.url(forResource: "faults", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([SwingFault].self, from: data) {
            faults = decoded
        }
    }

    func fault(_ id: String) -> SwingFault? { faults.first { $0.id == id } }

    var allLessons: [Lesson] { curriculum.tracks.flatMap(\.lessons) }
    func lesson(_ id: String) -> Lesson? { allLessons.first { $0.id == id } }
    func track(containing lessonId: String) -> LessonTrack? {
        curriculum.tracks.first { $0.lessons.contains { $0.id == lessonId } }
    }

    // MARK: User state

    func activate(userId: UUID) {
        guard self.userId != userId else { return }
        self.userId = userId
        profile        = Self.read(dir(userId), "profile.json")
        progress       = Self.read(dir(userId), "progress.json") ?? [:]
        swings         = Self.read(dir(userId), "swings.json") ?? []
        lessonSessions = Self.read(dir(userId), "sessions.json") ?? []
        playerModel    = Self.read(dir(userId), "player_model.json") ?? PlayerSwingModel()
    }

    var hasCompletedIntake: Bool { profile != nil }

    func saveProfile(_ p: LessonProfile) {
        var updated = p
        updated.updatedAt = Date()
        profile = updated
        persist(updated, "profile.json")
    }

    // MARK: Syllabus (intake → ordered lesson plan)

    /// Tracks ordered by intake relevance: focus-area matches first, foundations always first
    /// for newcomers/beginners, checkup-only users get their pick in chosen order.
    var orderedTracks: [LessonTrack] {
        guard let profile else { return curriculum.tracks }
        let focus = Set(profile.focusAreas)
        let needsFoundations = profile.skillLevel == .newcomer || profile.skillLevel == .beginner
            || focus.contains(.startFromZero)
        return curriculum.tracks.sorted { a, b in
            func rank(_ t: LessonTrack) -> Int {
                if needsFoundations && t.id == "foundations" { return -1 }
                if !focus.isDisjoint(with: Set(t.focusAreas)) { return 0 }
                return 1
            }
            let (ra, rb) = (rank(a), rank(b))
            if ra != rb { return ra < rb }
            return false   // stable: keep curriculum order within a rank
        }
    }

    /// Main-path units: universal skills every golfer walks through, in intake order.
    var coreTracks: [LessonTrack] { orderedTracks.filter { $0.kind == "core" } }
    /// Off-path problem-fix tracks, opened from their own cards.
    var fixTracks: [LessonTrack] { curriculum.tracks.filter { $0.kind == "fix" } }

    func status(of lesson: Lesson) -> LessonStatus {
        if let p = progress[lesson.id], p.status == .completed || p.status == .mastered {
            return p.status
        }
        // Locked until all prerequisites are completed.
        for pre in lesson.prerequisites {
            let s = progress[pre]?.status
            if s != .completed && s != .mastered { return .locked }
        }
        return progress[lesson.id]?.status ?? .available
    }

    /// The lesson the "Continue" hero should point at.
    var nextLesson: Lesson? {
        for track in orderedTracks {
            for lesson in track.lessons {
                let s = status(of: lesson)
                if s == .available || s == .inProgress { return lesson }
            }
        }
        return nil
    }

    var completedLessonCount: Int {
        progress.values.filter { $0.status == .completed || $0.status == .mastered }.count
    }

    // MARK: Progress mutation

    func beginLesson(_ lesson: Lesson) -> LessonSessionRecord {
        var p = progress[lesson.id] ?? LessonProgress(lessonId: lesson.id)
        if p.status == .available || p.status == .locked { p.status = .inProgress }
        p.attempts += 1
        progress[lesson.id] = p
        persist(progress, "progress.json")
        return LessonSessionRecord(
            userId: userId ?? UUID(),
            lessonId: lesson.id,
            lessonTitle: lesson.title,
            trackTitle: track(containing: lesson.id)?.title ?? "",
            stepCount: lesson.steps.count
        )
    }

    func completeStep(_ step: LessonStep, in lesson: Lesson) {
        var p = progress[lesson.id] ?? LessonProgress(lessonId: lesson.id, status: .inProgress)
        if !p.completedSteps.contains(step.id) { p.completedSteps.append(step.id) }
        progress[lesson.id] = p
        persist(progress, "progress.json")
    }

    func completeLesson(_ lesson: Lesson, session: LessonSessionRecord, score: Int?) {
        var p = progress[lesson.id] ?? LessonProgress(lessonId: lesson.id)
        p.status = .completed
        p.completedAt = Date()
        if let score { p.bestScore = max(p.bestScore ?? 0, score) }
        progress[lesson.id] = p
        persist(progress, "progress.json")

        var record = session
        record.endedAt = Date()
        record.stepsCompleted = lesson.steps.count
        record.score = score
        lessonSessions.append(record)
        persist(lessonSessions, "sessions.json")
    }

    // MARK: Swing records

    func addSwing(_ swing: SwingRecording) {
        swings.append(swing)
        persist(swings, "swings.json")
        if swing.analyzed {
            playerModel.absorb(swing)
            if let s = swing.overallScore,
               playerModel.bestSwingId == nil
                || s >= (swings.first { $0.id == playerModel.bestSwingId }?.overallScore ?? 0) {
                playerModel.bestSwingId = swing.id
            }
            persist(playerModel, "player_model.json")
        }
    }

    func updateSwing(_ swing: SwingRecording) {
        guard let i = swings.firstIndex(where: { $0.id == swing.id }) else { return addSwing(swing) }
        let wasAnalyzed = swings[i].analyzed
        swings[i] = swing
        persist(swings, "swings.json")
        if swing.analyzed && !wasAnalyzed {
            playerModel.absorb(swing)
            persist(playerModel, "player_model.json")
        }
    }

    func deleteSwing(id: UUID) {
        if let s = swings.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: videoURL(for: s))
        }
        swings.removeAll { $0.id == id }
        persist(swings, "swings.json")
    }

    // MARK: Paths

    static func swingsDir(userId: UUID) -> URL {
        AppStorageManager.userRoot(for: userId).appendingPathComponent("swings")
    }

    private func dir(_ uid: UUID) -> URL {
        AppStorageManager.userRoot(for: uid).appendingPathComponent("lessons")
    }

    func videoURL(for swing: SwingRecording) -> URL {
        Self.swingsDir(userId: swing.userId).appendingPathComponent(swing.videoPath)
    }

    // MARK: Persistence plumbing

    private func persist<T: Encodable>(_ value: T, _ file: String) {
        guard let uid = userId else { return }
        let d = dir(uid)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: d.appendingPathComponent(file), options: .atomic)
        }
    }

    private static func read<T: Decodable>(_ dir: URL, _ file: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Coach Advisor (decision tree: pose faults × real ball data → suggestions)
//
// This is the "app knows what the player does" layer: it reads the PlayerSwingModel
// (camera-measured swing tendencies) AND the launch monitor's SavedShots (measured ball
// flight) and only makes a call when the two agree — a pose hypothesis confirmed by ball
// data outranks either signal alone.

struct CoachSuggestion: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let icon: String
    let lessonId: String?
    /// 0 = pose-only or ball-only hint · 1 = both signals agree (lead with these)
    let priority: Int
    /// Camera metrics behind this read — the deep-dive charts plot these.
    var metricKinds: [String] = []
}

enum CoachAdvisor {

    /// Signed curvature tendency from recent shots: + fade/slice, − draw/hook (RH signs;
    /// spin axis is already signed in SavedShotMetrics).
    private static func ballTendency(_ shots: [SavedShot]) -> (curve: Double, pushPull: Double, n: Int) {
        let recent = shots.suffix(30).filter { !$0.isBadShot && $0.metrics.ballSpeedMph > 0 }
        guard !recent.isEmpty else { return (0, 0, 0) }
        let axes = recent.map { $0.metrics.spinAxisDegrees }
        let hlas = recent.map { $0.metrics.hlaDirection.lowercased() == "left" ? -$0.metrics.hlaDegrees
                                                                               : $0.metrics.hlaDegrees }
        return (axes.reduce(0, +) / Double(axes.count),
                hlas.reduce(0, +) / Double(hlas.count),
                recent.count)
    }

    @MainActor
    static func suggestions(model: PlayerSwingModel, shots: [SavedShot],
                            library: LessonLibrary) -> [CoachSuggestion] {
        var out: [CoachSuggestion] = []
        let ball = ballTendency(shots)
        let avg = model.metricAverages
        let steep    = (avg[SwingMetricKind.deliveryPlane.rawValue] ?? 0) > 22
        let shallow  = (avg[SwingMetricKind.deliveryPlane.rawValue] ?? 0) < -22
        let inside   = (avg[SwingMetricKind.takeawayPath.rawValue] ?? 0) < -22
        let outside  = (avg[SwingMetricKind.takeawayPath.rawValue] ?? 0) > 22
        let quick    = (avg[SwingMetricKind.tempoRatio.rawValue] ?? 3.0) < 2.3
        let sway     = (avg[SwingMetricKind.headSway.rawValue] ?? 0) > 30
        let earlyExt = (avg[SwingMetricKind.earlyExtension.rawValue] ?? 0) > 25

        // ── Confirmed patterns (camera + ball agree) ─────────────────────────
        if (steep || outside), ball.curve > 4, ball.n >= 5 {
            out.append(CoachSuggestion(
                title: "Confirmed: over-the-top slice pattern",
                detail: "Your camera swings show the club \(steep ? "steep at delivery" : "working outside on the takeaway"), and your last \(ball.n) measured shots curve right (avg spin axis +\(Int(ball.curve))°). The Slice track's transition work is your highest-value practice.",
                icon: "arrow.up.right", lessonId: "slice.path", priority: 1,
                metricKinds: ["delivery_plane", "takeaway_path"]))
        }
        if (shallow || inside), ball.curve < -4, ball.n >= 5 {
            out.append(CoachSuggestion(
                title: "Confirmed: inside-out hook pattern",
                detail: "The club works \(inside ? "inside early" : "shallow into delivery") on camera and your measured shots curve left (avg spin axis \(Int(ball.curve))°). Quiet hands + body rotation is the fix.",
                icon: "arrow.up.left", lessonId: "hook.release", priority: 1,
                metricKinds: ["delivery_plane", "takeaway_path"]))
        }
        if sway, ball.n >= 5 {
            let inconsistent = shots.suffix(20).map { $0.metrics.smashFactor }.filter { $0 > 0 }
            let sd: Double = {
                guard inconsistent.count > 3 else { return 0 }
                let m = inconsistent.reduce(0, +) / Double(inconsistent.count)
                return (inconsistent.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(inconsistent.count)).squareRoot()
            }()
            if sd > 0.12 {
                out.append(CoachSuggestion(
                    title: "Confirmed: sway is costing you contact",
                    detail: "Your head moves laterally on camera AND your smash factor varies shot to shot (±\(String(format: "%.2f", sd))) — the classic sway signature. Low-point control drills will tighten both.",
                    icon: "circle.dotted", lessonId: "contact.lowpoint", priority: 1,
                    metricKinds: ["head_sway"]))
            }
        }

        // ── Single-signal reads ──────────────────────────────────────────────
        if out.isEmpty {
            if steep { out.append(CoachSuggestion(title: "Club steep at delivery",
                detail: "Camera shows the hands above the address plane coming down. Feel the club drop behind you from the top before it swings out.",
                icon: "arrow.down.right.circle", lessonId: "slice.path", priority: 0, metricKinds: ["delivery_plane"])) }
            if inside { out.append(CoachSuggestion(title: "Takeaway working inside",
                detail: "The hands pull inside the plane line in the first move. One-piece takeaway reps will neutralize it.",
                icon: "arrow.turn.up.right", lessonId: "foundations.takeaway", priority: 0, metricKinds: ["takeaway_path"])) }
            if quick { out.append(CoachSuggestion(title: "Transition is quick",
                detail: "Your backswing:downswing ratio is running under 2.3:1. The 3:1 drill smooths everything downstream.",
                icon: "metronome", lessonId: "tempo.ratio", priority: 0, metricKinds: ["tempo_ratio"])) }
            if earlyExt { out.append(CoachSuggestion(title: "Losing posture at impact",
                detail: "Your hips drift toward the ball on the downswing. Wall-butt drill: keep your rear against a wall through the strike.",
                icon: "figure.stand", lessonId: "contact.balance", priority: 0, metricKinds: ["early_extension"])) }
            if ball.curve > 6 && ball.n >= 5 {
                out.append(CoachSuggestion(title: "Ball data: fade/slice bias",
                    detail: "Average spin axis +\(Int(ball.curve))° over \(ball.n) shots. Record a down-the-line swing so Coach can pinpoint whether it's the takeaway or the transition.",
                    icon: "video.badge.waveform", lessonId: "slice.diagnose", priority: 0))
            }
            if ball.curve < -6 && ball.n >= 5 {
                out.append(CoachSuggestion(title: "Ball data: draw/hook bias",
                    detail: "Average spin axis \(Int(ball.curve))° over \(ball.n) shots. A down-the-line recording will show whether the club is working too far inside.",
                    icon: "video.badge.waveform", lessonId: "hook.diagnose", priority: 0))
            }
        }

        // Persistent camera faults not already covered.
        for faultId in model.persistentFaults.prefix(2) {
            guard let f = library.fault(faultId),
                  !out.contains(where: { $0.lessonId == f.lessonId }) else { continue }
            out.append(CoachSuggestion(title: f.title, detail: f.drill,
                                       icon: "exclamationmark.triangle.fill",
                                       lessonId: f.lessonId, priority: 0))
        }
        return out.sorted { $0.priority > $1.priority }
    }
}
