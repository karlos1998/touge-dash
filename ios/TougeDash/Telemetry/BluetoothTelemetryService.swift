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

/// The telemetry path is passive: it only reads and subscribes. Optional BT
/// control cards use the separate, tightly scoped policy below.
enum BluetoothTelemetryAccessPolicy {
    static let allowsCharacteristicWrites = false

    static func shouldSubscribe(to properties: CBCharacteristicProperties) -> Bool {
        properties.contains(.notify) || properties.contains(.indicate)
    }

    static func shouldRead(_ properties: CBCharacteristicProperties) -> Bool {
        properties.contains(.read)
    }
}

/// ECU control is intentionally separate from the passive telemetry contract.
/// Only the two profiles observed in eDash are accepted; an arbitrary writable
/// characteristic must never become a control target.
enum ECUControlTransportPolicy {
    static let nordicUARTService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let nordicUARTRX = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let emuService = CBUUID(string: "FFE0")
    static let emuCharacteristic = CBUUID(string: "FFE1")

    static func priority(service: CBUUID, characteristic: CBUUID) -> Int? {
        if service == nordicUARTService, characteristic == nordicUARTRX { return 2 }
        if service == emuService, characteristic == emuCharacteristic { return 1 }
        return nil
    }
}

private enum ECUControlTransportError: LocalizedError {
    case unavailable
    case busy
    case rejected
    case disconnected

