import SwiftUI

// MARK: - Learn hub persistence

extension TCLearning {
    /// Comma-joined ids of lessons the user has opened. Local-only, like the
    /// tutorial flags — reading progress never touches the network.
    static let learnReadKey = "tc.learn.read"

    static func lessonRead(_ id: String) -> Bool {
        readLessonIDs().contains(id)
    }

    static func markLessonRead(_ id: String) {
        var ids = readLessonIDs()
        guard !ids.contains(id) else { return }
        ids.insert(id)
        UserDefaults.standard.set(ids.sorted().joined(separator: ","), forKey: learnReadKey)
    }

    private static func readLessonIDs() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: learnReadKey) ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }
}

// MARK: - Lesson model

/// One short beginner lesson. All content is curated and lives in the app —
/// free for every tier, readable offline at the range.
struct LearnLesson: Identifiable {
    struct Section {
        let heading: String
        let body: String
    }

    let id: String
    let icon: String          // SF Symbol
    let title: String
    let minutes: Int
    let summary: String       // one line under the title in the list
    let sections: [Section]
    let glossaryIDs: [String] // chips at the bottom, open GlossaryCardView

    static let catalog: [LearnLesson] = [
        LearnLesson(
            id: "first_shot",
            icon: "figure.golf",
            title: "Reading your first shot",
            minutes: 2,
            summary: "What carry, total, and ball speed actually tell you",
            sections: [
                Section(heading: "Carry is the number that matters",
                        body: "Carry is how far the ball flies before it first lands. Total adds the roll after landing. When you pick a club to clear water or reach a green, you're asking about carry — roll depends on the ground, carry depends on you. Learn your carry numbers first."),
                Section(heading: "Ball speed is king",
                        body: "Of everything on the result screen, ball speed is the single biggest driver of distance. It's how fast the ball leaves the face. More swing speed helps, but only if you strike it well — which is what smash factor measures."),
                Section(heading: "Don't chase every number",
                        body: "One shot tells you almost nothing; ten shots tell you a lot. Look for your averages and your misses, not your single best. The Insights tab does this for you once a few shots are saved."),
            ],
            glossaryIDs: ["carry", "total", "ball_speed"]
        ),
        LearnLesson(
            id: "smash_factor",
            icon: "bolt.fill",
            title: "Smash factor: strike quality",
            minutes: 2,
            summary: "One number that says how cleanly you hit it",
            sections: [
                Section(heading: "What it is",
                        body: "Smash factor is ball speed divided by club speed — how much of your swing became ball flight. It's the purest measure of strike quality: swing speed is potential, smash factor is how much of it you cashed in."),
                Section(heading: "What's good",
                        body: "With a driver, 1.50 is about the physical ceiling; 1.44 and up is a well-struck drive. Irons run lower — around 1.33 to 1.38 for a 7-iron is solid. If your smash is low, the fix is contact, not swinging harder."),
                Section(heading: "How to use it",
                        body: "Hit five shots with the same club and watch smash factor instead of distance. A centered strike with a smooth swing will out-carry a hard swing off the heel every time. Strike first, speed second."),
            ],
            glossaryIDs: ["smash_factor", "ball_speed", "club_speed"]
        ),
        LearnLesson(
            id: "ball_curve",
            icon: "arrow.triangle.swap",
            title: "Why the ball curves",
            minutes: 3,
            summary: "Face vs path — the physics behind slices and draws",
            sections: [
                Section(heading: "Two numbers control everything",
                        body: "The face angle (where the clubface points at impact) mostly decides where the ball starts. The gap between face and club path (the direction the head is travelling) decides how it curves. Every slice, hook, draw, and fade comes from that pair."),
                Section(heading: "The classic slice",
                        body: "A slice is a face open to the path — usually a path swinging left with a face pointing less left. The ball starts near the face direction, then curves away. Closing the gap between face and path straightens the flight."),
                Section(heading: "Name your shot",
                        body: "Starts at target and curves gently right: a fade. Curves gently left: a draw. Starts right and stays right: a push. Starts left and stays left: a pull. Watch face-to-path on the result screen — under 2° of gap keeps curve playable."),
            ],
            glossaryIDs: ["face_angle", "club_path", "hla"]
        ),
        LearnLesson(
            id: "spin",
            icon: "arrow.clockwise",
            title: "Backspin & sidespin",
            minutes: 2,
            summary: "Spin keeps the ball in the air — and bends it",
            sections: [
                Section(heading: "Backspin is lift",
                        body: "Backspin makes the ball climb and hang in the air. Too little and shots fall out of the sky early; too much with a driver and the ball balloons up and lands short. Wedges want lots of spin — that's what stops the ball on a green."),
                Section(heading: "Ballpark numbers",
                        body: "A driver flies best around 2,000–3,000 rpm. A 7-iron sits near 6,000–7,000. Wedges run 8,000 and up. You don't need to memorize these — just know that driver spin should be low and wedge spin high."),
                Section(heading: "Sidespin bends the flight",
                        body: "Sidespin (tilted spin axis) is what actually curves the ball, and it comes from the face-to-path gap in the previous lesson. Big sidespin numbers mean a big gap — fix the face and path, and the spin fixes itself."),
            ],
            glossaryIDs: ["spin_rate", "face_angle", "club_path"]
        ),
        LearnLesson(
            id: "launch_angle",
            icon: "arrow.up.right",
            title: "Launch angle",
            minutes: 2,
            summary: "The takeoff window that maximizes carry",
            sections: [
                Section(heading: "The window",
                        body: "Launch angle (VLA) is how steeply the ball takes off. Each club has a happy window: a driver flies furthest launching around 12–16°, a 7-iron near 16–20°, wedges 25° and up. Inside the window, carry is easy; outside it, you leak distance."),
                Section(heading: "Low and high misses",
                        body: "Launching a driver too low (under 10°) usually means hitting down on it or too little loft — the ball never gets airborne long enough to carry. Launching too high with lots of spin balloons. High launch with LOW spin is the modern distance recipe."),
                Section(heading: "Launch and spin travel together",
                        body: "Read launch angle next to backspin. Low launch + high spin = the classic distance-killing drive. If both numbers drift the same direction shot after shot, that's a setup change (tee height, ball position), not a swing rebuild."),
            ],
            glossaryIDs: ["vla", "launch_angle", "spin_rate", "apex"]
        ),
        LearnLesson(
            id: "gapping",
            icon: "ruler",
            title: "Know your real distances",
            minutes: 2,
            summary: "Gapping — the fastest way to lower your scores",
            sections: [
                Section(heading: "Most amateurs don't know their numbers",
                        body: "Ask a mid-handicapper their 7-iron distance and they'll quote their best strike ever. Course decisions built on your best shot come up short all day. Your average carry is your real number — and it's usually 10+ yards less than you think."),
                Section(heading: "Build your gapping",
                        body: "Hit 8–10 shots with each club in Range mode and let the app average the carries. Good gapping means a steady step between clubs — around 10–15 yards. If two clubs carry the same distance, one of them is a wasted slot."),
                Section(heading: "Use carry, not total",
                        body: "Pick clubs by carry. The front bunker doesn't care how far the ball rolls after it lands in it. Once your gapping is saved, the Insights tab shows your ladder — that chart is worth more strokes than a new driver."),
            ],
            glossaryIDs: ["gapping", "carry", "dispersion"]
        ),
        LearnLesson(
            id: "clean_reading",
            icon: "camera.viewfinder",
            title: "Getting a clean reading",
            minutes: 2,
            summary: "Set up the camera so every shot tracks",
            sections: [
                Section(heading: "Position the phone",
                        body: "Put the phone on a tripod at ball height or slightly above, a few feet to the side of the ball, aimed across your target line. The ball and your impact zone should sit comfortably inside the frame — not at the edges."),
                Section(heading: "Light and background",
                        body: "The camera tracks a fast-moving white ball, so contrast is everything. Outdoors, avoid shooting straight into the sun. Indoors or in a garage, more light is always better, and a plain, darker background beats a cluttered one."),
                Section(heading: "Keep it still",
                        body: "Any camera wobble reads as ball movement. Use a tripod rather than leaning the phone on a bag, and let vibrations settle after you place it. If a shot fails to track, the review screen shows what the camera saw — check framing first."),
            ],
            glossaryIDs: ["range_mode", "nfc_tag"]
        ),
    ]
}

