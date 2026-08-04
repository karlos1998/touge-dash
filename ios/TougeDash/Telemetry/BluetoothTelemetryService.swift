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

/// Touge Dash is a passive dashboard. Its BLE contract intentionally exposes
/// only GATT reads and notifications; ECU/logger writes are never permitted.
enum BluetoothTelemetryAccessPolicy {
    static let allowsCharacteristicWrites = false

    static func shouldSubscribe(to properties: CBCharacteristicProperties) -> Bool {
        properties.contains(.notify) || properties.contains(.indicate)
    }

    static func shouldRead(_ properties: CBCharacteristicProperties) -> Bool {
        properties.contains(.read)
    }
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
        case .ready: localized("Gotowy")
        case .scanning: localized("Skanowanie")
        case .connecting(let name): String(format: localized("Łączenie: %@"), name)
        case .connected(let name): name
        case .disconnected(let reason): reason ?? localized("Rozłączono")
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
    @Published private(set) var connectedIsSimulator = false

    var onBytes: ((Data) -> Void)?
    var onConnectionChanged: ((BluetoothConnectionState) -> Void)?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var shouldScan = false
    private var attemptedAutomaticConnection = false
    private var hasTriedRememberedPeripheral = false
    private var connectionTimeoutTask: Task<Void, Never>?
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
        let tryRememberedPeripheral = !hasTriedRememberedPeripheral
        hasTriedRememberedPeripheral = true
        beginScanning(tryRememberedPeripheral: tryRememberedPeripheral)
    }

    private func resumeScanning() {
        guard shouldScan else { return }
        beginScanning(tryRememberedPeripheral: false)
    }

    private func beginScanning(tryRememberedPeripheral: Bool) {
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

        if tryRememberedPeripheral,
           let storedIdentifier = UserDefaults.standard.string(forKey: lastPeripheralKey),
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
            appendDiagnostic(localized("Connecting to remembered ECUMaster interface"))
            connect(to: remembered)
            return
        }

        setState(.scanning)
        appendDiagnostic(localized("Scanning only for ECUMaster BLE interfaces"))
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
        appendDiagnostic(String(
            format: localized("Connecting to %@ [%@]"),
            device.name,
            device.id.uuidString
        ))
        if peripheral.state == .connected {
            activateConnectedPeripheral(peripheral)
            return
        }
        // CoreBluetooth rejects the combination of connection notification and
        // auto-reconnect options on the physical iPhone with CBError.invalidParameters.
        // We handle reconnects ourselves, so the plain BLE connection is sufficient.
        central.connect(peripheral, options: nil)
        scheduleConnectionTimeout(for: peripheral)
    }

    func disconnect() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        connectedIdentifier = nil
        connectedIsSimulator = false
        setState(.disconnected(nil))
    }

    private func setState(_ newState: BluetoothConnectionState) {
        state = newState
        onConnectionChanged?(newState)
    }

    private func activateConnectedPeripheral(_ peripheral: CBPeripheral) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        connectedPeripheral = peripheral
        connectedIdentifier = peripheral.identifier
        peripheral.delegate = self
        let discoveredName = devices.first(where: { $0.id == peripheral.identifier })?.name
        let name = discoveredName ?? peripheral.name ?? "ECUMaster interface"
        let isSimulator = Self.isSimulatorName(name)
        connectedIsSimulator = isSimulator
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
        if !isSimulator {
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastPeripheralKey)
        }
        setState(.connected(name))
        appendDiagnostic(localized("Connected; discovering GATT services"))
        bluetoothDebugLog("connected name=\(name) id=\(peripheral.identifier.uuidString)")
        peripheral.discoverServices(nil)
    }

    private func scheduleConnectionTimeout(for peripheral: CBPeripheral) {
        connectionTimeoutTask?.cancel()
        let identifier = peripheral.identifier
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self,
                  self.connectedPeripheral?.identifier == identifier,
                  !self.state.isConnected else { return }
            self.appendDiagnostic(localized("Connection timed out; continuing scan"))
            self.central.cancelPeripheralConnection(peripheral)
            self.connectedPeripheral = nil
            self.setState(.disconnected(localized("Connection timed out")))
            self.resumeScanning()
        }
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

    private static func isSimulatorName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("emulogger sim") || normalized.contains("touge dash simulator")
    }

    private static func isECUMasterAdvertisement(name: String, advertisementData: [String: Any]) -> Bool {
        if likelyEMUName(name) { return true }

        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
           serviceUUIDs.contains(CBUUID(string: "FFE0")) {
            return true
        }

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
        case .poweredOff: setState(.unavailable(localized("Bluetooth wyłączony")))
        case .unauthorized: setState(.unavailable(localized("Brak uprawnienia Bluetooth")))
        case .unsupported: setState(.unavailable(localized("BLE unsupported")))
        case .resetting: setState(.unavailable(localized("Restart Bluetooth")))
        case .unknown: setState(.unavailable(localized("Nieznany stan Bluetooth")))
        @unknown default: setState(.unavailable(localized("Bluetooth niedostępny")))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? localized("Unknown BLE device")
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
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        bluetoothDebugLog("connection failed name=\(peripheral.name ?? "unknown") error=\(error?.localizedDescription ?? "unknown")")
        appendDiagnostic(String(
            format: localized("Connection failed: %@"),
            error?.localizedDescription ?? localized("unknown error")
        ))
        setState(.disconnected(error?.localizedDescription))
        connectedPeripheral = nil
        connectedIdentifier = nil
        connectedIsSimulator = false
        resumeScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        bluetoothDebugLog("disconnected name=\(peripheral.name ?? "unknown") error=\(error?.localizedDescription ?? "none")")
        appendDiagnostic(String(
            format: localized("Disconnected: %@"),
            error?.localizedDescription ?? localized("connection closed")
        ))
        setState(.disconnected(error?.localizedDescription))
        connectedPeripheral = nil
        connectedIdentifier = nil
        connectedIsSimulator = false
        resumeScanning()
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let peripheral = restored.first else { return }
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripherals[peripheral.identifier] = peripheral
        bluetoothDebugLog("restored name=\(peripheral.name ?? "unknown") state=\(peripheral.state.rawValue)")
        appendDiagnostic(String(
            format: localized("Restored Bluetooth connection to %@"),
            peripheral.name ?? peripheral.identifier.uuidString
        ))
        if peripheral.state == .connected {
            activateConnectedPeripheral(peripheral)
        }
    }
}

