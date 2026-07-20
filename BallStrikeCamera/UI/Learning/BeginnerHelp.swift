import SwiftUI

// MARK: - Learning defaults (local persistence keys)

/// Local, offline-friendly state for beginner help + the guided tutorial. Kept
/// separate from the server-gated intro slides (profiles.onboarding_completed)
/// so toggling help never touches the network and works before login sync.
enum TCLearning {
    static let beginnerHelpKey    = "tc.beginnerHelp"
    static let tutorialDoneKey    = "tc.tutorialCompleted"

    /// True unless the user has explicitly turned beginner help off.
    static var beginnerHelpEnabled: Bool {
        UserDefaults.standard.object(forKey: beginnerHelpKey) as? Bool ?? true
    }

    /// Per-screen "seen" key for one-time contextual coach marks.
    static func coachKey(_ id: String) -> String { "tc.coach.\(id)" }
}

// MARK: - Glossary

/// One plain-English explanation of a golf / launch-monitor term.
struct GlossaryEntry: Identifiable {
    let id: String            // stable key, e.g. "smash_factor"
    let term: String          // display name, e.g. "Smash Factor"
    let definition: String
    let example: String?      // optional quick, concrete example

    static func entry(_ id: String) -> GlossaryEntry? { catalog[id] }

    /// Curated set — the terms that actually trip up beginners. Add freely.
    static let catalog: [String: GlossaryEntry] = {
        let entries: [GlossaryEntry] = [
            GlossaryEntry(id: "ball_speed", term: "Ball Speed",
                definition: "How fast the ball leaves the clubface right after impact, in miles per hour. It's the single biggest driver of how far the ball goes.",
                example: "A typical amateur driver ball speed is around 130-150 mph."),
            GlossaryEntry(id: "club_speed", term: "Club Speed",
                definition: "How fast the clubhead is moving through impact, in miles per hour. More club speed is potential distance, but only if you strike it well.",
                example: "Tour pros swing a driver around 113 mph; many amateurs are 85-100 mph."),
            GlossaryEntry(id: "smash_factor", term: "Smash Factor",
                definition: "Ball speed divided by club speed. It measures how cleanly you caught the ball, i.e. how much of your speed became ball speed.",
                example: "1.50 is about the max with a driver. Lower means an off-centre or thin strike."),
            GlossaryEntry(id: "launch_angle", term: "Launch Angle (VLA)",
                definition: "The vertical angle the ball takes off at, measured up from the ground in degrees. Together with spin it sets how high and far the ball flies.",
                example: "A driver often launches 12-16 degrees; a wedge much higher."),
            GlossaryEntry(id: "vla", term: "VLA",
                definition: "Vertical Launch Angle: how steeply upward the ball leaves the ground, in degrees. Higher VLA means a higher flight.",
                example: "Driver ~14 degrees, 7-iron ~18 degrees, wedge 30 degrees or more."),
            GlossaryEntry(id: "hla", term: "HLA",
                definition: "Horizontal Launch Angle: the left/right direction the ball starts on, in degrees. Negative is left, positive is right (for a right-hander).",
                example: "0 degrees means the ball starts dead straight at your target line."),
            GlossaryEntry(id: "spin_rate", term: "Spin Rate",
                definition: "How fast the ball is spinning backward, in revolutions per minute. Spin holds the ball in the air; too much costs distance, too little drops it early.",
                example: "Driver ~2,500 rpm is efficient; wedges spin 8,000+ rpm to stop on the green."),
            GlossaryEntry(id: "carry", term: "Carry",
                definition: "How far the ball flies through the air before it first lands, in yards. This is the number that matters for carrying a hazard or reaching a green.",
                example: "\"My 7-iron carries 155\" means it lands 155 yards away before any roll."),
            GlossaryEntry(id: "total", term: "Total Distance",
                definition: "Carry plus rollout: how far the ball ends up from where you hit it, including the roll after it lands.",
                example: "A drive that carries 240 and rolls 20 has a total of 260 yards."),
            GlossaryEntry(id: "apex", term: "Apex",
                definition: "The highest point of the ball's flight, measured in feet or yards. Higher apex usually means a softer landing.",
                example: "A well-struck 7-iron might peak around 90 feet."),
            GlossaryEntry(id: "dispersion", term: "Dispersion",
                definition: "How spread out your shots are left-to-right (and short-to-long) with a given club. Tighter dispersion means more predictable, reliable shots.",
                example: "The oval on your shot chart shows where most of your shots land."),
            GlossaryEntry(id: "nfc_tag", term: "NFC Club Tag",
                definition: "A small sticker on your club that your iPhone can read with a tap. Tap it before a shot and the shot is logged to that club automatically.",
                example: "Tap your 7-iron tag, hit a shot, and it files under \"7 Iron\" with no menus."),
            GlossaryEntry(id: "gapping", term: "Gapping",
                definition: "The yardage difference between your clubs. Good gapping means consistent distance steps so you always have the right club for a number.",
                example: "If your 7-iron carries 150 and 8-iron 140, your gap there is 10 yards."),
            GlossaryEntry(id: "range_mode", term: "Range Mode",
                definition: "Practice mode. Set your phone on a tripod beside the ball and hit shots to see full launch-monitor numbers and build your gapping.",
                example: nil),
            GlossaryEntry(id: "sim_mode", term: "Sim Mode",
                definition: "Streams your shots live to the True Carry web simulator so you can play virtual courses from your phone's data.",
                example: nil),
            GlossaryEntry(id: "course_mode", term: "Course Mode",
                definition: "Play a real course with GPS, per-hole scoring, and your tracked shots saved to the round.",
                example: nil),
            GlossaryEntry(id: "handicap", term: "Handicap",
                definition: "A number that estimates your scoring ability so players of different levels can compete fairly. Lower is better.",
                example: "A 10 handicap shoots roughly 10 over the course rating on a good day."),
            GlossaryEntry(id: "face_angle", term: "Face Angle",
                definition: "Which way the clubface points at impact relative to the target, in degrees. Open points right, closed points left (for a right-hander). It's the main thing that starts the ball offline.",
                example: "A face 2 degrees open at impact starts the ball slightly right."),
            GlossaryEntry(id: "club_path", term: "Club Path",
                definition: "The left/right direction the clubhead is travelling through impact, in degrees. The gap between path and face angle is what curves the ball.",
                example: "An in-to-out path with a square face tends to draw the ball."),
        ]
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }()
}

