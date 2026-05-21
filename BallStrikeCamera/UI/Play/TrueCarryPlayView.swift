import SwiftUI

struct TrueCarryPlayView: View {
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController

    @State private var selectedMode: PlayMode = .range
    @State private var showCamera = false
    @State private var showSim = false
    @State private var showCourseSearch = false
    @State private var showCourseMode = false
    @State private var showRoundSetup = false
    @State private var showUpgradeAlert = false
    @State private var selectedCourse: GolfCourse?
    @State private var selectedTeeBox: TeeBox?
    @State private var showSessions = false
    @State private var unfinishedRound: CourseRound?
    @State private var resumeRound: CourseRound?
    @StateObject private var prewarmer = NearbyCoursePrewarmer()
    @StateObject private var prewarmLocation = LocationService()

    enum PlayMode { case range, sim, course }

    // MARK: Derived helpers

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2,
           let f = parts[0].first,
           let l = parts[1].first {
            return "\(f)\(l)"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var startTitle: String {
        switch selectedMode {
        case .range:  return "Start Session"
        case .sim:    return "Start Sim Session"
        case .course: return "Start Round"
        }
    }

    private var startIcon: String {
        switch selectedMode {
        case .range:  return "camera.fill"
        case .sim:    return "display"
        case .course: return "magnifyingglass"
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    TCHeaderBar(initials: userInitials) {
                        TCBellButton(badgeCount: 0) { showSessions = true }
                    }
                    pageTitleSection
                    if let r = unfinishedRound { resumeRoundCard(r) }
                    modeCardsSection
                    sessionSetupSection
                    startButtonSection
                    chipsRow
                    upNextCard
                    Spacer(minLength: 140)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen().ignoresSafeArea().statusBarHidden(true)
        }
        .sheet(isPresented: $showSim) {
            SimModeView()
        }
        .sheet(isPresented: $showCourseSearch) {
            if let uid = session.currentUser?.id {
                NavigationStack {
                    CourseSearchView(userId: uid) { course, tee in
                        selectedCourse = course
                        selectedTeeBox = tee
                        showCourseSearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showRoundSetup = true
                        }
                    }
                }
                .tcAppearance()
            }
        }
        .sheet(isPresented: $showRoundSetup) {
            if let course = selectedCourse, let tee = selectedTeeBox {
                NavigationStack {
                    RoundSetupView(course: course, teeBox: tee) {
                        showRoundSetup = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showCourseMode = true
                        }
                    }
                }
                .tcAppearance()
            }
        }
        .alert("Course Mode", isPresented: $showUpgradeAlert) {
            Button("Upgrade") {
                if let url = URL(string: "https://truecarry.app/pricing") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Course Mode is available with Basic, Pro, or Unlimited plans.")
        }
        .fullScreenCover(isPresented: $showCourseMode) {
            if let uid = session.currentUser?.id,
               let course = selectedCourse,
               let tee = selectedTeeBox {
                CourseModeGPSHoleView(
                    userId: uid,
                    backend: session.backend,
                    initialCourse: course,
                    initialTeeBox: tee
                )
            }
        }
        .sheet(isPresented: $showSessions) {
            NavigationStack {
                PastSessionsView()
            }
            .tcAppearance()
        }
        .fullScreenCover(item: $resumeRound) { round in
            if let uid = session.currentUser?.id {
                CourseModeGPSHoleView(
                    userId: uid,
                    backend: session.backend,
                    initialRound: round
                )
            }
        }
        .task {
            await refreshUnfinishedRound()
            prewarmLocation.requestPermission()
            // Flush any deferred remote writes from prior offline rounds.
            await SyncQueue.shared.flush(using: session.backend)
        }
        .onChange(of: showCourseMode) { isShowing in
            // Recheck unfinished rounds after the user leaves a round screen.
            if !isShowing { Task { await refreshUnfinishedRound() } }
        }
        .onChange(of: prewarmLocation.currentLocation?.latitude) { _ in
            guard let loc = prewarmLocation.currentLocation else { return }
            prewarmer.warm(near: loc)
        }
        .onDisappear { prewarmer.cancel() }
    }

    // MARK: Resume

