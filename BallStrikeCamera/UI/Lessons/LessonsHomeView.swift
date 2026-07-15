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
            if requirePro() { showFreeAnalysis = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("Analyze My Swing")
                    .font(.system(size: 15, weight: .black, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Color(red: 0.16, green: 0.62, blue: 0.74),
                                            Color(red: 0.10, green: 0.45, blue: 0.58)],
                                   startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
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
                    .background(Circle().fill(top.priority > 0 ? TCTheme.gold : TCTheme.cyan))
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
                .strokeBorder((top.priority > 0 ? TCTheme.gold : TCTheme.cyan).opacity(0.5), lineWidth: 1.4))
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
                    if !library.hasCompletedIntake { intakeBanner }
                    readPopup
                    roadmapSection
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
        .sheet(item: $selectedRead) { read in
            CoachReadDetailView(read: read, shots: recentShots) { lessonId in
                selectedRead = nil
                if let lesson = library.lesson(lessonId) { activeLesson = lesson }
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
            Text("Unlock the full lesson library, swing analysis, and your personal coaching plan.")
        }
    }

    // MARK: Pro gate

    private var proGateCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.golf")
                .font(.system(size: 40))
                .foregroundColor(TCTheme.gold)
            Text("TrueCarry Coach")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Text("Guided lessons from your first grip to real ball-flight numbers — with camera swing analysis that scores your tempo, balance and body motion, and a plan that adapts to what it sees.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
            TCPrimaryGoldButton(title: "Upgrade to Pro", icon: "lock.open.fill") {
                UIApplication.shared.open(session.entitlementVM.upgradeURL)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .tcCard(padding: 20)
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

    private var intakePromptCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 36))
                .foregroundColor(TCTheme.sage)
            Text("Let's build your plan")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Text("Five quick questions — your answers pick which lessons you see and how your swings are graded.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
            TCPrimaryGoldButton(title: "Start", icon: "arrow.right") { showIntake = true }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .tcCard(padding: 20)
    }

    // MARK: Continue hero

    @ViewBuilder
    private var continueHero: some View {
        if let lesson = library.nextLesson {
            Button { activeLesson = lesson } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(TCTheme.goldGradient).frame(width: 46, height: 46)
                        Image(systemName: lesson.icon)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CONTINUE · \(library.track(containing: lesson.id)?.title.uppercased() ?? "")")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(TCTheme.gold)
                            .tracking(1.2)
                        Text(lesson.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("\(lesson.subtitle) · \(lesson.minutes) min")
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(TCTheme.gold)
                }
                .tcCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var analyzeSwingCard: some View {
        Button { showFreeAnalysis = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TCTheme.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyze my swing")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Tripod + face-on camera · auto-record · instant score")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard()
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
                                    .fill((read.priority > 0 ? TCTheme.gold : TCTheme.cyan).opacity(0.16))
                                    .frame(width: 38, height: 38)
                                Image(systemName: read.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(read.priority > 0 ? TCTheme.gold : TCTheme.cyan)
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

    // MARK: Your Focus (one designated card per intake answer)

    @ViewBuilder
    private var focusSection: some View {
        if let areas = library.profile?.focusAreas, !areas.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                TCSectionHeader(title: "Your Focus")
                ForEach(areas) { area in
                    focusCard(area)
                }
            }
        }
    }

    @ViewBuilder
    private func focusCard(_ area: FocusArea) -> some View {
        let track = library.curriculum.tracks.first { $0.focusAreas.contains(area) }
        let next = track?.lessons.first {
            let st = library.status(of: $0)
            return st == .available || st == .inProgress
        }
        Button {
            if area == .checkup { showFreeAnalysis = true }
            else if let next { activeLesson = next }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TCTheme.sage.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: area.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.sage)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    if area == .checkup {
                        Text("Open the Swing Studio anytime — instant score + verdicts")
                            .font(.system(size: 11)).foregroundColor(TCTheme.textMuted)
                    } else if let next {
                        Text("Next up: \(next.title) · \(next.minutes) min")
                            .font(.system(size: 11)).foregroundColor(TCTheme.textMuted)
                    } else if track != nil {
                        Text("Track complete — retake any lesson below")
                            .font(.system(size: 11)).foregroundColor(TCTheme.sage)
                    } else {
                        Text("Program in the works — Coach's Read covers this today")
                            .font(.system(size: 11)).foregroundColor(TCTheme.textUltraMuted)
                    }
                }
                Spacer()
                Image(systemName: area == .checkup ? "video.fill" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard(padding: 12)
        }
        .buttonStyle(.plain)
        .disabled(area != .checkup && next == nil && track != nil)
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
        return HStack(spacing: 0) {
            statCell("\(library.completedLessonCount)", "LESSONS", "checkmark.seal.fill", TCTheme.gold)
            statDivider
            statCell("\(library.swings.filter(\.analyzed).count)", "SWINGS", "video.fill", TCTheme.cyan)
            statDivider
            statCell(avg.map { "\($0)" } ?? "—", "AVG SCORE", "chart.line.uptrend.xyaxis", TCTheme.sage)
        }
        .tcCard(padding: 12)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 30)
    }

    private func statCell(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundColor(tint)
                Text(value).font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(label).font(.system(size: 8.5, weight: .bold)).foregroundColor(.white.opacity(0.75)).tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

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
            ForEach(Array(library.orderedTracks.enumerated()), id: \.element.id) { unitIndex, track in
                VStack(spacing: 0) {
                    unitBanner(track, number: unitIndex + 1)
                    roadPath(track)
                }
            }
        }
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
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(track.subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(trackCompleted(track)
                      ? LinearGradient(colors: [Color(red: 0.30, green: 0.55, blue: 0.28), Color(red: 0.20, green: 0.42, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                      : LinearGradient(colors: [Color(red: 0.72, green: 0.55, blue: 0.18), Color(red: 0.55, green: 0.40, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    /// The winding node path: fixed row height so the dotted connector is a simple
    /// point-to-point Canvas behind staggered circles.
    private func roadPath(_ track: LessonTrack) -> some View {
        let nodeList = nodes(for: track)
        let rowH: CGFloat = 96
        let offsets: [CGFloat] = [0, -68, -96, -68, 0, 68, 96, 68]
        func xOffset(_ i: Int) -> CGFloat { offsets[i % offsets.count] }

        return ZStack {
            Canvas { ctx, size in
                let cx = size.width / 2
                var path = Path()
                for i in 0..<nodeList.count {
                    let pt = CGPoint(x: cx + xOffset(i), y: CGFloat(i) * rowH + rowH / 2)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(TCTheme.border),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 12]))
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
            roadCircle(
                icon: status == .locked ? "lock.fill" : lesson.icon,
                label: lesson.title,
                state: status == .locked ? .locked
                     : (status == .completed || status == .mastered) ? .done
                     : isCurrent ? .current : .open,
                score: library.progress[lesson.id]?.bestScore
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
                       state: anyDone ? .practice : .locked, score: nil) {
                if anyDone, requirePro() { practiceTrack = track }
            }
        case .checkpoint(let track):
            let done = trackCompleted(track)
            roadCircle(icon: done ? "trophy.fill" : "lock.fill",
                       label: done ? "Unit complete!" : "Finish the unit",
                       state: done ? .trophy : .locked, score: nil) {
                if done { completedUnitTitle = track.title }
            }
        }
    }

    private enum NodeState { case locked, open, current, done, practice, trophy }

    private func roadCircle(icon: String, label: String, state: NodeState,
                            score: Int?, action: @escaping () -> Void) -> some View {
        let fill: Color = {
            switch state {
            case .locked:   return TCTheme.panelRaised
            case .open:     return TCTheme.gold.opacity(0.85)
            case .current:  return TCTheme.gold
            case .done:     return TCTheme.sage
            case .practice: return TCTheme.cyan
            case .trophy:   return Color(red: 0.85, green: 0.62, blue: 0.15)
            }
        }()
        let iconColor: Color = state == .locked ? TCTheme.textUltraMuted : .white
        return Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if state == .current {
                        // Pulsing halo + START bubble on the active node.
                        Circle().stroke(TCTheme.gold.opacity(0.45), lineWidth: 5)
                            .frame(width: 78, height: 78)
                        Text("START")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(TCTheme.gold)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(TCTheme.panel))
                            .overlay(Capsule().strokeBorder(TCTheme.gold, lineWidth: 1.5))
                            .offset(y: -52)
                    }
                    // "3D" base edge, Duolingo-style.
                    Circle().fill(fill.opacity(state == .locked ? 0.5 : 0.55))
                        .frame(width: 62, height: 62)
                        .offset(y: 4)
                    Circle().fill(fill).frame(width: 62, height: 62)
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
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(state == .locked ? TCTheme.textUltraMuted : TCTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 130)
            }
        }
        .buttonStyle(.plain)
        .disabled(state == .locked)
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
                            TCSectionHeader(title: "Your gear")
                            toggleRow("I have clubs", isOn: $hasClubs)
                            toggleRow("I have a net or range access", isOn: $hasNet)
                            toggleRow("I have a phone tripod", isOn: $hasTripod)
                        }
                        .tcCard(padding: 14)

                        TCPrimaryGoldButton(title: "Build my plan", icon: "checkmark") {
                            var p = existing ?? LessonProfile()
                            p.skillLevel = skill
                            p.focusAreas = Array(focuses)
                            p.hasClubs = hasClubs
                            p.hasNetOrRange = hasNet
                            p.hasTripod = hasTripod
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
                        .fill((read.priority > 0 ? TCTheme.gold : TCTheme.cyan).opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: read.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(read.priority > 0 ? TCTheme.gold : TCTheme.cyan)
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
                            .foregroundStyle(TCTheme.cyan)
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
                        BarMark(x: .value("Shot", i), y: .value("Spin Axis", shot.metrics.spinAxisDegrees))
                            .foregroundStyle(shot.metrics.spinAxisDegrees >= 0
                                             ? Color(red: 0.9, green: 0.45, blue: 0.25)
                                             : TCTheme.cyan)
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
