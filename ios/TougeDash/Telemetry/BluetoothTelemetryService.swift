@preconcurrency import CoreBluetooth
import Combine
import Foundation

private func bluetoothDebugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    FileHandle.standardError.write(Data(("[TougeDash BLE] \(message())\n").utf8))
    #endif
}

struct DiscoveredTelemetryDevice: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let rssi: Int
    let isLikelyEMU: Bool
}

enum BluetoothConnectionState: Equatable, Sendable {
    case unavailable(String)
    case ready
    case scanning
    case connecting(String)
    case connected(String)
    case disconnected(String?)

    var label: String {
        switch self {
        case .unavailable(let reason): reason
        case .ready: "Gotowy"
        case .scanning: "Skanowanie"
        case .connecting(let name): "Łączenie: \(name)"
        case .connected(let name): name
        case .disconnected(let reason): reason ?? "Rozłączono"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

@MainActor
final class BluetoothTelemetryService: NSObject, ObservableObject {
    @Published private(set) var state: BluetoothConnectionState = .ready
    @Published private(set) var devices: [DiscoveredTelemetryDevice] = []
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var receivedPacketCount = 0
    @Published private(set) var receivedByteCount = 0
    @Published private(set) var lastPacketHex = ""
    @Published private(set) var connectedIdentifier: UUID?

    var onBytes: ((Data) -> Void)?
    var onConnectionChanged: ((BluetoothConnectionState) -> Void)?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var shouldScan = false
    private var attemptedAutomaticConnection = false
    private let lastPeripheralKey = "TougeDash.lastECUMasterPeripheral"
    private let debugLogURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("tougedash-ble.log")

    override init() {
        super.init()
        #if DEBUG
        try? Data().write(to: debugLogURL, options: .atomic)
        #endif
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
                CBCentralManagerOptionRestoreIdentifierKey: "it.letscode.touge-dash.central"
            ]
        )
    }

    func startScanning() {
        shouldScan = true
        bluetoothDebugLog("start scanning centralState=\(central.state.rawValue)")
        guard central.state == .poweredOn else { return }
        guard !state.isConnected else { return }
        if case .connecting = state { return }
        devices = []
        peripherals = [:]
        attemptedAutomaticConnection = false
        receivedPacketCount = 0
        receivedByteCount = 0
        lastPacketHex = ""

        if let storedIdentifier = UserDefaults.standard.string(forKey: lastPeripheralKey),
           let identifier = UUID(uuidString: storedIdentifier),
           let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            let remembered = DiscoveredTelemetryDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "ECUMaster",
                rssi: 0,
                isLikelyEMU: true
            )
            peripherals[peripheral.identifier] = peripheral
            devices = [remembered]
            attemptedAutomaticConnection = true
            appendDiagnostic("Connecting to remembered ECUMaster interface")
            connect(to: remembered)
            return
        }

        setState(.scanning)
        appendDiagnostic("Scanning only for ECUMaster BLE interfaces")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        shouldScan = false
        central.stopScan()
        if !state.isConnected { setState(.ready) }
    }

    func connect(to device: DiscoveredTelemetryDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        bluetoothDebugLog("connect requested name=\(device.name) state=\(peripheral.state.rawValue)")
        shouldScan = true
        central.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        setState(.connecting(device.name))
        appendDiagnostic("Connecting to \(device.name) [\(device.id.uuidString)]")
        if peripheral.state == .connected {
            activateConnectedPeripheral(peripheral)
            return
        }
        // CoreBluetooth rejects the combination of connection notification and
        // auto-reconnect options on the physical iPhone with CBError.invalidParameters.
        // We handle reconnects ourselves, so the plain BLE connection is sufficient.
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        connectedIdentifier = nil
        setState(.disconnected(nil))
    }

    private func setState(_ newState: BluetoothConnectionState) {
        state = newState
        onConnectionChanged?(newState)
    }

    private func activateConnectedPeripheral(_ peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectedIdentifier = peripheral.identifier
        peripheral.delegate = self
        let name = peripheral.name ?? "ECUMaster interface"
        peripherals[peripheral.identifier] = peripheral
        let connectedDevice = DiscoveredTelemetryDevice(
            id: peripheral.identifier,
            name: name,
            rssi: devices.first(where: { $0.id == peripheral.identifier })?.rssi ?? 0,
            isLikelyEMU: true
        )
        if let index = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[index] = connectedDevice
        } else {
            devices = [connectedDevice]
        }
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastPeripheralKey)
        setState(.connected(name))
        appendDiagnostic("Connected; discovering GATT services")
        bluetoothDebugLog("connected name=\(name) id=\(peripheral.identifier.uuidString)")
        peripheral.discoverServices(nil)
    }

    private func appendDiagnostic(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        let line = "\(timestamp)  \(message)"
        diagnostics.append(line)
        if diagnostics.count > 120 { diagnostics.removeFirst(diagnostics.count - 120) }
        #if DEBUG
        if let handle = try? FileHandle(forWritingTo: debugLogURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
        }
        #endif
    }

    private static func likelyEMUName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return ["emu", "ecumaster", "canbt", "btcan", "edl", "logger"].contains { normalized.contains($0) }
    }

    private static func isECUMasterAdvertisement(name: String, advertisementData: [String: Any]) -> Bool {
        if likelyEMUName(name) { return true }

        let advertisedText = advertisementData.values.compactMap { value -> String? in
            if let text = value as? String { return text }
            if let data = value as? Data { return String(data: data, encoding: .utf8) }
            return nil
        }.joined(separator: " ")

        return likelyEMUName(advertisedText)
    }
}

