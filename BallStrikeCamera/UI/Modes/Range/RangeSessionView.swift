import SwiftUI

struct RangeSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: RangeSessionViewModel
    @State private var showCamera = false
    @State private var showEndAlert = false
    @State private var showSaveSheet = false
    @State private var saveSheetDefaultName = "Range Session"

    private let userId: UUID
    private let backend: AppBackend

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
        _vm = StateObject(wrappedValue: RangeSessionViewModel(userId: userId, backend: backend))
    }

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: BSTheme.sectionGap) {
                    sessionHeader
                    if vm.sessionActive {
                        liveStatsGrid
                        clubPickerCard
                        hitButton
                        shotHistorySection
                        endSessionButton
                    } else {
                        startCard
                    }
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, BSTheme.hPad)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Range Session")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    if vm.sessionActive { showEndAlert = true }
                    else { dismiss() }
                }
                .foregroundColor(BSTheme.textMuted)
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .confirmationDialog("End Range Session?", isPresented: $showEndAlert, titleVisibility: .visible) {
            Button("Save Session") {
                Task {
                    saveSheetDefaultName = await vm.computeDefaultName()
                    showSaveSheet = true
                }
            }
            Button("Discard Session", role: .destructive) {
                Task {
                    await vm.discardSession()
                    dismiss()
                }
            }
            Button("Continue Session", role: .cancel) {}
        } message: {
            Text(vm.shots.isEmpty
                 ? "Save this session to History or delete it?"
                 : "Save this session to History or delete it? You have \(vm.shots.count) shot\(vm.shots.count == 1 ? "" : "s").")
        }
        .sheet(isPresented: $showSaveSheet) {
            SessionSaveSheet(
                config: SessionSaveConfig(
                    type: .range,
                    defaultName: saveSheetDefaultName,
                    date: vm.activeSession?.startedAt ?? Date()
                ),
                onSave: { name, desc in
                    Task { await vm.endSessionWithDetails(name: name, description: desc); dismiss() }
                },
                onDelete: {
                    Task { await vm.discardSession(); dismiss() }
                }
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen(
                userId: userId,
                backend: backend,
                initialClubId: vm.selectedClub?.id,
                initialClubName: vm.selectedClub?.name,
                context: ShotContext(sourceMode: .range)
            )
        }
        .task {
            await vm.loadClubs()
            publishWatchRangeState()
        }
        .onAppear {
            registerWatchRangeControls()
        }
        .onDisappear {
            WatchConnectivityBridge.shared.unregisterRangeCommandHandler()
        }
        .onChange(of: vm.activeSession?.id) { _ in
            publishWatchRangeState()
        }
        .onChange(of: vm.shots.count) { _ in
            publishWatchRangeState()
        }
        .onChange(of: vm.selectedClub?.id) { _ in
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
            if !vm.sessionActive {
                await vm.startSession()
            }
            publishWatchRangeState()
            return .success()
        case .rangeEnd:
            if vm.sessionActive {
                await vm.endSession()
            }
            publishWatchRangeState()
            return .success()
        case .roundNextHole, .roundPreviousHole, .roundSetScore:
            return .failure("That command is for Round mode.")
        }
    }

    private func publishWatchRangeState() {
        let summary = vm.summary
        WatchConnectivityBridge.shared.publishRange(
            WatchCompanionRangeSnapshot(
                isActive: vm.sessionActive,
                selectedClubName: vm.selectedClub?.name,
                shotCount: summary.shotCount,
                averageCarryYards: Int(summary.avgCarry.rounded()),
                bestCarryYards: Int(summary.bestCarry.rounded()),
                averageBallSpeedMph: Int(summary.avgBallSpeed.rounded())
            ),
            latestShot: vm.shots.last.map { shot in
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

    // MARK: - Sub-views

    private var sessionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.sessionActive ? "Session Active" : "Start Session")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(BSTheme.textPrimary)
                Text(vm.sessionActive
                     ? "\(vm.shots.count) shot\(vm.shots.count == 1 ? "" : "s")"
                     : "Select a club and start hitting")
                    .font(.system(size: 14))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            if vm.sessionActive {
                StatusPill(text: "LIVE", color: BSTheme.fairwayGreen)
            }
        }
    }

    private var startCard: some View {
        VStack(spacing: 20) {
            clubPickerCard

            Toggle(isOn: $vm.saveOriginalFrames) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Original Frames")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BSTheme.textPrimary)
                    Text("41 raw frames per shot (~12 MB each)")
                        .font(.system(size: 12))
                        .foregroundColor(BSTheme.textMuted)
                }
            }
            .tint(BSTheme.electricCyan)
            .premiumCard(padding: 16)

            PremiumActionButton(
                title: "Start Session",
                icon: "play.fill",
                style: .gradient(BSTheme.rangeGradient),
                action: { Task { await vm.startSession() } }
            )
        }
    }

    private var clubPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Club")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
            if vm.clubs.isEmpty {
                Text("No clubs — add some in Profile > Clubs")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.textMuted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.clubs) { club in
                            Button {
                                vm.selectedClub = club
                            } label: {
                                Text(club.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(vm.selectedClub?.id == club.id ? .black : BSTheme.textMuted)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(vm.selectedClub?.id == club.id ? BSTheme.fairwayGreen : BSTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .premiumCard()
    }

    private var hitButton: some View {
        PremiumActionButton(
            title: "Hit Shot",
            icon: "camera.fill",
            style: .gradient(BSTheme.rangeGradient),
            action: { showCamera = true }
        )
    }

    private var liveStatsGrid: some View {
        let s = vm.summary
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                   GridItem(.flexible()), GridItem(.flexible())],
                         spacing: 10) {
            StatTile(label: "Shots",      value: "\(s.shotCount)",              accent: BSTheme.electricCyan)
            StatTile(label: "Avg Carry",  value: s.shotCount > 0 ? "\(Int(s.avgCarry)) yd" : "—", accent: BSTheme.fairwayGreen)
            StatTile(label: "Best",       value: s.shotCount > 0 ? "\(Int(s.bestCarry)) yd" : "—", accent: BSTheme.gold)
            StatTile(label: "Ball Spd",   value: s.shotCount > 0 ? "\(Int(s.avgBallSpeed)) mph" : "—", accent: BSTheme.electricCyan)
        }
    }

    private var shotHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Shot History")
            if vm.shots.isEmpty {
                Text("No shots yet.")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.textMuted)
                    .padding(.leading, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.shots.reversed()) { shot in
                        ShotHistoryRow(shot: shot)
                    }
                }
            }
        }
    }

    private var endSessionButton: some View {
        Button {
            showEndAlert = true
        } label: {
            Text("End Session")
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

// MARK: - Shot History Row

private struct ShotHistoryRow: View {
    let shot: SavedShot
    var body: some View {
        HStack(spacing: 12) {
            Text(shot.clubName ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSTheme.electricCyan)
                .frame(width: 64, alignment: .leading)
            Spacer()
            metricPill("\(Int(shot.metrics.carryYards)) yd", label: "carry")
            metricPill("\(Int(shot.metrics.ballSpeedMph)) mph", label: "spd")
            metricPill(String(format: "%.2f", shot.metrics.smashFactor), label: "smash")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metricPill(_ value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(BSTheme.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(BSTheme.textMuted)
        }
        .frame(minWidth: 52)
    }
}
