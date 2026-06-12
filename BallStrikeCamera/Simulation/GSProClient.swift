import Foundation
import Network

/// Pure networking layer for the GSPro Connect API.
/// GSPro runs a TCP server on port 921. We connect, send newline-delimited JSON shot
/// messages, and receive player-info responses (code 201) that tell us the current
/// club and player handedness selected inside GSPro.
final class GSProClient {

    static let defaultPort: UInt16 = 921
    private static let delimiter = Data("\n".utf8)

    // Callbacks — always invoked on the main queue.
    var onStateChange: ((GSProConnectionState) -> Void)?
    var onPlayerInfo: ((GSProPlayerInfo) -> Void)?
    var onStatusMessage: ((String) -> Void)?

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let queue = DispatchQueue(label: "com.truecarry.gspro.tcp", qos: .userInitiated)

    // MARK: - Connect / Disconnect

    func connect(host: String, port: UInt16) {
        disconnect()
        notify(.connecting)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            notify(.failed("Invalid port."))
            return
        }
        let conn = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(host), port: nwPort),
            using: .tcp
        )
        connection = conn
        receiveBuffer = Data()

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.notify(.connected)
                self.startReceiving(conn)
            case .failed(let err):
                self.notify(.failed(self.describe(err)))
                self.connection = nil
            case .cancelled:
                self.notify(.disconnected)
                self.connection = nil
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
    }

    // MARK: - Send

    func encode(_ message: GSProShotMessage) throws -> Data {
        var payload = try JSONEncoder().encode(message)
        payload.append(contentsOf: Self.delimiter)
        return payload
    }

    func sendRaw(_ payload: Data, completion: @escaping (Error?) -> Void) {
        guard let conn = connection else {
            completion(GSProError.notConnected)
            return
        }
        conn.send(content: payload, completion: .contentProcessed { err in
            DispatchQueue.main.async { completion(err) }
        })
    }

    // MARK: - Receive

    private func startReceiving(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processBuffer()
            }
            if error != nil || isComplete {
                self.notify(.disconnected)
                return
            }
            self.startReceiving(conn)
        }
    }

    private func processBuffer() {
        while let range = receiveBuffer.range(of: Self.delimiter) {
            let line = receiveBuffer.subdata(in: receiveBuffer.startIndex..<range.lowerBound)
            receiveBuffer.removeSubrange(..<range.upperBound)
            guard !line.isEmpty else { continue }
            decodeMessage(line)
        }
    }

    private func decodeMessage(_ data: Data) {
        #if DEBUG
        if let s = String(data: data, encoding: .utf8) { print("[GSPro] ← \(s)") }
        #endif

        guard let response = try? JSONDecoder().decode(GSProResponse.self, from: data) else { return }

        if let player = response.player {
            DispatchQueue.main.async { [weak self] in self?.onPlayerInfo?(player) }
        }
        if let msg = response.message, !msg.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.onStatusMessage?(msg) }
        }
    }

    // MARK: - Helpers

    private func notify(_ state: GSProConnectionState) {
        DispatchQueue.main.async { [weak self] in self?.onStateChange?(state) }
    }

    private func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED: return "Connection refused. Is GSPro running with Connect enabled?"
            case .ETIMEDOUT:    return "Timed out. Check the IP address."
            case .ENETUNREACH:  return "Network unreachable."
            default:            return "Couldn't connect. Make sure GSPro is open and on the same Wi-Fi."
            }
        default:
            return "Couldn't connect. Make sure GSPro is open and on the same Wi-Fi."
        }
    }

    deinit { disconnect() }
}
