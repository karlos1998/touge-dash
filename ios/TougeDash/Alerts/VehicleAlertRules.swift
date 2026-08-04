import Foundation

struct VehicleAlertRules: Codable, Equatable, Sendable {
    var cooldownSeconds = 300

    var lowOilPressureEnabled = true
    var minimumOilPressureBar = 1.5
    var lowOilMinimumRPM = 3_000.0
    var lowOilDurationSeconds = 0.75

    var leanUnderBoostEnabled = true
    var maximumAFR = 13.5
    var leanMinimumBoostBar = 0.5
    var leanDurationSeconds = 0.5

    var overboostEnabled = true
    var maximumBoostBar = 1.5
    var overboostDurationSeconds = 0.5

    var highCoolantTemperatureEnabled = true
    var maximumCoolantCelsius = 110.0
    var coolantDurationSeconds = 2.0

    var highOilTemperatureEnabled = true
    var maximumOilTemperatureCelsius = 120.0
    var oilTemperatureDurationSeconds = 2.0

    var lowBatteryVoltageEnabled = true
    var minimumBatteryVoltage = 11.5
    var lowBatteryMinimumRPM = 800.0
    var lowBatteryDurationSeconds = 3.0

    var lowFuelPressureEnabled = false
    var minimumFuelPressureBar = 2.5
    var lowFuelPressureMinimumRPM = 1_500.0
    var lowFuelPressureDurationSeconds = 1.0

    static let standard = VehicleAlertRules()

    func validated() -> VehicleAlertRules {
        var value = self
        value.cooldownSeconds = value.cooldownSeconds.clamped(to: 30...3_600)
        value.minimumOilPressureBar = value.minimumOilPressureBar.clamped(to: 0.1...10)
        value.lowOilMinimumRPM = value.lowOilMinimumRPM.clamped(to: 0...12_000)
        value.lowOilDurationSeconds = value.lowOilDurationSeconds.clamped(to: 0.1...30)
        value.maximumAFR = value.maximumAFR.clamped(to: 8...25)
        value.leanMinimumBoostBar = value.leanMinimumBoostBar.clamped(to: -1...5)
        value.leanDurationSeconds = value.leanDurationSeconds.clamped(to: 0.1...30)
        value.maximumBoostBar = value.maximumBoostBar.clamped(to: 0...5)
        value.overboostDurationSeconds = value.overboostDurationSeconds.clamped(to: 0.1...30)
        value.maximumCoolantCelsius = value.maximumCoolantCelsius.clamped(to: 70...180)
        value.coolantDurationSeconds = value.coolantDurationSeconds.clamped(to: 0.1...30)
        value.maximumOilTemperatureCelsius = value.maximumOilTemperatureCelsius.clamped(to: 70...200)
        value.oilTemperatureDurationSeconds = value.oilTemperatureDurationSeconds.clamped(to: 0.1...30)
        value.minimumBatteryVoltage = value.minimumBatteryVoltage.clamped(to: 8...16)
        value.lowBatteryMinimumRPM = value.lowBatteryMinimumRPM.clamped(to: 0...12_000)
        value.lowBatteryDurationSeconds = value.lowBatteryDurationSeconds.clamped(to: 0.1...30)
        value.minimumFuelPressureBar = value.minimumFuelPressureBar.clamped(to: 0.1...20)
        value.lowFuelPressureMinimumRPM = value.lowFuelPressureMinimumRPM.clamped(to: 0...12_000)
        value.lowFuelPressureDurationSeconds = value.lowFuelPressureDurationSeconds.clamped(to: 0.1...30)
        return value
    }

    func applyingWarningState(to snapshot: TelemetrySnapshot) -> TelemetrySnapshot {
        let rules = validated()
        var value = snapshot
        let coolantWarning = rules.highCoolantTemperatureEnabled &&
            snapshot.coolantCelsius >= rules.maximumCoolantCelsius
        let oilTemperatureWarning = rules.highOilTemperatureEnabled &&
            snapshot.oilTemperatureCelsius >= rules.maximumOilTemperatureCelsius
        let batteryWarning = rules.lowBatteryVoltageEnabled &&
            snapshot.rpm >= rules.lowBatteryMinimumRPM &&
            snapshot.batteryVoltage > 0 &&
            snapshot.batteryVoltage < rules.minimumBatteryVoltage
        let oilPressureWarning = rules.lowOilPressureEnabled &&
            snapshot.rpm >= rules.lowOilMinimumRPM &&
            snapshot.oilPressureBar > 0 &&
            snapshot.oilPressureBar < rules.minimumOilPressureBar
        let leanWarning = rules.leanUnderBoostEnabled &&
            snapshot.boostBar >= rules.leanMinimumBoostBar &&
            snapshot.afr > rules.maximumAFR
        let overboostWarning = rules.overboostEnabled && snapshot.boostBar > rules.maximumBoostBar
        let fuelPressureWarning = rules.lowFuelPressureEnabled &&
            snapshot.rpm >= rules.lowFuelPressureMinimumRPM &&
            snapshot.fuelPressureBar > 0 &&
            snapshot.fuelPressureBar < rules.minimumFuelPressureBar

        value.configuredCoolantWarning = coolantWarning
        value.configuredOilTemperatureWarning = oilTemperatureWarning
        value.configuredBatteryVoltageWarning = batteryWarning
        value.configuredCriticalWarning = snapshot.hasCheckEngine || coolantWarning || oilTemperatureWarning ||
            batteryWarning || oilPressureWarning || leanWarning || overboostWarning || fuelPressureWarning
        return value
    }
}

