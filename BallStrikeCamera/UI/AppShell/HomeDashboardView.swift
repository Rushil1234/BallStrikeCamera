import SwiftUI

// MARK: - Mock data (unique IDs)

private struct RecentShotMock: Identifiable {
    let id = UUID()
    let club: String
    let carry: String
    let total: String
    let ballSpeed: String
    let ago: String
}

private struct FriendActivityMock: Identifiable {
    let id = UUID()
    let name: String
    let action: String
    let metric: String
    let ago: String
}

// MARK: - View

struct HomeDashboardView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var showCamera  = false
    @State private var showRange   = false
    @State private var showSim     = false
    @State private var showCourse  = false
    @State private var showProfile = false

    private var firstName: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "Golfer"
        return name.components(separatedBy: " ").first ?? name
    }

    private let recentShots: [RecentShotMock] = [
        RecentShotMock(club: "Driver", carry: "241",  total: "263", ballSpeed: "148", ago: "2h ago"),
        RecentShotMock(club: "7 Iron", carry: "164",  total: "171", ballSpeed: "112", ago: "2h ago"),
        RecentShotMock(club: "PW",     carry: "108",  total: "112", ballSpeed: "94",  ago: "Yesterday"),
        RecentShotMock(club: "6 Iron", carry: "178",  total: "184", ballSpeed: "119", ago: "Yesterday"),
    ]

    private let friendActivity: [FriendActivityMock] = [
        FriendActivityMock(name: "Landon",  action: "hit a massive drive",       metric: "284 yd", ago: "30m ago"),
        FriendActivityMock(name: "Kevin",   action: "finished a range session",  metric: "22 shots", ago: "1h ago"),
        FriendActivityMock(name: "Marcus",  action: "shot a new best",           metric: "78 score", ago: "3h ago"),
    ]

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: BSTheme.sectionGap) {
                    headerView
                    heroCard
                    quickModeRow
                    recentShotsSection
                    friendsSection
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, BSTheme.hPad)
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
        .fullScreenCover(isPresented: $showRange)  { RangeModeView()  }
        .sheet(isPresented: $showSim) {
            if let uid = session.currentUser?.id {
                SimModeView(userId: uid, backend: session.backend)
            }
        }
        .sheet(isPresented: $showCourse)           { EmptyView() } // Course flow lives in TrueCarryPlayView
        .sheet(isPresented: $showProfile) {
            NavigationStack { TrueCarryProfileView() }
                .tcAppearance()
        }
    }

    // MARK: Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hey, \(firstName) 👋")
                    .font(.system(size: 30, weight: .black))
                    .foregroundColor(BSTheme.textPrimary)
                Text("Launch monitor · Golf performance")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            Button { showProfile = true } label: {
                Circle()
                    .fill(BSTheme.panel)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "person.circle")
                            .font(.system(size: 20))
                            .foregroundColor(BSTheme.textSecondary)
                    )
                    .overlay(Circle().strokeBorder(BSTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    // MARK: Hero Card

    private var heroCard: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 18) {
                // Top accent line
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [BSTheme.electricCyan, BSTheme.fairwayGreen],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Text("Ready to capture?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(BSTheme.textPrimary)
                Text("Track ball flight, replay impact, and review full launch metrics in real time.")
                    .font(.system(size: 14))
                    .foregroundColor(BSTheme.textSecondary)
                    .lineSpacing(3)

                // Status pills
                HStack(spacing: 8) {
                    StatusPill(text: "240 FPS",      color: BSTheme.electricCyan)
                    StatusPill(text: "Trained VLA",  color: BSTheme.fairwayGreen)
                    StatusPill(text: "Replay Ready", color: BSTheme.gold)
                }

                VStack(spacing: 10) {
                    PremiumActionButton(
                        title: "Quick Start Live Shot",
                        icon: "camera.fill",
                        style: .gradient(BSTheme.rangeGradient),
                        action: { showCamera = true }
                    )
                    .glowingAccent(BSTheme.electricCyan, radius: 18)

                    PremiumActionButton(
                        title: "Simulate Shot",
                        icon: "sparkles",
                        style: .ghost,
                        action: { showCamera = true }
                    )
                }
            }
        }
    }

    // MARK: Quick Mode Row

    private var quickModeRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Modes")
            HStack(spacing: 10) {
                quickModeButton(icon: "target", label: "Range", gradient: BSTheme.rangeGradient) { showRange = true }
                quickModeButton(icon: "display",  label: "Sim",   gradient: BSTheme.simGradient)   { showSim = true }
                quickModeButton(icon: "flag.fill", label: "Course",gradient: BSTheme.courseGradient){ showCourse = true }
            }
        }
    }

    private func quickModeButton(
        icon: String, label: String, gradient: LinearGradient, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(gradient)
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(BSTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(BSTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Recent Shots

    private var recentShotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(
                title: "Recent Shots",
                trailing: AnyView(
                    Button("See All") {}
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSTheme.electricCyan)
                )
            )
            VStack(spacing: 8) {
                ForEach(recentShots) { shot in
                    recentShotRow(shot)
                }
            }
        }
    }

    private func recentShotRow(_ shot: RecentShotMock) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BSTheme.electricCyan.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 15))
                    .foregroundColor(BSTheme.electricCyan)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(shot.club)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text(shot.ago)
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            HStack(spacing: 18) {
                metricPair(value: shot.total, unit: "yd", label: "total")
                metricPair(value: shot.ballSpeed, unit: "mph", label: "ball spd")
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BSTheme.border, lineWidth: 1)
        )
    }

    private func metricPair(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(BSTheme.textPrimary)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(BSTheme.textMuted)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(BSTheme.textMuted)
        }
    }

    // MARK: Friends Activity

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Friends Activity")
            VStack(spacing: 8) {
                ForEach(friendActivity) { item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(BSTheme.fairwayGreen.opacity(0.16))
                            .frame(width: 38, height: 38)
                            .overlay(
                                Text(String(item.name.prefix(1)))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(BSTheme.fairwayGreen)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BSTheme.textPrimary)
                                Text(item.action)
                                    .font(.system(size: 13))
                                    .foregroundColor(BSTheme.textSecondary)
                            }
                            .lineLimit(1)
                            Text(item.ago)
                                .font(.system(size: 11))
                                .foregroundColor(BSTheme.textMuted)
                        }
                        Spacer()
                        Text(item.metric)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(BSTheme.fairwayGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BSTheme.fairwayGreen.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(BSTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(BSTheme.border, lineWidth: 1)
                    )
                }
            }
        }
    }
}
