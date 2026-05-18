import SwiftUI

struct RoundSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore
    @State private var leaderboardEnabled = false
    @State private var showSettingsInfo = false

    let course: GolfCourse
    let teeBox: TeeBox
    let onStart: () -> Void

    var body: some View {
        ZStack {
            TrueCarryBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    // MARK: Header Row
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(TCTheme.textMuted)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                        TrueCarryLogo(size: 18)
                        Spacer()
                        Spacer(minLength: 36)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)

                    // MARK: Title Area
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Round Setup")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("Review your settings and start your round.")
                            .font(.system(size: 14))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TCTheme.hPad)

                    // MARK: Course Card
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(TCTheme.sageGradient)
                                .frame(width: 56, height: 56)
                            Image(systemName: "flag.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.65))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(course.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(TCTheme.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(TCTheme.sage)
                                Text(course.city + ", " + course.state)
                                    .font(.system(size: 12))
                                    .foregroundColor(TCTheme.textMuted)
                            }

                            HStack(spacing: 8) {
                                TCPill(text: teeBox.name + " Tees", color: TCTheme.sage)
                                TCPill(text: "\(teeBox.totalYards) yds", color: TCTheme.gold)
                            }

                            if let rating = teeBox.rating, let slope = teeBox.slope {
                                Text(String(format: "Rating %.1f / Slope %d", rating, slope))
                                    .font(.system(size: 11))
                                    .foregroundColor(TCTheme.textMuted)
                            }
                        }

                        Spacer()
                    }
                    .tcCard()
                    .padding(.horizontal, TCTheme.hPad)

                    // MARK: Leaderboard Card
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(TCTheme.goldGradient)
                                .frame(width: 40, height: 40)
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Leaderboard")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(TCTheme.textPrimary)
                            Text("Compete with friends on the leaderboard.")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                        }

                        Spacer()

                        Toggle("", isOn: $leaderboardEnabled)
                            .tint(TCTheme.sage)
                            .labelsHidden()
                    }
                    .tcCard()
                    .padding(.horizontal, TCTheme.hPad)

                    // MARK: Round Settings Card
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ROUND SETTINGS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(TCTheme.gold)
                            .tracking(2)
                            .padding(.bottom, 8)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        TCSettingsRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Tracking",
                            value: "Automatic",
                            accent: TCTheme.sage
                        )
                        TCDivider()
                        TCSettingsRow(
                            icon: "location.circle.fill",
                            title: "Rangefinder",
                            value: "Phone GPS",
                            accent: TCTheme.cyan
                        )
                        TCDivider()
                        TCSettingsRow(
                            icon: "info.circle.fill",
                            title: "Info Displayed",
                            value: "3 Items",
                            accent: TCTheme.gold
                        )
                        TCDivider()
                        TCSettingsRow(
                            icon: "star.circle.fill",
                            title: "Events & Challenges",
                            value: "2 Active",
                            accent: TCTheme.gold
                        )
                        .padding(.bottom, 4)
                    }
                    .background(TCTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                            .strokeBorder(TCTheme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, TCTheme.hPad)

                    // MARK: Start Round Button
                    TCPrimaryGoldButton(title: "Start Round", icon: "flag.fill") {
                        onStart()
                    }
                    .padding(.horizontal, TCTheme.hPad)

                    // MARK: Edit Settings Button
                    TCOutlineButton(title: "Edit Settings", color: TCTheme.textMuted) {
                        showSettingsInfo = true
                    }
                        .padding(.horizontal, TCTheme.hPad)

                    Spacer(minLength: 60)
                }
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(true)
        .alert("Round Settings", isPresented: $showSettingsInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tracking, rangefinder, and event settings are shown above. Leaderboard is \(leaderboardEnabled ? "on" : "off") for this setup.")
        }
    }
}