struct CloudVehicleAlertConfiguration: Codable, Equatable, Sendable {
    let vehicleId: UUID
    let revision: Int
    let cooldownSeconds: Int
    let lowOilPressureEnabled: Bool
    let minimumOilPressureBar: Double
    let lowOilMinimumRpm: Double
    let lowOilDurationSeconds: Double
    let leanUnderBoostEnabled: Bool
    let maximumAfr: Double
    let leanMinimumBoostBar: Double
    let leanDurationSeconds: Double
    let overboostEnabled: Bool
    let maximumBoostBar: Double
    let overboostDurationSeconds: Double
    let highCoolantTemperatureEnabled: Bool
    let maximumCoolantCelsius: Double
    let coolantDurationSeconds: Double
    let highOilTemperatureEnabled: Bool
    let maximumOilTemperatureCelsius: Double
    let oilTemperatureDurationSeconds: Double
    let lowBatteryVoltageEnabled: Bool
    let minimumBatteryVoltage: Double
    let lowBatteryMinimumRpm: Double
    let lowBatteryDurationSeconds: Double
    let lowFuelPressureEnabled: Bool
    let minimumFuelPressureBar: Double
    let lowFuelPressureMinimumRpm: Double
    let lowFuelPressureDurationSeconds: Double
    let updatedByAccountId: UUID?
    let updatedByDisplayName: String?
    let updatedAt: Date

    var rules: VehicleAlertRules {
        VehicleAlertRules(
            cooldownSeconds: cooldownSeconds,
            lowOilPressureEnabled: lowOilPressureEnabled,
            minimumOilPressureBar: minimumOilPressureBar,
            lowOilMinimumRPM: lowOilMinimumRpm,
            lowOilDurationSeconds: lowOilDurationSeconds,
            leanUnderBoostEnabled: leanUnderBoostEnabled,
            maximumAFR: maximumAfr,
            leanMinimumBoostBar: leanMinimumBoostBar,
            leanDurationSeconds: leanDurationSeconds,
            overboostEnabled: overboostEnabled,
            maximumBoostBar: maximumBoostBar,
            overboostDurationSeconds: overboostDurationSeconds,
            highCoolantTemperatureEnabled: highCoolantTemperatureEnabled,
            maximumCoolantCelsius: maximumCoolantCelsius,
            coolantDurationSeconds: coolantDurationSeconds,
            highOilTemperatureEnabled: highOilTemperatureEnabled,
            maximumOilTemperatureCelsius: maximumOilTemperatureCelsius,
            oilTemperatureDurationSeconds: oilTemperatureDurationSeconds,
            lowBatteryVoltageEnabled: lowBatteryVoltageEnabled,
            minimumBatteryVoltage: minimumBatteryVoltage,
            lowBatteryMinimumRPM: lowBatteryMinimumRpm,
            lowBatteryDurationSeconds: lowBatteryDurationSeconds,
            lowFuelPressureEnabled: lowFuelPressureEnabled,
            minimumFuelPressureBar: minimumFuelPressureBar,
            lowFuelPressureMinimumRPM: lowFuelPressureMinimumRpm,
            lowFuelPressureDurationSeconds: lowFuelPressureDurationSeconds
        ).validated()
    }
}

struct CloudVehicleAlertConfigurationUpdate: Encodable, Sendable {
    let revision: Int
    let cooldownSeconds: Int
    let lowOilPressureEnabled: Bool
    let minimumOilPressureBar: Double
    let lowOilMinimumRpm: Double
    let lowOilDurationSeconds: Double
    let leanUnderBoostEnabled: Bool
    let maximumAfr: Double
    let leanMinimumBoostBar: Double
    let leanDurationSeconds: Double
    let overboostEnabled: Bool
    let maximumBoostBar: Double
    let overboostDurationSeconds: Double
    let highCoolantTemperatureEnabled: Bool
    let maximumCoolantCelsius: Double
    let coolantDurationSeconds: Double
    let highOilTemperatureEnabled: Bool
    let maximumOilTemperatureCelsius: Double
    let oilTemperatureDurationSeconds: Double
    let lowBatteryVoltageEnabled: Bool
    let minimumBatteryVoltage: Double
    let lowBatteryMinimumRpm: Double
    let lowBatteryDurationSeconds: Double
    let lowFuelPressureEnabled: Bool
    let minimumFuelPressureBar: Double
    let lowFuelPressureMinimumRpm: Double
    let lowFuelPressureDurationSeconds: Double

