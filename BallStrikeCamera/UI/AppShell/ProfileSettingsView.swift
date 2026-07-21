import SwiftUI
import UserNotifications

struct ProfileSettingsView: View {
    @EnvironmentObject var session: AuthSessionStore
    @Environment(\.openURL) private var openURL

    @State private var showClubs = false
    @State private var showEditProfile = false
    @State private var showResetPreferences = false

    // Account: export + delete
    @State private var isExporting = false
    @State private var exportFile: ExportFile?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var accountError: String?

    @AppStorage("tc_notifications_enabled") private var notificationsOn = true
    @AppStorage("tc_camera_frame_rate") private var frameRate = "240 fps"
    @AppStorage("tc_camera_exposure") private var exposureMode = "Auto"
    @AppStorage("tc_camera_side") private var cameraSide = "Down-the-line"
    @AppStorage("tc_default_play_mode") private var defaultPlayMode = "Range"
    @AppStorage("tc_dev_mode") private var devMode = false   // same key as EntitlementViewModel
    @ObservedObject private var hub = RFIDHubManager.shared

    private var profile: UserProfile? { session.userProfile }
    private var user: AppUser?        { session.currentUser }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

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
                    hubSection
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
                NavigationStack { ClubsInBagView(userId: uid, backend: session.backend) }
                    .tcAppearance()
            }
        }
        .sheet(isPresented: $showEditProfile) {
            NavigationStack { EditProfileSheet() }
                .tcAppearance()
        }
        .alert("Reset Preferences?", isPresented: $showResetPreferences) {
            Button("Reset", role: .destructive) { resetPreferences() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores notification, feed, camera, and appearance defaults. Your profile, clubs, shots, and rounds stay intact.")
        }
        .onChange(of: notificationsOn) { enabled in
            if enabled { requestNotificationPermission() }
        }
    }

    // MARK: Profile Card (tap to edit)

    private var profileCard: some View {
        Button { showEditProfile = true } label: {
            HStack(spacing: 18) {
                ZStack {
                    Circle().fill(BSTheme.rangeGradient).frame(width: 72, height: 72)
                    Text(String((profile?.displayName ?? user?.name ?? "?").prefix(1)))
                        .font(.system(size: 30, weight: .black))
                        .foregroundColor(.white)
                }
                .shadow(color: BSTheme.electricCyan.opacity(0.30), radius: 12)

                VStack(alignment: .leading, spacing: 5) {
                    Text(profile?.displayName ?? user?.name ?? "Guest")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(BSTheme.textPrimary)
                        .fitOneLine(0.6)
                    HStack(spacing: 8) {
                        StatusPill(text: profile?.handedness.rawValue ?? "Right-handed", color: BSTheme.electricCyan)
                        StatusPill(text: user?.subscriptionStatus.rawValue.capitalized ?? "Free", color: BSTheme.textMuted)
                    }
                    Text(profile?.homeCourseName.isEmpty == false
                         ? "Home: \(profile!.homeCourseName)" : "Home Course: Not set")
                        .font(.system(size: 12))
                        .foregroundColor(BSTheme.textMuted)
                    if let email = user?.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundColor(BSTheme.textMuted)
                            .fitOneLine()
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSTheme.textMuted)
            }
            .premiumCard(padding: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: Subscription

    private var subscriptionCard: some View {
        Button { openURL(AppConfig.pricingURL) } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BSTheme.gold.opacity(0.16)).frame(width: 44, height: 44)
                    Image(systemName: "star.fill").font(.system(size: 18)).foregroundColor(BSTheme.gold)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("True Carry Pro").font(.system(size: 15, weight: .semibold)).foregroundColor(BSTheme.textPrimary)
                    Text("Unlock analytics, feed, and unlimited sessions.")
                        .font(.system(size: 12)).foregroundColor(BSTheme.textMuted)
                }
                Spacer()
                Text("Upgrade")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(BSTheme.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .premiumCard(padding: 14)
            .overlay(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                .strokeBorder(BSTheme.gold.opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Account

    private var accountSection: some View {
        BSSettingsSection("Account") {
            Button { showEditProfile = true } label: {
                BSSettingsRow(icon: "person.fill", title: "Edit Profile", accent: BSTheme.electricCyan)
            }.buttonStyle(.plain)
            BSDivider()
            ToggleSettingsRow(icon: "bell.fill", title: "Notifications",
                              accent: BSTheme.simBlue, isOn: $notificationsOn)
            BSDivider()
            // Real GDPR/CCPA export: pulls the caller's full data as JSON from the backend.
            Button { Task { await exportData() } } label: {
                BSSettingsRow(icon: "square.and.arrow.up",
                              title: isExporting ? "Preparing…" : "Export Data",
                              accent: BSTheme.fairwayGreen)
            }.buttonStyle(.plain).disabled(isExporting)
            BSDivider()
            LinkSettingsRow(icon: "lock.fill", title: "Privacy",
                            url: AppConfig.websiteURL.appendingPathComponent("privacy"), accent: BSTheme.textMuted)
            BSDivider()
            // Apple requires an in-app way to delete the account + all data.
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                BSSettingsRow(icon: "trash.fill",
                              title: isDeleting ? "Deleting…" : "Delete Account",
                              accent: BSTheme.dangerRed)
            }.buttonStyle(.plain).disabled(isDeleting)
        }
        .sheet(item: $exportFile) { file in
            ActivityViewController(activityItems: [file.url])
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently deletes your account and all data — clubs, shots, rounds, videos, and stats. This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { accountError != nil }, set: { if !$0 { accountError = nil } })) {
            Button("OK", role: .cancel) { accountError = nil }
        } message: { Text(accountError ?? "") }
    }

    // MARK: Account actions

    private func exportData() async {
        isExporting = true; defer { isExporting = false }
        do {
            let data = try await session.backend.exportMyData()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("truecarry-data-export.json")
            try data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url)
        } catch {
            accountError = "Couldn't export your data. \(error.localizedDescription)"
        }
    }

    private func deleteAccount() async {
        isDeleting = true; defer { isDeleting = false }
        do {
            try await session.backend.deleteAccount()
            await session.signOut()   // account is gone; drop the local session
        } catch {
            accountError = "Couldn't delete your account. Please try again. \(error.localizedDescription)"
        }
    }

    private var clubsSection: some View {
        BSSettingsSection("Clubs in Bag") {
            Button { showClubs = true } label: {
                BSSettingsRow(icon: "figure.golf", title: "Manage Clubs", value: "View bag", accent: BSTheme.fairwayGreen)
            }.buttonStyle(.plain)
        }
    }

    // MARK: Preferences (all live, persisted to the profile)

    private var preferencesSection: some View {
        BSSettingsSection("Preferences") {
            HandednessRow()
            BSDivider()
            MenuSettingsRow(icon: "ruler.fill", title: "Distance Units", accent: BSTheme.electricCyan,
                            value: profile?.distanceUnit.rawValue ?? "Yards",
                            options: DistanceUnit.allCases.map { $0.rawValue }) { picked in
                guard var p = profile, let u = DistanceUnit(rawValue: picked) else { return }
                p.distanceUnit = u; Task { await session.saveProfile(p) }
            }
            BSDivider()
            MenuSettingsRow(icon: "gauge.with.needle.fill", title: "Speed Units", accent: BSTheme.electricCyan,
                            value: profile?.speedUnit.rawValue ?? "mph",
                            options: SpeedUnit.allCases.map { $0.rawValue }) { picked in
                guard var p = profile, let u = SpeedUnit(rawValue: picked) else { return }
                p.speedUnit = u; Task { await session.saveProfile(p) }
            }
            BSDivider()
            Button { showEditProfile = true } label: {
                BSSettingsRow(icon: "flag.fill", title: "Home Course",
                              value: profile?.homeCourseName.isEmpty == false ? profile!.homeCourseName : "Not set",
                              accent: BSTheme.gold)
            }.buttonStyle(.plain)
            BSDivider()
            MenuSettingsRow(icon: "play.fill", title: "Default Play Mode", accent: BSTheme.gold,
                            value: defaultPlayMode,
                            options: ["Range", "Simulator", "Course"]) { defaultPlayMode = $0 }
        }
    }

    // MARK: Camera (persisted via AppStorage)

    private var cameraSection: some View {
        BSSettingsSection("Camera") {
            MenuSettingsRow(icon: "camera.fill", title: "Frame Rate", accent: BSTheme.simBlue,
                            value: frameRate, options: ["120 fps", "240 fps"]) { frameRate = $0 }
            BSDivider()
            MenuSettingsRow(icon: "camera.aperture", title: "Exposure Mode", accent: BSTheme.simBlue,
                            value: exposureMode, options: ["Auto", "Locked", "Low Light"]) { exposureMode = $0 }
            BSDivider()
            MenuSettingsRow(icon: "arrow.left.arrow.right", title: "Camera Side", accent: BSTheme.simBlue,
                            value: cameraSide,
                            options: ["Down-the-line", "Face-on", "Auto from handedness"]) { cameraSide = $0 }
        }
    }

    // MARK: TrueCarry Hub (BLE pairing)

    private var hubSection: some View {
        BSSettingsSection("TrueCarry Hub") {
            if hub.isPaired {
                BSSettingsRow(icon: "dot.radiowaves.left.and.right", title: "Hub",
                              subtitle: hub.connectionState.label,
                              accent: hub.connectionState.isConnected ? BSTheme.fairwayGreen : BSTheme.simBlue)
                BSDivider()
                BSSettingsRow(icon: "arrow.triangle.2.circlepath", title: "Reset & Re-pair Hub",
                              subtitle: "Forget this hub and pair again", accent: BSTheme.dangerRed) {
                    hub.resetPairing()
                }
            } else {
                BSSettingsRow(icon: "dot.radiowaves.left.and.right", title: "Pair Hub",
                              subtitle: hub.connectionState == .pairing
                                  ? "Pairing… hold your hub next to the phone"
                                  : "Tap, then hold your hub next to the phone",
                              accent: BSTheme.simBlue) {
                    hub.startPairing()
                }
            }
        }
    }

    // MARK: App

    private var appSection: some View {
        BSSettingsSection("App") {
            AppearanceRow()
            BSDivider()
            BSSettingsRow(icon: "info.circle.fill", title: "Version", value: appVersion, accent: BSTheme.textMuted)
            BSDivider()
            LinkSettingsRow(icon: "questionmark.circle.fill", title: "Help & Support",
                            url: URL(string: "mailto:support@truecarry.app")!, accent: BSTheme.electricCyan)
            BSDivider()
            LinkSettingsRow(icon: "doc.text.fill", title: "Privacy Policy",
                            url: AppConfig.websiteURL.appendingPathComponent("privacy"), accent: BSTheme.textMuted)
            BSDivider()
            LinkSettingsRow(icon: "doc.text.fill", title: "Terms of Service",
                            url: AppConfig.websiteURL.appendingPathComponent("terms"), accent: BSTheme.textMuted)
            BSDivider()
            Button { showResetPreferences = true } label: {
                BSSettingsRow(icon: "arrow.counterclockwise", title: "Reset Preferences", accent: BSTheme.dangerRed)
            }.buttonStyle(.plain)
        }
    }

    private var signOutButton: some View {
        Button { Task { await session.signOut() } } label: {
            Text("Sign Out")
                .font(.system(size: 15, weight: .semibold)).foregroundColor(BSTheme.dangerRed)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(BSTheme.dangerRed.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(BSTheme.dangerRed.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if !granted {
                DispatchQueue.main.async { notificationsOn = false }
            }
        }
    }

    private func resetPreferences() {
        notificationsOn = true
        frameRate = "240 fps"
        exposureMode = "Auto"
        cameraSide = "Down-the-line"
        defaultPlayMode = "Range"
        UserDefaults.standard.set(AppAppearance.dark.rawValue, forKey: AppearanceStore.key)
        AppearanceStore.applyToWindows(.dark)
    }
}

// MARK: - Edit Profile sheet

private struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore
    @State private var name = ""
    @State private var homeCourse = ""
    @State private var saving = false

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            ScrollView {
                VStack(spacing: 18) {
                    field(title: "Display Name", text: $name, placeholder: "Your name")
                    field(title: "Home Course", text: $homeCourse, placeholder: "e.g. Pebble Beach")
                    Button {
                        saving = true
                        var p = session.userProfile ?? UserProfile(userId: session.currentUser?.id ?? UUID(), displayName: name)
                        p.displayName = name.trimmingCharacters(in: .whitespaces)
                        p.homeCourseName = homeCourse.trimmingCharacters(in: .whitespaces)
                        Task { await session.saveProfile(p); dismiss() }
                    } label: {
                        Text(saving ? "Saving…" : "Save")
                            .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(BSTheme.gold)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .padding(BSTheme.hPad)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundColor(BSTheme.textMuted) } }
        .onAppear {
            name = session.userProfile?.displayName ?? session.currentUser?.name ?? ""
            homeCourse = session.userProfile?.homeCourseName ?? ""
        }
    }

    private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(BSTheme.textMuted)
            TextField(placeholder, text: text)
                .font(.system(size: 16)).foregroundColor(BSTheme.textPrimary)
                .padding(14)
                .background(BSTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Reusable interactive rows

private struct ToggleSettingsRow: View {
    let icon: String; let title: String; let accent: Color
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 14) {
            iconBadge(icon, accent)
            Text(title).font(.system(size: 15)).foregroundColor(BSTheme.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct MenuSettingsRow: View {
    let icon: String; let title: String; let accent: Color
    let value: String; let options: [String]
    let onPick: (String) -> Void
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button { onPick(opt) } label: {
                    if opt == value { Label(opt, systemImage: "checkmark") } else { Text(opt) }
                }
            }
        } label: {
            HStack(spacing: 14) {
                iconBadge(icon, accent)
                Text(title).font(.system(size: 15)).foregroundColor(BSTheme.textPrimary)
                Spacer()
                Text(value).font(.system(size: 14)).foregroundColor(BSTheme.textMuted)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundColor(BSTheme.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
    }
}

private struct LinkSettingsRow: View {
    let icon: String; let title: String; let url: URL; let accent: Color
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button { openURL(url) } label: {
            HStack(spacing: 14) {
                iconBadge(icon, accent)
                Text(title).font(.system(size: 15)).foregroundColor(BSTheme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundColor(BSTheme.textMuted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

@ViewBuilder
private func iconBadge(_ icon: String, _ accent: Color) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent.opacity(0.15)).frame(width: 32, height: 32)
        Image(systemName: icon).font(.system(size: 13)).foregroundColor(accent)
    }
}

// MARK: - Appearance Row (Light / Dark / System)

private struct AppearanceRow: View {
    @AppStorage(AppearanceStore.key) private var raw = AppAppearance.dark.rawValue
    var body: some View {
        HStack(spacing: 14) {
            iconBadge("paintbrush.fill", BSTheme.gold)
            Text("Appearance").font(.system(size: 15)).foregroundColor(BSTheme.textPrimary)
            Spacer()
            Picker("", selection: $raw) {
                ForEach(AppAppearance.allCases) { mode in Text(mode.label).tag(mode.rawValue) }
            }
            .pickerStyle(.segmented).frame(width: 180)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Handedness Row (inline picker)

private struct HandednessRow: View {
    @EnvironmentObject var session: AuthSessionStore
    var body: some View {
        HStack(spacing: 14) {
            iconBadge("hand.raised.fill", BSTheme.electricCyan)
            Text("Handedness").font(.system(size: 15)).foregroundColor(BSTheme.textPrimary)
            Spacer()
            Picker("", selection: Binding(
                get: { session.userProfile?.handedness ?? .right },
                set: { newVal in Task { await session.updateHandedness(newVal) } }
            )) {
                ForEach(Handedness.allCases, id: \.self) { h in Text(h.rawValue).tag(h) }
            }
            .pickerStyle(.segmented).frame(width: 170)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// Identifiable wrapper so the export share sheet can be presented via .sheet(item:).
private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
