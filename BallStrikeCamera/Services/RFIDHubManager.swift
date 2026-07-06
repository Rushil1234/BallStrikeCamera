import CoreBluetooth
import Foundation

// MARK: - RFIDHubManager
//
// Manages the BLE connection to the TrueCarry Hub (AtomS3 Lite + RFID 2 Unit).
//
// Device binding (so four players' hubs don't cross-connect during a round):
//   • Each user PAIRS once. We persist the chosen hub's CoreBluetooth identifier,
//     namespaced by user id, in UserDefaults.
//   • After that the app ONLY ever connects to that specific hub — it reconnects by
//     identifier (central.connect on the retrieved peripheral), so nearby hubs are ignored
//     and it auto-reconnects whenever the bound hub is in range.
//   • If it ever gets stuck/misbinds, `resetPairing()` clears the binding so the user
//     can pair again from scratch.
//
// Pairing picks the CLOSEST hub: it scans briefly, collects candidates, and binds the one
// with the strongest signal (RSSI) — i.e. the hub the user is holding next to their phone.
//
// Club selection: when the hub reads a tag it notifies the full URI (truecarry://nfc/{uuid}),
// which we hand to NFCManager.handleNFCURL(_:); existing club-selection observers react.

@MainActor
final class RFIDHubManager: NSObject, ObservableObject {

    static let shared = RFIDHubManager()

    // MARK: - State

    enum ConnectionState: Equatable {
        case idle           // Bluetooth not ready
        case needsPairing   // BT on, but this user hasn't paired a hub yet
        case pairing        // actively discovering hubs to bind the closest one
        case scanning       // paired; looking for the bound hub
        case connecting
        case connected
        case disconnected

        var label: String {
            switch self {
            case .idle:         return "Hub off"
            case .needsPairing: return "Tap to pair your hub"
            case .pairing:      return "Pairing…"
            case .scanning:     return "Looking for your hub…"
            case .connecting:   return "Connecting…"
            case .connected:    return "Hub connected"
            case .disconnected: return "Hub disconnected"
            }
        }

        var isConnected: Bool { self == .connected }
    }

    @Published var connectionState: ConnectionState = .idle
    @Published private(set) var isPaired: Bool = false

    /// Set by AuthSessionStore after login so the bound hub is per-user. Changing it re-evaluates
    /// the binding (a different user on this phone connects to *their* hub, not the previous one).
    var currentUserId: UUID? {
        didSet {
            guard currentUserId != oldValue else { return }
            isPaired = (boundIdentifier != nil)
            reevaluateConnection()
        }
    }

    // MARK: - BLE UUIDs (must match TrueCarryHub.ino exactly)

    static let serviceUUID = CBUUID(string: "12E40001-89AB-CDEF-0123-456789ABCDEF")
    static let tagCharUUID = CBUUID(string: "12E40002-89AB-CDEF-0123-456789ABCDEF")

    // MARK: - Private

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    // Pairing: collect candidates for a short window, then bind the strongest.
    private var pairingCandidates: [(peripheral: CBPeripheral, rssi: Int)] = []
    private let pairingWindow: TimeInterval = 2.5

    private override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Bound-device persistence (per user)

