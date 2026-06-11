import Foundation

@MainActor
final class GSProViewModel: ObservableObject {

    // MARK: - Persisted settings

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "gspro_host") }
    }
    @Published var portString: String {
        didSet { UserDefaults.standard.set(portString, forKey: "gspro_port") }
    }

    // MARK: - Connection state

    @Published private(set) var connectionState: GSProConnectionState = .disconnected
    @Published private(set) var playerInfo: GSProPlayerInfo?
    @Published private(set) var statusMessage: String?

    // MARK: - Send state

    @Published private(set) var isSending = false
    @Published var lastSendFeedback: String?

    // MARK: - Scan state

    @Published private(set) var isScanning = false
    @Published var scanResults: [String] = []
    @Published var scanMessage: String?

    // MARK: - Private

    private let client = GSProClient()
    private var shotCounter = 0
    private var heartbeatTask: Task<Void, Never>?

    // MARK: - Computed

    var port: UInt16? {
        guard let v = UInt16(portString.trimmingCharacters(in: .whitespaces)), v >= 1 else { return nil }
        return v
    }

    var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && port != nil
    }

    // MARK: - Init

    init() {
        host       = UserDefaults.standard.string(forKey: "gspro_host") ?? ""
        portString = UserDefaults.standard.string(forKey: "gspro_port") ?? "921"

        client.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.connectionState = state
                if case .connected = state {
                    self?.sendReadySignal()
                    self?.startHeartbeat()
                } else {
                    self?.stopHeartbeat()
                }
            }
        }
        client.onPlayerInfo = { [weak self] info in
            Task { @MainActor [weak self] in self?.playerInfo = info }
        }
        client.onStatusMessage = { [weak self] msg in
            Task { @MainActor [weak self] in self?.statusMessage = msg }
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
            connectionState = .failed("Invalid port.")
            return
        }
        shotCounter = 0
        client.connect(host: trimmed, port: p)
    }

    func disconnect() {
        stopHeartbeat()
        client.disconnect()
        connectionState = .disconnected
        playerInfo = nil
    }

    func scanForHosts() async {
        guard !isScanning else { return }
        isScanning = true
        scanResults = []
        scanMessage = nil
        defer { isScanning = false }
        let p = port ?? GSProClient.defaultPort
        do {
            let found = try await SimNetworkScanner().scan(port: p)
            if found.count == 1 {
                host = found[0]
                scanMessage = "Found \(found[0]) — IP filled in."
            } else if found.isEmpty {
                scanMessage = "No PC found. Make sure GSPro Connect is running and your PC's firewall allows port \(p)."
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
        shotCounter += 1
        let msg = GSProShotMessage.testShot(number: shotCounter)
        await send(message: msg, label: "Test shot")
    }

    func sendMetrics(_ metrics: SavedShotMetrics) async {
        shotCounter += 1
        let msg = GSProShotMessage.shot(number: shotCounter, metrics: metrics)
        await send(message: msg, label: "Shot")
    }

    // MARK: - Ready signal

    private func sendReadySignal() {
        shotCounter += 1
        let msg = GSProShotMessage.ready(number: shotCounter)
        guard let payload = try? client.encode(msg) else { return }
        #if DEBUG
        if let str = String(data: payload, encoding: .utf8) { print("[GSPro] → ready: \(str)") }
        #endif
        client.sendRaw(payload) { _ in }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.connectionState.isConnected else { continue }
                self.shotCounter += 1
                let hb = GSProShotMessage.heartbeat(number: self.shotCounter)
                if let payload = try? self.client.encode(hb) {
                    self.client.sendRaw(payload) { _ in }
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Private send

    private func send(message: GSProShotMessage, label: String) async {
        guard connectionState.isConnected else {
            lastSendFeedback = "Not connected to GSPro."
            return
        }
        isSending = true
        lastSendFeedback = nil
        defer { isSending = false }

        do {
            let payload = try client.encode(message)
            #if DEBUG
            if let str = String(data: payload, encoding: .utf8) { print("[GSPro] → \(str)") }
            #endif
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                client.sendRaw(payload) { error in
                    if let e = error { cont.resume(throwing: e) }
                    else             { cont.resume() }
                }
            }
            lastSendFeedback = "\(label) sent to GSPro."
        } catch {
            lastSendFeedback = error.localizedDescription
        }

        let feedback = lastSendFeedback
        try? await Task.sleep(for: .seconds(4))
        if lastSendFeedback == feedback { lastSendFeedback = nil }
    }

    deinit { heartbeatTask?.cancel() }
}
