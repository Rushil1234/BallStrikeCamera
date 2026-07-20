import SwiftUI

// ⚠️ TEMPORARY STUBS — DELETE THIS FILE when Rushil pushes the real implementations.
//
// Commits d6bbbaf..06d1473 integrated calls to nine files (UI/Learning/*,
// AICoachService, HandicapShareCard, GhostMatch, WeeklyChallenge) that were never
// committed — main did not build for anyone else. Every stub below is the minimal
// compile-satisfying no-op for the call sites that exist in committed code. When the
// real files land, Xcode will flag duplicate symbols: resolve by deleting THIS file.

// MARK: TutorialController (UI/Learning/TutorialController.swift)
final class TutorialController: ObservableObject {
    @Published var isActive = false
    @Published var requestedTab: TCTab? = nil
    static var shouldAutoStart: Bool { false }   // stub: never auto-start
    static var isTourActive: Bool { false }
    func start() {}
    func startAt(_ step: Int) {}
    func clearRequestedTab() { requestedTab = nil }
}

extension View {
    func tutorialHost(_ controller: TutorialController) -> some View { self }
}

enum TutorialAnchorID: Hashable {
    case playStartHero
    case dockTab(Int)
}

extension TCTab {
    var tutorialAnchorID: TutorialAnchorID { .dockTab(rawValue) }
}

extension View {
    func tutorialAnchor(_ id: TutorialAnchorID) -> some View { self }
}

// MARK: LearnHub (UI/Learning/LearnHub.swift)
struct LearnHubView: View {
    var body: some View {
        Text("Learn Hub coming soon")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: AI Coach (Services/AICoachService.swift + UI/Learning/AICoachCard.swift)
enum AICoachService {
    struct ShotPayload {
        init(_ metrics: SavedShotMetrics, clubName: String?) {}
    }
}

struct AICoachCard: View {
    enum Mode { case session, shot }
    let mode: Mode
    let shots: [AICoachService.ShotPayload]
    let isPro: Bool
    let subtitle: String
    var body: some View { EmptyView() }
}

// MARK: Beginner help (UI/Learning/BeginnerHelp.swift)
enum TCLearning {
    static let beginnerHelpKey = "tc_beginner_help_enabled"
}

extension View {
    /// Stub: real version shows a one-time coach-mark bubble keyed by `id`.
    func firstTimeHint(id: String, icon: String, text: String) -> some View { self }
}

// MARK: Handicap share card (UI/History/HandicapShareCard.swift)
@MainActor
func renderHandicapCard(indexString: String, usedCount: Int, totalCount: Int,
                        attestedCount: Int) -> UIImage? { nil }

// MARK: Ghost match (UI/Courses/GhostMatch.swift)
struct GhostStrip: View {
    let ghost: CourseRound
    let currentHoles: [RoundHole]
    let currentHoleNumber: Int
    let onEnd: () -> Void
    var body: some View { EmptyView() }
}

struct GhostOfferChip: View {
    let bestScore: Int?
    let onPick: () -> Void
    let onDismiss: () -> Void
    var body: some View { EmptyView() }
}

enum GhostPersistence {
    static func clear() {}
    static func save(roundId: UUID, ghostId: UUID) {}
    static func ghostId(forRound roundId: UUID) -> UUID? { nil }
}

enum GhostMatchScorer {
    static func candidates(from rounds: [CourseRound], courseId: String,
                           excluding: UUID) -> [CourseRound] { [] }
}

struct GhostPickerSheet: View {
    let candidates: [CourseRound]
    let onPick: (CourseRound) -> Void
    var body: some View { EmptyView() }
}

// MARK: Glossary info mark (UI/Learning — Rushil's variant of TCInfoMark)
struct InfoMark: View {
    let term: String
    let size: CGFloat
    init(_ term: String, size: CGFloat = 11) {
        self.term = term
        self.size = size
    }
    var body: some View { EmptyView() }
}

// MARK: Weekly challenge (UI/AppShell/WeeklyChallenge.swift)
struct VerifiedChallengeCard: View {
    let refreshToken: Int
    var body: some View { EmptyView() }
}
