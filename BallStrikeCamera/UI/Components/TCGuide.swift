import SwiftUI

// MARK: - TrueCarry Guide
// One system for two jobs: (1) a per-screen click-through tour that auto-shows on first
// visit and can be re-opened anytime from a ⓘ button, and (2) element-level info marks
// (TCInfoMark) for single controls that deserve their own explanation.
// All copy lives in GuideCatalog so it can be edited in one place.

enum GuideScreen: String, CaseIterable {
    case home, insights, play, history, locker, range, coach, swingStudio
}

// MARK: - Golf profile (first-launch quiz answers; drives ALL guide copy)

struct GolfProfile: Codable, Equatable {
    enum Experience: String, Codable, CaseIterable {
        case neverHeld, justStarting, fewTimesAYear, playRegularly, seriousGolfer, plusHandicap

        var label: String {
            switch self {
            case .neverHeld: return "Never held a club"
            case .justStarting: return "Just starting out"
            case .fewTimesAYear: return "Play a few times a year"
            case .playRegularly: return "Play regularly"
            case .seriousGolfer: return "Serious golfer (single digits)"
            case .plusHandicap: return "Scratch or better"
            }
        }
        var blurb: String {
            switch self {
            case .neverHeld: return "Brand new — welcome to golf!"
            case .justStarting: return "Learning the basics"
            case .fewTimesAYear: return "Casual rounds and range trips"
            case .playRegularly: return "Weekly-ish golf"
            case .seriousGolfer: return "Working the handicap down"
            case .plusHandicap: return "Better than scratch"
            }
        }
    }

    enum Knowledge: String, Codable, CaseIterable {
        case ballData, launchMonitors, simulators, coursePlay

        var label: String {
            switch self {
            case .ballData: return "Ball data (speed, launch, spin)"
            case .launchMonitors: return "Launch monitors"
            case .simulators: return "Golf simulators (GSPro etc.)"
            case .coursePlay: return "Playing on a course"
            }
        }
    }

    var experience: Experience = .playRegularly
    var knowledge: Set<Knowledge> = []

    /// Never held / just starting: define EVERYTHING, steer to Coach first.
    var isNewToGolf: Bool { experience == .neverHeld || experience == .justStarting }
    /// Anything below regular play, or unfamiliar with ball data: keep terms defined.
    var wantsDefinitions: Bool { isNewToGolf || experience == .fewTimesAYear || !knowledge.contains(.ballData) }
    var knowsSims: Bool { knowledge.contains(.simulators) }
    var knowsMonitors: Bool { knowledge.contains(.launchMonitors) }

    private static let key = "tc_golf_profile_v1"
    static var current: GolfProfile? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GolfProfile.self, from: d)
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - Spotlight targets
// Tag any control with .tcGuideTarget("id"); tours whose step names that id get a
// punched-out highlight around the control with the rest of the screen darkened.

struct TCGuideTargetKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func tcGuideTarget(_ id: String) -> some View {
        anchorPreference(key: TCGuideTargetKey.self, value: .bounds) { [id: $0] }
    }
}

struct GuideStep {
    let icon: String
    let title: String
    let text: String
    /// Fully-defined variant for players still learning the vocabulary. nil = same text.
    var beginnerText: String? = nil
    /// Spotlight target id (see .tcGuideTarget). nil = centered card, no cutout.
    var target: String? = nil

    func resolvedText(_ p: GolfProfile?) -> String {
        (p?.wantsDefinitions ?? false) ? (beginnerText ?? text) : text
    }
}

enum GuideCatalog {
    /// Steps for a screen, tailored to the saved GolfProfile: players still learning the
    /// vocabulary get every term defined; brand-new golfers also get "start with Coach"
    /// steering prepended where it matters.
    static func steps(for screen: GuideScreen) -> [GuideStep] {
        var out = base[screen] ?? []
        let p = GolfProfile.current
        if p?.isNewToGolf == true {
            switch screen {
            case .play:
                out.insert(GuideStep(icon: "graduationcap.fill", title: "Start with Coach",
                                     text: "",
                                     beginnerText: "Since you're new to golf, tap Coach first. It teaches grip, stance, and your first swings step by step — you don't even need a ball. Everything else in the app gets easier once you've done the first two lessons."),
                           at: 0)
            case .range:
                out.insert(GuideStep(icon: "lightbulb.fill", title: "New to all this?",
                                     text: "",
                                     beginnerText: "Quick translations before you start: BALL SPEED is how fast the ball leaves the club. LAUNCH is the angle it takes off at. CARRY is how far it flies before touching the ground. That's most of the vocabulary you need — the app measures all of it for you."),
                           at: 0)
            default: break
            }
        }
        return out
    }

