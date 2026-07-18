import SwiftUI

// MARK: - Tab Enum

enum TCTab: Int, CaseIterable {
    case home = 0, insights = 1, play = 2, history = 3, locker = 4

    var label: String {
        switch self {
        case .home:     return "Feed"
        case .insights: return "Insights"
        case .play:     return "Play"
        case .history:  return "History"
        case .locker:   return "Locker"
        }
    }
    var icon: String {
        switch self {
        case .home:     return "newspaper.fill"
        case .insights: return "chart.bar.xaxis"
        case .play:     return "flag.fill"
        case .history:  return "clock.fill"
        case .locker:   return "person.crop.circle.fill"
        }
    }
    var isCenter: Bool { self == .play }
}

// MARK: - Bottom Dock

struct TCBottomDock: View {
    @Binding var selectedTab: TCTab
    @Environment(\.safeAreaInsets) private var safeInsets

    private var bottomPadding: CGFloat { max(safeInsets.bottom, 6) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(TCTab.allCases, id: \.rawValue) { tab in
                if tab.isCenter {
                    centerPlayButton(tab)
                } else {
                    dockItem(tab)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, bottomPadding)
        .background(
            Rectangle()
                .fill(TCTheme.dockBackground)
                .overlay(Rectangle().fill(TCTheme.borderMedium).frame(height: 1), alignment: .top)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: -3)
    }

    // MARK: Standard tab item

    private func dockItem(_ tab: TCTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textSecondary.opacity(0.75))
                Text(tab.label)
                    .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textSecondary.opacity(0.75))
                Rectangle()
                    .fill(selected ? TCTheme.gold : Color.clear)
                    .frame(width: selected ? 18 : 0, height: 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .animation(.easeInOut(duration: 0.20), value: selected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: Centered Play button

    private func centerPlayButton(_ tab: TCTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selectedTab = tab }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(selected ? TCTheme.goldGradient : LinearGradient(
                            colors: [TCTheme.panel, TCTheme.panelRaised],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 50, height: 50)
                        .shadow(color: selected ? TCTheme.gold.opacity(0.40) : Color.black.opacity(0.30),
                                radius: selected ? 8 : 4, x: 0, y: 2)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    selected ? TCTheme.gold.opacity(0.50) : TCTheme.borderMedium,
                                    lineWidth: 1
                                )
                        )

                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(selected ? .white : TCTheme.textSecondary.opacity(0.85))
                }
                .offset(y: -4)

                Text(tab.label)
                    .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                    .foregroundColor(selected ? TCTheme.gold : TCTheme.textSecondary.opacity(0.75))
                    .offset(y: -4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Safe Area Insets (environment key)

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets = .init()
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

// MARK: - App Shell

struct TrueCarryAppShell: View {
    @State private var selectedTab: TCTab = .home
    @State private var showUsernameSetup = false
    @State private var didPromptUsername = false
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController
    @ObservedObject private var roundBeacon = ActiveRoundBeacon.shared
    /// Round opened by tapping the banner — presented from the shell so it works on any tab.
    @State private var bannerRound: CourseRound?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                tabContent
                    .ignoresSafeArea(edges: .bottom)
                    .environment(\.safeAreaInsets, geo.safeAreaInsets)

                VStack(spacing: 0) {
                    Spacer()
                    TCBottomDock(selectedTab: $selectedTab)
                        .environment(\.safeAreaInsets, geo.safeAreaInsets)
                }
                .ignoresSafeArea(.keyboard)
                .ignoresSafeArea(edges: .bottom)

                // Weekly-goal / course-unlock celebration toasts, above everything.
                // (Transparent when idle — empty space passes touches through.)
                GoalCelebrationOverlay()
            }
            .overlay(alignment: .top) {
                // "Round in progress" — shown whenever a live round exists and course mode
                // itself is off screen; tapping jumps back into the round.
                if let round = roundBeacon.round, !roundBeacon.courseViewVisible {
                    activeRoundBanner(round)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.8),
                       value: roundBeacon.round == nil || roundBeacon.courseViewVisible)
        }
        .background(TCTheme.background.ignoresSafeArea())
        .tcAppearance()
        .sheet(isPresented: $showUsernameSetup) {
            NavigationStack { TCEditProfileSheet() }.tcAppearance()
        }
        .fullScreenCover(item: $bannerRound) { round in
            CourseModeGPSHoleView(
                userId: session.currentUser?.id ?? UUID(),
                backend: session.backend,
                initialRound: round
            )
        }
        .task {
            // Seed the round-in-progress banner on cold start — course mode isn't running
            // yet to set the beacon itself.
            guard let uid = session.currentUser?.id, ActiveRoundBeacon.shared.round == nil,
                  !ActiveRoundBeacon.shared.courseViewVisible else { return }
            let all = (try? await session.backend.loadCourseRounds(userId: uid)) ?? []
            if !ActiveRoundBeacon.shared.courseViewVisible {
                ActiveRoundBeacon.shared.round = all.first(where: { $0.endedAt == nil })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tcOpenLiveSim)) { _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selectedTab = .play }
        }
        // QR sim pairing: published value re-emits on subscribe, so this fires even
        // when the deep link arrived before this view existed (cold start / login).
        .onReceive(DeepLinkRouter.shared.$pendingSimCode) { code in
            guard code != nil else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selectedTab = .play }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tcResumeRound)) { _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selectedTab = .play }
        }
        .onAppear(perform: maybePromptUsername)
        .onChange(of: session.userProfile?.username) { _ in maybePromptUsername() }
    }

    /// Tap-to-return pill for a round in progress. Posting `.tcResumeRound` lands on the
    /// Play tab, which reloads the unfinished round and reopens course mode fullscreen.
    private func activeRoundBanner(_ round: CourseRound) -> some View {
        let holeNumber = round.holes.first(where: { $0.score == nil })?.holeNumber
        return Button {
            bannerRound = round
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TCTheme.gold)
                VStack(alignment: .leading, spacing: 1) {
                    Text(holeNumber.map { "Round in progress · Hole \($0)" } ?? "Round in progress")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(round.courseName) — tap to return")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(red: 0.10, green: 0.23, blue: 0.13)))
            .overlay(Capsule().strokeBorder(TCTheme.gold.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    /// One-time-per-launch nudge to pick a username so the app shows @handles instead of email.
    private func maybePromptUsername() {
        guard !didPromptUsername,
              session.currentUser != nil,
              session.userProfile != nil,
              (session.userProfile?.username ?? "").isEmpty else { return }
        didPromptUsername = true
        showUsernameSetup = true
    }

    @ViewBuilder
    private var tabContent: some View {
        // .tcGuide sits on each tab's ROOT view (not the stack) so the tour and its ⓘ
        // button scope to that page and disappear when a child view is pushed.
        switch selectedTab {
        case .home:
            NavigationStack { FeedHomeView().tcGuide(.home) }
        case .insights:
            NavigationStack { TrueCarryInsightsView().tcGuide(.insights) }
        case .play:
            NavigationStack { TrueCarryPlayView().tcGuide(.play) }
        case .history:
            NavigationStack { TrueCarryHistoryView().tcGuide(.history) }
        case .locker:
            NavigationStack { TrueCarryLockerView().tcGuide(.locker) }
        }
    }
}
