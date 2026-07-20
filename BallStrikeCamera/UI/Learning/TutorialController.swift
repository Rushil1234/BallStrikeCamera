import SwiftUI

// MARK: - Anchor identities

/// Stable identities for the UI elements the guided tour can spotlight. Elements
/// opt in with `.tutorialAnchor(_:)` and report their on-screen frame.
enum TutorialAnchorID: String, CaseIterable {
    case feedTab, insightsTab, playTab, historyTab, lockerTab
    case playStartHero
}

extension TCTab {
    /// The dock anchor that represents this tab in the tour.
    var tutorialAnchorID: TutorialAnchorID {
        switch self {
        case .home:     return .feedTab
        case .insights: return .insightsTab
        case .play:     return .playTab
        case .history:  return .historyTab
        case .locker:   return .lockerTab
        }
    }
}

// MARK: - Step model

/// One stop on the linear tour. `anchor == nil` renders a centered card with no
/// spotlight (used for the closing step).
struct TutorialStep: Identifiable {
    let id = UUID()
    let tab: TCTab                 // tab that must be active for this step
    let anchor: TutorialAnchorID?  // element to spotlight
    let title: String
    let body: String
}

// MARK: - Controller

/// Drives the first-run guided tour: which step is showing, which tab it needs,
/// and where every registered anchor currently sits on screen. Owned by the app
/// shell and injected as an `EnvironmentObject`.
final class TutorialController: ObservableObject {
    /// Mirror of `isActive` that decoupled views (e.g. the Play screen) can read
    /// without taking an EnvironmentObject dependency — used to hold back
    /// side-effectful prompts (location, etc.) while the coach is on screen.
    static private(set) var isTourActive = false

    @Published private(set) var isActive = false {
        didSet { TutorialController.isTourActive = isActive }
    }
    @Published private(set) var index = 0
    /// Set when a step needs a different tab; the shell observes and switches.
    @Published var requestedTab: TCTab?
    /// Latest measured frames for each anchor, in the shell's coordinate space.
    @Published var anchors: [TutorialAnchorID: CGRect] = [:]

    let steps: [TutorialStep] = [
        TutorialStep(tab: .home, anchor: .feedTab,
            title: "Your Feed",
            body: "Shots and rounds from you and the golfers you follow land here. It's your home base."),
        TutorialStep(tab: .insights, anchor: .insightsTab,
            title: "Insights",
            body: "Your averages, club gapping, and trends over time. This is where practice turns into a plan."),
        TutorialStep(tab: .play, anchor: .playTab,
            title: "Play",
            body: "The heart of the app. Warm up on the range, play a course round, or stream to the web simulator."),
        TutorialStep(tab: .play, anchor: .playStartHero,
            title: "Start a session",
            body: "Tap here to begin. Stand your iPhone on a tripod beside the ball and it becomes the launch monitor."),
        TutorialStep(tab: .history, anchor: .historyTab,
            title: "History",
            body: "Every session and round is saved here, ready to revisit and compare."),
        TutorialStep(tab: .locker, anchor: .lockerTab,
            title: "Your Locker",
            body: "Your clubs, stats, and settings live here. You can replay this tutorial anytime from Locker."),
        TutorialStep(tab: .locker, anchor: nil,
            title: "You're all set",
            body: "See a term you don't know? Tap the ⓘ next to it for a quick, plain-English explanation. Now go hit some shots."),
    ]

    var currentStep: TutorialStep? {
        guard isActive, steps.indices.contains(index) else { return nil }
        return steps[index]
    }

    var isLastStep: Bool { index >= steps.count - 1 }
    var progress: (current: Int, total: Int) { (index + 1, steps.count) }

    // MARK: Lifecycle

    /// Starts the tour from the beginning. Safe to call repeatedly.
    func start() {
        index = 0
        isActive = true
        requestedTab = steps.first?.tab
    }

    #if DEBUG
    /// DEBUG helper: jump the tour to a specific step (used by the screenshot
    /// harness). Never called in release builds.
    func startAt(_ i: Int) {
        index = max(0, min(i, steps.count - 1))
        isActive = true
        requestedTab = steps[index].tab
    }
    #endif

    func advance() {
        guard isActive else { return }
        if isLastStep {
            finish()
        } else {
            index += 1
            requestedTab = steps[index].tab
        }
    }

    func skip() { finish() }

    private func finish() {
        isActive = false
        requestedTab = nil
        UserDefaults.standard.set(true, forKey: TCLearning.tutorialDoneKey)
    }

    func clearRequestedTab() { requestedTab = nil }

    // MARK: Anchor registry

    func updateAnchors(_ new: [TutorialAnchorID: CGRect]) {
        // Merge so anchors from screens that aren't currently mounted don't get
        // wiped by a partial preference update.
        for (k, v) in new { anchors[k] = v }
    }

    /// Frame of the current step's spotlight target, if known and on screen.
    var currentAnchorRect: CGRect? {
        guard let anchor = currentStep?.anchor else { return nil }
        return anchors[anchor]
    }

    /// Whether the tour should auto-start: never seen, and not still in the
    /// server-gated intro slides.
    static var shouldAutoStart: Bool {
        !UserDefaults.standard.bool(forKey: TCLearning.tutorialDoneKey)
    }
}
