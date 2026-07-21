import SwiftUI
import Charts

// MARK: - TrueCarry Coach: Lessons home (Play → Lessons)

struct LessonsHomeView: View {
    @EnvironmentObject var session: AuthSessionStore
    @ObservedObject private var library = LessonLibrary.shared

    @State private var showIntake = false
    @State private var activeLesson: Lesson?
    @State private var showFreeAnalysis = false
    @State private var showUpgrade = false
    @State private var recentShots: [SavedShot] = []
    @State private var practiceTrack: LessonTrack?
    @State private var completedUnitTitle: String?
    @State private var selectedRead: CoachSuggestion?
    @State private var fixTrackSheet: LessonTrack?
    @State private var showFlightLab = false
    @State private var labPreset: LabPreset? = nil
    @State private var showDrillLibrary = false

    private var isPro: Bool { !session.entitlementVM.isFreeTier }

    /// Pro is checked when the user tries to DO something — browsing the path is free.
    private func requirePro() -> Bool {
        if isPro { return true }
        showUpgrade = true
        return false
    }

    /// Always-on-screen action: full swing analysis at any time, from anywhere on the path.
    private var analyzeFAB: some View {
        Button {
            // Free tier gets ONE analyzed swing a week — the taste that sells the rest.
            if isPro || library.freeSwingAvailable { showFreeAnalysis = true }
            else { showUpgrade = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.80, green: 0.69, blue: 0.48))
                Text("Analyze My Swing")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.93, green: 0.89, blue: 0.82))
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Color(red: 0.17, green: 0.30, blue: 0.20),
                                            Color(red: 0.09, green: 0.16, blue: 0.11)],
                                   startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().strokeBorder(Color(red: 0.72, green: 0.60, blue: 0.37).opacity(0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 88)   // clears the tab dock
    }

    /// Compact dismissible coach popup — top read, tap for the evidence deep-dive.
    @State private var hideReadPopup = false
    @ViewBuilder
    private var readPopup: some View {
        let reads = CoachAdvisor.suggestions(model: library.playerModel,
                                             shots: recentShots, library: library)
        if let top = reads.first, !hideReadPopup {
            HStack(spacing: 10) {
                Image(systemName: top.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(top.priority > 0 ? TCTheme.gold : Self.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text("COACH SAYS")
                        .font(.system(size: 8.5, weight: .black))
                        .foregroundColor(TCTheme.textUltraMuted).tracking(1.2)
                    Text(top.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(2)
                }
                Spacer()
                Button { withAnimation { hideReadPopup = true } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.textUltraMuted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(TCTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder((top.priority > 0 ? TCTheme.gold : Self.accent).opacity(0.5), lineWidth: 1.4))
            .contentShape(Rectangle())
            .onTapGesture { selectedRead = top }
        }
    }

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    // The roadmap IS the screen — always visible for everyone who opens
                    // Coach. Pro is enforced when STARTING a lesson/analysis, not for looking.
                    statsBar
                    goalBanner
                    firstSessionHero
                    rustCard
                    refresherCard
                    if !library.hasCompletedIntake { intakeBanner }
                    readPopup
                    roadmapSection
                    graduationCard
                    flightLabCard
                    drillLibraryCard
                    coachReadSection
                    weaknessSection
                    recentSwingsSection
                    Spacer(minLength: 140)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 12)
            }
        }
        .overlay(alignment: .bottom) { analyzeFAB }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbar {
            if isPro && library.hasCompletedIntake {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showIntake = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TCTheme.textMuted)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                TCGuideButton(screen: .coach, size: 14)
            }
        }
        .onAppear {
            if let uid = session.currentUser?.id { library.activate(userId: uid) }
        }
        .task {
            // Ball-flight knowledge for the Coach's Read: recent launch-monitor shots.
            if let uid = session.currentUser?.id {
                recentShots = ((try? await session.backend.loadShots(userId: uid)) ?? [])
                    .sorted { $0.timestamp < $1.timestamp }
            }
        }
        .sheet(isPresented: $showIntake) {
            LessonIntakeView(existing: library.profile) { profile in
                library.saveProfile(profile)
                showIntake = false
            }
            .tcAppearance()
        }
        .fullScreenCover(item: $activeLesson) { lesson in
            LessonPlayerView(lesson: lesson) { activeLesson = nil }
                .tcAppearance()
        }
        .fullScreenCover(isPresented: $showFreeAnalysis) {
            SwingStudioView(lessonId: nil, requiredSwings: 1) { showFreeAnalysis = false }
                .tcAppearance()
        }
        // Free for everyone — it's teaching material, not coaching.
        .fullScreenCover(isPresented: $showFlightLab) {
            CoachLabView(onDone: { showFlightLab = false; labPreset = nil },
                         initialPreset: labPreset)
                .tcAppearance()
        }
        .sheet(isPresented: $showDrillLibrary) {
            DrillLibrarySheet(faults: library.faults) { lessonId in
                showDrillLibrary = false
                if let lesson = library.lesson(lessonId), requirePro() { activeLesson = lesson }
            }
            .tcAppearance()
        }
        .tcGuide(.coach, showButton: false)
        .sheet(item: $selectedRead) { read in
            CoachReadDetailView(read: read, shots: recentShots) { lessonId in
                selectedRead = nil
                if let lesson = library.lesson(lessonId) { activeLesson = lesson }
            }
            .tcAppearance()
        }
        .sheet(item: $fixTrackSheet) { track in
            FixTrackSheet(track: track) { lesson in
                fixTrackSheet = nil
                activeLesson = lesson
            }
            .tcAppearance()
        }
        .fullScreenCover(item: $practiceTrack) { track in
            // Practice node: two reps focused on this unit's metrics, no lesson gating.
            SwingStudioView(lessonId: "practice.\(track.id)", requiredSwings: 2) {
                practiceTrack = nil
            }
            .tcAppearance()
        }
        .alert("Unit complete! \u{1F3C6}", isPresented: Binding(
            get: { completedUnitTitle != nil },
            set: { if !$0 { completedUnitTitle = nil } }
        )) {
            Button("Keep going") { completedUnitTitle = nil }
        } message: {
            Text("You've finished every lesson in \(completedUnitTitle ?? "this unit") — the next unit is open.")
        }
        .alert("TrueCarry Coach is a Pro feature", isPresented: $showUpgrade) {
            Button("Upgrade") { UIApplication.shared.open(session.entitlementVM.upgradeURL) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Free includes one analyzed swing each week. Pro unlocks unlimited analysis, the full lesson library, and your personal coaching plan.")
        }
    }

    // MARK: Coaching-arc cards (goal, first session, rust, re-checks, graduation)

    /// The one outcome everything anchors to, always visible.
    @ViewBuilder
    private var goalBanner: some View {
        if let goal = library.profile?.primaryGoal {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.gold)
                Text("GOAL: \(goal.displayName.uppercased())")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(TCTheme.textPrimary).tracking(1.0)
                Spacer()
                Text("Everything below is ordered around it")
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Capsule().fill(TCTheme.gold.opacity(0.10)))
            .overlay(Capsule().strokeBorder(TCTheme.borderGold, lineWidth: 1))
        }
    }

    /// Day one: no menus — one button that walks a brand-new player into lesson one.
    @ViewBuilder
    private var firstSessionHero: some View {
        if library.swings.isEmpty, library.completedLessonCount == 0,
           let first = library.coreTracks.first?.lessons.first {
            Button {
                if requirePro() { activeLesson = first }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR FIRST SESSION")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white.opacity(0.85)).tracking(1.4)
                    Text("Coach walks you through everything — 10 minutes, no experience needed.")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Start: \(first.title)", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.40, blue: 0.26),
                                                  Color(red: 0.11, green: 0.22, blue: 0.14)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
        }
    }

    /// 10+ idle days: warm back up with the LAST thing you worked on, not new material.
    @ViewBuilder
    private var rustCard: some View {
        if let days = library.daysSinceLastWork, days >= 10,
           let lesson = library.lastWorkedLesson {
            Button {
                if requirePro() { activeLesson = lesson }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Self.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Been \(days) days — knock the rust off")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("Quick refresher of \(lesson.title) before anything new")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TCTheme.textUltraMuted)
                }
                .tcCard(padding: 12)
            }
            .buttonStyle(.plain)
        }
    }

    /// Spaced re-check: a passed skill drifted out of band — coaches circle back.
    @ViewBuilder
    private var refresherCard: some View {
        if let lesson = library.regressedLessons.first {
            Button {
                if requirePro() { activeLesson = lesson }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(TCTheme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(lesson.title) is slipping")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("You passed this — recent swings say it needs a revisit")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TCTheme.textUltraMuted)
                }
                .tcCard(padding: 12)
            }
            .buttonStyle(.plain)
        }
    }

    /// Body unit passed → measurable BALL goal on the range. Closes the body→ball loop.
    @ViewBuilder
    private var graduationCard: some View {
        if let track = library.coreTracks.last(where: { trackCompleted($0) }),
           let goal = library.rangeGoal(for: track) {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(track.title) passed — take it to the range", systemImage: "flag.checkered")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(goal)
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The launch monitor grades it — hit Play → Range when you're out there.")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tcCard(padding: 14)
        }
    }

    /// Standalone drill library — for the player who knows what they want to work on.
    private var drillLibraryCard: some View {
        Button { showDrillLibrary = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Self.accent.opacity(0.16))
                        .frame(width: 46, height: 46)
                    Image(systemName: "list.star")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Self.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drill Library")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Every drill, searchable — feel → drill → constraint ladders")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: Ball Flight Lab entry

    /// Interactive physics diagrams (CoachLabView) — animated explanations instead of
    /// videos. Free for all tiers.
    private var flightLabCard: some View {
        Button { showFlightLab = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TCTheme.sage.opacity(0.16))
                        .frame(width: 46, height: 46)
                    Image(systemName: "atom")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(TCTheme.sage)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ball Flight Lab")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Drag face, path, launch & strike — watch the flight explain itself")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .fill(TCTheme.panel)
                    .overlay(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                        .stroke(TCTheme.borderSage, lineWidth: 1.2))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var intakeBanner: some View {
        Button { showIntake = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personalize your path")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("5 quick questions reorder these units around YOUR game")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Coach's Read (pose faults × measured ball data)

    @ViewBuilder
    private var coachReadSection: some View {
        let reads = CoachAdvisor.suggestions(model: library.playerModel,
                                             shots: recentShots, library: library)
        if !reads.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                TCSectionHeader(title: "Coach's Read")
                ForEach(reads.prefix(2)) { read in
                    Button {
                        selectedRead = read
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill((read.priority > 0 ? TCTheme.gold : Self.accent).opacity(0.16))
                                    .frame(width: 38, height: 38)
                                Image(systemName: read.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(read.priority > 0 ? TCTheme.gold : Self.accent)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(read.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(TCTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Text(read.detail)
                                    .font(.system(size: 12))
                                    .foregroundColor(TCTheme.textMuted)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if read.lessonId != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(TCTheme.textUltraMuted)
                                    .padding(.top, 10)
                            }
                        }
                        .tcCard(padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Weaknesses

    @ViewBuilder
    private var weaknessSection: some View {
        let faults = library.playerModel.persistentFaults.compactMap { library.fault($0) }
        if !faults.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                TCSectionHeader(title: "Working On")
                ForEach(faults.prefix(3)) { fault in
                    Button {
                        if let id = fault.lessonId, let lesson = library.lesson(id) {
                            activeLesson = lesson
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(TCTheme.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fault.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(TCTheme.textPrimary)
                                Text(fault.drill)
                                    .font(.system(size: 11))
                                    .foregroundColor(TCTheme.textMuted)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if let preset = Self.labPreset(for: fault) {
                                Button {
                                    labPreset = preset
                                    showFlightLab = true
                                } label: {
                                    Image(systemName: "atom")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(TCTheme.sage)
                                        .frame(width: 30, height: 30)
                                        .background(Circle().fill(TCTheme.sage.opacity(0.14)))
                                }
                                .buttonStyle(.plain)
                            }
                            if fault.lessonId != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(TCTheme.textUltraMuted)
                            }
                        }
                        .padding(12)
                        .background(TCTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(TCTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Progress stats (top of the path)

    private var statsBar: some View {
        let scores = library.playerModel.lastScores.suffix(5)
        let avg = scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
        return HStack(spacing: 8) {
            statTile("\(library.completedLessonCount)", "LESSONS", "checkmark.seal.fill", TCTheme.gold)
            statTile("\(library.swings.filter(\.analyzed).count)", "SWINGS", "video.fill", Self.accent)
            statTile(avg.map { "\($0)" } ?? "—",
                     avg == nil ? "NO SCORES YET" : "AVG SCORE",
                     "chart.line.uptrend.xyaxis", TCTheme.sage)
        }
    }

    /// One stat = one tile: tinted icon chip, big number, label — all in theme ink so it
    /// reads in BOTH modes (the old bar hardcoded white text onto a white light-mode card).
    private func statTile(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
            }
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TCTheme.panel)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(TCTheme.borderMedium, lineWidth: 1))
        )
    }

    /// Coach's action accent — TrueCarry forest green, solid enough to carry white
    /// content in BOTH modes (unlike TCTheme.cyan, which flips to light bone in dark).
    static let accent = Color(red: 0.24, green: 0.42, blue: 0.28)

    // MARK: Roadmap (Duolingo-style winding path of nodes)

    private enum RoadNode: Identifiable {
        case lesson(Lesson)
        case practice(LessonTrack)
        case checkpoint(LessonTrack)
        var id: String {
            switch self {
            case .lesson(let l):     return l.id
            case .practice(let t):   return "practice.\(t.id)"
            case .checkpoint(let t): return "checkpoint.\(t.id)"
            }
        }
    }

    /// A unit = one track's lessons, with a practice node mid-unit and a trophy checkpoint
    /// at the end — the "more along the way" beats between lessons.
    private func nodes(for track: LessonTrack) -> [RoadNode] {
        var out: [RoadNode] = []
        for (i, lesson) in track.lessons.enumerated() {
            out.append(.lesson(lesson))
            // Drop a practice rep station after every 2nd lesson (needs swing metrics to matter).
            if i == 1 && track.lessons.count > 2 { out.append(.practice(track)) }
        }
        out.append(.checkpoint(track))
        return out
    }

    private func trackCompleted(_ track: LessonTrack) -> Bool {
        track.lessons.allSatisfy {
            let s = library.status(of: $0)
            return s == .completed || s == .mastered
        }
    }

    /// The single node the START bubble points at.
    private var currentNodeId: String? {
        library.nextLesson?.id
    }

    private var roadmapSection: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR PATH")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(TCTheme.textMuted).tracking(1.6)
                Text("Top to bottom, one node at a time — passing a lesson opens the next. Gold = up next, green = passed.")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textUltraMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(library.coreTracks.enumerated()), id: \.element.id) { unitIndex, track in
                VStack(spacing: 0) {
                    unitBanner(track, number: unitIndex + 1)
                    roadPath(track)
                }
                if unitIndex == 0 { fixTracksSection }
            }
        }
    }

    // MARK: Fix My Game (off-path, personal problem tracks — clickable cards)

    /// Which fix track the player's OWN data points at (measured ball curve first,
    /// then camera faults) — that card wears the RECOMMENDED badge.
    private var recommendedFixId: String? {
        let recent = recentShots.suffix(30).filter { !$0.isBadShot && $0.metrics.ballSpeedMph > 0 }
        if recent.count >= 5 {
            let axis = recent.map { $0.metrics.spinAxisDegrees }.reduce(0, +) / Double(recent.count)
            if axis > 4 { return "slice" }
            if axis < -4 { return "hook" }
        }
        let faults = library.playerModel.persistentFaults
        if faults.contains("steep_delivery") { return "slice" }
        if faults.contains("shallow_delivery") { return "hook" }
        return nil
    }

    @ViewBuilder
    private var fixTracksSection: some View {
        let fixes = library.fixTracks
        if !fixes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("FIX MY GAME")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(TCTheme.textMuted)
                    .tracking(1.6)
                Text("Side quests — jump in whenever your ball flight asks for one.")
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textUltraMuted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(fixes) { track in
                            fixCard(track)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func fixCard(_ track: LessonTrack) -> some View {
        let done = track.lessons.filter {
            let st = library.status(of: $0); return st == .completed || st == .mastered
        }.count
        let recommended = track.id == recommendedFixId
        return Button {
            if requirePro() { fixTrackSheet = track }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: track.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if recommended {
                        Text("FOR YOU")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(Color(red: 0.35, green: 0.27, blue: 0.10))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white))
                    }
                }
                Spacer(minLength: 2)
                Text(track.title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                Text("\(done)/\(track.lessons.count) lessons")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(14)
            .frame(width: 170, height: 120, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: track.id == "slice"
                            ? [Color(red: 0.78, green: 0.58, blue: 0.22), Color(red: 0.55, green: 0.40, blue: 0.14)]
                            : [Color(red: 0.26, green: 0.44, blue: 0.30), Color(red: 0.13, green: 0.26, blue: 0.16)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(recommended ? Color.white.opacity(0.8) : Color.white.opacity(0.15),
                              lineWidth: recommended ? 2 : 1))
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func unitBanner(_ track: LessonTrack, number: Int) -> some View {
        let done = track.lessons.filter {
            let s = library.status(of: $0); return s == .completed || s == .mastered
        }.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("UNIT \(number)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(1.5)
                Text(track.title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(track.subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
            }
            Spacer()
            ZStack {
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 4).frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: CGFloat(done) / CGFloat(max(track.lessons.count, 1)))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                Text("\(done)/\(track.lessons.count)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(trackCompleted(track)
                      ? LinearGradient(colors: [Color(red: 0.30, green: 0.60, blue: 0.30), Color(red: 0.18, green: 0.44, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                      : unitGradient(number))
        )
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
    }

    /// Each unit gets its own vivid identity color, Duolingo-section style.
    private func unitGradient(_ number: Int) -> LinearGradient {
        // Brand family only: marker gold, carry forest, aged bronze, fairway moss.
        let palettes: [[Color]] = [
            [Color(red: 0.80, green: 0.62, blue: 0.24), Color(red: 0.58, green: 0.43, blue: 0.15)],  // marker gold
            [Color(red: 0.24, green: 0.42, blue: 0.28), Color(red: 0.12, green: 0.24, blue: 0.15)],  // carry forest
            [Color(red: 0.62, green: 0.48, blue: 0.28), Color(red: 0.42, green: 0.32, blue: 0.18)],  // aged bronze
            [Color(red: 0.36, green: 0.48, blue: 0.34), Color(red: 0.20, green: 0.30, blue: 0.20)],  // fairway moss
        ]
        let p = palettes[(number - 1) % palettes.count]
        return LinearGradient(colors: p, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The winding node path: fixed row height so the dotted connector is a simple
    /// point-to-point Canvas behind staggered circles.
    private func roadPath(_ track: LessonTrack) -> some View {
        let nodeList = nodes(for: track)
        // Taller rows so the 78px halo + label + caption never spill into the next node,
        // and a gentler horizontal swing so the (up to 130px) labels can't collide with a
        // neighbouring node's circle. Previously 96px rows + ±96 offsets overlapped.
        let rowH: CGFloat = 164
        let offsets: [CGFloat] = [0, -54, -76, -54, 0, 54, 76, 54]
        func xOffset(_ i: Int) -> CGFloat { offsets[i % offsets.count] }

        // How far down this unit the player has actually gotten — the connector is
        // SOLID SAGE up to there and dashed beyond, so progress reads at a glance.
        let doneCount: Int = {
            var n = 0
            for node in nodeList {
                if case .lesson(let l) = node {
                    let st = library.status(of: l)
                    if st == .completed || st == .mastered { n += 1; continue }
                }
                break
            }
            return n
        }()

        return ZStack {
            Canvas { ctx, size in
                let cx = size.width / 2
                func center(_ i: Int) -> CGPoint {
                    CGPoint(x: cx + xOffset(i), y: CGFloat(i) * rowH + rowH / 2)
                }
                // Smooth curve through the nodes (quad midpoints), split into the
                // travelled part and the road ahead.
                func curve(_ from: Int, _ to: Int) -> Path {
                    var path = Path()
                    guard to > from else { return path }
                    path.move(to: center(from))
                    if to == from + 1 {
                        path.addLine(to: center(to))
                        return path
                    }
                    for i in (from + 1)..<to {
                        let mid = CGPoint(x: (center(i).x + center(i + 1).x) / 2,
                                          y: (center(i).y + center(i + 1).y) / 2)
                        path.addQuadCurve(to: mid, control: center(i))
                    }
                    path.addLine(to: center(to))
                    return path
                }
                if doneCount > 0 {
                    ctx.stroke(curve(0, min(doneCount, nodeList.count - 1)),
                               with: .color(TCTheme.sage.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
                if doneCount < nodeList.count - 1 {
                    ctx.stroke(curve(max(doneCount, 0), nodeList.count - 1),
                               with: .color(TCTheme.textUltraMuted.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 11]))
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(nodeList.enumerated()), id: \.element.id) { i, node in
                    nodeView(node, in: track)
                        .frame(height: rowH)
                        .offset(x: xOffset(i))
                }
            }
        }
        .frame(height: rowH * CGFloat(nodeList.count))
        .padding(.top, 6)
    }

    @ViewBuilder
    private func nodeView(_ node: RoadNode, in track: LessonTrack) -> some View {
        switch node {
        case .lesson(let lesson):
            let status = library.status(of: lesson)
            let isCurrent = lesson.id == currentNodeId
            let p = library.progress[lesson.id]
            let caption: String = {
                switch status {
                case .locked:
                    if let pre = lesson.prerequisites.first,
                       let preLesson = library.lesson(pre) {
                        return "After \(preLesson.title)"
                    }
                    return "Locked"
                case .completed, .mastered:
                    var bits: [String] = []
                    if let b = p?.bestScore { bits.append("Best \(b)") }
                    if let st = p?.bestStreak, st >= 3 { bits.append("\(st) in a row") }
                    return bits.isEmpty ? "Passed — replay anytime" : bits.joined(separator: " · ")
                default:
                    return isCurrent ? "Up next · \(lesson.minutes) min" : "\(lesson.minutes) min"
                }
            }()
            roadCircle(
                icon: status == .locked ? "lock.fill" : lesson.icon,
                label: lesson.title,
                caption: caption,
                state: status == .locked ? .locked
                     : (status == .completed || status == .mastered) ? .done
                     : isCurrent ? .current : .open,
                score: p?.bestScore
            ) {
                if status != .locked, requirePro() { activeLesson = lesson }
            }
        case .practice(let track):
            // Practice unlocks once anything in the unit is done — rep what you learned.
            let anyDone = track.lessons.contains {
                let s = library.status(of: $0); return s == .completed || s == .mastered
            }
            roadCircle(icon: anyDone ? "dumbbell.fill" : "lock.fill",
                       label: "Practice reps",
                       caption: anyDone ? "2 graded swings, no lesson" : "Opens with your first pass",
                       state: anyDone ? .practice : .locked, score: nil) {
                if anyDone, requirePro() { practiceTrack = track }
            }
        case .checkpoint(let track):
            let done = trackCompleted(track)
            roadCircle(icon: done ? "trophy.fill" : "lock.fill",
                       label: done ? "Unit complete!" : "Unit trophy",
                       caption: done ? "Every lesson passed" : "Pass every lesson above",
                       state: done ? .trophy : .locked, score: nil) {
                if done { completedUnitTitle = track.title }
            }
        }
    }

    private enum NodeState { case locked, open, current, done, practice, trophy }

    private func roadCircle(icon: String, label: String, caption: String? = nil,
                            state: NodeState,
                            score: Int?, action: @escaping () -> Void) -> some View {
        let fill: Color = {
            switch state {
            case .locked:   return TCTheme.panelRaised
            case .open:     return TCTheme.gold.opacity(0.85)
            case .current:  return TCTheme.gold
            case .done:     return TCTheme.sage
            case .practice: return LessonsHomeView.accent
            case .trophy:   return Color(red: 0.85, green: 0.62, blue: 0.15)
            }
        }()
        let iconColor: Color = state == .locked ? TCTheme.textMuted : .white
        return Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if state == .current {
                        // Pulsing gold halo marks the active node; the "Up next" caption
                        // below says the rest (the old START bubble collided with the
                        // unit banner above).
                        Circle().stroke(TCTheme.gold.opacity(0.45), lineWidth: 5)
                            .frame(width: 78, height: 78)
                    }
                    // "3D" base edge, Duolingo-style.
                    Circle().fill(fill.opacity(state == .locked ? 0.5 : 0.55))
                        .frame(width: 62, height: 62)
                        .offset(y: 4)
                    Circle().fill(fill).frame(width: 62, height: 62)
                    if state == .locked {
                        // Locked nodes are panel-on-background — give them an edge so
                        // they read as slots, not smudges.
                        Circle().strokeBorder(TCTheme.borderMedium, lineWidth: 1.2)
                            .frame(width: 62, height: 62)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(iconColor)
                    if state == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .background(Circle().fill(TCTheme.sage))
                            .offset(x: 22, y: -22)
                    }
                    if let score {
                        Text("\(score)")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .offset(y: 24)
                    }
                }
                // Label + caption in a solid card so the dotted connector reads as
                // passing BEHIND the text, never through the letter gaps.
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(state == .locked ? TCTheme.textUltraMuted : TCTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(state == .current ? TCTheme.gold : TCTheme.textUltraMuted)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 132)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(TCTheme.panelRaised)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(state == .current ? TCTheme.gold.opacity(0.55) : TCTheme.border,
                                          lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                )
            }
        }
        .buttonStyle(.plain)
        .disabled(state == .locked)
    }

    /// Which Ball Flight Lab preset shows THIS miss's physics.
    static func labPreset(for fault: SwingFault) -> LabPreset? {
        if let id = fault.lessonId {
            if id.hasPrefix("slice") { return .slice }
            if id.hasPrefix("hook") { return .hook }
            if id.hasPrefix("contact") { return .toeStrike }
        }
        return nil
    }

    // MARK: Recent swings

    @ViewBuilder
    private var recentSwingsSection: some View {
        let recent = Array(library.swings.filter(\.analyzed).suffix(5).reversed())
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                TCSectionHeader(title: "Recent Swings")
                ForEach(recent) { swing in
                    NavigationLink {
                        SwingReplayView(swing: swing)
                    } label: {
                        SwingRowView(swing: swing)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Shared swing row (home + history)

struct SwingRowView: View {
    let swing: SwingRecording

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TCTheme.panelRaised)
                    .frame(width: 44, height: 44)
                if let path = swing.thumbnailPath,
                   let img = UIImage(contentsOfFile: LessonLibrary.swingsDir(userId: swing.userId).appendingPathComponent(path).path) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "figure.golf")
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(swing.headline.isEmpty ? "Swing" : swing.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                Text("\(Self.df.string(from: swing.recordedAt)) · \(swing.viewAngle.displayName)")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            if let score = swing.overallScore {
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(score >= 70 ? TCTheme.sage : TCTheme.gold)
                    Text("SCORE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(TCTheme.textUltraMuted)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TCTheme.textUltraMuted)
        }
        .padding(12)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(TCTheme.border, lineWidth: 1))
    }
}

// MARK: - Intake questionnaire (questionnaire-only by design)

struct LessonIntakeView: View {
    var existing: LessonProfile?
    let onDone: (LessonProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var skill: SkillLevel = .beginner
    @State private var focuses: Set<FocusArea> = []
    @State private var hasClubs = true
    @State private var hasNet = false
    @State private var hasTripod = false
    @State private var primaryGoal: FocusArea? = nil
    @State private var limitedMobility = false

    var body: some View {
        NavigationStack {
            ZStack {
                TrueCarryBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: TCTheme.sectionGap) {
                        VStack(alignment: .leading, spacing: 10) {
                            TCSectionHeader(title: "How much golf have you played?")
                            ForEach(SkillLevel.allCases) { level in
                                choiceRow(level.displayName, selected: skill == level) { skill = level }
                            }
                        }
                        .tcCard(padding: 14)

                        VStack(alignment: .leading, spacing: 10) {
                            TCSectionHeader(title: "What do you want to work on?")
                            Text("Pick as many as you like — this orders your lessons.")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                            ForEach(FocusArea.allCases) { area in
                                choiceRow(area.displayName, icon: area.icon,
                                          selected: focuses.contains(area)) {
                                    if focuses.contains(area) { focuses.remove(area) }
                                    else { focuses.insert(area) }
                                }
                            }
                        }
                        .tcCard(padding: 14)

                        VStack(alignment: .leading, spacing: 10) {
                            TCSectionHeader(title: "What's the ONE goal?")
                            Text("Coach anchors the roadmap, reads and check-ins to this.")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                            ForEach([FocusArea.startFromZero, .slice, .hook, .contact, .distance, .scoring], id: \.self) { area in
                                choiceRow(area.displayName, icon: area.icon,
                                          selected: primaryGoal == area) {
                                    primaryGoal = primaryGoal == area ? nil : area
                                }
                            }
                        }
                        .tcCard(padding: 14)

                        VStack(alignment: .leading, spacing: 10) {
                            TCSectionHeader(title: "Your gear & body")
                            toggleRow("I have clubs", isOn: $hasClubs)
                            toggleRow("I have a net or range access", isOn: $hasNet)
                            toggleRow("I have a phone tripod", isOn: $hasTripod)
                            toggleRow("Limited flexibility or an injury", isOn: $limitedMobility)
                            if limitedMobility {
                                Text("Turn and posture targets relax — Coach won't demand a range your body can't give.")
                                    .font(.system(size: 11))
                                    .foregroundColor(TCTheme.textUltraMuted)
                            }
                        }
                        .tcCard(padding: 14)

                        TCPrimaryGoldButton(title: "Build my plan", icon: "checkmark") {
                            var p = existing ?? LessonProfile()
                            p.skillLevel = skill
                            p.focusAreas = Array(focuses)
                            p.hasClubs = hasClubs
                            p.hasNetOrRange = hasNet
                            p.hasTripod = hasTripod
                            p.primaryGoal = primaryGoal
                            p.limitedMobility = limitedMobility
                            onDone(p)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            .onAppear {
                if let existing {
                    skill = existing.skillLevel
                    focuses = Set(existing.focusAreas)
                    hasClubs = existing.hasClubs
                    hasNet = existing.hasNetOrRange
                    hasTripod = existing.hasTripod
                    primaryGoal = existing.primaryGoal
                    limitedMobility = existing.limitedMobility ?? false
                }
            }
        }
    }

    private func choiceRow(_ title: String, icon: String? = nil,
                           selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selected ? TCTheme.sage : TCTheme.textMuted)
                        .frame(width: 22)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundColor(selected ? TCTheme.sage : TCTheme.textUltraMuted)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
        }
        .tint(TCTheme.sage)
        .padding(.vertical, 4)
    }
}

// MARK: - Coach's Read deep dive (tap a suggestion → the evidence behind it)

struct CoachReadDetailView: View {
    let read: CoachSuggestion
    let shots: [SavedShot]
    let onOpenLesson: (String) -> Void

    @ObservedObject private var library = LessonLibrary.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                TrueCarryBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: TCTheme.sectionGap) {
                        headerCard
                        ForEach(read.metricKinds, id: \.self) { kindRaw in
                            if let kind = SwingMetricKind(rawValue: kindRaw) {
                                metricTrendCard(kind)
                            }
                        }
                        ballFlightCard
                        if let lessonId = read.lessonId, let lesson = library.lesson(lessonId) {
                            TCPrimaryGoldButton(title: "Work on it: \(lesson.title)", icon: "figure.golf") {
                                onOpenLesson(lessonId)
                            }
                        }
                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Coach's Read")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(TCTheme.sage)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((read.priority > 0 ? TCTheme.gold : LessonsHomeView.accent).opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: read.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(read.priority > 0 ? TCTheme.gold : LessonsHomeView.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if read.priority > 0 {
                        Text("CAMERA + BALL DATA AGREE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(TCTheme.gold)
                            .tracking(1.2)
                    }
                    Text(read.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(read.detail)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tcCard(padding: 16)
    }

    /// One camera metric across your analyzed swings, with the target band shaded.
    @ViewBuilder
    private func metricTrendCard(_ kind: SwingMetricKind) -> some View {
        let points: [(idx: Int, value: Double, low: Double, high: Double)] =
            library.swings.filter(\.analyzed)
                .compactMap { swing in swing.metrics.first { $0.kind == kind } }
                .suffix(15)
                .enumerated()
                .map { ($0.offset, $0.element.value, $0.element.targetLow, $0.element.targetHigh) }
        if points.count >= 2, let band = points.last {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TCSectionHeader(title: kind.displayName)
                    Spacer()
                    Text("target \(fmt(band.low, kind))–\(fmt(band.high, kind))")
                        .font(.system(size: 10))
                        .foregroundColor(TCTheme.textUltraMuted)
                }
                Chart {
                    RectangleMark(
                        xStart: .value("s", -0.5), xEnd: .value("e", Double(points.count) - 0.5),
                        yStart: .value("lo", band.low), yEnd: .value("hi", band.high)
                    )
                    .foregroundStyle(TCTheme.sage.opacity(0.12))
                    ForEach(points, id: \.idx) { p in
                        LineMark(x: .value("Swing", p.idx), y: .value("Value", p.value))
                            .foregroundStyle(LessonsHomeView.accent)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Swing", p.idx), y: .value("Value", p.value))
                            .foregroundStyle(p.value >= p.low && p.value <= p.high ? TCTheme.sage : TCTheme.gold)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(TCTheme.border.opacity(0.5))
                        AxisValueLabel().foregroundStyle(TCTheme.textMuted)
                    }
                }
                .frame(height: 130)
                Text("Your last \(points.count) measured swings — green dots are in the target band.")
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard(padding: 14)
        }
    }

    /// Measured ball flight: spin axis per shot (fade right, draw left) + the averages.
    @ViewBuilder
    private var ballFlightCard: some View {
        let recent = shots.suffix(20).filter { !$0.isBadShot && $0.metrics.ballSpeedMph > 0 }
        if recent.count >= 5 {
            let axes = Array(recent.enumerated())
            let avgAxis = recent.map { $0.metrics.spinAxisDegrees }.reduce(0, +) / Double(recent.count)
            VStack(alignment: .leading, spacing: 10) {
                TCSectionHeader(title: "Measured Ball Flight")
                Chart {
                    RuleMark(y: .value("straight", 0))
                        .foregroundStyle(TCTheme.textMuted.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    ForEach(axes, id: \.offset) { i, shot in
                        // Integer x has no unit, so Charts logs a "falling back to fixed
                        // dimension" complaint on every render without an explicit width.
                        BarMark(x: .value("Shot", i), y: .value("Spin Axis", shot.metrics.spinAxisDegrees),
                                width: .fixed(10))
                            .foregroundStyle(shot.metrics.spinAxisDegrees >= 0
                                             ? Color(red: 0.9, green: 0.45, blue: 0.25)
                                             : LessonsHomeView.accent)
                            .cornerRadius(2)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(TCTheme.border.opacity(0.5))
                        AxisValueLabel().foregroundStyle(TCTheme.textMuted)
                    }
                }
                .frame(height: 130)
                HStack(spacing: 0) {
                    ballStat(String(format: "%+.1f°", avgAxis), "AVG SPIN AXIS")
                    Rectangle().fill(TCTheme.border).frame(width: 1, height: 26)
                    ballStat("\(recent.count)", "SHOTS")
                    Rectangle().fill(TCTheme.border).frame(width: 1, height: 26)
                    ballStat(avgAxis > 2 ? "FADE/SLICE" : (avgAxis < -2 ? "DRAW/HOOK" : "NEUTRAL"), "TENDENCY")
                }
                Text("Orange bars curve right, blue curve left — from your launch monitor shots.")
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard(padding: 14)
        }
    }

    private func ballStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(TCTheme.textPrimary)
            Text(label).font(.system(size: 8, weight: .bold))
                .foregroundColor(TCTheme.textMuted).tracking(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ v: Double, _ kind: SwingMetricKind) -> String {
        kind == .tempoRatio ? String(format: "%.1f", v) : "\(Int(v))\(kind.unit)"
    }
}

// MARK: - Fix track sheet (off-path lesson list)

struct FixTrackSheet: View {
    let track: LessonTrack
    let onOpen: (Lesson) -> Void
    @ObservedObject private var library = LessonLibrary.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                TrueCarryBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(track.subtitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(TCTheme.textSecondary)
                        ForEach(track.lessons) { lesson in
                            let status = library.status(of: lesson)
                            let locked = status == .locked
                            let done = status == .completed || status == .mastered
                            Button { if !locked { onOpen(lesson) } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: done ? "checkmark.circle.fill" : (locked ? "lock.fill" : lesson.icon))
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(done ? TCTheme.sage : (locked ? TCTheme.textUltraMuted : TCTheme.gold))
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lesson.title)
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundColor(locked ? TCTheme.textUltraMuted : TCTheme.textPrimary)
                                        Text("\(lesson.subtitle) · \(lesson.minutes) min")
                                            .font(.system(size: 13))
                                            .foregroundColor(TCTheme.textMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(TCTheme.textUltraMuted)
                                }
                                .tcCard(padding: 14)
                            }
                            .buttonStyle(.plain)
                            .disabled(locked)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 12)
                }
            }
            .navigationTitle(track.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(TCTheme.sage)
                }
            }
        }
    }
}


// MARK: - Drill Library (standalone, searchable — outside the lesson path)

struct DrillLibrarySheet: View {
    let faults: [SwingFault]
    let onOpenLesson: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [SwingFault] {
        guard !query.isEmpty else { return faults }
        let q = query.lowercased()
        return faults.filter {
            $0.title.lowercased().contains(q) || $0.explanation.lowercased().contains(q)
                || $0.drill.lowercased().contains(q)
                || ($0.drillLadder ?? []).contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TrueCarryBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(filtered) { fault in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(fault.title)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(TCTheme.textPrimary)
                                Text(fault.explanation)
                                    .font(.system(size: 12))
                                    .foregroundColor(TCTheme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(Array((fault.drillLadder ?? [fault.drill]).enumerated()),
                                        id: \.offset) { i, drill in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(i + 1)")
                                            .font(.system(size: 11, weight: .black, design: .monospaced))
                                            .foregroundColor(TCTheme.gold)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(TCTheme.gold.opacity(0.14)))
                                        Text(drill)
                                            .font(.system(size: 13))
                                            .foregroundColor(TCTheme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                if let lessonId = fault.lessonId {
                                    Button { onOpenLesson(lessonId) } label: {
                                        Label("Open the lesson", systemImage: "arrow.right.circle.fill")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(TCTheme.sage)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .tcCard(padding: 14)
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 10)
                }
            }
            .searchable(text: $query, prompt: "sway, slice, tempo…")
            .navigationTitle("Drill Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(TCTheme.sage)
                }
            }
        }
    }
}
