import SwiftUI

struct CourseRoundView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: CourseRoundViewModel
    @State private var showSearch = false
    @State private var showScorecard = false
    @State private var showFinishAlert = false

    init(userId: UUID, backend: AppBackend) {
        _vm = StateObject(wrappedValue: CourseRoundViewModel(userId: userId, backend: backend))
    }

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            if vm.roundActive {
                activeRoundView
            } else {
                startRoundView
            }
        }
        .navigationTitle("Course Mode")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    if vm.roundActive { showFinishAlert = true }
                    else { dismiss() }
                }
                .foregroundColor(BSTheme.textMuted)
            }
            if vm.roundActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScorecard = true
                    } label: {
                        Image(systemName: "list.number")
                            .foregroundColor(BSTheme.electricCyan)
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            CourseSearchView(userId: vm.location.currentLocation != nil ? UUID() : UUID()) { course, tee in
                Task { await vm.startRound(course: course, teeBox: tee) }
            }
        }
        .sheet(isPresented: $showScorecard) {
            if let round = vm.activeRound {
                ScorecardView(round: round, course: vm.selectedCourse)
            }
        }
        .alert("Finish Round?", isPresented: $showFinishAlert) {
            Button("Finish & Save", role: .destructive) {
                Task { await vm.finishRound(); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Start Round

    private var startRoundView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: BSTheme.sectionGap) {
                VStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 44))
                        .foregroundColor(BSTheme.fairwayGreen)
                        .glowingAccent(BSTheme.fairwayGreen, radius: 28)
                    Text("Start a Round")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(BSTheme.textPrimary)
                    Text("Search for a course to begin tracking your round with launch monitor data.")
                        .font(.system(size: 14))
                        .foregroundColor(BSTheme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                PremiumActionButton(
                    title: "Find a Course",
                    icon: "magnifyingglass",
                    style: .gradient(BSTheme.courseGradient),
                    action: { showSearch = true }
                )
                Spacer(minLength: 32)
            }
            .padding(.horizontal, BSTheme.hPad)
        }
    }

    // MARK: - Active Round

    private var activeRoundView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: BSTheme.sectionGap) {
                roundHeader
                if let idx = vm.activeRound.map({ _ in vm.currentHoleIndex }),
                   let round = vm.activeRound,
                   idx < round.holes.count {
                    HoleView(
                        hole: round.holes[idx],
                        golfHole: vm.selectedCourse?.holes.first { $0.number == round.holes[idx].holeNumber },
                        teeBox: vm.selectedTeeBox,
                        location: vm.location,
                        onScoreSet: { score, putts, fairway, gir in
                            Task {
                                await vm.setScore(
                                    holeIndex: idx,
                                    score: score,
                                    putts: putts,
                                    fairwayHit: fairway,
                                    gir: gir
                                )
                            }
                        }
                    )
                    holeNavigator
                }
                Spacer(minLength: 32)
            }
            .padding(.horizontal, BSTheme.hPad)
            .padding(.top, 4)
        }
    }

    private var roundHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.activeRound?.courseName ?? "")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(BSTheme.textPrimary)
                Text("\(vm.selectedTeeBox?.name ?? "") Tees")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                let summary = vm.activeRound?.scoreSummary
                let diff = (summary?.totalScore ?? 0) - (summary?.totalPar ?? 0)
                Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(diff < 0 ? BSTheme.fairwayGreen : (diff == 0 ? BSTheme.electricCyan : BSTheme.textPrimary))
                Text("score to par")
                    .font(.system(size: 11))
                    .foregroundColor(BSTheme.textMuted)
            }
        }
    }

    private var holeNavigator: some View {
        HStack(spacing: 12) {
            Button {
                if vm.currentHoleIndex > 0 { vm.goToHole(vm.currentHoleIndex - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(vm.currentHoleIndex > 0 ? BSTheme.electricCyan : BSTheme.textMuted)
                    .frame(width: 44, height: 44)
                    .background(BSTheme.panel)
                    .clipShape(Circle())
            }
            .disabled(vm.currentHoleIndex == 0)
            .buttonStyle(.plain)

            Spacer()

            if let count = vm.activeRound?.holes.count, vm.currentHoleIndex < count - 1 {
                Button {
                    vm.advanceHole()
                } label: {
                    Text("Next Hole")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(BSTheme.fairwayGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showFinishAlert = true
                } label: {
                    Text("Finish Round")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(BSTheme.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                if let count = vm.activeRound?.holes.count,
                   vm.currentHoleIndex < count - 1 {
                    vm.goToHole(vm.currentHoleIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSTheme.electricCyan)
                    .frame(width: 44, height: 44)
                    .background(BSTheme.panel)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
