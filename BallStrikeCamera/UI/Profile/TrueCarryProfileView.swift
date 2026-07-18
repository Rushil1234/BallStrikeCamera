import SwiftUI

enum ProfileRoute: Identifiable {
    case edit, clubs, homeGolfers
    case info(TCInfoPage)
    var id: String {
        switch self {
        case .edit: return "edit"
        case .clubs: return "clubs"
        case .homeGolfers: return "golfers"
        case .info(let p): return "info-\(p.rawValue)"
        }
    }
}

struct TrueCarryProfileView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var route: ProfileRoute?
    @AppStorage(AppearanceStore.key) private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage("tc_feed_autoshare_enabled") private var autoShareFeed = true
    @AppStorage("tc_default_visibility") private var defaultVisibilityRaw = ShotVisibility.friends.rawValue
    @AppStorage(FrameArchiveService.enabledKey) private var saveAllFrames = false
    @AppStorage("tc_capture_720") private var capture720 = true

    // Frame-archive export (developer testing tool)
    @State private var frameExportURL: URL?
    @State private var frameArchiveError: String?
    @State private var archiveRefresh = 0   // bump to re-read the on-disk count

    // Real-time Google Drive dev-mode uploader (developer testing tool)
    @AppStorage(GoogleDriveUploadService.enabledKey) private var driveDevMode = false
    #if DEBUG
    @State private var showBallTrackingTester = false
    #endif
    @StateObject private var driveAuth = GoogleDriveAuthService.shared
    @StateObject private var driveUploader = GoogleDriveUploadService.shared
    @State private var isConnectingDrive = false
    @State private var driveConnectError: String?

    private var profile: UserProfile? { session.userProfile }
    private var user: AppUser?        { session.currentUser }

    // Primary name shown big — prefers username, never the raw email.
    private var displayName: String { session.displayHandle }

    /// A real (non-email) display name distinct from the username, if one exists — shown small.
    private var realName: String? {
        let dn = profile?.displayName ?? ""
        guard !dn.isEmpty, !dn.contains("@"), dn != displayName else { return nil }
        return dn
    }

    private var userInitials: String {
        let name = displayName
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

    private var devMode: Bool { session.entitlementVM.isDeveloperMode }

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) { EmptyView() }

                    if devMode {
                        devModeBanner
                    }

                    VStack(spacing: TCTheme.sectionGap) {
                        profileHeader
                        displayCard
                        preferencesCard
                        bagCard
                        communityCard
                        accountCard
                        appCard
                        developerCard
                        signOutButton
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        #if DEBUG
        .fullScreenCover(isPresented: $showBallTrackingTester) {
            BallTrackingTestView(onDismiss: { showBallTrackingTester = false })
        }
        #endif
        .sheet(item: $route) { r in
            NavigationStack {
                switch r {
                case .edit:        TCEditProfileSheet()
                case .clubs:
                    if let uid = user?.id { ClubsInBagView(userId: uid, backend: session.backend) }
                case .homeGolfers: HomeCourseGolfersView()
                case .info(let p): TCInfoPageView(page: p)
                }
            }
            .tcAppearance()
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
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)

                if let real = realName {
                    Text(real)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(1).truncationMode(.tail)
                }

                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10))
                        .foregroundColor(TCTheme.textMuted)
                    Text(homeCourseName)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(1).truncationMode(.tail)
                }

                Text(session.entitlementVM.tierDisplayName + (devMode ? " Mode" : " Plan"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(devMode ? Color(red: 1, green: 0.6, blue: 0) : TCTheme.textUltraMuted)
                    .tracking(0.5)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Display (appearance + feed sharing)

    private var displayCard: some View {
        VStack(spacing: 0) {
            sectionLabel("DISPLAY")
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 24, alignment: .leading)
                    Text("Appearance")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(TCTheme.textPrimary)
                    Spacer()
                    Picker("", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                rowDivider

                HStack(spacing: 14) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share activities to feed")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("Auto-post rounds & sessions to friends")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $autoShareFeed)
                        .labelsHidden()
                        .tint(TCTheme.gold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .tcCard()
        }
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            sectionLabel("PREFERENCES")
            VStack(spacing: 0) {
                handednessRow
                rowDivider
                genderRow
                rowDivider
                defaultVisibilityRow
            }
            .tcCard()
        }
    }

    private var genderRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "person")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("Gender")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Used for tee rating/slope in handicap calc")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { session.userProfile?.gender ?? .male },
                set: { newVal in Task { await session.updateGender(newVal) } }
            )) {
                ForEach(Gender.allCases, id: \.self) { g in
                    Text(g.rawValue).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var defaultVisibilityRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "eye")
                .font(.system(size: 14)).foregroundColor(TCTheme.textMuted)
                .frame(width: 24, alignment: .leading)
            Text("Shot Visibility")
                .font(.system(size: 15, weight: .medium)).foregroundColor(TCTheme.textPrimary)
            Spacer()
            Picker("", selection: $defaultVisibilityRaw) {
                Text("Only me").tag(ShotVisibility.private.rawValue)
                Text("Friends").tag(ShotVisibility.friends.rawValue)
                Text("Everyone").tag(ShotVisibility.public.rawValue)
            }
            .pickerStyle(.menu).tint(TCTheme.textMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var handednessRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
                .frame(width: 24, alignment: .leading)
            Text("Handedness")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(TCTheme.textPrimary)
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
            Button { route = .clubs } label: {
                settingRow(icon: "figure.golf", title: "Manage Clubs")
            }
            .buttonStyle(.plain)
            .tcCard()
        }
    }

    // MARK: - Community

    private var communityCard: some View {
        VStack(spacing: 0) {
            sectionLabel("COMMUNITY")
            Button { route = .homeGolfers } label: {
                settingRow(icon: "person.3.fill", title: "Golfers at My Home Course",
                           value: profile?.homeCourseName.isEmpty == false ? "" : "Set a course")
            }
            .buttonStyle(.plain)
            .disabled(profile?.homeCourseName.isEmpty != false)
            .tcCard()
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(spacing: 0) {
            sectionLabel("ACCOUNT")
            VStack(spacing: 0) {
                Button { route = .edit } label: {
                    settingRow(icon: "person.fill", title: "Edit Profile",
                               value: emailValue, showChevron: true)
                }.buttonStyle(.plain)
            }
            .tcCard()
        }
    }

    private var emailValue: String {
        guard let email = user?.email, !email.isEmpty else { return "" }
        return email
    }

    // MARK: - App

    private var appCard: some View {
        VStack(spacing: 0) {
            sectionLabel("APP")
            VStack(spacing: 0) {
                settingRow(icon: "info.circle.fill", title: "Version", value: appVersion,
                           showChevron: false)
                rowDivider
                Button { route = .info(.help) } label: {
                    settingRow(icon: "questionmark.circle.fill", title: "Help & Support")
                }.buttonStyle(.plain)
                rowDivider
                Button { route = .info(.privacy) } label: {
                    settingRow(icon: "lock.fill", title: "Privacy Policy")
                }.buttonStyle(.plain)
                rowDivider
                Button { route = .info(.terms) } label: {
                    settingRow(icon: "doc.text.fill", title: "Terms of Service")
                }.buttonStyle(.plain)
            }
            .tcCard()
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    // MARK: - Developer Mode Banner

    private var devModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 11))
            Text("DEVELOPER MODE — All features unlocked")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
        }
        .foregroundColor(.black.opacity(0.85))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(red: 1, green: 0.75, blue: 0))
    }

    // MARK: - Developer Card

    private var developerCard: some View {
        VStack(spacing: 0) {
            sectionLabel("DEVELOPER")
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 1, green: 0.6, blue: 0))
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developer Mode")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("Unlocks all features and bypasses limits")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $session.entitlementVM.isDeveloperMode)
                        .tint(Color(red: 1, green: 0.6, blue: 0))
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                rowDivider

                settingRow(icon: "person.badge.key.fill", title: "Account",
                           value: "dev@truecarry.app", showChevron: false)

                rowDivider

                // Save-all-frames testing toggle: persists every shot's raw 41-frame burst to disk.
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 1, green: 0.6, blue: 0))
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save All Frames")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("Archive every shot's raw 41 frames for Garmin comparison")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $saveAllFrames)
                        .tint(Color(red: 1, green: 0.6, blue: 0))
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                rowDivider

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("720p Measurement Capture")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("2x precision for speed/VLA. Turn OFF if you see frame-drop warnings at the range.")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $capture720)
                        .tint(Color(red: 1, green: 0.6, blue: 0))
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                rowDivider

                #if DEBUG
                // Offline live-parity replay: loads archived/exported shots and runs the EXACT
                // production pipeline with per-frame overlays (ball track, club, metrics).
                Button { showBallTrackingTester = true } label: {
                    settingRow(icon: "scope", title: "Ball Tracking Tester",
                               value: "replay saved shots")
                }
                .buttonStyle(.plain)

                rowDivider
                #endif

                let _ = archiveRefresh   // recompute count/size when bumped
                settingRow(icon: "internaldrive.fill", title: "Archived Shots",
                           value: "\(FrameArchiveService.shared.shotCount()) · \(archiveSizeString)",
                           showChevron: false)

                rowDivider

                Button { exportAllFrames() } label: {
                    settingRow(icon: "square.and.arrow.up.fill", title: "Export All Frames (ZIP)")
                }
                .buttonStyle(.plain)
                .disabled(FrameArchiveService.shared.shotCount() == 0)

                rowDivider

                // Bulk-send the whole local archive to Drive, one zip per shot. Resumable:
                // already-uploaded shots are skipped, so a re-tap continues where it stopped.
                Button { driveUploader.uploadArchive() } label: {
                    settingRow(icon: "icloud.and.arrow.up",
                               title: "Upload Archive to Drive",
                               value: archiveUploadStatusString,
                               showChevron: false)
                }
                .buttonStyle(.plain)
                .disabled(!driveAuth.isSignedIn
                          || driveUploader.archiveUpload?.isRunning == true
                          || driveUploader.pendingArchiveCount() == 0)

                rowDivider

                Button { clearFrameArchive() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                            .foregroundColor(TCTheme.danger)
                            .frame(width: 24, alignment: .leading)
                        Text("Clear Frame Archive")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TCTheme.danger)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(FrameArchiveService.shared.shotCount() == 0)

                rowDivider

                // Real-time uploader: every accepted shot auto-sends straight to Drive, no
                // manual export tap. Complements the local archive above.
                HStack(spacing: 14) {
                    Image(systemName: "icloud.and.arrow.up.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 1, green: 0.6, blue: 0))
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dev Mode: Auto-Upload to Drive")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TCTheme.textPrimary)
                        Text(driveAuth.isSignedIn
                             ? "Every accepted shot uploads live to \(driveAuth.accountEmail ?? "Drive")"
                             : "Connect Google Drive below to enable")
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $driveDevMode)
                        .tint(Color(red: 1, green: 0.6, blue: 0))
                        .labelsHidden()
                        .disabled(!driveAuth.isSignedIn)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                rowDivider

                Button { toggleGoogleDriveConnection() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: driveAuth.isSignedIn ? "checkmark.icloud.fill" : "link")
                            .font(.system(size: 14))
                            .foregroundColor(driveAuth.isSignedIn ? TCTheme.sage : TCTheme.textPrimary)
                            .frame(width: 24, alignment: .leading)
                        Text(driveAuth.isSignedIn
                             ? "Disconnect Google Drive (\(driveAuth.accountEmail ?? "connected"))"
                             : "Connect Google Drive")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TCTheme.textPrimary)
                        Spacer()
                        if isConnectingDrive { ProgressView().tint(TCTheme.textMuted) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isConnectingDrive)
            }
            .tcCard()
        }
        .onAppear { archiveRefresh &+= 1 }
        .sheet(isPresented: Binding(
            get: { frameExportURL != nil },
            set: { if !$0 { frameExportURL = nil } }
        )) {
            if let url = frameExportURL { ShareSheet(items: [url]) }
        }
        .alert("Export failed", isPresented: Binding(
            get: { frameArchiveError != nil },
            set: { if !$0 { frameArchiveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(frameArchiveError ?? "") }
        .alert("Google Drive", isPresented: Binding(
            get: { driveConnectError != nil },
            set: { if !$0 { driveConnectError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(driveConnectError ?? "") }
    }

    private func toggleGoogleDriveConnection() {
        if driveAuth.isSignedIn {
            GoogleDriveAuthService.shared.signOut()
            driveDevMode = false
            return
        }
        isConnectingDrive = true
        Task {
            do {
                try await GoogleDriveAuthService.shared.signIn()
            } catch {
                driveConnectError = "Could not connect Google Drive: \(error.localizedDescription)"
            }
            isConnectingDrive = false
        }
    }

    private var archiveSizeString: String {
        let bytes = FrameArchiveService.shared.totalBytes()
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private var archiveUploadStatusString: String {
        if let st = driveUploader.archiveUpload {
            if st.isRunning { return "uploading \(st.done + st.failed + 1)/\(st.total)…" }
            if st.total == 0 { return "nothing new to upload" }
            return st.failed == 0
                ? "done — \(st.done) uploaded"
                : "\(st.done) uploaded · \(st.failed) failed (tap to retry)"
        }
        guard driveAuth.isSignedIn else { return "connect Drive below first" }
        let pending = driveUploader.pendingArchiveCount()
        return pending == 0 ? "all shots uploaded" : "\(pending) shots pending"
    }

    private func exportAllFrames() {
        do {
            guard let url = try FrameArchiveService.shared.exportZip() else {
                frameArchiveError = "No archived frames to export yet."
                return
            }
            frameExportURL = url
        } catch {
            frameArchiveError = error.localizedDescription
        }
    }

    private func clearFrameArchive() {
        FrameArchiveService.shared.clear()
        archiveRefresh &+= 1
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
            .foregroundColor(TCTheme.textUltraMuted)
            .tracking(1.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }

    private func settingRow(icon: String, title: String, value: String = "",
                            showChevron: Bool = true) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
                .frame(width: 24, alignment: .leading)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(TCTheme.textPrimary)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textMuted)
                    .lineLimit(1).truncationMode(.middle)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())   // whole row is tappable, not just the text/chevron
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(TCTheme.border)
            .frame(height: 1)
            .padding(.leading, 54)
    }
}



// MARK: - In-app legal / help content
// Real, self-contained pages so every Settings link leads somewhere concrete.

enum TCInfoPage: String, Identifiable {
    case terms, privacy, help
    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms:   return "Terms of Service"
        case .privacy: return "Privacy Policy"
        case .help:    return "Help & Support"
        }
    }
}

struct TCInfoPageView: View {
    let page: TCInfoPage

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                        VStack(alignment: .leading, spacing: 6) {
                            if !sec.heading.isEmpty {
                                Text(sec.heading)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(TCTheme.textPrimary)
                            }
                            Text(sec.body)
                                .font(.system(size: 14))
                                .foregroundColor(TCTheme.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Last updated June 2026")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textUltraMuted)
                        .padding(.top, 8)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct Sec { let heading: String; let body: String }

    private var sections: [Sec] {
        switch page {
        case .terms:   return Self.terms
        case .privacy: return Self.privacy
        case .help:    return Self.help
        }
    }

    // MARK: Content

    private static let terms: [Sec] = [
        Sec(heading: "", body: "Welcome to True Carry. By creating an account or using the app you agree to these Terms. Please read them carefully."),
        Sec(heading: "1. Using True Carry", body: "True Carry estimates golf shot metrics using your device camera and connected launch monitors. Metrics are estimates for practice and entertainment and should not be relied on for wagering, instruction certification, or equipment fitting decisions."),
        Sec(heading: "2. Your Account", body: "You are responsible for activity under your account and for keeping your login secure. You must provide accurate information and be at least 13 years old to use the app."),
        Sec(heading: "3. Subscriptions", body: "Paid tiers (Basic, Pro, Unlimited) unlock additional sessions, stored replay frames, course/sim modes, and advanced insights. Subscriptions renew automatically until cancelled in your App Store settings. Free accounts retain full shot metrics but a limited number of stored replay frames per session."),
        Sec(heading: "4. Your Content", body: "Shots, sessions, rounds, and posts you create remain yours. By sharing to the feed or marking content visible to friends, you grant other permitted users the right to view it in the app. You can delete your content at any time from History."),
        Sec(heading: "5. Acceptable Use", body: "Do not misuse the service, attempt to access other users' data, reverse-engineer the app, or upload unlawful content. We may suspend accounts that violate these Terms."),
        Sec(heading: "6. Disclaimer", body: "The app is provided \u{201C}as is\u{201D} without warranties of accuracy. Camera-based measurements vary with lighting, framing, and calibration."),
        Sec(heading: "7. Changes", body: "We may update these Terms; continued use after changes means you accept them. Material changes will be surfaced in the app."),
        Sec(heading: "8. Contact", body: "Questions about these Terms? Email support@truecarry.app.")
    ]

    private static let privacy: [Sec] = [
        Sec(heading: "", body: "This Privacy Policy explains what True Carry collects, why, and the choices you have."),
        Sec(heading: "What we collect", body: "Account info (email, username, display name, home course), your golf data (shots, sessions, rounds, clubs), and optional captured frames/video for shot replay. We also collect basic device and diagnostic data to keep the app working."),
        Sec(heading: "How we use it", body: "To calculate and display your metrics, sync your history across devices, power insights and the friends feed, and enforce subscription limits. We do not sell your personal data."),
        Sec(heading: "Camera & location", body: "Camera frames are processed on-device to track the ball. Frames are only uploaded for shots you save (up to your tier's limit) so replay works across devices. Location is used only in Course mode to place shots on the map and is never shared without your action."),
        Sec(heading: "Who can see your data", body: "By default, shots and sessions are visible only to you, your friends, and golfers who share your home course. You control visibility per item (Only me / Friends & home course / Everyone). Anything you don't share stays private to your account."),
        Sec(heading: "Data retention & deletion", body: "Your data is kept until you delete it. You can delete individual shots, whole sessions, or clear all history from the History screen. Deleting your account removes your stored data."),
        Sec(heading: "Contact", body: "Privacy questions? Email privacy@truecarry.app.")
    ]

    private static let help: [Sec] = [
        Sec(heading: "Getting started", body: "Place your ball inside the on-screen circle and hold steady. Once the ball is locked (green circle) and confirmed still, swing — True Carry captures the impact and shows your metrics."),
        Sec(heading: "Sessions", body: "Sessions start automatically with your first shot and keep every shot's metrics. At the end you can save the session to History or discard it. Sessions auto-end after 15 minutes of inactivity."),
        Sec(heading: "Replay frames & tiers", body: "Every good shot saves its metrics. Captured frames (for replay) are stored up to your tier's per-session limit — Free 10, Basic 100, Pro 1000, Unlimited unlimited. Shots you mark as bad are not saved at all."),
        Sec(heading: "Better accuracy", body: "Use even lighting, keep the camera steady on a tripod, and make sure the ball contrasts with the surface. Tune camera FOV in a future update for trusted club/face numbers."),
        Sec(heading: "Contact us", body: "Still stuck? Email support@truecarry.app and include your username and what you were doing when the issue happened.")
    ]
}

// MARK: - Edit profile (display name, username, home course)

struct TCEditProfileSheet: View {
    @EnvironmentObject var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var username = ""
    @State private var homeCourse = ""
    @State private var saving = false
    @State private var seeded = false
    @State private var error: String?

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Display Name", text: $displayName, placeholder: "Your name")
                    field("Username", text: $username, placeholder: "username", prefix: "@", autocap: false)
                    Text("Lowercase letters, numbers, and underscores. Visible to friends instead of your email.")
                        .font(.system(size: 11)).foregroundColor(TCTheme.textMuted)

                    NavigationLink {
                        HomeCoursePickerView(selected: $homeCourse)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HOME COURSE").font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(TCTheme.textMuted)
                                Text(homeCourse.isEmpty ? "Choose a course" : homeCourse)
                                    .font(.system(size: 15)).foregroundColor(TCTheme.textPrimary)
                                    .lineLimit(1).truncationMode(.tail)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(TCTheme.textUltraMuted)
                        }
                        .padding(14).background(TCTheme.panelRaised).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if let error { Text(error).font(.system(size: 12)).foregroundColor(TCTheme.danger) }

                    Button { Task { await save() } } label: {
                        Text(saving ? "Saving…" : "Save")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(TCTheme.gold).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(saving)
                    Spacer(minLength: 40)
                }
                .padding(TCTheme.hPad)
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() }.foregroundColor(TCTheme.textMuted) } }
        .onAppear {
            // Seed ONCE — otherwise returning from the home-course picker wipes what was typed.
            guard !seeded else { return }
            seeded = true
            displayName = session.userProfile?.displayName ?? session.currentUser?.name ?? ""
            username    = session.userProfile?.username ?? ""
            homeCourse  = session.userProfile?.homeCourseName ?? ""
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        guard let uid = session.currentUser?.id else { return }
        var p = session.userProfile ?? UserProfile(userId: uid, displayName: displayName)
        let cleanUser = username.lowercased().trimmingCharacters(in: .whitespaces)
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        p.username = cleanUser.isEmpty ? nil : cleanUser
        // The username is the name shown everywhere (feed, leaderboard, search all read
        // display_name). So when a username is set, it becomes the display name too.
        let typedName = displayName.trimmingCharacters(in: .whitespaces)
        if !cleanUser.isEmpty {
            p.displayName = cleanUser
        } else {
            p.displayName = typedName
        }
        p.homeCourseName = homeCourse.trimmingCharacters(in: .whitespaces)
        await session.saveProfile(p)
        await session.refreshCache()
        dismiss()
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, placeholder: String,
                       prefix: String = "", autocap: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(TCTheme.textMuted)
            HStack(spacing: 2) {
                if !prefix.isEmpty { Text(prefix).foregroundColor(TCTheme.textMuted) }
                TextField(placeholder, text: text)
                    .foregroundColor(TCTheme.textPrimary)
                    .textInputAutocapitalization(autocap ? .words : .never)
                    .autocorrectionDisabled(!autocap)
            }
            .padding(14).background(TCTheme.panelRaised).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Home course picker (real catalog search)

struct HomeCoursePickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GolfCourse] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            VStack(spacing: 12) {
                TextField("Search course name", text: $query)
                    .foregroundColor(TCTheme.textPrimary)
                    .autocorrectionDisabled()
                    .padding(14).background(TCTheme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: query) { _ in runSearch() }

                if searching {
                    ProgressView().tint(TCTheme.gold).padding(.top, 20)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(results) { course in
                            Button { choose(course.name) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.name)
                                        .font(.system(size: 15, weight: .medium)).foregroundColor(TCTheme.textPrimary)
                                        .lineLimit(1).truncationMode(.tail)
                                    let loc = [course.city, course.state].filter { !$0.isEmpty }.joined(separator: ", ")
                                    if !loc.isEmpty {
                                        Text(loc).font(.system(size: 12)).foregroundColor(TCTheme.textMuted)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(TCTheme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                                    .strokeBorder(TCTheme.border, lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        // Always allow using exactly what was typed (custom / not-listed course).
                        if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                            Button { choose(query.trimmingCharacters(in: .whitespaces)) } label: {
                                Text("Use \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}")
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(TCTheme.gold)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(TCTheme.hPad).padding(.top, 12)
        }
        .navigationTitle("Home Course")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choose(_ name: String) {
        selected = name
        dismiss()
    }

    private func runSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; searching = false; return }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)   // debounce
            guard !Task.isCancelled else { return }
            let found = await CourseCatalog.search(query: q, near: nil, limit: 25)
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }
}


// MARK: - Golfers at my home course

struct HomeCourseGolfersView: View {
    @EnvironmentObject var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var golfers: [FriendProfile] = []
    @State private var loading = true

    private var courseName: String { session.userProfile?.homeCourseName ?? "" }

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(courseName.isEmpty ? "No home course set" : courseName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(1).truncationMode(.tail)

                    if loading {
                        ProgressView().tint(TCTheme.gold).frame(maxWidth: .infinity).padding(.top, 40)
                    } else if golfers.isEmpty {
                        Text("No other golfers have set this as their home course yet.")
                            .font(.system(size: 14)).foregroundColor(TCTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 24)
                    } else {
                        ForEach(golfers) { g in
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(TCTheme.panelRaised).frame(width: 42, height: 42)
                                    Text(g.initials).font(.system(size: 15, weight: .bold)).foregroundColor(TCTheme.gold)
                                }
                                Text(g.displayName)
                                    .font(.system(size: 15, weight: .medium)).foregroundColor(TCTheme.textPrimary)
                                    .lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .padding(12).background(TCTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                                .strokeBorder(TCTheme.border, lineWidth: 1))
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad).padding(.top, 12)
            }
        }
        .navigationTitle("Home Course")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundColor(TCTheme.gold) } }
        .task {
            golfers = (try? await session.backend.golfersAtHomeCourse()) ?? []
            loading = false
        }
    }
}
