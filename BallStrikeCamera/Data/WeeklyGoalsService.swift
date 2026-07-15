import Foundation
import SwiftUI

// MARK: - Goal completions + Sim Course Unlocks

/// A queued celebration popup (goal completed or course unlocked).
struct GoalCelebration: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let icon: String
    let isUnlock: Bool
}

/// A sim course on the unlock ladder. IDs match Website/src/lib/courses.ts (the sim bundle).
struct SimCourseUnlock: Identifiable {
    let id: String
    let name: String
    let goalsRequired: Int
}

/// Unlock progression driven by the SAME weekly challenges the home feed already shows
/// (Weekly Long Drive, GIR Streak, Range Volume, …). Whenever a challenge card reaches 100%
/// it is credited ONCE for that week, a celebration pops, and the credit is banked forever —
/// the lifetime total is what unlocks sim courses, so nothing has to be re-accomplished.
/// All state lives in UserDefaults: instant, offline, zero backend coupling.
@MainActor
final class WeeklyGoalsService: ObservableObject {

    static let shared = WeeklyGoalsService()

    /// Celebrations waiting to be shown; the app-shell overlay presents them one at a time.
    @Published private(set) var celebrationQueue: [GoalCelebration] = []
    /// Bumped whenever credits/unlocks change so the unlock card refreshes.
    @Published private(set) var revision = 0

    static let unlockLadder: [SimCourseUnlock] = [
        SimCourseUnlock(id: "pine-hollow",     name: "Pine Hollow National",  goalsRequired: 0),
        SimCourseUnlock(id: "pebble-private",  name: "Cypress Coast Links",   goalsRequired: 3),
        SimCourseUnlock(id: "standrews-old",   name: "St Andrews Old Course", goalsRequired: 6),
        SimCourseUnlock(id: "augusta-national", name: "Augusta National",     goalsRequired: 10),
    ]

    private let defaults = UserDefaults.standard
    private let totalKey    = "tc_goals_total_completed"
    private let unlockedKey = "tc_sim_courses_unlocked"

    private init() {}

    // MARK: - Week bucketing

    /// "2026-W29" — ISO week. The feed challenges are computed over rolling weekly windows,
    /// so each challenge can earn at most one credit per week; the credits themselves are
    /// banked into the lifetime total and never expire.
    private var weekKey: String {
        let cal = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }

    private var creditedKey: String { "tc_goals_\(weekKey)_credited" }

    private var creditedThisWeek: Set<String> {
        Set(defaults.stringArray(forKey: creditedKey) ?? [])
    }

    // MARK: - Public state

    /// Lifetime count of completed challenges — the currency that unlocks sim courses.
    var totalGoalsCompleted: Int {
        _ = revision
        return defaults.integer(forKey: totalKey)
    }

    var unlockedCourseIds: Set<String> {
        _ = revision
        var ids = Set(defaults.stringArray(forKey: unlockedKey) ?? [])
        ids.insert("pine-hollow")   // base course is always playable
        ids.insert("range")
        return ids
    }

    func isUnlocked(_ courseId: String) -> Bool { unlockedCourseIds.contains(courseId) }

    /// The next course on the ladder still locked, with how many completed challenges remain.
    var nextUnlock: (course: SimCourseUnlock, goalsRemaining: Int)? {
        let unlocked = unlockedCourseIds
        for course in Self.unlockLadder where !unlocked.contains(course.id) {
            return (course, max(0, course.goalsRequired - totalGoalsCompleted))
        }
        return nil
    }

    // MARK: - Challenge syncing

    /// Feed the current state of the home-page challenge cards. Any challenge at 100% that
    /// hasn't been credited this week: celebration popup + one permanent credit toward the
    /// course-unlock ladder.
    func syncChallenges(_ challenges: [FeedChallengePreview]) {
        var credited = creditedThisWeek
        var newlyCompleted: [FeedChallengePreview] = []
        for challenge in challenges where challenge.progress >= 1.0 && !credited.contains(challenge.id) {
            credited.insert(challenge.id)
            newlyCompleted.append(challenge)
        }
        guard !newlyCompleted.isEmpty else { return }
        defaults.set(Array(credited), forKey: creditedKey)
        defaults.set(defaults.integer(forKey: totalKey) + newlyCompleted.count, forKey: totalKey)
        for challenge in newlyCompleted {
            celebrationQueue.append(GoalCelebration(
                title: "Goal Complete!",
                message: challenge.title,
                icon: challenge.icon,
                isUnlock: false
            ))
        }
        evaluateUnlocks()
        revision += 1
    }

    func dismissCelebration(_ celebration: GoalCelebration) {
        celebrationQueue.removeAll { $0.id == celebration.id }
    }

    // MARK: - Unlock evaluation

    private func evaluateUnlocks() {
        let total = defaults.integer(forKey: totalKey)
        var unlocked = Set(defaults.stringArray(forKey: unlockedKey) ?? [])
        for course in Self.unlockLadder
        where course.goalsRequired > 0 && total >= course.goalsRequired && !unlocked.contains(course.id) {
            unlocked.insert(course.id)
            celebrationQueue.append(GoalCelebration(
                title: "New Course Unlocked!",
                message: "\(course.name) is now playable in the True Carry sim.",
                icon: "lock.open.fill",
                isUnlock: true
            ))
        }
        defaults.set(Array(unlocked), forKey: unlockedKey)
    }
}