extension BluetoothTelemetryService: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard invalidatedServices.contains(where: { $0.uuid == CBUUID(string: "FFE0") }) else { return }
        appendDiagnostic(localized("Simulator stopped service FFE0; reconnecting"))
        central.cancelPeripheralConnection(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appendDiagnostic(String(format: localized("Service discovery error: %@"), error.localizedDescription))
            return
        }
        for service in peripheral.services ?? [] {
            bluetoothDebugLog("service \(service.uuid.uuidString)")
            appendDiagnostic(String(format: localized("Service %@"), service.uuid.uuidString))
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendDiagnostic(String(format: localized("Characteristic discovery error: %@"), error.localizedDescription))
            return
        }
        for characteristic in service.characteristics ?? [] {
            let properties = characteristic.properties
            bluetoothDebugLog("characteristic \(characteristic.uuid.uuidString) properties=\(properties.rawValue)")
            appendDiagnostic(String(
                format: localized("Characteristic %@ properties=%lld"),
                characteristic.uuid.uuidString,
                Int64(properties.rawValue)
            ))
            if BluetoothTelemetryAccessPolicy.shouldSubscribe(to: properties) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if BluetoothTelemetryAccessPolicy.shouldRead(properties) {
                peripheral.readValue(for: characteristic)
            }
            if properties.contains(.write) || properties.contains(.writeWithoutResponse) {
                appendDiagnostic(String(
                    format: localized("Characteristic %@ offers writes; ignored by read-only policy"),
                    characteristic.uuid.uuidString
                ))
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendDiagnostic(String(
                format: localized("Notification error for %@: %@"),
                characteristic.uuid.uuidString,
                error.localizedDescription
            ))
        } else {
            appendDiagnostic(String(format: localized("Subscribed to %@"), characteristic.uuid.uuidString))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendDiagnostic(String(format: localized("Value error: %@"), error.localizedDescription))
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
