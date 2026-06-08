import SwiftUI

// MARK: - Provider option model

private struct SimProviderOption: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
}

// MARK: - Main view

struct SimModeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var simVM: SimSessionViewModel
    @StateObject private var ogsVM = OpenGolfSimViewModel()
    @StateObject private var gsproVM = GSProViewModel()

    @State private var selectedProvider = "OGS"
    @State private var showCamera = false
    @State private var showEndConfirmation = false
    @State private var showSaveSheet = false
    @State private var saveSheetDefaultName = "Sim Session"
    @State private var simulateFeedback: String?

    private let userId: UUID
    private let backend: AppBackend

    private let providers: [SimProviderOption] = [
        SimProviderOption(name: "OGS",       subtitle: "OpenGolfSim — TCP connection",  icon: "antenna.radiowaves.left.and.right"),
        SimProviderOption(name: "GSPro",      subtitle: "GSPro — full feature set",      icon: "display"),
        SimProviderOption(name: "Local JSON", subtitle: "Export shot data to JSON file", icon: "doc.text"),
    ]

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
        _simVM = StateObject(wrappedValue: SimSessionViewModel(userId: userId, backend: backend))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BSTheme.sectionGap) {
                        subheader
                        providerSection
                        if selectedProvider == "OGS"   { ogsConnectionSection }
                        if selectedProvider == "GSPro" { gsproConnectionSection }
                        sessionSection
                        if simVM.sessionActive { activeSessionSection }
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, BSTheme.hPad)
                    .padding(.top, 4)
                }
            }
            .navigationTitle("Simulator")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        if simVM.sessionActive {
                            showEndConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(BSTheme.electricCyan)
                    .fontWeight(.semibold)
                }
                if simVM.sessionActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End") { showEndConfirmation = true }
                            .foregroundColor(BSTheme.dangerRed)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .tcAppearance()
        // Camera screen for real shots
        .fullScreenCover(isPresented: $showCamera) {
            SimCameraScreen(simVM: simVM, ogsVM: ogsVM, gsproVM: gsproVM)
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
        // Phase 1: Save / Delete / Continue
        .confirmationDialog("End Sim Session?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
            Button("Save Sim Session") {
                Task {
                    saveSheetDefaultName = await simVM.computeDefaultName()
                    showSaveSheet = true
                }
            }
            Button("Delete Sim Session", role: .destructive) {
                Task {
                    await simVM.discardSession()
                    dismiss()
                }
            }
            Button("Continue Session", role: .cancel) {}
        } message: {
            Text(simVM.shots.isEmpty
                 ? "Save this sim session to History or delete it?"
                 : "Save this sim session to History or delete it? You have \(simVM.shots.count) shot\(simVM.shots.count == 1 ? "" : "s").")
        }
        // Phase 2: Name + description
        .sheet(isPresented: $showSaveSheet) {
            SessionSaveSheet(
                config: SessionSaveConfig(
                    type: .sim,
                    defaultName: saveSheetDefaultName,
                    date: simVM.activeSession?.startedAt ?? Date()
                ),
                onSave: { name, desc in
                Task {
                    await simVM.endSessionWithDetails(
                        name: name,
                        description: desc,
                        usedOGS: ogsVM.connectionState.isConnected
                    )
                    dismiss()
                }
                },
                onDelete: {
                    Task { await simVM.discardSession(); dismiss() }
                }
            )
        }
        .task {
            await simVM.loadClubs()
            publishWatchRangeState()
        }
        .onAppear {
            registerWatchRangeControls()
        }
        .onDisappear {
            WatchConnectivityBridge.shared.unregisterRangeCommandHandler()
        }
        .onChange(of: simVM.activeSession?.id) { _ in
            publishWatchRangeState()
        }
        .onChange(of: simVM.shots.count) { _ in
            publishWatchRangeState()
        }
        .onChange(of: simVM.selectedClub?.id) { _ in
            publishWatchRangeState()
        }
    }

    private func registerWatchRangeControls() {
        WatchConnectivityBridge.shared.registerRangeCommandHandler { command in
            await handleWatchRangeCommand(command)
        }
        publishWatchRangeState()
    }

    private func handleWatchRangeCommand(_ command: WatchCommand) async -> WatchCommandResult {
        switch command.kind {
        case .refresh, .rangeRefresh:
            publishWatchRangeState()
            return .success()
        case .rangeStart:
            if !simVM.sessionActive {
                await simVM.startSession(provider: .ogs, usedOGS: ogsVM.connectionState.isConnected)
            }
            publishWatchRangeState()
            return .success()
        case .rangeEnd:
            if simVM.sessionActive {
                await simVM.endSession()
            }
            publishWatchRangeState()
            return .success()
        case .roundNextHole, .roundPreviousHole, .roundSetScore:
            return .failure("That command is for Round mode.")
        }
    }

    private func publishWatchRangeState() {
        let summary = simVM.summary
        WatchConnectivityBridge.shared.publishRange(
            WatchCompanionRangeSnapshot(
                isActive: simVM.sessionActive,
                selectedClubName: simVM.selectedClub?.name,
                shotCount: summary.shotCount,
                averageCarryYards: Int(summary.avgCarry.rounded()),
                bestCarryYards: Int(summary.bestCarry.rounded()),
                averageBallSpeedMph: Int(summary.avgBallSpeed.rounded())
            ),
            latestShot: simVM.shots.last.map { shot in
                WatchCompanionShotSnapshot(
                    clubName: shot.clubName,
                    carryYards: Int(shot.metrics.carryYards.rounded()),
                    totalYards: Int(shot.metrics.totalYards.rounded()),
                    ballSpeedMph: Int(shot.metrics.ballSpeedMph.rounded()),
                    smashFactor: shot.metrics.smashFactor,
                    timestamp: shot.timestamp
                )
            }
        )
    }

    // MARK: - Subheader

    private var subheader: some View {
        Text("Connect True Carry to your simulator over Wi-Fi.")
            .font(.system(size: 14))
            .foregroundColor(BSTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Provider picker

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Provider")
            VStack(spacing: 8) {
                ForEach(providers) { p in
                    Button { selectedProvider = p.name } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedProvider == p.name
                                          ? BSTheme.simBlue.opacity(0.25)
                                          : BSTheme.panel)
                                    .frame(width: 38, height: 38)
                                Image(systemName: p.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(selectedProvider == p.name
                                                     ? BSTheme.electricCyan
                                                     : BSTheme.textMuted)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BSTheme.textPrimary)
                                Text(p.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundColor(BSTheme.textMuted)
                            }
                            Spacer()
                            if selectedProvider == p.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(BSTheme.electricCyan)
                                    .font(.system(size: 18))
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedProvider == p.name ? BSTheme.panelRaised : BSTheme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    selectedProvider == p.name
                                        ? BSTheme.electricCyan.opacity(0.40)
                                        : BSTheme.border,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - OGS Connection section (only when OGS selected)

    private var ogsConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "OpenGolfSim Connection")
            VStack(alignment: .leading, spacing: 14) {
                Text("Make sure your iPhone and computer are on the same Wi-Fi, then enter your computer's local IP address.")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
                    .lineSpacing(2)

                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Text("Host").font(.system(size: 13, weight: .semibold)).foregroundColor(BSTheme.textMuted).frame(width: 42, alignment: .leading)
                        TextField("192.168.1.x", text: $ogsVM.host)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(BSTheme.textPrimary)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    Divider().background(BSTheme.border)
                    HStack(spacing: 12) {
                        Text("Port").font(.system(size: 13, weight: .semibold)).foregroundColor(BSTheme.textMuted).frame(width: 42, alignment: .leading)
                        TextField("3111", text: $ogsVM.portString)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(BSTheme.textPrimary)
                            .keyboardType(.numberPad)
                    }
                }
                .premiumCard(padding: 14)

                ogsStatusRow

                HStack(spacing: 10) {
                    PremiumActionButton(
                        title: ogsVM.connectionState.isConnecting ? "Connecting…" : "Connect",
                        icon: "antenna.radiowaves.left.and.right",
                        style: .gradient(BSTheme.simGradient),
                        action: { ogsVM.connect() }
                    )
                    .disabled(!ogsVM.canConnect || ogsVM.connectionState.isConnecting || ogsVM.connectionState.isConnected)
                    .opacity(!ogsVM.canConnect || ogsVM.connectionState.isConnecting || ogsVM.connectionState.isConnected ? 0.45 : 1)

                    if ogsVM.connectionState.isConnected || ogsVM.connectionState.isConnecting {
                        PremiumActionButton(title: "Disconnect", icon: "xmark.circle", style: .ghost, action: { ogsVM.disconnect() })
                    }
                }

                if ogsVM.connectionState.isConnected {
                    PremiumActionButton(
                        title: ogsVM.isSending ? "Sending…" : "Send Test Shot",
                        icon: "paperplane.fill",
                        style: .ghost,
                        action: { Task { await ogsVM.sendTestShot() } }
                    )
                    .disabled(ogsVM.isSending)
                    .opacity(ogsVM.isSending ? 0.5 : 1)
                }

                if let feedback = ogsVM.lastSendFeedback {
                    Text(feedback)
                        .font(.system(size: 12))
                        .foregroundColor(feedback.hasSuffix("sent.") ? BSTheme.fairwayGreen : BSTheme.dangerRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result = ogsVM.lastResult {
                    ogsResultRow(result)
                }
            }
        }
    }

    private var ogsStatusRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(ogsStatusColor.opacity(0.18)).frame(width: 34, height: 34)
                Circle().fill(ogsStatusColor).frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ogsVM.connectionState.label).font(.system(size: 14, weight: .semibold)).foregroundColor(BSTheme.textPrimary)
                if let status = ogsVM.simStatus { Text("Simulator: \(status)").font(.system(size: 11)).foregroundColor(BSTheme.textMuted) }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func ogsResultRow(_ result: OpenGolfSimShotResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OGS Last Result").font(.system(size: 12, weight: .semibold)).foregroundColor(BSTheme.textMuted)
            HStack(spacing: 10) {
                if let v = result.carry { StatTile(label: "Carry", value: "\(Int(v))", unit: "yd", accent: BSTheme.electricCyan) }
                if let v = result.total { StatTile(label: "Total", value: "\(Int(v))", unit: "yd", accent: BSTheme.fairwayGreen) }
                if let v = result.roll  { StatTile(label: "Roll",  value: "\(Int(v))", unit: "yd", accent: BSTheme.gold) }
            }
        }
    }

    private var ogsStatusColor: Color {
        switch ogsVM.connectionState {
        case .connected:    return BSTheme.fairwayGreen
        case .connecting:   return BSTheme.gold
        case .disconnected: return BSTheme.textMuted
        case .failed:       return BSTheme.dangerRed
        }
    }

    // MARK: - GSPro Connection section

    private var gsproConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "GSPro Connection")
            VStack(alignment: .leading, spacing: 14) {
                Text("Make sure your iPhone and PC are on the same Wi-Fi. Enter your PC's local IP — GSPro Connect listens on port 921.")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
                    .lineSpacing(2)

                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Text("Host").font(.system(size: 13, weight: .semibold)).foregroundColor(BSTheme.textMuted).frame(width: 42, alignment: .leading)
                        TextField("192.168.1.x", text: $gsproVM.host)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(BSTheme.textPrimary)
                            .keyboardType(.decimalPad)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    Divider().background(BSTheme.border)
                    HStack(spacing: 12) {
                        Text("Port").font(.system(size: 13, weight: .semibold)).foregroundColor(BSTheme.textMuted).frame(width: 42, alignment: .leading)
                        TextField("921", text: $gsproVM.portString)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundColor(BSTheme.textPrimary)
                            .keyboardType(.numberPad)
                    }
                }
                .premiumCard(padding: 14)

                gsproStatusRow

                HStack(spacing: 10) {
                    PremiumActionButton(
                        title: gsproVM.connectionState.isConnecting ? "Connecting…" : "Connect",
                        icon: "antenna.radiowaves.left.and.right",
                        style: .gradient(BSTheme.simGradient),
                        action: { gsproVM.connect() }
                    )
                    .disabled(!gsproVM.canConnect || gsproVM.connectionState.isConnecting || gsproVM.connectionState.isConnected)
                    .opacity(!gsproVM.canConnect || gsproVM.connectionState.isConnecting || gsproVM.connectionState.isConnected ? 0.45 : 1)

                    if gsproVM.connectionState.isConnected || gsproVM.connectionState.isConnecting {
                        PremiumActionButton(title: "Disconnect", icon: "xmark.circle", style: .ghost, action: { gsproVM.disconnect() })
                    }
                }

                if gsproVM.connectionState.isConnected {
                    PremiumActionButton(
                        title: gsproVM.isSending ? "Sending…" : "Send Test Shot",
                        icon: "paperplane.fill",
                        style: .ghost,
                        action: { Task { await gsproVM.sendTestShot() } }
                    )
                    .disabled(gsproVM.isSending)
                    .opacity(gsproVM.isSending ? 0.5 : 1)
                }

                if let feedback = gsproVM.lastSendFeedback {
                    Text(feedback)
                        .font(.system(size: 12))
                        .foregroundColor(feedback.hasSuffix("GSPro.") ? BSTheme.fairwayGreen : BSTheme.dangerRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let info = gsproVM.playerInfo {
                    gsproPlayerInfoRow(info)
                }
            }
        }
    }

    private var gsproStatusRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(gsproStatusColor.opacity(0.18)).frame(width: 34, height: 34)
                Circle().fill(gsproStatusColor).frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(gsproVM.connectionState.label).font(.system(size: 14, weight: .semibold)).foregroundColor(BSTheme.textPrimary)
                if let msg = gsproVM.statusMessage { Text(msg).font(.system(size: 11)).foregroundColor(BSTheme.textMuted) }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func gsproPlayerInfoRow(_ info: GSProPlayerInfo) -> some View {
        HStack(spacing: 10) {
            if let club = info.clubDisplayName {
                StatTile(label: "Club in GSPro", value: club, accent: BSTheme.electricCyan)
            }
            if let handed = info.handed {
                StatTile(label: "Handed", value: handed, accent: BSTheme.gold)
            }
        }
    }

    private var gsproStatusColor: Color {
        switch gsproVM.connectionState {
        case .connected:    return BSTheme.fairwayGreen
        case .connecting:   return BSTheme.gold
        case .disconnected: return BSTheme.textMuted
        case .failed:       return BSTheme.dangerRed
        }
    }

    // MARK: - Session section (start / stats)

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: simVM.sessionActive ? "Active Session" : "Session")

            if simVM.sessionActive {
                // Live stats row
                HStack(spacing: 10) {
                    StatTile(label: "Shots",    value: "\(simVM.shots.count)",                          accent: BSTheme.electricCyan)
                    StatTile(label: "Avg Carry",
                             value: simVM.shots.isEmpty ? "—" : "\(Int(simVM.summary.avgCarry))",
                             unit: simVM.shots.isEmpty ? "" : "yd",
                             accent: BSTheme.fairwayGreen)
                    StatTile(label: "Best",
                             value: simVM.shots.isEmpty ? "—" : "\(Int(simVM.summary.bestCarry))",
                             unit: simVM.shots.isEmpty ? "" : "yd",
                             accent: BSTheme.gold)
                }
            } else {
                PremiumActionButton(
                    title: "Start Session",
                    icon: "play.fill",
                    style: .gradient(BSTheme.simGradient),
                    action: {
                        Task { await simVM.startSession(provider: providerEnum, usedOGS: ogsVM.connectionState.isConnected) }
                    }
                )
            }
        }
    }

    // MARK: - Active session controls

    @ViewBuilder
    private var activeSessionSection: some View {
        VStack(spacing: 10) {
            // Hit real shot
            PremiumActionButton(
                title: "Hit Shot",
                icon: "camera.fill",
                style: .gradient(BSTheme.rangeGradient),
                action: { showCamera = true }
            )
            .glowingAccent(BSTheme.electricCyan)

            // Simulate shot
            PremiumActionButton(
                title: "Simulate Shot",
                icon: "sparkles",
                style: .ghost,
                action: {
                    Task {
                        let shot = await simVM.addSimulatedShot()
                        if ogsVM.connectionState.isConnected {
                            await ogsVM.sendMetrics(shot.metrics)
                            simulateFeedback = "Shot sent to OpenGolfSim."
                        } else if gsproVM.connectionState.isConnected {
                            await gsproVM.sendMetrics(shot.metrics)
                            simulateFeedback = "Shot sent to GSPro."
                        } else {
                            simulateFeedback = "Simulated locally — connect to a simulator to send shots."
                        }
                    }
                }
            )

            if let feedback = simulateFeedback {
                Text(feedback)
                    .font(.system(size: 12))
                    .foregroundColor(feedback.contains("sent") ? BSTheme.fairwayGreen : BSTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { simulateFeedback = nil }
                    }
            }
        }

        // Shot history
        if !simVM.shots.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                BSectionHeader(title: "Shots This Session")
                VStack(spacing: 8) {
                    ForEach(Array(simVM.shots.reversed().enumerated()), id: \.element.id) { idx, shot in
                        simShotRow(shot, number: simVM.shots.count - idx)
                    }
                }
            }
        }
    }

    private func simShotRow(_ shot: SavedShot, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("#\(number)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(BSTheme.textMuted)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(shot.clubName ?? "Unknown club")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text(shot.source == .simulated ? "Simulated" : "Live shot")
                    .font(.system(size: 11))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            if shot.metrics.carryYards > 0 {
                Text("\(Int(shot.metrics.carryYards)) yd")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(BSTheme.electricCyan)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BSTheme.border, lineWidth: 1))
    }

    // MARK: - Helpers

    private var providerEnum: SimProvider {
        switch selectedProvider {
        case "GSPro":      return .gspro
        case "OGS":        return .ogs
        case "Local JSON": return .localJson
        default:           return .notConnected
        }
    }
}