extension BluetoothTelemetryService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothDebugLog("central state=\(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            if let connectedPeripheral, connectedPeripheral.state == .connected {
                if !state.isConnected {
                    activateConnectedPeripheral(connectedPeripheral)
                }
                return
            }
            setState(.ready)
            if shouldScan { startScanning() }
        case .poweredOff: setState(.unavailable("Bluetooth wyłączony"))
        case .unauthorized: setState(.unavailable("Brak uprawnienia Bluetooth"))
        case .unsupported: setState(.unavailable("BLE offline"))
        case .resetting: setState(.unavailable("Restart Bluetooth"))
        case .unknown: setState(.unavailable("Nieznany stan Bluetooth"))
        @unknown default: setState(.unavailable("Bluetooth niedostępny"))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unknown BLE device"
        guard Self.isECUMasterAdvertisement(name: name, advertisementData: advertisementData) else { return }
        bluetoothDebugLog("accepted ECUMaster device name=\(name)")
        let item = DiscoveredTelemetryDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            isLikelyEMU: true
        )
        peripherals[peripheral.identifier] = peripheral
        if let index = devices.firstIndex(where: { $0.id == item.id }) {
            devices[index] = item
        } else {
            devices.append(item)
        }
        devices.sort { $0.rssi > $1.rssi }

        if !attemptedAutomaticConnection {
            attemptedAutomaticConnection = true
            connect(to: item)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        activateConnectedPeripheral(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        bluetoothDebugLog("connection failed name=\(peripheral.name ?? "unknown") error=\(error?.localizedDescription ?? "unknown")")
        appendDiagnostic("Connection failed: \(error?.localizedDescription ?? "unknown error")")
        setState(.disconnected(error?.localizedDescription))
        connectedPeripheral = nil
        if shouldScan { startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        bluetoothDebugLog("disconnected name=\(peripheral.name ?? "unknown") error=\(error?.localizedDescription ?? "none")")
        appendDiagnostic("Disconnected: \(error?.localizedDescription ?? "connection closed")")
        setState(.disconnected(error?.localizedDescription))
        connectedPeripheral = nil
        if shouldScan { startScanning() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let peripheral = restored.first else { return }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripherals[peripheral.identifier] = peripheral
        bluetoothDebugLog("restored name=\(peripheral.name ?? "unknown") state=\(peripheral.state.rawValue)")
        appendDiagnostic("Restored Bluetooth connection to \(peripheral.name ?? peripheral.identifier.uuidString)")
        if peripheral.state == .connected {
            activateConnectedPeripheral(peripheral)
        }
    }
}

extension BluetoothTelemetryService: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appendDiagnostic("Service discovery error: \(error.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] {
            bluetoothDebugLog("service \(service.uuid.uuidString)")
            appendDiagnostic("Service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendDiagnostic("Characteristic discovery error: \(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            let properties = characteristic.properties
            bluetoothDebugLog("characteristic \(characteristic.uuid.uuidString) properties=\(properties.rawValue)")
            appendDiagnostic("Characteristic \(characteristic.uuid.uuidString) properties=\(properties.rawValue)")
            if properties.contains(.notify) || properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendDiagnostic("Notification error for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        } else {
            appendDiagnostic("Subscribed to \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendDiagnostic("Value error: \(error.localizedDescription)")
            return
        }
        guard let value = characteristic.value, !value.isEmpty else { return }
        receivedPacketCount += 1
        receivedByteCount += value.count
        lastPacketHex = value.prefix(40).map { String(format: "%02X", $0) }.joined(separator: " ")
        if receivedPacketCount <= 10 || receivedPacketCount.isMultiple(of: 100) {
            bluetoothDebugLog("RX #\(receivedPacketCount) [\(characteristic.uuid.uuidString)] \(lastPacketHex)")
        }
        if receivedPacketCount <= 10 || receivedPacketCount.isMultiple(of: 100) {
            appendDiagnostic("RX #\(receivedPacketCount) [\(characteristic.uuid.uuidString)] \(lastPacketHex)")
        }
        onBytes?(value)
    }
}
