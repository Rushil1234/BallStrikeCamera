import Foundation

@MainActor
final class OpenGolfSimViewModel: ObservableObject {

    // MARK: - Persisted settings

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "ogs_host") }
    }
    @Published var portString: String {
        didSet { UserDefaults.standard.set(portString, forKey: "ogs_port") }
    }

    // MARK: - Connection state (forwarded from client callbacks)

    @Published private(set) var connectionState: OGSConnectionState = .disconnected
    @Published private(set) var lastResult: OpenGolfSimShotResult?
    @Published private(set) var simStatus: String?

    // MARK: - Send state

    @Published private(set) var isSending = false
    @Published var lastSendFeedback: String?

    // MARK: - Scan state

    @Published private(set) var isScanning = false
    @Published var scanResults: [String] = []
    @Published var scanMessage: String?

    // MARK: - Private

    private let client = OpenGolfSimClient()
    private var didAutoScanOnFailure = false

    // MARK: - Computed

    var port: UInt16? {
        guard let v = UInt16(portString.trimmingCharacters(in: .whitespaces)), v >= 1 else {
            return nil
        }
        return v
    }

    var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && port != nil
    }

    // MARK: - Init

    init() {
        host       = UserDefaults.standard.string(forKey: "ogs_host") ?? ""
        portString = UserDefaults.standard.string(forKey: "ogs_port") ?? "3111"

        client.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.connectionState = state
                switch state {
                case .connected:
                    self.didAutoScanOnFailure = false
                case .failed:
                    guard !self.didAutoScanOnFailure,
                          !self.host.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    self.didAutoScanOnFailure = true
                    let prevHost = self.host
                    await self.scanForHosts()
                    if self.host != prevHost {
                        try? await Task.sleep(for: .seconds(0.4))
                        self.connect()
                    }
                default: break
                }
            }
        }
        client.onResult = { [weak self] result in
            Task { @MainActor [weak self] in self?.lastResult = result }
        }
        client.onStatusMessage = { [weak self] status in
            Task { @MainActor [weak self] in self?.simStatus = status }
        }
    }

    // MARK: - Actions

    func connect() {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            connectionState = .failed("Enter the computer's local IP address.")
            return
        }
        guard let p = port else {
            connectionState = .failed("Invalid port. Enter a number between 1 and 65535.")
            return
        }
        client.connect(host: trimmed, port: p)
    }

    func disconnect() {
        client.disconnect()
        connectionState = .disconnected
        didAutoScanOnFailure = false
    }

    func scanForHosts() async {
        guard !isScanning else { return }
        isScanning = true
        scanResults = []
        scanMessage = nil
        defer { isScanning = false }
        let p = port ?? OpenGolfSimClient.defaultPort
        do {
            let found = try await SimNetworkScanner().scan(port: p)
            if found.count == 1 {
                host = found[0]
                scanMessage = "Found \(found[0]) — IP filled in."
            } else if found.isEmpty {
                scanMessage = "No PC found. Make sure OpenGolfSim is running and your PC's firewall allows port \(p)."
            } else {
                scanResults = found
            }
        } catch {
            scanMessage = error.localizedDescription
        }
        let msg = scanMessage
        try? await Task.sleep(for: .seconds(6))
        if scanMessage == msg { scanMessage = nil }
    }

    func sendTestShot() async {
        await send(shot: .testShot, label: "Test shot")
    }

    func sendMetrics(_ metrics: SavedShotMetrics) async {
        let shot = OpenGolfSimShot.from(metrics: metrics)
        await send(shot: shot, label: "Shot")
    }

    // MARK: - Private

    private func send(shot: OpenGolfSimShot, label: String) async {
        guard connectionState.isConnected else {
            lastSendFeedback = "Not connected to simulator."
            return
        }
        isSending = true
        lastSendFeedback = nil
        defer { isSending = false }

        do {
            let payload = try client.encode(shot)
            #if DEBUG
            if let str = String(data: payload, encoding: .utf8) { print("[OGS] → \(str)") }
            #endif
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                client.sendRaw(payload) { error in
                    if let e = error { cont.resume(throwing: e) }
                    else { cont.resume() }
                }
            }
            lastSendFeedback = "\(label) sent."
        } catch {
            lastSendFeedback = error.localizedDescription
        }
        // Auto-clear after 4 seconds so the label doesn't linger.
        let feedback = lastSendFeedback
        try? await Task.sleep(for: .seconds(4))
        if lastSendFeedback == feedback { lastSendFeedback = nil }
    }
}