    private func bindingKey() -> String {
        "tc_hub_bound_\(currentUserId?.uuidString ?? "default")"
    }
    private var boundIdentifier: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: bindingKey()) else { return nil }
            return UUID(uuidString: s)
        }
        set {
            if let id = newValue { UserDefaults.standard.set(id.uuidString, forKey: bindingKey()) }
            else { UserDefaults.standard.removeObject(forKey: bindingKey()) }
            isPaired = (newValue != nil)
        }
    }

    // MARK: - Public API

    /// Normal auto-connect: only ever targets the user's bound hub. No-op (→ needsPairing) until paired.
    func startScanning() {
        guard central.state == .poweredOn else { return }
        guard connectionState != .connected, connectionState != .connecting, connectionState != .pairing else { return }
        connectToBoundHub()
    }

    /// Begin pairing: discover nearby hubs and bind the closest (strongest RSSI). Call from a UI
    /// "Pair hub" button while the user holds their hub next to the phone.
    func startPairing() {
        guard central.state == .poweredOn else { return }
        TCLog.ble.info("[RFIDHub] Pairing started — collecting candidates for \(self.pairingWindow)s")
        if let p = peripheral { central.cancelPeripheralConnection(p); peripheral = nil }
        pairingCandidates.removeAll()
        connectionState = .pairing
        central.stopScan()
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + pairingWindow) { [weak self] in
            self?.finishPairing()
        }
    }

    /// Forget the bound hub so the user can pair again. The "reset" escape hatch.
    func resetPairing() {
        TCLog.ble.info("[RFIDHub] Pairing reset for user \(self.currentUserId?.uuidString ?? "default")")
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        boundIdentifier = nil
        connectionState = central.state == .poweredOn ? .needsPairing : .idle
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        central.stopScan()
        connectionState = central.state == .poweredOn
            ? (isPaired ? .disconnected : .needsPairing)
            : .idle
    }

    // MARK: - Private helpers

    /// Connect directly to the bound hub by identifier (ignores every other hub). Falls back to a
    /// filtered scan if the system no longer has the peripheral cached.
    private func connectToBoundHub() {
        guard let id = boundIdentifier else { connectionState = .needsPairing; return }
        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            TCLog.ble.info("[RFIDHub] Reconnecting to bound hub \(id)")
            peripheral = known
            known.delegate = self
            connectionState = .connecting
            central.connect(known, options: nil)   // resolves whenever the bound hub is in range
        } else {
            // Not cached → scan and connect only when the bound identifier appears.
            TCLog.ble.info("[RFIDHub] Bound hub not cached — scanning for \(id)")
            connectionState = .scanning
            central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
        }
    }

    private func finishPairing() {
        central.stopScan()
        guard connectionState == .pairing else { return }
        guard let best = pairingCandidates.max(by: { $0.rssi < $1.rssi })?.peripheral else {
            TCLog.ble.info("[RFIDHub] Pairing found no hubs")
            connectionState = .needsPairing
            return
        }
        TCLog.ble.info("[RFIDHub] Paired to \(best.name ?? "hub") \(best.identifier) (\(self.pairingCandidates.count) candidates)")
        boundIdentifier = best.identifier
        peripheral = best
        best.delegate = self
        connectionState = .connecting
        central.connect(best, options: nil)
    }

    /// Called when the bound user changes: drop any current connection and connect to the new
    /// user's hub (or wait for pairing if they have none).
    private func reevaluateConnection() {
        guard central.state == .poweredOn else { return }
        if let p = peripheral { central.cancelPeripheralConnection(p); peripheral = nil }
        central.stopScan()
        connectionState = .scanning
        connectToBoundHub()
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.connectionState != .connected, self.connectionState != .pairing else { return }
            self.startScanning()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension RFIDHubManager: @preconcurrency CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        TCLog.ble.info("[RFIDHub] centralManagerDidUpdateState: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            isPaired = (boundIdentifier != nil)
            if isPaired { connectToBoundHub() }
            else { connectionState = .needsPairing }
        case .poweredOff:    connectionState = .idle
        case .unauthorized:  connectionState = .idle
        case .unsupported:   connectionState = .idle
        case .resetting, .unknown: break
        @unknown default: break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        if connectionState == .pairing {
            // Collect; the closest (strongest RSSI) wins when the window closes.
            if let idx = pairingCandidates.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier }) {
                pairingCandidates[idx].rssi = RSSI.intValue
            } else {
                pairingCandidates.append((peripheral, RSSI.intValue))
            }
            return
        }
        // Normal scan fallback: connect ONLY to the bound hub, ignore everyone else's.
        guard peripheral.identifier == boundIdentifier else {
            TCLog.ble.info("[RFIDHub] Ignoring non-bound hub \(peripheral.identifier)")
            return
        }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        TCLog.ble.info("[RFIDHub] Connected to bound hub")
        connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        TCLog.ble.info("[RFIDHub] Disconnected — will reconnect to bound hub")
        self.peripheral = nil
        connectionState = .disconnected
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        TCLog.ble.error("[RFIDHub] Failed to connect: \(error?.localizedDescription ?? "unknown")")
        self.peripheral = nil
        connectionState = .disconnected
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension RFIDHubManager: @preconcurrency CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.tagCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == Self.tagCharUUID {
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              let data = characteristic.value,
              let uriString = String(data: data, encoding: .utf8),
              let url = URL(string: uriString) else { return }
        NFCManager.shared.handleNFCURL(url)
    }
}