    private func resumeRoundCard(_ round: CourseRound) -> some View {
        Button { resumeRound = round } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(TCTheme.goldGradient)
                        .frame(width: 40, height: 40)
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Resume Round")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.gold)
                        .tracking(0.5)
                    Text(round.courseName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1)
                    let played = round.holes.filter { $0.score != nil }.count
                    Text("\(played)/\(round.holes.count) holes scored  ·  \(round.teeBoxName) Tees")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
            }
            .tcCard()
        }
        .buttonStyle(.plain)
    }

    private func refreshUnfinishedRound() async {
        guard let uid = session.currentUser?.id else { return }
        let all = (try? await session.backend.loadCourseRounds(userId: uid)) ?? []
        unfinishedRound = all.first(where: { $0.endedAt == nil })
    }

    // MARK: Page Title

    private var pageTitleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Play")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
            Text("Choose a mode and set up your session.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Mode Cards (horizontal HStack)

    private var modeCardsSection: some View {
        HStack(spacing: 10) {
            TCModeCard(
                icon: "target",
                title: "Range Mode",
                subtitle: "Dial in your game. Track every shot.",
                accent: TCTheme.cyan,
                isSelected: selectedMode == .range
            ) {
                selectedMode = .range
            }

            TCModeCard(
                icon: "display",
                title: "Sim Mode",
                subtitle: "Play virtual courses indoors.",
                accent: TCTheme.gold,
                isSelected: selectedMode == .sim
            ) {
                selectedMode = .sim
            }

            TCModeCard(
                icon: "map.fill",
                title: "Course Mode",
                subtitle: "Play real courses. On the course.",
                accent: TCTheme.sage,
                isSelected: selectedMode == .course
            ) {
                selectedMode = .course
            }
        }
    }

    // MARK: Session Setup Card

    private var sessionSetupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TCSectionHeader(title: "Session Setup")
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                TCSettingsRow(
                    icon: "flag.fill",
                    title: "Course",
                    value: "Stone Ridge GC",
                    accent: TCTheme.sage
                )
                TCDivider()
                TCSettingsRow(
                    icon: "tshirt",
                    title: "Tee Box",
                    value: "Blue – 6,412 yds",
                    accent: TCTheme.cyan
                )
                TCDivider()
                TCSettingsRow(
                    icon: "list.bullet",
                    title: "Session Type",
                    value: sessionTypeValue,
                    accent: TCTheme.gold
                )
                TCDivider()
                TCSettingsRow(
                    icon: "hand.raised.fill",
                    title: "Handedness",
                    value: session.userProfile?.handedness.rawValue ?? "Right",
                    accent: TCTheme.textMuted,
                    showChevron: false
                )
            }
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
        }
    }

    private var sessionTypeValue: String {
        switch selectedMode {
        case .sim:    return "Sim Session"
        case .course: return "Full Round"
        case .range:  return "Practice"
        }
    }

    // MARK: Start Button

    private var startButtonSection: some View {
        TCPrimaryGoldButton(title: startTitle, icon: startIcon) {
            handleStart()
        }
    }

    private func handleStart() {
        switch selectedMode {
        case .range:  showCamera = true
        case .sim:    showSim = true
        case .course:
            let decision = session.entitlementVM.canPerform(.courseMode)
            if decision.allowed {
                showCourseSearch = true
            } else {
                showUpgradeAlert = true
            }
        }
    }

    // MARK: Quick Chips Row

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                TCChipButton(title: "Use Last Setup", icon: "arrow.clockwise") {
                    handleStart()
                }
                TCChipButton(title: "Choose Club", icon: "figure.golf") {
                    selectedMode = .range
                    showCamera = true
                }
                TCChipButton(title: "Saved Sessions", icon: "list.bullet") {
                    showSessions = true
                }
                TCChipButton(title: "Sim History", icon: "clock") {
                    selectedMode = .sim
                    showSim = true
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Up Next Card

    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UP NEXT")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.4)
                .foregroundColor(TCTheme.gold)

            HStack(spacing: 14) {
                Image(systemName: "flag")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 34, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Hole 1")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.textSecondary)

                    Text("Par 4  ·  392 yds")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TCTheme.textMuted)

                    Text("Stone Ridge GC")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
            }
        }
        .tcCard()
        .contentShape(Rectangle())
        .onTapGesture {
            showCourseSearch = true
        }
    }
}
