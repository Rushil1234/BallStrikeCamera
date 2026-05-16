import SwiftUI

struct ModeSelectionView: View {
    @State private var showRange  = false
    @State private var showSim    = false
    @State private var showCourse = false

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: BSTheme.cardGap + 4) {
                    headerSection
                    BSModeCard(
                        icon: "target",
                        title: "Range Mode",
                        subtitle: "Practice freely. Track carry, ball speed, spin, and club path for every shot. Review frame-by-frame replay.",
                        gradient: BSTheme.rangeGradient,
                        chips: ["Metrics", "Replay", "Sessions"],
                        action: { showRange = true }
                    )
                    .glowingAccent(BSTheme.electricCyan, radius: 20)

                    BSModeCard(
                        icon: "display",
                        title: "Simulator Mode",
                        subtitle: "Send shot data to GSPro, OGS, or any OpenAPI-compatible simulator over WiFi.",
                        gradient: BSTheme.simGradient,
                        chips: ["JSON Output", "WiFi", "OpenAPI"],
                        action: { showSim = true }
                    )

                    BSModeCard(
                        icon: "flag.fill",
                        title: "Course Mode",
                        subtitle: "Track every shot in a real round. Automatic hole-by-hole scoring with club recommendations.",
                        gradient: BSTheme.courseGradient,
                        chips: ["Scorecard", "Caddie", "Rounds"],
                        action: { showCourse = true }
                    )
                    .glowingAccent(BSTheme.gold, radius: 18)

                    comingSoonNote
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, BSTheme.hPad)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Modes")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .fullScreenCover(isPresented: $showRange)  { RangeModeView()  }
        .sheet(isPresented: $showSim)              { SimModeView()    }
        .sheet(isPresented: $showCourse)           { CourseModeView() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Choose your experience.")
                .font(.system(size: 15))
                .foregroundColor(BSTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var comingSoonNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(BSTheme.gold)
            Text("Sim and Course modes are coming soon. Range Mode is fully active.")
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
