import SwiftUI
import WatchConnectivity

@main
struct TrueCarryWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityStore()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(connectivity)
                .task {
                    connectivity.activate()
                    connectivity.send(.init(kind: .refresh))
                }
        }
    }
}

@MainActor
final class WatchConnectivityStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var appState = WatchAppState.empty
    @Published var isPhoneReachable = false
    @Published var commandMessage: String?
    @Published var isSendingCommand = false

    private var isActive = false

    func activate() {
        guard WCSession.isSupported(), !isActive else { return }
        isActive = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        isPhoneReachable = session.isReachable
    }

    func send(_ command: WatchCommand) {
        guard WCSession.default.activationState == .activated else {
            commandMessage = "Phone connection is not ready."
            return
        }

        guard let payload = try? JSONEncoder().encode(command) else {
            commandMessage = "Could not send command."
            return
        }

        isSendingCommand = true
        let message = [WatchPayload.commandKey: payload]
        WCSession.default.sendMessage(message) { [weak self] reply in
            Task { @MainActor in
                self?.isSendingCommand = false
                self?.handleReply(reply)
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.isSendingCommand = false
                self?.commandMessage = error.localizedDescription
            }
        }
    }

    private func handleReply(_ reply: [String: Any]) {
        guard let raw = reply[WatchPayload.resultKey] as? Data,
              let result = try? JSONDecoder().decode(WatchCommandResult.self, from: raw) else {
            commandMessage = nil
            return
        }
        commandMessage = result.accepted ? result.message : result.message
    }

    private func apply(_ context: [String: Any]) {
        guard let raw = context[WatchPayload.stateKey] as? Data,
              let state = try? JSONDecoder().decode(WatchAppState.self, from: raw) else { return }
        appState = state
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            if let error {
                self.commandMessage = error.localizedDescription
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.apply(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.apply(message)
        }
    }
}

private struct WatchDashboardView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ConnectionRow(isReachable: connectivity.isPhoneReachable,
                                  updatedAt: connectivity.appState.lastUpdated)
                }

                Section {
                    NavigationLink {
                        RoundDetailView()
                    } label: {
                        RoundCard(round: connectivity.appState.round)
                    }

                    NavigationLink {
                        RangeDetailView()
                    } label: {
                        RangeCard(range: connectivity.appState.range,
                                  latestShot: connectivity.appState.latestShot)
                    }
                }

                if let message = connectivity.commandMessage, !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("True Carry")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        connectivity.send(.init(kind: .refresh))
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(connectivity.isSendingCommand)
                }
            }
        }
    }
}

private struct ConnectionRow: View {
    var isReachable: Bool
    var updatedAt: Date

    var body: some View {
        HStack {
            Label(isReachable ? "Phone connected" : "Phone unavailable",
                  systemImage: isReachable ? "iphone.gen3.radiowaves.left.and.right" : "iphone.slash")
                .foregroundStyle(isReachable ? .green : .orange)
            Spacer()
            Text(updatedAt, style: .time)
                .foregroundStyle(.secondary)
                .font(.caption2)
        }
    }
}

private struct RoundCard: View {
    var round: WatchCompanionRoundSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Round", systemImage: "flag.fill")
                .font(.headline)
            if let round {
                Text(round.courseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Text("Hole \(round.holeNumber)")
                    Spacer()
                    Text("\(round.centerYards) yd")
                        .fontWeight(.semibold)
                }
            } else {
                Text("No active round")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RangeCard: View {
    var range: WatchCompanionRangeSnapshot?
    var latestShot: WatchCompanionShotSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Range", systemImage: "scope")
                .font(.headline)
            if let range, range.isActive {
                HStack {
                    Text(range.selectedClubName ?? "Club")
                    Spacer()
                    Text("\(range.shotCount) shots")
                        .fontWeight(.semibold)
                }
                if let latestShot {
                    Text("Last \(latestShot.carryYards) yd carry")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No active session")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RoundDetailView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore
    @State private var scoreDraft = 4

    private var round: WatchCompanionRoundSnapshot? { connectivity.appState.round }

    var body: some View {
        List {
            if let round {
                Section {
                    VStack(spacing: 4) {
                        Text("\(round.centerYards)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("center yards")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    HStack {
                        YardageColumn(label: "Front", value: round.frontYards)
                        YardageColumn(label: "Back", value: round.backYards)
                    }
                }

                Section {
                    LabeledContent("Course", value: round.courseName)
                    LabeledContent("Hole", value: "\(round.holeNumber) of \(round.holeCount)")
                    LabeledContent("Par", value: "\(round.par)")
                    LabeledContent("Total", value: "\(round.totalScore)")
                    LabeledContent("To Par", value: scoreToParText(round.scoreToPar))
                }

                Section {
                    Stepper(value: $scoreDraft, in: 1...12) {
                        Text("Score \(scoreDraft)")
                    }
                    Button("Save Score") {
                        connectivity.send(.init(kind: .roundSetScore,
                                                holeNumber: round.holeNumber,
                                                score: scoreDraft))
                    }
                }

                Section {
                    HStack {
                        Button {
                            connectivity.send(.init(kind: .roundPreviousHole))
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!round.canGoPrevious)

                        Spacer()

                        Button {
                            connectivity.send(.init(kind: .roundNextHole))
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!round.canGoNext)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "flag.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Round")
                        .font(.headline)
                    Text("Start or resume a round on iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Round")
        .onAppear {
            if let score = round?.score ?? round?.par {
                scoreDraft = score
            }
            connectivity.send(.init(kind: .refresh))
        }
        .onChange(of: round?.holeNumber) { _ in
            if let score = round?.score ?? round?.par {
                scoreDraft = score
            }
        }
    }

    private func scoreToParText(_ value: Int) -> String {
        value == 0 ? "E" : value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct YardageColumn: View {
    var label: String
    var value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RangeDetailView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityStore

    private var range: WatchCompanionRangeSnapshot? { connectivity.appState.range }
    private var latestShot: WatchCompanionShotSnapshot? { connectivity.appState.latestShot }

    var body: some View {
        List {
            Section {
                if let range, range.isActive {
                    VStack(spacing: 6) {
                        Text("\(range.shotCount)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("shots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    LabeledContent("Club", value: range.selectedClubName ?? "Not selected")
                    LabeledContent("Avg Carry", value: "\(range.averageCarryYards) yd")
                    LabeledContent("Best", value: "\(range.bestCarryYards) yd")
                    LabeledContent("Ball Speed", value: "\(range.averageBallSpeedMph) mph")
                } else {
                    Text("No active range session")
                        .foregroundStyle(.secondary)
                }
            }

            if let latestShot {
                Section("Latest Shot") {
                    LabeledContent("Club", value: latestShot.clubName ?? "Unknown")
                    LabeledContent("Carry", value: "\(latestShot.carryYards) yd")
                    LabeledContent("Total", value: "\(latestShot.totalYards) yd")
                    LabeledContent("Speed", value: "\(latestShot.ballSpeedMph) mph")
                    LabeledContent("Smash", value: String(format: "%.2f", latestShot.smashFactor))
                }
            }

            Section {
                if range?.isActive == true {
                    Button(role: .destructive) {
                        connectivity.send(.init(kind: .rangeEnd))
                    } label: {
                        Label("End Session", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        connectivity.send(.init(kind: .rangeStart))
                    } label: {
                        Label("Start Session", systemImage: "play.fill")
                    }
                }
            }
        }
        .navigationTitle("Range")
        .onAppear {
            connectivity.send(.init(kind: .rangeRefresh))
        }
    }
}