    static let base: [GuideScreen: [GuideStep]] = [
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
                      text: "Tap any club to see its carry, total, ball speed, launch and spin from every measured shot. The small number on each chip is how many shots are on record for it.",
                      beginnerText: "Each chip is one of your clubs. Tap it to see that club's numbers from every shot you've hit: CARRY (how far the ball flies in the air), TOTAL (flight plus bounce and roll), BALL SPEED, LAUNCH angle, and SPIN. The small number shows how many shots the app has measured with that club."),
            GuideStep(icon: "square.grid.2x2", title: "ALL view",
                      text: "Plots your whole bag on one chart so gaps and overlaps stand out. Every club keeps its own color — the key at the bottom maps colors to clubs."),
            GuideStep(icon: "ruler", title: "Bag gapping",
                      text: "Clubs sorted by average carry. Look for two clubs within a few yards of each other (doing the same job) or a hole bigger than ~15 yards (a distance you can't hit).",
                      beginnerText: "GAPPING means knowing how far each club goes, so you always know which one to pull. This chart sorts your clubs by distance. Two clubs going the same distance are doing the same job; a big empty gap between clubs is a distance you don't have an answer for yet."),
            GuideStep(icon: "scope", title: "Dispersion & consistency",
                      text: "Pro shows left/right spread and shot-to-shot repeatability per club — how tight your misses are, not just how far the average flies."),
            GuideStep(icon: "info.circle", title: "Where the data comes from",
                      text: "Every measured shot in Range, Course, and Sim modes feeds these charts automatically. More shots per club = steadier numbers."),
        ],
        .play: [
            GuideStep(icon: "figure.golf", title: "Range",
                      text: "The launch monitor. Set your phone on its tripod, place a ball, and every shot is measured (speed, launch, carry, spin) and saved to your history.",
                      beginnerText: "This is your practice mode. A LAUNCH MONITOR is a device that measures each shot — how fast the ball left (ball speed), the angle it took off at (launch), and how far it flew (carry). Your phone's camera does all of that here: stand it on the tripod beside your ball, and every swing gets measured and saved automatically."),
            GuideStep(icon: "map.fill", title: "Course",
                      text: "A GPS round with hole-by-hole scoring. Shots you capture with the camera are pinned to the hole you're playing automatically — the map view shows each shot where it happened.",
                      beginnerText: "For when you play on a real golf course. The app uses GPS to know which hole you're on, keeps your score hole by hole, and if you set your phone up to capture shots, it pins each one to the exact spot on the course map where you hit it."),
            GuideStep(icon: "tv.fill", title: "Simulator",
                      text: "Play GSPro or other sims using your phone as the launch monitor. Pair with the TrueCarry Bridge desktop app by scanning its QR code. Setup guides for each sim live on our website.",
                      beginnerText: "A golf SIMULATOR is a video game you play with real swings — you hit a real ball into a net, and your shot flies on the screen. True Carry is the measuring device: your phone watches the ball and sends the numbers to the sim on your computer. To connect one, you install our Bridge app on the computer and scan its QR code with your phone. Our website has a step-by-step setup guide for every supported sim."),
            GuideStep(icon: "arrow.uturn.left", title: "Resume round",
                      text: "An unfinished round shows at the top of this page — tap it to pick up exactly where you left off."),
            GuideStep(icon: "graduationcap.fill", title: "Coach",
                      text: "Guided lessons plus camera swing analysis that scores your tempo, balance, and body motion (Pro)."),
        ],
        .history: [
            GuideStep(icon: "number.square.fill", title: "Handicap index",
                      text: "Computed from your best round differentials. The dots on the bars mark which rounds are currently counted toward the index.",
                      beginnerText: "A HANDICAP is golf's measure of skill — lower is better, and it lets players of different levels compete fairly. The app computes yours automatically from your best rounds. The dots on the bars mark which rounds currently count toward it."),
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
                      text: "Place a ball in view. The phase pill goes Searching → Tracking → Ready as the camera finds and locks onto it. When it says Ready, swing away.",
                      beginnerText: "Put a ball on the ground where the camera can see it. Watch the little status pill: it goes Searching → Tracking → READY as the camera finds your ball. When it says Ready, you're clear to swing — the app does everything else."),
            GuideStep(icon: "timer", title: "Shutter buttons",
                      text: "Four shutter speeds — faster freezes the ball and club better but needs more light. The colored dot on each button grades it for the CURRENT light: green is clean, yellow works but adds grain, red will hurt tracking (too dark = murky frames, too bright = streak risk). The dot with the white ring is the recommended button."),
            GuideStep(icon: "dot.radiowaves.left.and.right", title: "The pills",
                      text: "Club sets which club the shot logs to. Count is shots this session. Simulate Shot runs a bundled sample through the full pipeline. Righty/Lefty flips the layout. Replay and Share Frames act on the last captured shot."),
            GuideStep(icon: "thermometer.sun.fill", title: "Heat",
                      text: "If the phone runs hot a yellow banner appears — heat causes dropped frames, which hurt speed accuracy. With no ball in view the screen also dims itself after ~30 seconds to stay cool; detection keeps running, so setting a ball (or tapping) wakes it."),
            GuideStep(icon: "chart.bar.doc.horizontal", title: "Results",
                      text: "After each shot you get ball speed, launch, carry, total, and spin. The side panel keeps the last shot's composite image and the bottom bar keeps its numbers."),
        ],
        .swingStudio: [
            GuideStep(icon: "iphone", title: "Set the phone up",
                      text: "Prop your phone upright — a tripod, a water bottle, anything stable. Then step back 8–10 feet until your WHOLE body is in the frame. The screen faces you so you can see yourself and every instruction."),
            GuideStep(icon: "figure.golf", title: "No club needed",
                      text: "The camera reads your BODY, not the club. Swing with a club or without one — practice swings in the living room count. Recording starts and stops by itself: get set, hold still for a second, then swing."),
            GuideStep(icon: "camera.metering.center.weighted", title: "Two views, auto-detected",
                      text: "Face the camera for the FACE-ON view (head movement, hip slide, balance). Turn so the camera looks down your target line for DOWN-THE-LINE (swing plane, takeaway path). The app detects which one you're using — the label at the top shows it."),
            GuideStep(icon: "play.rectangle.fill", title: "Instant replay",
                      text: "Right after each swing you get the replay with your skeleton drawn on it, phase-by-phase stills (address, top, impact, finish), your swing score, and the ONE thing to work on next."),
            GuideStep(icon: "clock.arrow.circlepath", title: "Everything is saved",
                      text: "Every analyzed swing lands in your History with all its numbers — tempo, hip slide, shoulder turn, balance — so you can watch them improve week over week."),
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
    /// Resolved spotlight frames from the host (target id -> rect in overlay space).
    var targetFrames: [String: CGRect] = [:]
    @State private var index = 0

    private var steps: [GuideStep] { GuideCatalog.steps(for: screen) }
    private let profile = GolfProfile.current

    private var cutout: CGRect? {
        guard let t = (steps.indices.contains(index) ? steps[index].target : nil) else { return nil }
        return targetFrames[t]
    }

    var body: some View {
        ZStack {
            // Dim everything; when the step names a target, punch a bright hole around it.
            SpotlightDimmer(cutout: cutout)
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

                    Text(step.resolvedText(profile))
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

/// Darkens the screen with an even-odd path so a rounded cutout stays bright, with a
/// gold ring drawing the eye to the highlighted control.
struct SpotlightDimmer: View {
    let cutout: CGRect?

    var body: some View {
        GeometryReader { geo in
            let full = CGRect(origin: .zero, size: geo.size)
            let hole = cutout.map { $0.insetBy(dx: -8, dy: -8) }
            Path { p in
                p.addRect(full)
                if let h = hole {
                    p.addRoundedRect(in: h, cornerSize: CGSize(width: 14, height: 14))
                }
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            if let h = hole {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TCTheme.gold, lineWidth: 2)
                    .frame(width: h.width, height: h.height)
                    .position(x: h.midX, y: h.midY)
                    .shadow(color: TCTheme.gold.opacity(0.5), radius: 8)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: cutout)
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
            .overlayPreferenceValue(TCGuideTargetKey.self) { anchors in
                if showTour {
                    GeometryReader { geo in
                        GuideOverlayView(screen: screen, onDone: {
                            withAnimation(.easeOut(duration: 0.2)) { showTour = false }
                            seen = true
                        }, targetFrames: anchors.mapValues { geo[$0] })
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

// MARK: - Welcome tour (first launch, on the app shell)
// Walks the whole app with REAL spotlights on the bottom-dock tabs (the rest of the
// screen dims; the highlighted tab stays bright inside a gold ring). Copy is tailored
// to the GolfProfile from the first-run quiz. Every slide can be skipped.

struct WelcomeSlide {
    let icon: String
    let title: String
    let whereChip: String?
    let target: String?
    let text: (GolfProfile?) -> String
}

enum WelcomeTourCatalog {
    static func slides() -> [WelcomeSlide] {
        let p = GolfProfile.current
        var out: [WelcomeSlide] = []

        out.append(WelcomeSlide(icon: "hand.wave.fill", title: "Quick tour?",
                                whereChip: nil, target: nil) { p in
            let base = "Two minutes, one page at a time — you can skip any step. "
            if p?.isNewToGolf == true {
                return base + "Since you're new to golf, watch for the Coach notes: that's where we'll teach you the game itself, not just the app."
            }
            return base + "We'll show you where everything lives and how the pieces fit together."
        })

        out.append(WelcomeSlide(icon: "house.fill", title: "Home",
                                whereChip: "Bottom bar · 1st tab", target: "dock.home") { p in
            p?.isNewToGolf == true
            ? "Your feed. Friends' shots and rounds show up here, and your weekly goals track themselves as you practice — finish them to unlock simulator courses. Nothing here needs golf knowledge; it fills in as you play."
            : "Activity feed, weekly goals (they self-track and unlock sim courses), and the round-in-progress banner if you leave a round mid-way."
        })

        out.append(WelcomeSlide(icon: "figure.golf", title: "Play — where everything happens",
                                whereChip: "Bottom bar · center tab", target: "dock.play") { p in
            if p?.isNewToGolf == true {
                return "The main tab. Inside you'll find RANGE (practice with your phone measuring every shot), SIMULATOR (hit into a net, play on a screen), COURSE (GPS scoring on a real course) — and COACH, which is where you should start: it teaches grip, stance, and your first swings from absolute zero."
            }
            var t = "Range (the launch monitor), Simulator, Course rounds, and Coach all live here."
            if p?.knowsSims != true {
                t += " For sims: install the True Carry Bridge app on your computer, scan its QR code with your phone, and the setup guide for each sim (GSPro and others) is on our website."
            } else {
                t += " Sim pairing is the QR flow via the True Carry Bridge desktop app — per-sim setup guides are on the website."
            }
            return t
        })

        out.append(WelcomeSlide(icon: "viewfinder", title: "The hitting screen",
                                whereChip: "Play → Range", target: nil) { p in
            p?.wantsDefinitions ?? false
            ? "Phone on the tripod beside your ball, screen facing you. Wait for the status pill to say READY, then swing. You'll get ball speed (how fast it left), launch (takeoff angle), carry (how far it flew), and spin — measured, not guessed. The four shutter buttons adapt to light: pick the one with the green dot."
            : "Set the phone, wait for READY, swing. Full launch numbers per shot; the shutter buttons are graded live for the current light — take the green-dot one."
        })

        out.append(WelcomeSlide(icon: "chart.bar.fill", title: "Insights",
                                whereChip: "Bottom bar", target: "dock.insights") { p in
            p?.wantsDefinitions ?? false
            ? "Every measured shot builds your personal charts: how far each club actually goes (that's called gapping), how tight your misses are, and how you're trending. It fills up automatically as you hit."
            : "Per-club distances, bag gapping, dispersion, and trends — fed automatically by every measured shot."
        })

        out.append(WelcomeSlide(icon: "clock.fill", title: "History",
                                whereChip: "Bottom bar", target: "dock.history") { p in
            p?.isNewToGolf == true
            ? "Every session, round, and swing you've recorded — with replays. Your handicap (golf's skill number — lower is better) computes itself here once you've played some rounds."
            : "Rounds, range sessions, swing analyses — with frame replays — plus your auto-computed handicap index."
        })

        out.append(WelcomeSlide(icon: "bag.fill", title: "Locker",
                                whereChip: "Bottom bar", target: "dock.locker") { p in
            p?.isNewToGolf == true
            ? "Your golf bag lives here — the clubs the whole app uses. Add the clubs you own (or the ones that came with a starter set) and the app learns how far YOU hit each one. Profile and settings are here too."
            : "Manage your bag (distances come from your own measured shots), saved shots, profile and settings."
        })

        out.append(WelcomeSlide(icon: p?.isNewToGolf == true ? "graduationcap.fill" : "checkmark.circle.fill",
                                title: p?.isNewToGolf == true ? "Start with Coach" : "You're set",
                                whereChip: p?.isNewToGolf == true ? "Play → Coach" : nil,
                                target: p?.isNewToGolf == true ? "dock.play" : nil) { p in
            if p?.isNewToGolf == true {
                return "Seriously — Coach first. Lesson one is holding the club; no ball needed, your camera coaches your body positions in real time. Each page also re-explains itself the first time you open it, and the ? button brings any guide back."
            }
            return "Each page walks you through itself the first time you open it, and the ? button on every screen brings the guide back anytime. Go hit something."
        })
        return out
    }
}

struct WelcomeTourView: View {
    let targetFrames: [String: CGRect]
    let onDone: () -> Void
    @State private var index = 0

    private let slides = WelcomeTourCatalog.slides()
    private var slide: WelcomeSlide { slides[min(index, slides.count - 1)] }
    private var cutout: CGRect? { slide.target.flatMap { targetFrames[$0] } }

    var body: some View {
        ZStack {
            SpotlightDimmer(cutout: cutout)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(TCTheme.gold.opacity(0.14)).frame(width: 54, height: 54)
                    Image(systemName: slide.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                }
                Text(slide.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if let chip = slide.whereChip {
                    Text(chip)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.gold)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(TCTheme.gold.opacity(0.12)))
                }
                Text(slide.text(GolfProfile.current))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TCTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForEach(slides.indices, id: \.self) { i in
                        Circle().fill(i == index ? TCTheme.gold : TCTheme.border)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    Button(action: onDone) {
                        Text("Skip tour")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TCTheme.textMuted)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Button {
                        if index < slides.count - 1 {
                            withAnimation(.easeInOut(duration: 0.18)) { index += 1 }
                        } else { onDone() }
                    } label: {
                        Text(index < slides.count - 1 ? "Next" : "Done")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.05, green: 0.09, blue: 0.07))
                            .padding(.horizontal, 26).padding(.vertical, 10)
                            .background(Capsule().fill(TCTheme.gold))
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
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(TCTheme.border, lineWidth: 1))
            )
            .padding(.horizontal, 28)
            // keep the card clear of a bottom-dock cutout
            .offset(y: cutout != nil ? -60 : 0)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}

/// Mounts the welcome tour on the app shell: fires once (after the first-run quiz sets
/// the pending flag), spotlights real dock tabs via their .tcGuideTarget anchors.
struct WelcomeTourHost: ViewModifier {
    @AppStorage("tc_welcome_tour_done_v1") private var done = true
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TCGuideTargetKey.self) { anchors in
                if show {
                    GeometryReader { geo in
                        WelcomeTourView(targetFrames: anchors.mapValues { geo[$0] }) {
                            withAnimation(.easeOut(duration: 0.2)) { show = false }
                            done = true
                        }
                    }
                    .zIndex(200)
                }
            }
            .onAppear {
                guard !done else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    if !done { withAnimation(.easeOut(duration: 0.25)) { show = true } }
                }
            }
    }
}

extension View {
    func tcWelcomeTour() -> some View { modifier(WelcomeTourHost()) }
}
