import SwiftUI

private struct MockHole: Identifiable {
    let id = UUID()
    let number: Int
    let par: Int
    let yards: Int
    let score: Int?
}

struct CourseModeView: View {
    @EnvironmentObject var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showRound = false
    @State private var showCamera = false

    private let holes: [MockHole] = [
        MockHole(number: 1, par: 4, yards: 382, score: nil),
        MockHole(number: 2, par: 3, yards: 168, score: nil),
        MockHole(number: 3, par: 5, yards: 523, score: nil),
        MockHole(number: 4, par: 4, yards: 388, score: nil),
        MockHole(number: 5, par: 4, yards: 401, score: nil),
        MockHole(number: 6, par: 3, yards: 142, score: nil),
        MockHole(number: 7, par: 5, yards: 541, score: nil),
        MockHole(number: 8, par: 4, yards: 375, score: nil),
        MockHole(number: 9, par: 4, yards: 418, score: nil),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BSTheme.sectionGap) {
                        subheader
                        courseSelectorCard
                        currentHoleCard
                        scorecard
                        actionSection
                        comingSoonNote
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, BSTheme.hPad)
                    .padding(.top, 4)
                }
            }
            .navigationTitle("Course Mode")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(BSTheme.gold)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showRound) {
            if let uid = session.currentUser?.id {
                NavigationStack {
                    CourseRoundView(userId: uid, backend: session.backend)
                }
                .preferredColorScheme(.dark)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen(context: ShotContext(sourceMode: .course))
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
    }

    private var subheader: some View {
        Text("Track every shot on-course with real-time club recommendations.")
            .font(.system(size: 14))
            .foregroundColor(BSTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var courseSelectorCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BSTheme.courseGradient)
                    .frame(width: 46, height: 46)
                Image(systemName: "map.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Pebble Beach Golf Links")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text("Blue Tees · Par 72 · 6,386 yd")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            Text("Change")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSTheme.gold)
        }
        .premiumCard(padding: 14)
    }

    private var currentHoleCard: some View {
        VStack(spacing: 0) {
            // Gradient top accent
            LinearGradient(colors: [BSTheme.gold, BSTheme.fairwayGreen], startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
                .clipShape(
                    UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 22)
                )

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Hole")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(BSTheme.textMuted)
                            .tracking(1)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("1")
                                .font(.system(size: 44, weight: .black, design: .monospaced))
                                .foregroundColor(BSTheme.textPrimary)
                            Text("of 18")
                                .font(.system(size: 15))
                                .foregroundColor(BSTheme.textMuted)
                        }
                    }
                    Spacer()
                    VStack(spacing: 10) {
                        holeStatBadge(value: "Par 4",   accent: BSTheme.fairwayGreen)
                        holeStatBadge(value: "382 yd",  accent: BSTheme.gold)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(BSTheme.gold)
                        .font(.system(size: 13))
                    Text("Recommended: Driver off the tee")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(BSTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(BSTheme.gold.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BSTheme.gold.opacity(0.30), lineWidth: 1)
                )

                // Mini scorecard stats
                HStack(spacing: 0) {
                    scoreStat(label: "Score", value: "—")
                    Divider().background(BSTheme.border).frame(height: 30)
                    scoreStat(label: "Fairways", value: "—")
                    Divider().background(BSTheme.border).frame(height: 30)
                    scoreStat(label: "GIR", value: "—")
                    Divider().background(BSTheme.border).frame(height: 30)
                    scoreStat(label: "Putts", value: "—")
                }
                .padding(.vertical, 8)
                .background(BSTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(18)
            .background(BSTheme.panel)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(BSTheme.border, lineWidth: 1)
        )
        .shadow(color: BSTheme.gold.opacity(0.12), radius: 16, x: 0, y: 6)
    }

    private func holeStatBadge(value: String, accent: Color) -> some View {
        Text(value)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(accent.opacity(0.35), lineWidth: 1))
    }

    private func scoreStat(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(BSTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(BSTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var scorecard: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Front 9 Scorecard")
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Hole").frame(width: 40, alignment: .leading)
                    Text("Par").frame(width: 36, alignment: .center)
                    Text("Yards").frame(width: 56, alignment: .center)
                    Spacer()
                    Text("Score").frame(width: 50, alignment: .center)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(BSTheme.panelRaised)

                ForEach(holes) { h in
                    HStack {
                        Text("\(h.number)")
                            .frame(width: 40, alignment: .leading)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(h.number == 1 ? BSTheme.gold : BSTheme.textPrimary)
                        Text("\(h.par)")
                            .frame(width: 36, alignment: .center)
                            .font(.system(size: 13))
                            .foregroundColor(BSTheme.textSecondary)
                        Text("\(h.yards)")
                            .frame(width: 56, alignment: .center)
                            .font(.system(size: 13))
                            .foregroundColor(BSTheme.textSecondary)
                        Spacer()
                        Text("—")
                            .frame(width: 50, alignment: .center)
                            .font(.system(size: 13))
                            .foregroundColor(BSTheme.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(h.number % 2 == 0 ? BSTheme.panelRaised.opacity(0.5) : Color.clear)

                    if h.number < 9 {
                        BSDivider()
                    }
                }
            }
            .background(BSTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                    .strokeBorder(BSTheme.border, lineWidth: 1)
            )
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            PremiumActionButton(
                title: "Start Round",
                icon: "flag.fill",
                style: .gradient(BSTheme.courseGradient),
                action: { showRound = true }
            )
            PremiumActionButton(
                title: "Track Shot",
                icon: "camera.fill",
                style: .ghost,
                action: { showCamera = true }
            )
        }
    }

    private var comingSoonNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "map")
                .foregroundColor(BSTheme.gold)
            Text("GPS course library and automatic scoring coming soon.")
                .font(.system(size: 12))
                .foregroundColor(BSTheme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(BSTheme.gold.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(BSTheme.gold.opacity(0.25), lineWidth: 1)
        )
    }
}
