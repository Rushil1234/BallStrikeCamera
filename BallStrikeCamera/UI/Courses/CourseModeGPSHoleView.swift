import SwiftUI

struct CourseModeGPSHoleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController
    @StateObject private var vm: CourseRoundViewModel

    @State private var showCamera      = false
    @State private var showScoreEntry  = false
    @State private var showScorecard   = false
    @State private var showFinishAlert = false
    @State private var gpsOn           = true
    @State private var infoMessage: String?

    let initialCourse: GolfCourse?
    let initialTeeBox: TeeBox?

    // MARK: - Computed Course/GPS Properties

    private var currentCourseHole: GolfHole? {
        guard let hole = vm.currentHole,
              let course = vm.selectedCourse else { return nil }
        return course.holes.first { $0.number == hole.holeNumber }
    }

    private var scorecardYardage: Int? {
        guard let gh = currentCourseHole,
              let tee = vm.selectedTeeBox else { return nil }
        return gh.teeYardsByTeeBox[tee.id]
    }

    private var gpsDistances: GreenDistances {
        guard let gh = currentCourseHole else { return GreenDistances() }
        return vm.location.greenDistances(
            front:  gh.greenFrontCoordinate?.clCoordinate,
            center: gh.greenCenterCoordinate?.clCoordinate,
            back:   gh.greenBackCoordinate?.clCoordinate
        )
    }

    private var displayYardage: Int? {
        if gpsOn, let gps = gpsDistances.center { return gps }
        return scorecardYardage
    }

    init(userId: UUID, backend: AppBackend,
         initialCourse: GolfCourse? = nil,
         initialTeeBox: TeeBox? = nil) {
        _vm = StateObject(wrappedValue: CourseRoundViewModel(userId: userId, backend: backend))
        self.initialCourse = initialCourse
        self.initialTeeBox = initialTeeBox
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Full-screen fairway background
            GeneratedFairwayView(landingFraction: 0.50, dispersionOffline: 0)
                .ignoresSafeArea()

            // Top + bottom dark gradient overlays
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [TCTheme.background.opacity(0.88), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 180)
                .ignoresSafeArea(edges: .top)
                Spacer()
                LinearGradient(
                    colors: [.clear, TCTheme.background.opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 240)
            }
            .ignoresSafeArea()

            // Top overlay bar
            topBar
                .padding(.top, topSafeArea)

            // Center content column
            VStack(spacing: 0) {
                Color.clear.frame(height: topSafeArea + 56)

                // Hole selector pill
                holeSelectorPill
                    .padding(.top, 8)

                // Plays Like yardage card (left) + GPS button (right) + yardage center
                ZStack(alignment: .center) {
                    playsLikeCard
                        .frame(width: 72)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)

                    yardageLabel

                    gpsPill
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 16)
                }
                .padding(.top, 24)

                Spacer()

                // Right tool rail
                rightToolRail
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .padding(.bottom, 260)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        // Player bottom panel via safeAreaInset
        .safeAreaInset(edge: .bottom, spacing: 0) {
            playerPanel
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        // Alerts & sheets
        .alert("Finish Round?", isPresented: $showFinishAlert) {
            Button("Finish & Save", role: .destructive) {
                Task { await vm.finishRound(); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your round will be saved.")
        }
        .alert("Course Tool", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen(
                shotCount: vm.activeRound?.shotIds.count ?? 0,
                context: buildContext(),
                onShotSaved: { shot in
                    Task { await vm.addShot(shot) }
                }
            )
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
        .sheet(isPresented: $showScoreEntry) {
            if let hole = vm.currentHole {
                ScoreEntryView(
                    holeNumber: hole.holeNumber,
                    par: hole.par,
                    existingScore: hole.score,
                    existingPutts: hole.putts,
                    holeYardage: scorecardYardage,
                    handicap: currentCourseHole?.handicap
                ) { s, p, f, g in
                    let idx = vm.currentHoleIndex
                    Task { await vm.setScore(holeIndex: idx, score: s, putts: p, fairwayHit: f, gir: g) }
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showScorecard) {
            if let round = vm.activeRound {
                NavigationStack {
                    ScorecardView(round: round, course: vm.selectedCourse)
                }
                .preferredColorScheme(.dark)
            }
        }
        .task {
            if let course = initialCourse, let tee = initialTeeBox {
                await vm.startRound(course: course, teeBox: tee)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { showFinishAlert = true } label: {
                ZStack {
                    Circle()
                        .fill(TCTheme.panelRaised.opacity(0.85))
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()
            TrueCarryLogo(size: 14)
            Spacer()

            Button { infoMessage = "Notifications will appear here when round events, challenges, or friend activity are connected." } label: {
                ZStack {
                    Circle()
                        .fill(TCTheme.panelRaised.opacity(0.85))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bell")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TCTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Hole Selector Pill

    private var holeSelectorPill: some View {
        HStack(spacing: 16) {
            Button {
                if vm.currentHoleIndex > 0 { vm.goToHole(vm.currentHoleIndex - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.gold)

                if let hole = vm.currentHole {
                    Text(ordinal(hole.holeNumber))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    let ydsStr = scorecardYardage.map { "  ·  \($0) yds" } ?? ""
                    Text("Par \(hole.par)\(ydsStr)  ·  HCP \(holeHandicap)")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                } else {
                    Text("Loading…")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
            }

            Button {
                if let round = vm.activeRound, vm.currentHoleIndex < round.holes.count - 1 {
                    vm.advanceHole()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.4))
        .background(TCTheme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(TCTheme.borderMedium, lineWidth: 1))
        .padding(.horizontal, TCTheme.hPad)
    }

    // MARK: - Plays Like Card

    private var playsLikeCard: some View {
        let dist = gpsDistances
        let hasGPS = gpsOn && dist.isAvailable
        return VStack(spacing: 3) {
            if hasGPS {
                if let f = dist.front {
                    Text("↑\(f)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                }
                if let c = dist.center {
                    Text("\(c)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                }
                if let b = dist.back {
                    Text("↓\(b)")
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.textMuted)
                }
            } else {
                Text(scorecardYardage.map { "\($0)" } ?? "—")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Scorecard")
                    .font(.system(size: 9))
                    .foregroundColor(TCTheme.textMuted)
            }
            Divider()
                .background(TCTheme.border)
                .padding(.vertical, 2)
            Text(hasGPS ? "GPS" : "Yards")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.gold)
                .tracking(1.5)
        }
        .padding(10)
        .background(TCTheme.panel.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Yardage Label

    private var yardageLabel: some View {
        VStack(spacing: 4) {
            Text(displayYardage.map { "\($0)" } ?? "—")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 2)
            let dist = gpsDistances
            if gpsOn && dist.isAvailable {
                let front = dist.front.map { "Front  \($0)" } ?? ""
                let back  = dist.back.map  { "Back  \($0)"  } ?? ""
                let sub   = [front, back].filter { !$0.isEmpty }.joined(separator: "  ·  ")
                if !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textSecondary)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            } else if let yds = scorecardYardage {
                Text("Scorecard  ·  \(yds) yds")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textSecondary)
                    .shadow(color: .black.opacity(0.5), radius: 3)
            }
        }
    }

    // MARK: - GPS Pill

    private var gpsPill: some View {
        Button { gpsOn.toggle() } label: {
            VStack(spacing: 3) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16))
                    .foregroundColor(gpsOn ? TCTheme.sage : TCTheme.textMuted)
                Text("GPS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(TCTheme.gold)
            }
            .frame(width: 44, height: 44)
            .background(TCTheme.panelRaised.opacity(0.86))
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(gpsOn ? TCTheme.sage.opacity(0.5) : TCTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Tool Rail

    private var rightToolRail: some View {
        VStack(spacing: 8) {
            toolButton("ruler.fill",           "Measure")
            toolButton("target",               "Targets")
            toolButton("arrow.down.to.line",   "Layup")
            toolButton("circle.fill",          "Green")
        }
        .padding(.trailing, 4)
    }

    private func toolButton(_ icon: String, _ label: String) -> some View {
        Button { infoMessage = "\(label) is ready for the course overlay once GPS target data is available." } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TCTheme.textSecondary)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
            }
            .frame(width: 42, height: 42)
            .background(TCTheme.panelRaised.opacity(0.82))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Player Bottom Panel

    private var playerPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Player info row
                HStack(spacing: 12) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(TCTheme.panelRaised)
                            .frame(width: 36, height: 36)
                        Circle()
                            .strokeBorder(TCTheme.borderGold, lineWidth: 1.5)
                            .frame(width: 36, height: 36)
                        Text(userInitials)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(TCTheme.gold)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(userName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(TCTheme.textPrimary)

                        let diff = (vm.activeRound?.scoreSummary.totalScore ?? 0)
                                 - (vm.activeRound?.scoreSummary.totalPar ?? 0)
                        let holeCount = vm.activeRound?.holes.count ?? 18
                        HStack(spacing: 4) {
                            Text(diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)")
                                .font(.system(size: 12))
                                .foregroundColor(diff < 0 ? TCTheme.sage : diff == 0 ? TCTheme.cyan : TCTheme.textMuted)
                            Text("·  Hole \(vm.currentHoleIndex + 1)/\(holeCount)")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("0:42")
                            .font(.system(size: 13))
                            .foregroundColor(TCTheme.textMuted)
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                    }
                }
                .padding(.top, 4)

                // Hit Shot button
                TCPrimaryGoldButton(title: "Hit Shot", icon: "camera.fill") {
                    showCamera = true
                }

                // Mini bottom tabs
                HStack(spacing: 0) {
                    miniTabButton("Scorecard", "list.number") { showScorecard = true }
                    miniTabButton("Score",     "pencil")      { showScoreEntry = true }
                    miniTabButton("Notes",     "note.text")   { infoMessage = "Round notes will be stored with this round once notes are added to the backend schema." }
                    miniTabButton("GPS \(gpsOn ? "ON" : "OFF")", "location.fill") { gpsOn.toggle() }
                }
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial.opacity(0.3))
            .background(TCTheme.panel.opacity(0.95))
            .overlay(Rectangle().fill(TCTheme.border).frame(height: 1), alignment: .top)
        }
    }

    private func miniTabButton(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(TCTheme.textMuted)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func buildContext() -> ShotContext {
        ShotContext(
            sourceMode: .course,
            courseRoundId: vm.activeRound?.id,
            holeNumber: vm.currentHole?.holeNumber,
            holePar: vm.currentHole?.par,
            holeYardage: scorecardYardage,
            courseName: vm.activeRound?.courseName,
            holeHandicap: holeHandicap
        )
    }

    private var holeHandicap: Int {
        guard let hole = vm.currentHole,
              let gh = vm.selectedCourse?.holes.first(where: { $0.number == hole.holeNumber })
        else { return vm.currentHole?.par == 3 ? 9 : 7 }
        return gh.handicap ?? 9
    }

    private var userName: String {
        session.userProfile?.displayName ?? "Player"
    }

    private var userInitials: String {
        let name = userName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "P")).uppercased()
                 + String((parts[1].first ?? "L")).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var topSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