    init(rules: VehicleAlertRules, revision: Int) {
        let rules = rules.validated()
        self.revision = revision
        cooldownSeconds = rules.cooldownSeconds
        lowOilPressureEnabled = rules.lowOilPressureEnabled
        minimumOilPressureBar = rules.minimumOilPressureBar
        lowOilMinimumRpm = rules.lowOilMinimumRPM
        lowOilDurationSeconds = rules.lowOilDurationSeconds
        leanUnderBoostEnabled = rules.leanUnderBoostEnabled
        maximumAfr = rules.maximumAFR
        leanMinimumBoostBar = rules.leanMinimumBoostBar
        leanDurationSeconds = rules.leanDurationSeconds
        overboostEnabled = rules.overboostEnabled
        maximumBoostBar = rules.maximumBoostBar
        overboostDurationSeconds = rules.overboostDurationSeconds
        highCoolantTemperatureEnabled = rules.highCoolantTemperatureEnabled
        maximumCoolantCelsius = rules.maximumCoolantCelsius
        coolantDurationSeconds = rules.coolantDurationSeconds
        highOilTemperatureEnabled = rules.highOilTemperatureEnabled
        maximumOilTemperatureCelsius = rules.maximumOilTemperatureCelsius
        oilTemperatureDurationSeconds = rules.oilTemperatureDurationSeconds
        lowBatteryVoltageEnabled = rules.lowBatteryVoltageEnabled
        minimumBatteryVoltage = rules.minimumBatteryVoltage
        lowBatteryMinimumRpm = rules.lowBatteryMinimumRPM
        lowBatteryDurationSeconds = rules.lowBatteryDurationSeconds
        lowFuelPressureEnabled = rules.lowFuelPressureEnabled
        minimumFuelPressureBar = rules.minimumFuelPressureBar
        lowFuelPressureMinimumRpm = rules.lowFuelPressureMinimumRPM
        lowFuelPressureDurationSeconds = rules.lowFuelPressureDurationSeconds
    }
}

@MainActor
final class VehicleAlertRuleStore: ObservableObject {
    struct Record: Codable, Equatable, Sendable {
        var rules: VehicleAlertRules
        var revision: Int
        var dirty: Bool
        var updatedAt: Date?
        var updatedByDisplayName: String?
        var conflict: CloudVehicleAlertConfiguration?
    }

    @Published private(set) var activeVehicleID: UUID
    @Published private(set) var records: [String: Record]

    private static let defaultsKey = "TougeDash.vehicleAlertRules.v1"

    init(defaults: UserDefaults = .standard) {
        activeVehicleID = LocalVehicleIdentity.resolve(defaults: defaults)
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder.tougeDashCloud().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
        self.defaults = defaults
    }

    private let defaults: UserDefaults

    var activeRecord: Record { record(for: activeVehicleID) }
    var activeRules: VehicleAlertRules { activeRecord.rules }

    func activateVehicle(_ id: UUID) {
        activeVehicleID = id
    }

    func record(for vehicleID: UUID) -> Record {
        records[vehicleID.uuidString] ?? Record(
            rules: .standard,
            revision: 1,
            dirty: false,
            updatedAt: nil,
            updatedByDisplayName: nil,
            conflict: nil
        )
    }

    func rules(for vehicleID: UUID) -> VehicleAlertRules {
        record(for: vehicleID).rules
    }

    func saveLocally(_ rules: VehicleAlertRules, for vehicleID: UUID) {
        var record = record(for: vehicleID)
        record.rules = rules.validated()
        record.dirty = true
        record.conflict = nil
        records[vehicleID.uuidString] = record
        persist()
    }

    func applyRemote(_ remote: CloudVehicleAlertConfiguration, to vehicleID: UUID) {
        let local = record(for: vehicleID)
        guard !local.dirty else {
            if remote.revision > local.revision {
                var conflicted = local
                conflicted.conflict = remote
                records[vehicleID.uuidString] = conflicted
                persist()
            }
            return
        }
        store(remote, for: vehicleID)
    }

    func markUploaded(_ remote: CloudVehicleAlertConfiguration, for vehicleID: UUID) {
        store(remote, for: vehicleID)
    }

    func acceptRemoteConflict(for vehicleID: UUID) {
        guard let remote = record(for: vehicleID).conflict else { return }
        store(remote, for: vehicleID)
    }

    func keepLocalAfterConflict(for vehicleID: UUID) {
        var record = record(for: vehicleID)
        guard let remote = record.conflict else { return }
        record.revision = remote.revision
        record.conflict = nil
        record.dirty = true
        records[vehicleID.uuidString] = record
        persist()
    }

    private func store(_ remote: CloudVehicleAlertConfiguration, for vehicleID: UUID) {
        records[vehicleID.uuidString] = Record(
            rules: remote.rules,
            revision: remote.revision,
            dirty: false,
            updatedAt: remote.updatedAt,
            updatedByDisplayName: remote.updatedByDisplayName,
            conflict: nil
        )
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder.tougeDashCloud().encode(records) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
