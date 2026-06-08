import CoreBluetooth
import Foundation

// MARK: - RFIDHubManager
//
// Manages the BLE connection to the TrueCarry Hub (AtomS3 Lite + RFID 2 Unit).
//
// Lifecycle:
//   • Instantiated once at app launch via RFIDHubManager.shared.
//   • CBCentralManager fires centralManagerDidUpdateState as soon as BT is ready,
//     which triggers startScanning() automatically — no manual call needed.
//   • On disconnect, auto-rescans after a 2-second delay.
//
// Club selection:
//   When the hub reads a tag, it notifies with the full URI string
//   (truecarry://nfc/{uuid}). This manager passes it to NFCManager.handleNFCURL(_:),
//   which sets NFCManager.lastScannedClubId. All existing club-selection observers
//   in RangeCameraScreen and SimCameraScreen react to that publish automatically —
//   no other app code needs to know about BLE.

@MainActor
final class RFIDHubManager: NSObject, ObservableObject {

    static let shared = RFIDHubManager()

    // MARK: - State

    enum ConnectionState: Equatable {
        case idle
        case scanning
        case connecting
        case connected
        case disconnected

        var label: String {
            switch self {
            case .idle:         return "Hub off"
            case .scanning:     return "Scanning…"
            case .connecting:   return "Connecting…"
            case .connected:    return "Hub connected"
            case .disconnected: return "Hub disconnected"
            }
        }

        var isConnected: Bool { self == .connected }
    }

    @Published var connectionState: ConnectionState = .idle

    // MARK: - BLE UUIDs (must match TrueCarryHub.ino exactly)

    static let serviceUUID = CBUUID(string: "12E40001-89AB-CDEF-0123-456789ABCDEF")
    static let tagCharUUID = CBUUID(string: "12E40002-89AB-CDEF-0123-456789ABCDEF")

    // MARK: - Private

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    private override init() {
        super.init()
        // Dispatch queue is .main so all delegate callbacks arrive on the main actor.
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Public API

    func startScanning() {
        print("[RFIDHub] startScanning — BT state: \(central.state.rawValue), connectionState: \(connectionState)")
        guard central.state == .poweredOn else { return }
        guard connectionState != .connected, connectionState != .connecting else { return }
        connectionState = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
        print("[RFIDHub] Scanning started for service \(Self.serviceUUID)")
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        connectionState = .idle
        central.stopScan()
    }

    // MARK: - Private helpers

    private func scheduleRescan() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startScanning()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension RFIDHubManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[RFIDHub] centralManagerDidUpdateState: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            print("[RFIDHub] Bluetooth powered on — starting scan")
            startScanning()
        case .poweredOff:
            print("[RFIDHub] Bluetooth is OFF")
            connectionState = .disconnected
        case .unauthorized:
            print("[RFIDHub] Bluetooth UNAUTHORIZED — check Info.plist NSBluetoothAlwaysUsageDescription")
            connectionState = .disconnected
        case .unsupported:
            print("[RFIDHub] Bluetooth unsupported on this device")
            connectionState = .disconnected
        case .resetting:
            print("[RFIDHub] Bluetooth resetting")
        case .unknown:
            print("[RFIDHub] Bluetooth state unknown")
        @unknown default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        print("[RFIDHub] Discovered peripheral: \(peripheral.name ?? "unnamed") RSSI: \(RSSI)")
        central.stopScan()
        self.peripheral = peripheral
        connectionState = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        print("[RFIDHub] Connected to hub")
        connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("[RFIDHub] Disconnected — will rescan in 2s")
        self.peripheral = nil
        connectionState = .disconnected
        scheduleRescan()
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("[RFIDHub] Failed to connect: \(error?.localizedDescription ?? "unknown")")
        self.peripheral = nil
        connectionState = .disconnected
        scheduleRescan()
    }
}

// MARK: - CBPeripheralDelegate

extension RFIDHubManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.tagCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == Self.tagCharUUID {
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil,
              let data = characteristic.value,
              let uriString = String(data: data, encoding: .utf8),
              let url = URL(string: uriString) else { return }

        NFCManager.shared.handleNFCURL(url)
    }
}
