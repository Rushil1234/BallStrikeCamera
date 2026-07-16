import SwiftUI

// MARK: - TrueCarry Guide
// One system for two jobs: (1) a per-screen click-through tour that auto-shows on first
// visit and can be re-opened anytime from a ⓘ button, and (2) element-level info marks
// (TCInfoMark) for single controls that deserve their own explanation.
// All copy lives in GuideCatalog so it can be edited in one place.

enum GuideScreen: String, CaseIterable {
    case home, insights, play, history, locker, range, coach
}

struct GuideStep {
    let icon: String
    let title: String
    let text: String
}

enum GuideCatalog {
    static let steps: [GuideScreen: [GuideStep]] = [
        .home: [
            GuideStep(icon: "person.2.fill", title: "Activity Feed",
                      text: "Posts from you and your friends — rounds, range sessions, single shots, and wins. Tap the ball to give a “gimme” (a like), tap the bubble to comment."),
            GuideStep(icon: "plus.circle.fill", title: "Share",
                      text: "Post a round, a range note, or a win. Each post can be visible to Everyone, Friends only, or kept Private."),
            GuideStep(icon: "flag.fill", title: "Round in progress",
                      text: "If you leave a course round mid-way, a banner appears at the top of the feed. Tap it to jump straight back to your scorecard."),
            GuideStep(icon: "trophy.fill", title: "Goals & challenges",
                      text: "Weekly goals track themselves as you hit shots and play rounds — no check-ins. Finishing them unlocks simulator courses."),
        ],
        .insights: [
            GuideStep(icon: "chart.bar.fill", title: "Club chips",
                      text: "Tap any club to see its carry, total, ball speed, launch and spin from every measured shot. The small number on each chip is how many shots are on record for it."),
            GuideStep(icon: "square.grid.2x2", title: "ALL view",
                      text: "Plots your whole bag on one chart so gaps and overlaps stand out. Every club keeps its own color — the key at the bottom maps colors to clubs."),
            GuideStep(icon: "ruler", title: "Bag gapping",
                      text: "Clubs sorted by average carry. Look for two clubs within a few yards of each other (doing the same job) or a hole bigger than ~15 yards (a distance you can't hit)."),
            GuideStep(icon: "scope", title: "Dispersion & consistency",
                      text: "Pro shows left/right spread and shot-to-shot repeatability per club — how tight your misses are, not just how far the average flies."),
            GuideStep(icon: "info.circle", title: "Where the data comes from",
                      text: "Every measured shot in Range, Course, and Sim modes feeds these charts automatically. More shots per club = steadier numbers."),
        ],
        .play: [
            GuideStep(icon: "figure.golf", title: "Range",
                      text: "The launch monitor. Set your phone on its tripod, place a ball, and every shot is measured (speed, launch, carry, spin) and saved to your history."),
            GuideStep(icon: "map.fill", title: "Course",
                      text: "A GPS round with hole-by-hole scoring. Shots you capture with the camera are pinned to the hole you're playing automatically — the map view shows each shot where it happened."),
            GuideStep(icon: "tv.fill", title: "Simulator",
                      text: "Play GSPro or other sims using your phone as the launch monitor. Pair with the TrueCarry Bridge desktop app by scanning its QR code."),
            GuideStep(icon: "arrow.uturn.left", title: "Resume round",
                      text: "An unfinished round shows at the top of this page — tap it to pick up exactly where you left off."),
            GuideStep(icon: "graduationcap.fill", title: "Coach",
                      text: "Guided lessons plus camera swing analysis that scores your tempo, balance, and body motion (Pro)."),
        ],
        .history: [
            GuideStep(icon: "number.square.fill", title: "Handicap index",
                      text: "Computed from your best round differentials. The dots on the bars mark which rounds are currently counted toward the index."),
            GuideStep(icon: "chart.bar.xaxis", title: "Score bars",
                      text: "One bar per round with the total score on the left. Tap a bar to see that round's details without leaving this page."),
            GuideStep(icon: "list.bullet.rectangle", title: "Rounds & sessions",
                      text: "Tap a round for its scorecard and a hole-by-hole shot map. Tap a range session for every shot with full metrics."),
            GuideStep(icon: "film", title: "Shot replay",
                      text: "Inside any shot's detail you can replay the captured frames and see the tracked ball flight drawn over them."),
        ],
        .locker: [
            GuideStep(icon: "bag.fill", title: "Your bag",
                      text: "The clubs shown across the whole app. Tap Manage Bag to add, remove, or edit clubs — distances shown come from your own measured shots."),
            GuideStep(icon: "square.stack.3d.up.fill", title: "Saved shots",
                      text: "Your raw shot library from every mode, newest first."),
            GuideStep(icon: "person.crop.circle", title: "Profile & settings",
                      text: "Camera options, Google Drive backup of captured frames, subscription, and sign out all live in your profile."),
        ],
        .range: [
            GuideStep(icon: "viewfinder", title: "Set a ball",
                      text: "Place a ball in view. The phase pill goes Searching → Tracking → Ready as the camera finds and locks onto it. When it says Ready, swing away."),
            GuideStep(icon: "timer", title: "Shutter buttons",
                      text: "Four shutter speeds — faster freezes the ball and club better but needs more light. The colored dot on each button grades it for the CURRENT light: green is clean, yellow works but adds grain, red will hurt tracking (too dark = murky frames, too bright = streak risk). The dot with the white ring is the recommended button."),
            GuideStep(icon: "dot.radiowaves.left.and.right", title: "The pills",
                      text: "Club sets which club the shot logs to. Count is shots this session. Simulate Shot runs a bundled sample through the full pipeline. Righty/Lefty flips the layout. Replay and Share Frames act on the last captured shot."),
            GuideStep(icon: "thermometer.sun.fill", title: "Heat",
                      text: "If the phone runs hot a yellow banner appears — heat causes dropped frames, which hurt speed accuracy. With no ball in view the screen also dims itself after ~30 seconds to stay cool; detection keeps running, so setting a ball (or tapping) wakes it."),
            GuideStep(icon: "chart.bar.doc.horizontal", title: "Results",
                      text: "After each shot you get ball speed, launch, carry, total, and spin. The side panel keeps the last shot's composite image and the bottom bar keeps its numbers."),
        ],
        .coach: [
            GuideStep(icon: "graduationcap.fill", title: "Lessons",
                      text: "Units run from grip and setup to a full swing with real ball-flight numbers. Finishing a unit's lessons opens the next one."),
            GuideStep(icon: "camera.viewfinder", title: "Analyze My Swing",
                      text: "Records your swing and scores tempo, balance, and body motion. “Coach Says” turns what it sees into the one drill worth working on next."),
            GuideStep(icon: "slider.horizontal.3", title: "Personalize your path",
                      text: "Five quick questions reorder the units around your game and set how your swings are graded."),
            GuideStep(icon: "atom", title: "Ball Flight Lab",
                      text: "Interactive physics, no videos: drag the face and path sliders and watch the ball's curve respond live — the fastest way to understand why the ball does what it does."),
        ],
    ]
}