    var errorDescription: String? {
        switch self {
        case .unavailable: localized("Brak zatwierdzonego kanału zapisu ECU.")
        case .busy: localized("Poprzednia zmiana nadal jest wysyłana.")
        case .rejected: localized("Bluetooth odrzucił ramkę sterującą.")
        case .disconnected: localized("Połączenie Bluetooth zostało przerwane.")
        }
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
    @Published private(set) var controlTransportAvailable = false

    var onBytes: ((Data) -> Void)?
    var onConnectionChanged: ((BluetoothConnectionState) -> Void)?
    var onControlTransportChanged: ((Bool) -> Void)?

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var shouldScan = false
    private var attemptedAutomaticConnection = false
    private var hasTriedRememberedPeripheral = false
    private var connectionTimeoutTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var retryDelayAfterRequestedDisconnect: Duration?
    private var totalPacketCount = 0
    private var totalByteCount = 0
    private var lastCounterPublishAt = Date.distantPast
    private var controlCharacteristic: CBCharacteristic?
    private var controlCharacteristicPriority = 0
    private var pendingControlWrite: (characteristicID: CBUUID, completion: (Result<Void, Error>) -> Void)?
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
                // v3 drops the stale restoration and pending connection records
                // created while the desktop simulator advertised the real logger
                // name and while the Mac/iPhone pairing keys were being repaired.
                CBCentralManagerOptionRestoreIdentifierKey: "it.letscode.touge-dash.central.v3"
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

    private func resumeScanning(after delay: Duration) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.resumeScanning()
        }
    }

    private func beginScanning(tryRememberedPeripheral: Bool) {
        bluetoothDebugLog("start scanning centralState=\(central.state.rawValue)")
        guard central.state == .poweredOn else { return }
        guard !state.isConnected else { return }
        if case .connecting = state { return }
        devices = []
        peripherals = [:]
        attemptedAutomaticConnection = false
        totalPacketCount = 0
        totalByteCount = 0
        lastCounterPublishAt = .distantPast
        receivedPacketCount = 0
        receivedByteCount = 0
        lastPacketHex = ""

        if tryRememberedPeripheral,
           let storedIdentifier = UserDefaults.standard.string(forKey: lastPeripheralKey),
           let identifier = UUID(uuidString: storedIdentifier),
           let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            let rememberedName = peripheral.name ?? "ECUMaster"
            if Self.isMacHostPeripheralName(rememberedName) {
                // A previous simulator build advertised the exact real-logger
                // name, so iOS persisted the Mac itself as the last ECU. Never
                // restore that stale host identity as a vehicle interface.
                UserDefaults.standard.removeObject(forKey: lastPeripheralKey)
                appendDiagnostic(localized("Removed stale Mac simulator Bluetooth identity"))
            } else {
                let remembered = DiscoveredTelemetryDevice(
                    id: peripheral.identifier,
                    name: rememberedName,
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
        }

        setState(.scanning)
        appendDiagnostic(localized("Scanning only for ECUMaster BLE interfaces"))
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        shouldScan = false
        reconnectTask?.cancel()
        reconnectTask = nil
        central.stopScan()
        if !state.isConnected { setState(.ready) }
    }

    func connect(to device: DiscoveredTelemetryDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
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
        reconnectTask?.cancel()
        reconnectTask = nil
        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        connectedIdentifier = nil
        connectedIsSimulator = false
        resetControlTransport(error: ECUControlTransportError.disconnected)
        setState(.disconnected(nil))
    }

    func writeControlFrame(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        guard ECUControlSnapshot.isValidStatusFrame(data),
              let peripheral = connectedPeripheral,
              peripheral.state == .connected,
              let characteristic = controlCharacteristic else {
            completion(.failure(ECUControlTransportError.unavailable))
            return
        }
        guard pendingControlWrite == nil else {
            completion(.failure(ECUControlTransportError.busy))
            return
        }

        let properties = characteristic.properties
        let writeType: CBCharacteristicWriteType
        if properties.contains(.write) {
            writeType = .withResponse
        } else if properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else {
            completion(.failure(ECUControlTransportError.unavailable))
            return
        }

        pendingControlWrite = (characteristic.uuid, completion)
        peripheral.writeValue(data, for: characteristic, type: writeType)
        appendDiagnostic("ECU TX [\(characteristic.uuid.uuidString)] \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        if writeType == .withoutResponse {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, let pending = self.pendingControlWrite,
                      pending.characteristicID == characteristic.uuid else { return }
                self.pendingControlWrite = nil
                pending.completion(.success(()))
            }
        }
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
        resetControlTransport()
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
            // CoreBluetooth may need several seconds to recover after either
            // side has removed an obsolete BLE bond. Cancelling at six seconds
            // caused a permanent connect/scan loop even though the peripheral
            // was healthy and advertising.
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self,
                  self.connectedPeripheral?.identifier == identifier,
                  !self.state.isConnected else { return }
            self.appendDiagnostic(localized("Connection timed out; continuing scan"))
            self.retryDelayAfterRequestedDisconnect = .seconds(3)
            self.central.cancelPeripheralConnection(peripheral)
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

    private static func isMacHostPeripheralName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("macbook")
            || normalized.contains("mac mini")
            || normalized.contains("mac studio")
            || normalized.contains("imac")
    }

    private static func requiresPairingRecoveryDelay(_ error: Error?) -> Bool {
        guard let error = error as NSError?, error.domain == CBErrorDomain else { return false }
        return error.code == CBError.peerRemovedPairingInformation.rawValue
            || error.code == CBError.encryptionTimedOut.rawValue
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

    private func considerControlCharacteristic(_ characteristic: CBCharacteristic, service: CBService) {
        guard characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse),
              let priority = ECUControlTransportPolicy.priority(
                service: service.uuid,
                characteristic: characteristic.uuid
              ), priority > controlCharacteristicPriority else {
            return
        }
        controlCharacteristic = characteristic
        controlCharacteristicPriority = priority
        controlTransportAvailable = true
        onControlTransportChanged?(true)
        appendDiagnostic(String(format: localized("Zatwierdzony kanał sterowania ECU: %@"), characteristic.uuid.uuidString))
    }

    private func resetControlTransport(error: Error? = nil) {
        controlCharacteristic = nil
        controlCharacteristicPriority = 0
        if controlTransportAvailable {
            controlTransportAvailable = false
            onControlTransportChanged?(false)
        }
        if let pending = pendingControlWrite {
            pendingControlWrite = nil
            pending.completion(.failure(error ?? ECUControlTransportError.unavailable))
        }
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
        resetControlTransport(error: error ?? ECUControlTransportError.disconnected)
        if Self.requiresPairingRecoveryDelay(error) {
            appendDiagnostic(localized("Bluetooth pairing changed; retrying after recovery delay"))
            resumeScanning(after: .seconds(8))
        } else {
            resumeScanning()
        }
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
        resetControlTransport(error: error ?? ECUControlTransportError.disconnected)
        let requestedRetryDelay = retryDelayAfterRequestedDisconnect
        retryDelayAfterRequestedDisconnect = nil
        if Self.requiresPairingRecoveryDelay(error) {
            appendDiagnostic(localized("Bluetooth pairing changed; retrying after recovery delay"))
            resumeScanning(after: .seconds(8))
        } else if let requestedRetryDelay {
            resumeScanning(after: requestedRetryDelay)
        } else {
            resumeScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let peripheral = restored.first else { return }
        let restoredName = peripheral.name ?? ""
        if Self.isMacHostPeripheralName(restoredName) {
            UserDefaults.standard.removeObject(forKey: lastPeripheralKey)
            central.cancelPeripheralConnection(peripheral)
            appendDiagnostic(localized("Ignored stale restored Mac simulator connection"))
            return
        }
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
                if ECUControlTransportPolicy.priority(service: service.uuid, characteristic: characteristic.uuid) != nil {
                    considerControlCharacteristic(characteristic, service: service)
                } else {
                    appendDiagnostic(String(
                        format: localized("Characteristic %@ offers writes; ignored by read-only policy"),
                        characteristic.uuid.uuidString
                    ))
                }
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
        totalPacketCount += 1
        totalByteCount += value.count
        let packetHex = value.prefix(40).map { String(format: "%02X", $0) }.joined(separator: " ")
        if totalPacketCount <= 10 || totalPacketCount.isMultiple(of: 100) {
            bluetoothDebugLog("RX #\(totalPacketCount) [\(characteristic.uuid.uuidString)] \(packetHex)")
        }
        if totalPacketCount <= 10 || totalPacketCount.isMultiple(of: 100) {
            appendDiagnostic("RX #\(totalPacketCount) [\(characteristic.uuid.uuidString)] \(packetHex)")
        }
        let now = Date.now
        if totalPacketCount == 1 || now.timeIntervalSince(lastCounterPublishAt) >= 0.2 {
            receivedPacketCount = totalPacketCount
            receivedByteCount = totalByteCount
            lastPacketHex = packetHex
            lastCounterPublishAt = now
        }
        onBytes?(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let pending = pendingControlWrite,
              pending.characteristicID == characteristic.uuid else { return }
        pendingControlWrite = nil
        if let error {
            appendDiagnostic(String(format: localized("Błąd zapisu sterowania ECU: %@"), error.localizedDescription))
            pending.completion(.failure(error))
        } else {
            pending.completion(.success(()))
        }
    }
}