// MARK: - Learn hub (lesson list)

/// The lesson library. Free for every tier and fully offline — content is
/// curated in-app so it works at the range with no signal.
struct LearnHubView: View {
    // Bumped when a lesson view marks itself read so rows refresh their check.
    @State private var readRefresh = 0

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: TCTheme.sectionGap) {
                    Text("Short reads that teach you what your numbers mean. No jargon, two minutes each.")
                        .font(.system(size: 13))
                        .foregroundColor(TCTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        ForEach(LearnLesson.catalog) { lesson in
                            NavigationLink {
                                LearnLessonView(lesson: lesson) { readRefresh += 1 }
                            } label: {
                                lessonRow(lesson)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .id(readRefresh)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Learn the Basics")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
    }

    private func lessonRow(_ lesson: LearnLesson) -> some View {
        let read = TCLearning.lessonRead(lesson.id)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(TCTheme.gold.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: lesson.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                Text(lesson.summary)
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if read {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.sage)
                }
                Text("\(lesson.minutes) min")
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TCTheme.textUltraMuted)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TCTheme.border, lineWidth: 1))
    }
}

// MARK: - Lesson detail

struct LearnLessonView: View {
    let lesson: LearnLesson
    var onRead: () -> Void = {}

    @State private var glossaryEntry: GlossaryEntry?

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    ForEach(Array(lesson.sections.enumerated()), id: \.offset) { _, section in
                        sectionView(section)
                    }

                    if !glossaryChips.isEmpty {
                        termsRow
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 12)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.clear, for: .navigationBar)
        .sheet(item: $glossaryEntry) { entry in
            GlossaryCardView(entry: entry)
                .presentationDetents([.height(300), .medium])
                .presentationDragIndicator(.visible)
                .tcAppearance()
        }
        .onAppear {
            TCLearning.markLessonRead(lesson.id)
            onRead()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TCTheme.gold.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: lesson.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                }
                Text("\(lesson.minutes) MIN READ")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(TCTheme.textMuted)
            }
            Text(lesson.title)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionView(_ section: LearnLesson.Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.heading)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundColor(TCTheme.gold)
            Text(section.body)
                .font(.system(size: 14.5))
                .foregroundColor(TCTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
    }

    private var glossaryChips: [GlossaryEntry] {
        lesson.glossaryIDs.compactMap { GlossaryEntry.entry($0) }
    }

    private var termsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TERMS IN THIS LESSON")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundColor(TCTheme.textMuted)
            FlowChips(entries: glossaryChips) { glossaryEntry = $0 }
        }
        .padding(.top, 4)
    }
}

/// A simple wrapping row of tappable glossary term chips.
private struct FlowChips: View {
    let entries: [GlossaryEntry]
    let onTap: (GlossaryEntry) -> Void

    var body: some View {
        // The catalogs cap out at 3-4 chips, so a wrapping HStack via
        // LazyVGrid keeps this simple without a custom flow layout.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                Button { onTap(entry) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(entry.term)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(TCTheme.gold)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(TCTheme.gold.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(TCTheme.gold.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