extension Notification.Name {
    /// Posted by TCGuideButton; the screen's tcGuide host presents the tour.
    static let tcShowGuide = Notification.Name("tcShowGuide")
}

// MARK: - Tour overlay

struct GuideOverlayView: View {
    let screen: GuideScreen
    let onDone: () -> Void
    @State private var index = 0

    private var steps: [GuideStep] { GuideCatalog.steps[screen] ?? [] }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {}   // swallow taps behind the card

            if let step = steps.indices.contains(index) ? steps[index] : nil {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(TCTheme.sage.opacity(0.16))
                            .frame(width: 54, height: 54)
                        Image(systemName: step.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(TCTheme.sage)
                    }

                    Text(step.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(step.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TCTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        ForEach(steps.indices, id: \.self) { i in
                            Circle()
                                .fill(i == index ? TCTheme.sage : TCTheme.border)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 2)

                    HStack(spacing: 10) {
                        if index > 0 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { index -= 1 }
                            } label: {
                                Text("Back")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(TCTheme.textMuted)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: onDone) {
                                Text("Skip")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(TCTheme.textMuted)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            if index < steps.count - 1 {
                                withAnimation(.easeInOut(duration: 0.15)) { index += 1 }
                            } else {
                                onDone()
                            }
                        } label: {
                            Text(index < steps.count - 1 ? "Next" : "Done")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(TCTheme.sage))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(22)
                .frame(maxWidth: 360)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(TCTheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(TCTheme.border, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 28)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Host modifier

private struct TCGuideModifier: ViewModifier {
    let screen: GuideScreen
    let showButton: Bool
    let buttonBottomPadding: CGFloat

    @AppStorage private var seen: Bool
    @State private var showTour = false

    init(screen: GuideScreen, showButton: Bool, buttonBottomPadding: CGFloat) {
        self.screen = screen
        self.showButton = showButton
        self.buttonBottomPadding = buttonBottomPadding
        _seen = AppStorage(wrappedValue: false, "tc_tour_seen_\(screen.rawValue)")
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if showButton && !showTour {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { showTour = true }
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(TCTheme.textMuted.opacity(0.9))
                            .background(Circle().fill(TCTheme.panel).padding(2))
                            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.bottom, buttonBottomPadding)
                    .accessibilityLabel("Page guide")
                }
            }
            .overlay {
                if showTour {
                    GuideOverlayView(screen: screen) {
                        withAnimation(.easeOut(duration: 0.2)) { showTour = false }
                        seen = true
                    }
                    .zIndex(90)
                }
            }
            .onAppear {
                guard !seen else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !seen { withAnimation(.easeOut(duration: 0.25)) { showTour = true } }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tcShowGuide)) { note in
                guard (note.object as? String) == screen.rawValue else { return }
                withAnimation(.easeOut(duration: 0.2)) { showTour = true }
            }
    }
}

extension View {
    /// Attach the page guide: auto-shows once on first visit, re-openable from the floating
    /// ⓘ button (or a manually placed TCGuideButton with `showButton: false`).
    func tcGuide(_ screen: GuideScreen, showButton: Bool = true, buttonBottomPadding: CGFloat = 104) -> some View {
        modifier(TCGuideModifier(screen: screen, showButton: showButton, buttonBottomPadding: buttonBottomPadding))
    }
}

/// A guide trigger for custom placement (toolbars, pill rows). The screen's `.tcGuide`
/// host presents the actual tour — this only posts the request.
struct TCGuideButton: View {
    let screen: GuideScreen
    var size: CGFloat = 16

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .tcShowGuide, object: screen.rawValue)
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page guide")
    }
}

// MARK: - Element-level info mark

private struct CompactPopoverIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCompactAdaptation(.popover)
        } else {
            content.presentationDetents([.medium])
        }
    }
}

/// Small “?” next to a single control or stat; tapping it pops a short description.
struct TCInfoMark: View {
    let title: String
    let text: String
    var tint: Color = TCTheme.textMuted
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) info")
        .popover(isPresented: $showing, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TCTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: 300, alignment: .topLeading)
            // Deployment target is iOS 16.0; true anchored popovers need 16.4+. On 16.0–16.3
            // this presents as a sheet, which reads fine — medium detent keeps it compact.
            .modifier(CompactPopoverIfAvailable())
        }
    }
}
