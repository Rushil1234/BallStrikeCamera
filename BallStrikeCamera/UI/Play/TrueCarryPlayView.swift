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

    /// Holds the course+tee atomically so fullScreenCover(item:) never sees a partial state.
    private struct PendingRound: Identifiable {
        let id = UUID(); let course: GolfCourse; let tee: TeeBox
    }
    @State private var pendingRound: PendingRound?
    @State private var unfinishedRound: CourseRound?
    @State private var resumeRound: CourseRound?
    @State private var didApplyDefaultMode = false
    @StateObject private var prewarmer = NearbyCoursePrewarmer()
    @StateObject private var prewarmLocation = LocationService()
    @AppStorage("tc_default_play_mode") private var defaultPlayMode = "Range"

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
        .sheet(isPresented: $showCourseSearch) {
            NavigationStack {
                CourseSearchView(userId: session.currentUser?.id ?? UUID()) { course, tee in
                    // Set atomically — fullScreenCover(item:) presents only when non-nil,
                    // and SwiftUI automatically queues it until the sheet is fully gone.
                    pendingRound = PendingRound(course: course, tee: tee)
                    showCourseSearch = false
                }
            }
            .tcAppearance()
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
        .fullScreenCover(item: $pendingRound) { pr in
            CourseModeGPSHoleView(
                userId: session.currentUser?.id ?? UUID(),
                backend: session.backend,
                initialCourse: pr.course,
                initialTeeBox: pr.tee
            )
        }
        .fullScreenCover(item: $resumeRound) { round in
            CourseModeGPSHoleView(
                userId: session.currentUser?.id ?? UUID(),
                backend: session.backend,
                initialRound: round
            )
        }
        .task {
            applyDefaultModeIfNeeded()
            await refreshUnfinishedRound()
            prewarmLocation.requestPermission()
            // Flush any deferred remote writes from prior offline rounds.
            await SyncQueue.shared.flush(using: session.backend)
        }
        .onChange(of: pendingRound?.id) { _ in
            // Recheck unfinished rounds when course mode closes (pendingRound cleared).
            if pendingRound == nil { Task { await refreshUnfinishedRound() } }
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
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
            Text("Choose how you want to play today.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Mode Cards

    private var modeCardsSection: some View {
        VStack(spacing: 14) {
            PlayModeTile(
                icon: "target",
                title: "Range Mode",
                subtitle: "Track every shot.",
                motif: .target,
                isSelected: selectedMode == .range
            ) { selectMode(.range) }

            PlayModeTile(
                icon: "display",
                title: "Sim Mode",
                subtitle: "Play virtual courses indoors.",
                motif: .sim,
                isSelected: selectedMode == .sim
            ) { selectMode(.sim) }

            PlayModeTile(
                icon: "map.fill",
                title: "Course Mode",
                subtitle: "Real courses with live GPS.",
                motif: .course,
                isSelected: selectedMode == .course
            ) { selectMode(.course) }
        }
    }

    private func selectMode(_ mode: PlayMode) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            selectedMode = mode
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

    private func applyDefaultModeIfNeeded() {
        guard !didApplyDefaultMode else { return }
        didApplyDefaultMode = true
        switch defaultPlayMode {
        case "Simulator": selectedMode = .sim
        case "Course": selectedMode = .course
        default: selectedMode = .range
        }
    }

}

// MARK: - Play Mode Tile (hero card with mode-specific motif)

enum PlayMotif { case target, sim, course }

private struct PlayModeTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let motif: PlayMotif
    let isSelected: Bool
    let action: () -> Void

    private let radius: CGFloat = 16

    var body: some View {
        Button(action: action) {
            ZStack {
                // Faint mode-specific line-art motif, bleeding off the right edge.
                motifView
                    .frame(width: 150, height: 150)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 30)
                    .opacity(isSelected ? 0.18 : 0.06)
                    .allowsHitTesting(false)

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(isSelected ? TCTheme.gold.opacity(0.18) : TCTheme.panelRaised)
                            .frame(width: 52, height: 52)
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(isSelected ? TCTheme.gold : TCTheme.textMuted)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(TCTheme.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    Spacer(minLength: 8)

                    selectionIndicator
                }
                .padding(.horizontal, 18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(isSelected ? TCTheme.gold.opacity(0.07) : TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(isSelected ? TCTheme.borderGold : TCTheme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var motifView: some View {
        let tint = isSelected ? TCTheme.gold : TCTheme.textPrimary
        switch motif {
        case .target: TargetRingsMotif(tint: tint)
        case .sim:    SimScreenMotif(tint: tint)
        case .course: CourseMapMotif(tint: tint)
        }
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .strokeBorder(TCTheme.border, lineWidth: 1.5)
                .frame(width: 24, height: 24)
                .opacity(isSelected ? 0 : 1)
            Circle()
                .fill(TCTheme.gold)
                .frame(width: 24, height: 24)
                .opacity(isSelected ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .opacity(isSelected ? 1 : 0)
        }
    }
}

// MARK: - Mode motifs (decorative line art)

private struct TargetRingsMotif: View {
    let tint: Color
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(tint, lineWidth: 1.5)
                    .frame(width: CGFloat(36 + i * 30), height: CGFloat(36 + i * 30))
            }
            Circle().fill(tint).frame(width: 12, height: 12)
        }
    }
}

private struct SimScreenMotif: View {
    let tint: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint, lineWidth: 1.5)
                .frame(width: 120, height: 84)
            BallFlightArc()
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 94, height: 56)
            Circle().fill(tint).frame(width: 6, height: 6).offset(x: 47, y: -28)
        }
    }
}

private struct CourseMapMotif: View {
    let tint: Color
    var body: some View {
        ZStack {
            FairwayShape()
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 110, height: 132)
            Image(systemName: "flag.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .offset(x: 20, y: -50)
        }
    }
}

private struct BallFlightArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.25)
        )
        return p
    }
}

private struct FairwayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX - 16, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.midX + 4, y: rect.minY),
            control1: CGPoint(x: rect.midX - 42, y: rect.midY),
            control2: CGPoint(x: rect.midX + 34, y: rect.midY * 0.8)
        )
        p.move(to: CGPoint(x: rect.midX + 20, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.midX + 22, y: rect.minY),
            control1: CGPoint(x: rect.midX + 4, y: rect.midY),
            control2: CGPoint(x: rect.midX + 56, y: rect.midY * 0.8)
        )
        return p
    }
}
