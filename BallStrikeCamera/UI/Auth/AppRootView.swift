import SwiftUI

struct AppRootView: View {
    @EnvironmentObject var session: AuthSessionStore
    /// Forwarded from the cold-start launch sequence so the login page plays its
    /// entrance exactly as the splash hands off (defaults true for standalone use).
    var launchComplete: Bool = true

    /// True only when the DEBUG screenshot harness is driving the tutorial, so the
    /// intro-slide cover is suppressed and the coach shows immediately. Always
    /// false in release builds.
    static var tutorialDemoActive: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TC_TUTORIAL_STEP"] != nil
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if session.isLoading {
                TrueCarryLoadingView()
            } else if session.isLoggedIn {
                MainTabView()
                    .fullScreenCover(isPresented: Binding(
                        get: { session.needsOnboarding && !Self.tutorialDemoActive },
                        set: { _ in }   // dismissed when completeOnboarding() flips the flag
                    )) {
                        OnboardingView()
                    }
                    .task(id: session.currentUser?.id) {
                        // DAU / retention telemetry (fire-and-forget).
                        await session.backend.logAnalyticsEvent(
                            "app_open", properties: [:], sessionId: nil)
                    }
            } else {
                LoginView(startEntrance: launchComplete)
            }
        }
        .tcAppearance()
        #if DEBUG
        // Screenshot harness: when TC_TUTORIAL_STEP is set, skip login by
        // entering guest mode so the tutorial coach can be inspected. No-op in
        // normal runs and entirely absent from release builds.
        .task(id: session.isLoading) {
            if ProcessInfo.processInfo.environment["TC_TUTORIAL_STEP"] != nil,
               !session.isLoggedIn, !session.isLoading {
                try? await session.continueAsGuest()
            }
        }
        // Screenshot harness: TC_DEBUG_RENDER=cards snapshots data-dependent
        // composites (handicap share card, ghost HUD) to Documents so they can
        // be inspected without playing rounds first. Absent from release builds.
        .task { await Self.debugRenderCardsIfRequested() }
        #endif
    }
}

#if DEBUG
extension AppRootView {
    /// TC_DEBUG_RENDER=cards → writes handicap-card + ghost-HUD snapshots into
    /// the app's Documents directory (paths printed to the console). These views
    /// only appear with real round data, so this is how they get eyeballed
    /// without playing 20 rounds first. DEBUG builds only.
    @MainActor
    static func debugRenderCardsIfRequested() async {
        guard ProcessInfo.processInfo.environment["TC_DEBUG_RENDER"] == "cards" else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        if let card = renderHandicapCard(indexString: "8.4", usedCount: 8, totalCount: 20, attestedCount: 3),
           let data = card.pngData() {
            let url = docs.appendingPathComponent("debug_handicap_card.png")
            try? data.write(to: url)
            print("[TC_DEBUG_RENDER] handicap card → \(url.path)")
        }

        // Ghost HUD in a mid-match state: up 1 thru 5, ghost made 4 here.
        let ghostHoles = (1...9).map { RoundHole(holeNumber: $0, par: 4, score: $0 == 6 ? 4 : 5) }
        var ghost = CourseRound(userId: UUID(), courseId: "debug", courseName: "Debug National", teeBoxName: "Blue")
        ghost.holes = ghostHoles
        ghost.scoreSummary.totalScore = 41
        ghost.scoreSummary.totalPar = 36
        let mine = (1...5).map { RoundHole(holeNumber: $0, par: 4, score: $0 == 3 ? 4 : 5) }
            + [RoundHole(holeNumber: 6, par: 4, score: nil)]
        let hud = VStack(spacing: 10) {
            GhostStrip(ghost: ghost, currentHoles: mine, currentHoleNumber: 6, onEnd: {})
            GhostOfferChip(bestScore: 41, onPick: {}, onDismiss: {})
        }
        .padding(24)
        .background(Color(red: 0.16, green: 0.30, blue: 0.18))   // stand-in for the course map
        let renderer = ImageRenderer(content: hud)
        renderer.scale = 3
        if let img = renderer.uiImage, let data = img.pngData() {
            let url = docs.appendingPathComponent("debug_ghost_hud.png")
            try? data.write(to: url)
            print("[TC_DEBUG_RENDER] ghost HUD → \(url.path)")
        }
    }
}
#endif

// MARK: - Animated launch / loading screen

struct TrueCarryLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false
    @State private var appear = false

    var body: some View {
        ZStack {
            TrueCarryBackground()

            VStack(spacing: 22) {
                ZStack {
                    // Soft pulsing halo behind the logo
                    Circle()
                        .fill(TCTheme.gold.opacity(0.10))
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulse ? 1.12 : 0.88)
                        .opacity(pulse ? 0.0 : 0.9)

                    // Rotating brand arc
                    Circle()
                        .trim(from: 0.0, to: 0.72)
                        .stroke(
                            AngularGradient(
                                colors: [TCTheme.gold.opacity(0.0), TCTheme.gold],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    TrueCarryLogo(size: 22)
                        .scaleEffect(pulse ? 1.04 : 0.96)
                }

                Text("Loading your game")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TCTheme.textMuted)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appear = true }
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
