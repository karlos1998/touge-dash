@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class BLEPeripheralSimulator: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "FFE0")
    static let characteristicUUID = CBUUID(string: "FFE1")
    static let advertisedName = "EMULOGGER SIM"

    @Published private(set) var bluetoothState = CBManagerState.unknown
    @Published private(set) var isAdvertising = false
    @Published private(set) var subscriberCount = 0
    @Published private(set) var notificationCount = 0
    @Published private(set) var byteCount = 0
    @Published private(set) var lastPacketHex = "—"
    @Published private(set) var controlState = SimulatorControlState()
    @Published private(set) var lastError: String?

    private var manager: CBPeripheralManager!
    private var characteristic: CBMutableCharacteristic?
    private var wantsAdvertising = false
    private var subscribedCentralIDs = Set<UUID>()
    private var pendingChunks: [Data] = []
    private var latestTelemetryPayload = Data()
    private var latestPayload = Data()

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    var statusText: String {
        if let lastError { return lastError }
        switch bluetoothState {
        case .poweredOn:
            if subscriberCount > 0 { return "iPhone połączony · wysyłanie telemetrii" }
            return isAdvertising ? "Czekam na iPhone’a" : "Logger zatrzymany"
        case .poweredOff: return "Bluetooth jest wyłączony"
        case .unauthorized: return "Brak zgody na Bluetooth"
        case .unsupported: return "Ten Mac nie obsługuje BLE peripheral"
        case .resetting: return "Bluetooth uruchamia się ponownie"
        case .unknown: return "Przygotowywanie Bluetooth…"
        @unknown default: return "Bluetooth jest niedostępny"
        }
    }

    func start() {
        wantsAdvertising = true
        lastError = nil
        guard bluetoothState == .poweredOn else { return }
        publishService()
    }

    func stop() {
        wantsAdvertising = false
        manager.stopAdvertising()
        manager.removeAllServices()
        characteristic = nil
        pendingChunks.removeAll()
        subscribedCentralIDs.removeAll()
        subscriberCount = 0
        isAdvertising = false
    }

    func send(_ payload: Data) {
        latestTelemetryPayload = payload
        publishLatestPayload()
    }

    private func publishLatestPayload() {
        latestPayload = latestTelemetryPayload + EMUFrameCodec.encodeControlLoopback(controlState)
        guard wantsAdvertising, subscriberCount > 0, characteristic != nil else { return }
        pendingChunks = chunks(for: latestPayload)
        drainPendingChunks()
    }

    func resetCounters() {
        notificationCount = 0
        byteCount = 0
        lastPacketHex = "—"
    }

    private func publishService() {
        manager.stopAdvertising()
        manager.removeAllServices()
        subscribedCentralIDs.removeAll()
        subscriberCount = 0

        let characteristic = CBMutableCharacteristic(
            type: Self.characteristicUUID,
            properties: [.read, .notify, .write],
            value: nil,
            permissions: [.readable, .writeable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        self.characteristic = characteristic
        manager.add(service)
    }

    private func startAdvertising() {
        guard wantsAdvertising else { return }
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: Self.advertisedName,
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
        ])
    }

    private func chunks(for payload: Data) -> [Data] {
        let centrals = characteristic?.subscribedCentrals ?? []
        let negotiatedSize = centrals.map(\.maximumUpdateValueLength).min() ?? 20
        let chunkSize = max(5, negotiatedSize)
        return stride(from: 0, to: payload.count, by: chunkSize).map { offset in
            payload.subdata(in: offset..<min(payload.count, offset + chunkSize))
        }
    }

    private func drainPendingChunks() {
        guard let characteristic else { return }
        while let chunk = pendingChunks.first {
            guard manager.updateValue(chunk, for: characteristic, onSubscribedCentrals: nil) else { return }
            pendingChunks.removeFirst()
            notificationCount += 1
            byteCount += chunk.count
            lastPacketHex = chunk.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }
}

extension BLEPeripheralSimulator: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        bluetoothState = peripheral.state
        if peripheral.state == .poweredOn, wantsAdvertising {
            publishService()
        } else if peripheral.state != .poweredOn {
            isAdvertising = false
            subscriberCount = 0
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            lastError = "Nie udało się wystawić FFE0: \(error.localizedDescription)"
            return
        }
        startAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            lastError = "Reklamowanie BLE nie wystartowało: \(error.localizedDescription)"
            isAdvertising = false
        } else {
            lastError = nil
            isAdvertising = peripheral.isAdvertising
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscribedCentralIDs.insert(central.identifier)
        subscriberCount = subscribedCentralIDs.count
        publishLatestPayload()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscribedCentralIDs.remove(central.identifier)
        subscriberCount = subscribedCentralIDs.count
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        drainPendingChunks()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == Self.characteristicUUID else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        guard request.offset <= latestPayload.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = latestPayload.subdata(in: request.offset..<latestPayload.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == Self.characteristicUUID,
                  let value = request.value,
                  let decoded = EMUFrameCodec.decodeControlStatus(value) else {
                peripheral.respond(to: request, withResult: .unlikelyError)
                continue
            }
            controlState = decoded
            peripheral.respond(to: request, withResult: .success)
            publishLatestPayload()
        }
    }
}
