import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var showClubs = false

    private var profile: UserProfile? { session.userProfile }
    private var user: AppUser?        { session.currentUser }

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: BSTheme.sectionGap) {
                    profileCard
                    subscriptionCard
                    accountSection
                    clubsSection
                    preferencesSection
                    cameraSection
                    appSection
                    signOutButton
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, BSTheme.hPad)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .sheet(isPresented: $showClubs) {
            if let uid = user?.id {
                NavigationStack {
                    ClubsInBagView(userId: uid, backend: session.backend)
                }
                .tcAppearance()
            }
        }
    }

    // MARK: Profile Card

    private var profileCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(BSTheme.rangeGradient)
                    .frame(width: 72, height: 72)
                Text(String((profile?.displayName ?? user?.name ?? "?").prefix(1)))
                    .font(.system(size: 30, weight: .black))
                    .foregroundColor(.white)
            }
            .shadow(color: BSTheme.electricCyan.opacity(0.30), radius: 12, x: 0, y: 0)

            VStack(alignment: .leading, spacing: 5) {
                Text(profile?.displayName ?? user?.name ?? "Guest")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(BSTheme.textPrimary)
                HStack(spacing: 8) {
                    StatusPill(text: profile?.handedness.rawValue ?? "Right-handed",
                               color: BSTheme.electricCyan)
                    StatusPill(text: user?.subscriptionStatus.rawValue.capitalized ?? "Free",
                               color: BSTheme.textMuted)
                }
                Text(profile?.homeCourseName.isEmpty == false
                     ? "Home: \(profile!.homeCourseName)"
                     : "Home Course: Not set")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
        }
        .premiumCard(padding: 16)
    }

    // MARK: Subscription Card

    private var subscriptionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BSTheme.gold.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "star.fill")
                    .font(.system(size: 18))
                    .foregroundColor(BSTheme.gold)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("BallStrike Pro")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text("Unlock analytics, feed, and unlimited sessions.")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            Text("Upgrade")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(BSTheme.gold)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .premiumCard(padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                .strokeBorder(BSTheme.gold.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: Account Section

    private var accountSection: some View {
        BSSettingsSection("Account") {
            BSSettingsRow(icon: "person.fill",         title: "Edit Profile",   accent: BSTheme.electricCyan)
            BSDivider()
            BSSettingsRow(icon: "bell.fill",           title: "Notifications",  value: "On",   accent: BSTheme.simBlue)
            BSDivider()
            BSSettingsRow(icon: "square.and.arrow.up", title: "Export Data",    accent: BSTheme.fairwayGreen)
            BSDivider()
            BSSettingsRow(icon: "lock.fill",           title: "Privacy",        accent: BSTheme.textMuted)
        }
    }

    // MARK: Clubs in Bag

    private var clubsSection: some View {
        BSSettingsSection("Clubs in Bag") {
            Button { showClubs = true } label: {
                BSSettingsRow(icon: "figure.golf", title: "Manage Clubs",
                              value: "View bag", accent: BSTheme.fairwayGreen)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Preferences

    private var preferencesSection: some View {
        BSSettingsSection("Preferences") {
            HandednessRow()
            BSDivider()
            BSSettingsRow(icon: "ruler.fill",             title: "Distance Units",
                          value: profile?.distanceUnit.rawValue ?? "Yards",   accent: BSTheme.electricCyan)
            BSDivider()
            BSSettingsRow(icon: "gauge.with.needle.fill", title: "Speed Units",
                          value: profile?.speedUnit.rawValue ?? "mph",         accent: BSTheme.electricCyan)
            BSDivider()
            BSSettingsRow(icon: "flag.fill",              title: "Home Course",
                          value: profile?.homeCourseName.isEmpty == false
                              ? profile!.homeCourseName : "Not set",           accent: BSTheme.gold)
            BSDivider()
            FeedShareRow()
        }
    }

    // MARK: Camera

    private var cameraSection: some View {
        BSSettingsSection("Camera") {
            BSSettingsRow(icon: "camera.fill",            title: "Frame Rate",      value: "240 fps",  accent: BSTheme.simBlue)
            BSDivider()
            BSSettingsRow(icon: "camera.aperture",        title: "Exposure Mode",   value: "Auto",     accent: BSTheme.simBlue)
            BSDivider()
            BSSettingsRow(icon: "arrow.left.arrow.right", title: "Camera Side",
                          value: profile?.handedness.rawValue ?? "Right-handed",   accent: BSTheme.simBlue)
            BSDivider()
            BSSettingsRow(icon: "square.stack.3d.up.fill",title: "Storage Used",    value: "128 MB",   accent: BSTheme.textMuted)
        }
    }

    // MARK: App

    private var appSection: some View {
        BSSettingsSection("App") {
            AppearanceRow()
            BSDivider()
            BSSettingsRow(icon: "info.circle.fill",         title: "Version",         value: "1.0.0", accent: BSTheme.textMuted)
            BSDivider()
            BSSettingsRow(icon: "questionmark.circle.fill", title: "Help & Support",                   accent: BSTheme.electricCyan)
            BSDivider()
            BSSettingsRow(icon: "doc.text.fill",            title: "Privacy Policy",                   accent: BSTheme.textMuted)
            BSDivider()
            BSSettingsRow(icon: "doc.text.fill",            title: "Terms of Service",                 accent: BSTheme.textMuted)
            BSDivider()
            BSSettingsRow(icon: "ant.fill",                 title: "Developer / Debug",                accent: BSTheme.dangerRed)
        }
    }

    // MARK: Sign Out

    private var signOutButton: some View {
        Button {
            Task { await session.signOut() }
        } label: {
            Text("Sign Out")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(BSTheme.dangerRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BSTheme.dangerRed.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(BSTheme.dangerRed.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Appearance Row (Light / Dark / System)

private struct AppearanceRow: View {
    @AppStorage(AppearanceStore.key) private var raw = AppAppearance.dark.rawValue
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BSTheme.gold.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.gold)
            }
            Text("Appearance")
                .font(.system(size: 15))
                .foregroundColor(BSTheme.textPrimary)
            Spacer()
            Picker("", selection: $raw) {
                ForEach(AppAppearance.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Feed Sharing Row (auto-post opt-out)

private struct FeedShareRow: View {
    @AppStorage("tc_feed_autoshare_enabled") private var autoShare = true
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BSTheme.fairwayGreen.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.fairwayGreen)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Share activities to feed")
                    .font(.system(size: 15))
                    .foregroundColor(BSTheme.textPrimary)
                Text("Auto-post completed rounds & sessions to friends")
                    .font(.system(size: 11))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            Toggle("", isOn: $autoShare)
                .labelsHidden()
                .tint(BSTheme.fairwayGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Handedness Row (inline picker)

private struct HandednessRow: View {
    @EnvironmentObject var session: AuthSessionStore
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BSTheme.electricCyan.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 14))
                    .foregroundColor(BSTheme.electricCyan)
            }
            Text("Handedness")
                .font(.system(size: 15))
                .foregroundColor(BSTheme.textPrimary)
            Spacer()
            Picker("", selection: Binding(
                get: { session.userProfile?.handedness ?? .right },
                set: { newVal in Task { await session.updateHandedness(newVal) } }
            )) {
                ForEach(Handedness.allCases, id: \.self) { h in
                    Text(h.rawValue).tag(h)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
