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
                    TCHeaderBar(initials: userInitials) { EmptyView() }
                    pageTitleSection
                    if let r = unfinishedRound { resumeRoundCard(r) }
                    modeCardsSection
                    startButtonSection
                    Spacer(minLength: 140)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showCamera) {
            if let uid = session.currentUser?.id {
                RangeCameraScreen(userId: uid, backend: session.backend)
                    .ignoresSafeArea().statusBarHidden(true)
            }
        }
        .sheet(isPresented: $showSim) {
            if let uid = session.currentUser?.id {
                SimModeView(userId: uid, backend: session.backend)
            }
        }
        .sheet(isPresented: $showCourseSearch, onDismiss: {
            // onDismiss fires after the sheet is fully gone — safe to present fullScreenCover now.
            if selectedCourse != nil && selectedTeeBox != nil {
                showCourseMode = true
            }
        }) {
            if let uid = session.currentUser?.id {
                NavigationStack {
                    CourseSearchView(userId: uid) { course, tee in
                        selectedCourse = course
                        selectedTeeBox = tee
                        showCourseSearch = false
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
            Text("Choose a mode to start.")
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

}
