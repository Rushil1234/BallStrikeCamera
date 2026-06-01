import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()

    @Published private(set) var state = WatchAppState.empty

    private var roundCommandHandler: ((WatchCommand) async -> WatchCommandResult)?
    private var rangeCommandHandler: ((WatchCommand) async -> WatchCommandResult)?
    private var isActive = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported(), !isActive else { return }
        isActive = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func registerRoundCommandHandler(_ handler: @escaping (WatchCommand) async -> WatchCommandResult) {
        roundCommandHandler = handler
    }

    func unregisterRoundCommandHandler() {
        roundCommandHandler = nil
    }

    func registerRangeCommandHandler(_ handler: @escaping (WatchCommand) async -> WatchCommandResult) {
        rangeCommandHandler = handler
    }

    func unregisterRangeCommandHandler() {
        rangeCommandHandler = nil
    }

    func publishRound(_ snapshot: WatchCompanionRoundSnapshot) {
        state.round = snapshot
        state.currentMode = .round
        state.lastUpdated = Date()
        sendCurrentState()
    }

    func clearRound() {
        state.round = nil
        state.currentMode = state.range?.isActive == true ? .range : .none
        state.lastUpdated = Date()
        sendCurrentState()
    }

    func publishRange(_ snapshot: WatchCompanionRangeSnapshot, latestShot: WatchCompanionShotSnapshot?) {
        state.range = snapshot
        state.latestShot = latestShot
        state.currentMode = snapshot.isActive ? .range : (state.round == nil ? .none : .round)
        state.lastUpdated = Date()
        sendCurrentState()
    }

    func clearRange() {
        state.range = nil
        state.latestShot = nil
        state.currentMode = state.round == nil ? .none : .round
        state.lastUpdated = Date()
        sendCurrentState()
    }

    private func sendCurrentState() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled,
              let payload = try? JSONEncoder().encode(state) else { return }

        let context = [WatchPayload.stateKey: payload]
        try? WCSession.default.updateApplicationContext(context)

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(context, replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleMessage(_ message: [String: Any]) async -> [String: Any] {
        guard let raw = message[WatchPayload.commandKey] as? Data,
              let command = try? JSONDecoder().decode(WatchCommand.self, from: raw) else {
            return encodedResult(.failure("Could not read the watch command."))
        }

        let result = await perform(command)
        sendCurrentState()
        return encodedResult(result)
    }

    private func perform(_ command: WatchCommand) async -> WatchCommandResult {
        switch command.kind {
        case .refresh:
            return .success()
        case .roundNextHole, .roundPreviousHole, .roundSetScore:
            guard let roundCommandHandler else {
                return .failure("Open an active round on iPhone first.")
            }
            return await roundCommandHandler(command)
        case .rangeStart, .rangeEnd, .rangeRefresh:
            guard let rangeCommandHandler else {
                return .failure("Open Range Session on iPhone first.")
            }
            return await rangeCommandHandler(command)
        }
    }

    private func encodedResult(_ result: WatchCommandResult) -> [String: Any] {
        guard let payload = try? JSONEncoder().encode(result) else { return [:] }
        return [WatchPayload.resultKey: payload]
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.sendCurrentState()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            self.sendCurrentState()
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            let reply = await self.handleMessage(message)
            replyHandler(reply)
        }
    }
}
