import Foundation
import Combine

/// Observable wrapper around SimBLEPeripheral.
/// Handles shot encoding and forwards Published changes to SwiftUI.
@MainActor
final class SimBLEViewModel: ObservableObject {

    let peripheral = SimBLEPeripheral()

    // Forward all peripheral Published changes so views subscribed to this VM re-render.
    @Published private(set) var state: BLEBridgeState = .unavailable
    @Published private(set) var bridgeStatus: BLEBridgeStatus?
    @Published var lastSendFeedback: String?

    private var shotCounter = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        peripheral.$state
            .receive(on: RunLoop.main)
            .assign(to: &$state)
        peripheral.$bridgeStatus
            .receive(on: RunLoop.main)
            .assign(to: &$bridgeStatus)
    }

    // MARK: - Lifecycle

    func start() { peripheral.start() }
    func stop()  { peripheral.stop() }

    // MARK: - Send

    func sendMetrics(_ metrics: SavedShotMetrics) async {
        guard state.isReady else {
            lastSendFeedback = "Bluetooth bridge not connected."
            return
        }
        shotCounter += 1
        let provider = bridgeStatus?.provider ?? .gspro
        guard let payload = encodeShot(metrics, provider: provider, number: shotCounter) else {
            lastSendFeedback = "Encoding error."
            return
        }
        let sent = peripheral.sendShot(payload)
        lastSendFeedback = sent ? "Shot sent via Bluetooth." : "Send queue full — retrying next shot."
        let fb = lastSendFeedback
        try? await Task.sleep(for: .seconds(4))
        if lastSendFeedback == fb { lastSendFeedback = nil }
    }

    func sendTestShot() async {
        var m = SavedShotMetrics()
        m.ballSpeedMph = 147.5; m.vlaDegrees = 14.3; m.hlaDegrees = 2.3
        m.backspinRpm  = 2500;  m.sidespinRpm = -800; m.spinAxisDegrees = -13.2
        m.carryYards   = 256.5
        await sendMetrics(m)
    }

    // MARK: - Private encoding

    private func encodeShot(_ metrics: SavedShotMetrics,
                             provider: SimProvider,
                             number: Int) -> Data? {
        switch provider {
        case .gspro:
            let msg = GSProShotMessage.shot(number: number, metrics: metrics)
            guard var d = try? JSONEncoder().encode(msg) else { return nil }
            d.append(contentsOf: "\n".utf8)
            return d
        case .ogs:
            let shot = OpenGolfSimShot.from(metrics: metrics)
            let msg  = OpenGolfSimShotMessage(shot: shot)
            guard var d = try? JSONEncoder().encode(msg) else { return nil }
            d.append(contentsOf: "\n".utf8)
            return d
        default:
            return nil
        }
    }
}
