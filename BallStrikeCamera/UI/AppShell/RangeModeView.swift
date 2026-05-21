import SwiftUI

private struct RangeShotMock: Identifiable {
    let id = UUID()
    let club: String
    let carry: Int
    let ballSpeed: Int
    let smash: Double
    let ago: String
}

struct RangeModeView: View {
    @EnvironmentObject var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera   = false
    @State private var showSession  = false
    @State private var selectedClub = "7 Iron"

    private let clubs = ["Driver","3W","5W","4I","5I","6I","7I","8I","9I","PW","GW","SW","LW"]
    private let shotHistory: [RangeShotMock] = [
        RangeShotMock(club: "7 Iron", carry: 162, ballSpeed: 112, smash: 1.44, ago: "2h ago"),
        RangeShotMock(club: "7 Iron", carry: 158, ballSpeed: 110, smash: 1.42, ago: "2h ago"),
        RangeShotMock(club: "7 Iron", carry: 165, ballSpeed: 114, smash: 1.45, ago: "3h ago"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                ScrollView(showsIndicators: false) {

                    VStack(spacing: BSTheme.sectionGap) {
                        clubPickerSection
                        actionSection
                        statsGrid
                        shotHistorySection
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, BSTheme.hPad)
                    .padding(.top, 4)
                }
            }
            .navigationTitle("Range Mode")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(BSTheme.electricCyan)
                        .fontWeight(.semibold)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                RangeCameraScreen().ignoresSafeArea().statusBarHidden(true)
            }
            .sheet(isPresented: $showSession) {
                if let uid = session.currentUser?.id {
                    NavigationStack {
                        RangeSessionView(userId: uid, backend: session.backend)
                    }
                    .tcAppearance()
                }
            }
            .onAppear {
                print("Navigating to RangeModeView")
                OrientationManager.shared.lockPortrait()
            }
        }
        .tcAppearance()
    }

    // MARK: Club Picker

    private var clubPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Club Selection")
            // Selected club card
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(BSTheme.rangeGradient)
                        .frame(width: 52, height: 52)
                    Image(systemName: "figure.golf")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedClub)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(BSTheme.textPrimary)
                    Text("Selected club")
                        .font(.system(size: 12))
                        .foregroundColor(BSTheme.textMuted)
                }
                Spacer()
                StatusPill(text: "Change", color: BSTheme.electricCyan)
            }
            .premiumCard(padding: 14)

            // Chip row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(clubs, id: \.self) { c in
                        Button { selectedClub = fullName(c) } label: {
                            Text(c)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectedClub == fullName(c) ? .black : BSTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    selectedClub == fullName(c)
                                        ? AnyView(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(BSTheme.rangeGradient))
                                        : AnyView(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(BSTheme.panel))
                                )
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(BSTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Actions

    private var actionSection: some View {
        VStack(spacing: 10) {
            PremiumActionButton(
                title: "Open Camera",
                icon: "camera.fill",
                style: .gradient(BSTheme.rangeGradient),
                action: { showCamera = true }
            )
            .glowingAccent(BSTheme.electricCyan)
            HStack(spacing: 10) {
                PremiumActionButton(
                    title: "Simulate Shot",
                    icon: "sparkles",
                    style: .ghost,
                    action: { showCamera = true }
                )
                PremiumActionButton(
                    title: "Start Session",
                    icon: "play.circle.fill",
                    style: .accent(BSTheme.fairwayGreen),
                    action: { showSession = true }
                )
            }
        }
    }

    // MARK: Stats Grid

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Session Averages")
            HStack(spacing: 10) {
                StatTile(label: "Avg Carry", value: "162", unit: "yd", icon: "arrow.up.right", accent: BSTheme.electricCyan)
                StatTile(label: "Avg Total", value: "170", unit: "yd", icon: "flag", accent: BSTheme.fairwayGreen)
            }
            HStack(spacing: 10) {
                StatTile(label: "Ball Speed", value: "112", unit: "mph", icon: "speedometer", accent: BSTheme.gold)
                StatTile(label: "Dispersion", value: "±9",  unit: "yd",  icon: "scope",       accent: BSTheme.simPurple)
            }
        }
    }

    // MARK: Shot History

    private var shotHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Recent Shots")
            VStack(spacing: 8) {
                ForEach(shotHistory) { shot in
                    ActivityRow(
                        icon: "circle.inset.filled",
                        title: shot.club,
                        subtitle: shot.ago,
                        stat: "\(shot.carry)",
                        statUnit: "yd",
                        accent: BSTheme.electricCyan
                    )
                }
            }
        }
    }

    private func fullName(_ abbrev: String) -> String {
        let map = ["3W":"3 Wood","5W":"5 Wood","4I":"4 Iron","5I":"5 Iron","6I":"6 Iron",
                   "7I":"7 Iron","8I":"8 Iron","9I":"9 Iron","PW":"PW","GW":"GW","SW":"SW","LW":"LW"]
        return map[abbrev] ?? abbrev
    }
}
