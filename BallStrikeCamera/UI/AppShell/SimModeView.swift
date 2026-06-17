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
    @StateObject private var bleVM = SimBLEViewModel()
    @StateObject private var liveSimService = LiveSimService()

    @State private var selectedProvider = "OGS"
    @State private var showCamera = false
    @State private var showLiveCamera = false
    @State private var showEndConfirmation = false
    @State private var showSaveSheet = false
    @State private var saveSheetDefaultName = "Sim Session"
    @State private var simulateFeedback: String?

    private let userId: UUID
    private let backend: AppBackend

    private let providers: [SimProviderOption] = [
        SimProviderOption(name: "OGS",       subtitle: "OpenGolfSim — same network",    icon: "antenna.radiowaves.left.and.right"),
        SimProviderOption(name: "GSPro",      subtitle: "GSPro — same network",          icon: "display"),
        SimProviderOption(name: "Bluetooth",  subtitle: "No Wi-Fi needed — BLE bridge",  icon: "dot.radiowaves.right"),
        SimProviderOption(name: "Live Sim",   subtitle: "Stream to browser — free, no PC needed", icon: "globe"),
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
                        if selectedProvider == "OGS"        { ogsConnectionSection }
                        if selectedProvider == "GSPro"       { gsproConnectionSection }
                        if selectedProvider == "Bluetooth"   { bleConnectionSection }
                        if selectedProvider == "Live Sim"    { liveSimSection }
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
            SimCameraScreen(simVM: simVM, ogsVM: ogsVM, gsproVM: gsproVM, bleVM: bleVM)
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
        // Camera screen for Live Sim mode
        .fullScreenCover(isPresented: $showLiveCamera) {
            LiveSimCameraScreen(simVM: simVM, liveSimService: liveSimService)
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
        .onChange(of: selectedProvider) { provider in
            // Start BLE peripheral only when Bluetooth mode is selected; stop otherwise.
            if provider == "Bluetooth" {
                bleVM.start()
            } else {
                bleVM.stop()
            }
            // Clear any previously entered code when switching away from Live Sim.
            if provider != "Live Sim" {
                liveSimService.enteredCode = ""
            }
        }
        .onDisappear { bleVM.stop() }
        // Phase 1: Save / Delete / Continue
        .alert("Save Failed", isPresented: Binding(
            get: { simVM.errorMessage != nil },
            set: { if !$0 { simVM.errorMessage = nil } }
        )) {
            Button("OK") { simVM.errorMessage = nil }
        } message: {
            Text(simVM.errorMessage ?? "")
        }
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
                        usedOGS: usedOGSNow,
                        provider: providerEnum
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
        VStack(alignment: .leading, spacing: 7) {
            Text("Play on your simulator")
                .font(.system(size: 23, weight: .bold, design: .serif))
                .foregroundColor(BSTheme.textPrimary)
            Text("Connect True Carry to your launch monitor or sim over Wi-Fi, then track every shot live.")
                .font(.system(size: 14))
                .foregroundColor(BSTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Provider picker

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Choose your setup")
            VStack(spacing: 10) {
                ForEach(providers) { p in
                    let isSel = selectedProvider == p.name
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedProvider = p.name
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSel ? BSTheme.gold.opacity(0.16) : BSTheme.panel)
                                    .frame(width: 46, height: 46)
                                Image(systemName: p.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(isSel ? BSTheme.gold : BSTheme.textMuted)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(BSTheme.textPrimary)
                                Text(p.subtitle)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(BSTheme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            ZStack {
                                Circle()
                                    .strokeBorder(BSTheme.border, lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                    .opacity(isSel ? 0 : 1)
                                Circle()
                                    .fill(BSTheme.gold)
                                    .frame(width: 22, height: 22)
                                    .opacity(isSel ? 1 : 0)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(BSTheme.panel)
                                    .opacity(isSel ? 1 : 0)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isSel ? BSTheme.panelRaised : BSTheme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSel ? BSTheme.gold.opacity(0.55) : BSTheme.border,
                                              lineWidth: isSel ? 1.5 : 1)
                        )
                        .shadow(color: isSel ? BSTheme.gold.opacity(0.14) : .clear, radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Live Sim section

    private var liveSimSection: some View {
        LiveSimCodeView(liveSimService: liveSimService) {
            if !simVM.sessionActive {
                Task { await simVM.startSession(provider: .liveSim, usedOGS: false) }
            }
            showLiveCamera = true
        }
    }

    // MARK: - OGS Connection section (only when OGS selected)

    private var ogsConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "OpenGolfSim Connection")
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect your PC to the same Wi-Fi or to this iPhone's personal hotspot, then tap Find PC — or enter the IP manually.")
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

                scanSection(isScanning: ogsVM.isScanning,
                            results: ogsVM.scanResults,
                            message: ogsVM.scanMessage,
                            disabled: ogsVM.connectionState.isConnected) {
                    Task { await ogsVM.scanForHosts() }
                } onSelect: { ip in
                    ogsVM.host = ip
                    ogsVM.scanResults = []
                }

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
                Text("Connect your PC to the same Wi-Fi or to this iPhone's personal hotspot, then tap Find PC — or enter the IP manually. GSPro Connect listens on port 921.")
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

                scanSection(isScanning: gsproVM.isScanning,
                            results: gsproVM.scanResults,
                            message: gsproVM.scanMessage,
                            disabled: gsproVM.connectionState.isConnected) {
                    Task { await gsproVM.scanForHosts() }
                } onSelect: { ip in
                    gsproVM.host = ip
                    gsproVM.scanResults = []
                }

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
                        Task { await simVM.startSession(provider: providerEnum, usedOGS: usedOGSNow) }
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
                action: {
                    if selectedProvider == "Live Sim" {
                        showLiveCamera = true
                    } else {
                        showCamera = true
                    }
                }
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

    // MARK: - Bluetooth (BLE Bridge) connection section

    private var bleConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Bluetooth Bridge")
            VStack(alignment: .leading, spacing: 14) {

                // Status indicator row
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(bleBridgeStatusColor.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: bleBridgeStatusIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(bleBridgeStatusColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bleVM.state.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(BSTheme.textPrimary)
                        if bleVM.state.isReady, let status = bleVM.bridgeStatus {
                            Text(status.linked
                                 ? "\(status.gameName) connected on port \(status.port)"
                                 : "Bridge connected — start \(status.gameName == "—" ? "your game" : status.gameName)")
                                .font(.system(size: 12))
                                .foregroundColor(status.linked ? BSTheme.fairwayGreen : BSTheme.gold)
                        } else if bleVM.state.isActive {
                            Text("Open TrueCarry Bridge on your PC or Mac")
                                .font(.system(size: 12))
                                .foregroundColor(BSTheme.textMuted)
                        }
                    }
                    Spacer()
                    if bleVM.state.isActive {
                        ProgressView()
                            .tint(BSTheme.textMuted)
                            .scaleEffect(0.75)
                            .opacity(bleVM.state.isReady ? 0 : 1)
                    }
                }
                .premiumCard(padding: 14)

                // Connection checklist — mirrors truecarry.app/connect so you can
                // confirm everything's linked from your phone (handy once GSPro is
                // full-screen on the computer).
                VStack(spacing: 0) {
                    bleCheckRow(
                        done: bleVM.state.isReady,
                        pending: false,
                        title: "Bridge connected",
                        detail: bleVM.state.isReady
                            ? "TrueCarry Bridge is paired over Bluetooth."
                            : "Open TrueCarry Bridge on your computer.")
                    Divider().background(BSTheme.border)
                    bleCheckRow(
                        done: bleSimDetected,
                        pending: !bleVM.state.isReady,
                        title: "Simulator detected",
                        detail: bleSimDetected
                            ? "\(bleVM.bridgeStatus?.gameName ?? "Simulator") running on your computer."
                            : "Open GSPro or OpenGolfSim on your computer.")
                    Divider().background(BSTheme.border)
                    bleCheckRow(
                        done: bleVM.bridgeStatus?.linked == true,
                        pending: !bleSimDetected,
                        title: "Ready to play",
                        detail: bleVM.bridgeStatus?.linked == true
                            ? "Shots forward automatically — swing away!"
                            : "Waiting for the simulator link.")
                }
                .premiumCard(padding: 6)

                // Download instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("First time setup")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSTheme.textMuted)
                    VStack(alignment: .leading, spacing: 5) {
                        bleStep("1", "On your Mac, download TrueCarry Bridge from:")
                        Text("truecarry.app/bridge")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(BSTheme.electricCyan)
                            .padding(.leading, 20)
                        bleStep("2", "Open the download and drag TrueCarry Bridge into Applications, then launch it.")
                        bleStep("3", "It runs in the menu bar (⛳︎). Keep this screen open until it connects.")
                    }
                }
                .padding(.top, 2)

                // Test shot (once bridge is ready)
                if bleVM.state.isReady {
                    PremiumActionButton(
                        title: "Send Test Shot",
                        icon: "paperplane.fill",
                        style: .ghost,
                        action: { Task { await bleVM.sendTestShot() } }
                    )
                    if let fb = bleVM.lastSendFeedback {
                        Text(fb)
                            .font(.system(size: 12))
                            .foregroundColor(fb.hasPrefix("Shot sent") ? BSTheme.fairwayGreen : BSTheme.dangerRed)
                    }
                }
            }
        }
    }

    private var bleBridgeStatusColor: Color {
        switch bleVM.state {
        case .ready:           return BSTheme.fairwayGreen
        case .advertising, .connected: return BSTheme.gold
        case .unavailable:     return BSTheme.textMuted
        case .failed:          return BSTheme.dangerRed
        }
    }

    private var bleBridgeStatusIcon: String {
        switch bleVM.state {
        case .ready:           return "checkmark"
        case .advertising, .connected: return "dot.radiowaves.right"
        case .unavailable:     return "dot.radiowaves.right"
        case .failed:          return "exclamationmark"
        }
    }

    private var bleSimDetected: Bool {
        guard let s = bleVM.bridgeStatus else { return false }
        return s.port == 921 || s.port == 3111
    }

    @ViewBuilder
    private func bleCheckRow(done: Bool, pending: Bool, title: String, detail: String) -> some View {
        let color: Color = done ? BSTheme.fairwayGreen : (pending ? BSTheme.textMuted : BSTheme.gold)
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 24, height: 24)
                Image(systemName: done ? "checkmark" : (pending ? "circle" : "exclamationmark"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private func bleStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(BSTheme.gold)
                .frame(width: 14, alignment: .center)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(BSTheme.textMuted)
                .lineSpacing(2)
        }
    }

    // MARK: - Scan section (shared by OGS + GSPro panels)

    @ViewBuilder
    private func scanSection(isScanning: Bool,
                             results: [String],
                             message: String?,
                             disabled: Bool,
                             onScan: @escaping () -> Void,
                             onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Find PC button / spinner
            HStack(spacing: 8) {
                if isScanning {
                    ProgressView()
                        .tint(BSTheme.textMuted)
                        .scaleEffect(0.75)
                    Text("Scanning network…")
                        .font(.system(size: 13))
                        .foregroundColor(BSTheme.textMuted)
                } else {
                    Button(action: onScan) {
                        Label("Find PC on network", systemImage: "network")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(disabled ? BSTheme.textMuted.opacity(0.5) : BSTheme.gold)
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                }
            }

            // Status / error message (auto-clears after a few seconds)
            if let msg = message {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(msg.hasPrefix("Found") ? BSTheme.fairwayGreen : BSTheme.dangerRed)
                    .lineSpacing(1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Multiple results — user picks one
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap a device to use its IP:")
                        .font(.system(size: 11))
                        .foregroundColor(BSTheme.textMuted)
                    ForEach(results, id: \.self) { ip in
                        Button { onSelect(ip) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 12))
                                    .foregroundColor(BSTheme.gold)
                                Text(ip)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(BSTheme.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 10))
                                    .foregroundColor(BSTheme.textMuted)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(BSTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(BSTheme.gold.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var providerEnum: SimProvider {
        switch selectedProvider {
        case "GSPro":      return .gspro
        case "OGS":        return .ogs
        // Bluetooth bridge: the game is whichever sim the bridge linked to
        // (reported back over BLE as port 921 = GSPro, 3111 = OGS).
        case "Bluetooth":  return bleVM.bridgeStatus?.provider ?? .notConnected
        case "Local JSON": return .localJson
        default:           return .notConnected
        }
    }

    /// True when the active path is OpenGolfSim — directly (OGS tab) or via the
    /// Bluetooth bridge linked to OGS.
    private var usedOGSNow: Bool {
        switch selectedProvider {
        case "OGS":       return ogsVM.connectionState.isConnected
        case "Bluetooth": return bleVM.bridgeStatus?.provider == .ogs
        default:          return false
        }
    }
}