// MARK: - Info mark

/// A small tappable "?" that reveals a plain-English definition. Renders nothing
/// when beginner help is off, so advanced users get a clean UI.
struct InfoMark: View {
    let entryID: String
    var size: CGFloat = 13

    @AppStorage(TCLearning.beginnerHelpKey) private var beginnerHelp = true
    @State private var showing = false

    init(_ entryID: String, size: CGFloat = 13) {
        self.entryID = entryID
        self.size = size
    }

    var body: some View {
        if beginnerHelp, let entry = GlossaryEntry.entry(entryID) {
            Button { showing = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(TCTheme.gold.opacity(0.85))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What is \(entry.term)?")
            .sheet(isPresented: $showing) {
                GlossaryCardView(entry: entry)
                    .presentationDetents([.height(300), .medium])
                    .presentationDragIndicator(.visible)
                    .tcAppearance()
            }
        }
    }
}

// MARK: - Glossary card

/// The definition sheet shown when an InfoMark is tapped.
struct GlossaryCardView: View {
    let entry: GlossaryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TCTheme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(TCTheme.gold)
                        Text(entry.term)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundColor(TCTheme.textPrimary)
                        Spacer(minLength: 0)
                    }

                    Text(entry.definition)
                        .font(.system(size: 15))
                        .foregroundColor(TCTheme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if let example = entry.example {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EXAMPLE")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.0)
                                .foregroundColor(TCTheme.gold)
                            Text(example)
                                .font(.system(size: 14))
                                .foregroundColor(TCTheme.textMuted)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(TCTheme.panelRaised.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - First-time contextual hint

/// A one-time, dismissible hint card pinned to the top of a screen. Used for the
/// state-dependent tutorial beats (camera setup, reading your first result) that
/// can't be driven by the linear tour. Shows once per id, only when beginner
/// help is on.
struct FirstTimeHint: View {
    let id: String
    let icon: String
    let text: String

    @AppStorage(TCLearning.beginnerHelpKey) private var beginnerHelp = true
    @State private var dismissed = false
    @State private var seen: Bool

    init(id: String, icon: String, text: String) {
        self.id = id
        self.icon = icon
        self.text = text
        _seen = State(initialValue: UserDefaults.standard.bool(forKey: TCLearning.coachKey(id)))
    }

    var body: some View {
        if beginnerHelp && !seen && !dismissed {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
                    .padding(.top, 1)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TCTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    markSeen()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TCTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(TCTheme.borderGold, lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func markSeen() {
        UserDefaults.standard.set(true, forKey: TCLearning.coachKey(id))
        withAnimation(.easeInOut(duration: 0.25)) { dismissed = true }
    }
}

extension View {
    /// Overlays a one-time beginner hint pinned to the top of the screen.
    func firstTimeHint(id: String, icon: String, text: String) -> some View {
        overlay(alignment: .top) {
            FirstTimeHint(id: id, icon: icon, text: text)
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
    }
}
