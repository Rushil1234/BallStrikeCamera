import CoreBluetooth
import Foundation

// UUIDs — must match bridge.py exactly
let kTCServiceUUID = CBUUID(string: "12E61727-B41A-436E-A1A4-BF0A6C7EC7BC")
let kTCShotUUID    = CBUUID(string: "12E61728-B41A-436E-A1A4-BF0A6C7EC7BC")  // Notify: phone → bridge
let kTCStatusUUID  = CBUUID(string: "12E61729-B41A-436E-A1A4-BF0A6C7EC7BC")  // Write:  bridge → phone

// MARK: - State + Status types

enum BLEBridgeState: Equatable {
    case unavailable    // Bluetooth off / not authorized
    case advertising    // Advertising, waiting for bridge to connect
    case connected      // Bridge connected, not yet subscribed
    case ready          // Bridge subscribed to shot notifications — fully operational
    case failed(String)

    var label: String {
        switch self {
        case .unavailable:    return "Bluetooth unavailable"
        case .advertising:    return "Waiting for TrueCarry Bridge…"
        case .connected:      return "Bridge connected"
        case .ready:          return "Ready"
        case .failed(let s):  return s
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isActive: Bool {
        switch self {
        case .advertising, .connected, .ready: return true
        default: return false
        }
    }
}

struct BLEBridgeStatus: Equatable {
    var port: Int       // 921 = GSPro, 3111 = OGS, 0 = sim not connected
    var linked: Bool    // bridge has an active TCP connection to the game

    var gameName: String {
        switch port {
        case 921:  return "GSPro"
        case 3111: return "OpenGolfSim"
        default:   return "—"
        }
    }

    var provider: SimProvider {
        port == 921 ? .gspro : .ogs
    }
}

private struct BLEStatusPayload: Codable {
    let port: Int
    let linked: Bool
}

// MARK: - SimBLEPeripheral

@MainActor
final class SimBLEPeripheral: NSObject, ObservableObject {

    @Published private(set) var state: BLEBridgeState = .unavailable
    @Published private(set) var bridgeStatus: BLEBridgeStatus?

    private var manager: CBPeripheralManager?
    private var shotChar: CBMutableCharacteristic?
    private var statusChar: CBMutableCharacteristic?
    private var subscribedCentrals: [CBCentral] = []

    // MARK: - Start / Stop

    func start() {
        guard manager == nil else { return }
        // Passing queue: nil defaults to main queue so delegate is called on main thread
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func stop() {
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager = nil
        shotChar = nil
        statusChar = nil
        subscribedCentrals = []
        state = .unavailable
        bridgeStatus = nil
    }

    // MARK: - Send shot notification

    /// Pushes shot data to all subscribed bridge centrals.
    /// Returns false if the transmit queue is full (rare — bridge connects immediately).
    @discardableResult
    func sendShot(_ data: Data) -> Bool {
        guard let char = shotChar, let mgr = manager, state.isReady else { return false }
        return mgr.updateValue(data, for: char, onSubscribedCentrals: nil)
    }

    // MARK: - Private setup

    private func buildAndAdvertise() {
        let shot = CBMutableCharacteristic(
            type: kTCShotUUID,
            properties: [.notify],
            value: nil,
            permissions: []         // central subscribes; no read permission needed
        )
        let status = CBMutableCharacteristic(
            type: kTCStatusUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        shotChar   = shot
        statusChar = status

        let service = CBMutableService(type: kTCServiceUUID, primary: true)
        service.characteristics = [shot, status]
        manager?.add(service)

        manager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [kTCServiceUUID],
            CBAdvertisementDataLocalNameKey: "TrueCarry"
        ])
        state = .advertising
    }
}

// MARK: - CBPeripheralManagerDelegate

extension SimBLEPeripheral: CBPeripheralManagerDelegate {

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch peripheral.state {
            case .poweredOn:
                self.buildAndAdvertise()
            case .poweredOff:
                self.state = .unavailable
                self.bridgeStatus = nil
            case .unauthorized:
                self.state = .failed("Bluetooth permission denied — enable in Settings → Privacy → Bluetooth.")
            case .unsupported:
                self.state = .failed("This device does not support Bluetooth LE.")
            default:
                self.state = .unavailable
            }
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let err = error {
            Task { @MainActor [weak self] in
                self?.state = .failed("Could not start advertising: \(err.localizedDescription)")
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                       didAdd service: CBService, error: Error?) {
        // Service added; advertising will follow from buildAndAdvertise
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                       central: CBCentral,
                                       didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard characteristic.uuid == kTCShotUUID else { return }
            if !self.subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
                self.subscribedCentrals.append(central)
            }
            self.state = .ready
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                       central: CBCentral,
                                       didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard characteristic.uuid == kTCShotUUID else { return }
            self.subscribedCentrals.removeAll { $0.identifier == central.identifier }
            if self.subscribedCentrals.isEmpty {
                self.state = .advertising
                self.bridgeStatus = nil
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager,
                                       didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            guard req.characteristic.uuid == kTCStatusUUID, let data = req.value else { continue }
            peripheral.respond(to: req, withResult: .success)
            if let payload = try? JSONDecoder().decode(BLEStatusPayload.self, from: data) {
                Task { @MainActor [weak self] in
                    self?.bridgeStatus = BLEBridgeStatus(port: payload.port, linked: payload.linked)
                }
            }
        }
    }

    // Called when the transmit queue drains after updateValue returned false.
    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Shots are fire-and-forget; no retry needed for our use case.
    }
}
