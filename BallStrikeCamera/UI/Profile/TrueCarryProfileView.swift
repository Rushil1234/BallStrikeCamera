import SwiftUI

struct TrueCarryProfileView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var showClubs = false

    private var profile: UserProfile? { session.userProfile }
    private var user: AppUser?        { session.currentUser }

    private var displayName: String {
        profile?.displayName ?? user?.name ?? "Golfer"
    }

    private var userInitials: String {
        let name = profile?.displayName ?? user?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2, let f = parts[0].first, let l = parts[1].first {
            return "\(f)\(l)"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var homeCourseName: String {
        let n = profile?.homeCourseName ?? ""
        return n.isEmpty ? "No home course set" : n
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) { EmptyView() }
                    VStack(spacing: TCTheme.sectionGap) {
                        profileHeader
                        preferencesCard
                        bagCard
                        cameraCard
                        accountCard
                        appCard
                        signOutButton
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showClubs) {
            if let uid = user?.id {
                NavigationStack {
                    ClubsInBagView(userId: uid, backend: session.backend)
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(TCTheme.panelRaised)
                    .frame(width: 72, height: 72)
                Circle()
                    .strokeBorder(TCTheme.gold.opacity(0.55), lineWidth: 2)
                    .frame(width: 72, height: 72)
                Text(userInitials)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(TCTheme.gold)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.40))
                    Text(homeCourseName)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.50))
                }

                Text(user?.subscriptionStatus == .pro ? "Pro Member" : "Free Plan")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(user?.subscriptionStatus == .pro ? TCTheme.gold : .white.opacity(0.35))
                    .tracking(0.5)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            sectionLabel("PREFERENCES")
            VStack(spacing: 0) {
                handednessRow
                rowDivider
                settingRow(icon: "ruler", title: "Distance Units",
                           value: profile?.distanceUnit.rawValue ?? "Yards")
                rowDivider
                settingRow(icon: "gauge.with.needle", title: "Speed Units",
                           value: profile?.speedUnit.rawValue ?? "mph")
            }
            .tcCard()
        }
    }

    private var handednessRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.50))
                .frame(width: 24, alignment: .leading)
            Text("Handedness")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Picker("", selection: Binding(
                get: { session.userProfile?.handedness ?? .right },
                set: { newVal in Task { await session.updateHandedness(newVal) } }
            )) {
                ForEach(Handedness.allCases, id: \.self) { h in
                    Text(h.short).tag(h)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Clubs

    private var bagCard: some View {
        VStack(spacing: 0) {
            sectionLabel("BAG")
            Button { showClubs = true } label: {
                settingRow(icon: "figure.golf", title: "Manage Clubs")
            }
            .buttonStyle(.plain)
            .tcCard()
        }
    }

    // MARK: - Camera

    private var cameraCard: some View {
        VStack(spacing: 0) {
            sectionLabel("CAMERA")
            VStack(spacing: 0) {
                settingRow(icon: "camera.fill", title: "Frame Rate", value: "240 fps")
                rowDivider
                settingRow(icon: "camera.aperture", title: "Exposure Mode", value: "Auto")
                rowDivider
                settingRow(icon: "arrow.left.arrow.right", title: "Camera Side",
                           value: profile?.handedness.rawValue ?? "Right-handed")
                rowDivider
                settingRow(icon: "square.stack.3d.up.fill", title: "Storage Used", value: "128 MB",
                           showChevron: false)
            }
            .tcCard()
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(spacing: 0) {
            sectionLabel("ACCOUNT")
            VStack(spacing: 0) {
                settingRow(icon: "person.fill", title: "Edit Profile")
                rowDivider
                settingRow(icon: "bell.fill", title: "Notifications", value: "On")
                rowDivider
                settingRow(icon: "square.and.arrow.up", title: "Export Data")
                rowDivider
                settingRow(icon: "lock.fill", title: "Privacy")
            }
            .tcCard()
        }
    }

    // MARK: - App

    private var appCard: some View {
        VStack(spacing: 0) {
            sectionLabel("APP")
            VStack(spacing: 0) {
                settingRow(icon: "info.circle.fill", title: "Version", value: "1.0.0",
                           showChevron: false)
                rowDivider
                settingRow(icon: "questionmark.circle.fill", title: "Help & Support")
                rowDivider
                settingRow(icon: "doc.text.fill", title: "Privacy Policy")
                rowDivider
                settingRow(icon: "doc.text.fill", title: "Terms of Service")
            }
            .tcCard()
        }
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            Task { await session.signOut() }
        } label: {
            Text("Sign Out")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TCTheme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TCTheme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(TCTheme.danger.opacity(0.30), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.35))
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }

    private func settingRow(icon: String, title: String, value: String = "",
                            showChevron: Bool = true) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.50))
                .frame(width: 24, alignment: .leading)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.45))
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.20))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 54)
    }
}
