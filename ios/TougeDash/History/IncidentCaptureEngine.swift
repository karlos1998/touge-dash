import Foundation
import SwiftData

struct IncidentCaptureEngine: Sendable {
    struct Configuration: Equatable, Sendable {
        var sampleInterval: TimeInterval = 1.0 / 25.0
        var preTriggerDuration: TimeInterval = 30
        var postTriggerDuration: TimeInterval = 60
        var cooldown: TimeInterval = 300
        var lowOilPressureEnabled = true
        var lowOilPressureBar = 1.5
        var lowOilMinimumRPM = 3_000.0
        var lowOilDuration: TimeInterval = 0.75
        var leanUnderBoostEnabled = true
        var leanAFR = 13.5
        var leanMinimumBoostBar = 0.5
        var leanDuration: TimeInterval = 0.5
        var overboostEnabled = true
        var overboostBar = 1.5
        var overboostDuration: TimeInterval = 0.5
        var highCoolantTemperatureEnabled = true
        var coolantTemperatureCelsius = 110.0
        var coolantDuration: TimeInterval = 2
        var highOilTemperatureEnabled = true
        var oilTemperatureCelsius = 120.0
        var oilTemperatureDuration: TimeInterval = 2
        var lowBatteryVoltageEnabled = true
        var lowBatteryVoltage = 11.5
        var lowBatteryMinimumRPM = 800.0
        var lowBatteryDuration: TimeInterval = 3
        var lowFuelPressureEnabled = false
        var lowFuelPressureBar = 2.5
        var lowFuelPressureMinimumRPM = 1_500.0
        var lowFuelPressureDuration: TimeInterval = 1

        static let standard = Configuration()
    }

    struct CompletedIncident: Sendable {
        let id: UUID
        let kind: IncidentKind
        let severity: IncidentSeverity
        let triggeredAt: Date
        let thresholdValue: Double
        let triggerValue: Double
        let triggerUnit: String
        let conditionDuration: TimeInterval
        let samples: [CapturedTelemetryPoint]
    }

    private struct RuleMatch: Sendable {
        let kind: IncidentKind
        let severity: IncidentSeverity
        let value: Double
        let threshold: Double
        let unit: String
        let debounce: TimeInterval
    }

    private struct ActiveCapture: Sendable {
        let id: UUID
        let match: RuleMatch
        let triggeredAt: Date
        let finishAt: Date
        let conditionStartedAt: Date
        var conditionEndedAt: Date?
        var samples: [CapturedTelemetryPoint]
    }

    private(set) var configuration: Configuration
    private var preTriggerBuffer: [CapturedTelemetryPoint] = []
    private var activeCaptures: [IncidentKind: ActiveCapture] = [:]
    private var conditionStartedAt: [IncidentKind: Date] = [:]
    private var lastTriggeredAt: [IncidentKind: Date] = [:]
    private var lastAcceptedAt = Date.distantPast

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    mutating func ingest(_ point: CapturedTelemetryPoint) -> [CompletedIncident] {
        guard point.timestamp.timeIntervalSince(lastAcceptedAt) >= configuration.sampleInterval else { return [] }
        lastAcceptedAt = point.timestamp

        for kind in activeCaptures.keys {
            activeCaptures[kind]?.samples.append(point)
        }

        var completed: [CompletedIncident] = []
        for (kind, capture) in activeCaptures where point.timestamp >= capture.finishAt {
            completed.append(complete(capture))
            activeCaptures.removeValue(forKey: kind)
        }

        preTriggerBuffer.append(point)
        let oldestAllowed = point.timestamp.addingTimeInterval(-configuration.preTriggerDuration)
        if let firstValid = preTriggerBuffer.firstIndex(where: { $0.timestamp >= oldestAllowed }), firstValid > 0 {
            preTriggerBuffer.removeFirst(firstValid)
        }

        let matches = matchingRules(for: point)
        let matchingKinds = Set(matches.map(\.kind))
        for kind in IncidentKind.allCases where !matchingKinds.contains(kind) {
            if activeCaptures[kind]?.conditionEndedAt == nil {
                activeCaptures[kind]?.conditionEndedAt = point.timestamp
            }
            conditionStartedAt.removeValue(forKey: kind)
        }
        for match in matches {
            if conditionStartedAt[match.kind] == nil {
                conditionStartedAt[match.kind] = point.timestamp
            }
            guard activeCaptures[match.kind] == nil,
                  let startedAt = conditionStartedAt[match.kind],
                  point.timestamp.timeIntervalSince(startedAt) >= match.debounce,
                  lastTriggeredAt[match.kind].map({ point.timestamp.timeIntervalSince($0) >= configuration.cooldown }) ?? true else {
                continue
            }
            activeCaptures[match.kind] = ActiveCapture(
                id: UUID(),
                match: match,
                triggeredAt: point.timestamp,
                finishAt: point.timestamp.addingTimeInterval(configuration.postTriggerDuration),
                conditionStartedAt: startedAt,
                conditionEndedAt: nil,
                samples: preTriggerBuffer
            )
            lastTriggeredAt[match.kind] = point.timestamp
        }
        return completed.sorted { $0.triggeredAt < $1.triggeredAt }
    }

    mutating func finishActiveCaptures() -> [CompletedIncident] {
        let completed = activeCaptures.values.map(complete).sorted { $0.triggeredAt < $1.triggeredAt }
        activeCaptures.removeAll()
        conditionStartedAt.removeAll()
        return completed
    }

    mutating func reset() {
        preTriggerBuffer.removeAll(keepingCapacity: true)
        activeCaptures.removeAll()
        conditionStartedAt.removeAll()
        lastTriggeredAt.removeAll()
        lastAcceptedAt = .distantPast
    }

    mutating func updateConfiguration(_ configuration: Configuration) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        conditionStartedAt.removeAll()
    }

    private func complete(_ capture: ActiveCapture) -> CompletedIncident {
        CompletedIncident(
            id: capture.id,
            kind: capture.match.kind,
            severity: capture.match.severity,
            triggeredAt: capture.triggeredAt,
            thresholdValue: capture.match.threshold,
            triggerValue: capture.match.value,
            triggerUnit: capture.match.unit,
            conditionDuration: max(
                0,
                (capture.conditionEndedAt ?? capture.samples.last?.timestamp ?? capture.triggeredAt)
                    .timeIntervalSince(capture.conditionStartedAt)
            ),
            samples: capture.samples
        )
    }

    private func matchingRules(for point: CapturedTelemetryPoint) -> [RuleMatch] {
        var matches: [RuleMatch] = []
        if configuration.lowOilPressureEnabled,
           point.rpm >= configuration.lowOilMinimumRPM,
           point.oilPressureBar > 0,
           point.oilPressureBar < configuration.lowOilPressureBar {
            matches.append(RuleMatch(
                kind: .lowOilPressure,
                severity: .critical,
                value: point.oilPressureBar,
                threshold: configuration.lowOilPressureBar,
                unit: "bar",
                debounce: configuration.lowOilDuration
            ))
        }
        if configuration.leanUnderBoostEnabled,
           point.boostBar >= configuration.leanMinimumBoostBar,
           point.afr > configuration.leanAFR {
            matches.append(RuleMatch(
                kind: .leanUnderBoost,
                severity: .critical,
                value: point.afr,
                threshold: configuration.leanAFR,
                unit: "AFR",
                debounce: configuration.leanDuration
            ))
        }
        if configuration.overboostEnabled, point.boostBar > configuration.overboostBar {
            matches.append(RuleMatch(
                kind: .overboost,
                severity: .critical,
                value: point.boostBar,
                threshold: configuration.overboostBar,
                unit: "bar",
                debounce: configuration.overboostDuration
            ))
        }
        if configuration.highCoolantTemperatureEnabled,
           point.coolantCelsius >= configuration.coolantTemperatureCelsius {
            matches.append(RuleMatch(
                kind: .highCoolantTemperature,
                severity: .critical,
                value: point.coolantCelsius,
                threshold: configuration.coolantTemperatureCelsius,
                unit: "°C",
                debounce: configuration.coolantDuration
            ))
        }
        if configuration.highOilTemperatureEnabled,
           point.oilTemperatureCelsius >= configuration.oilTemperatureCelsius {
            matches.append(RuleMatch(
                kind: .highOilTemperature,
                severity: .critical,
                value: point.oilTemperatureCelsius,
                threshold: configuration.oilTemperatureCelsius,
                unit: "°C",
                debounce: configuration.oilTemperatureDuration
            ))
        }
        if configuration.lowBatteryVoltageEnabled,
           point.rpm >= configuration.lowBatteryMinimumRPM,
           point.batteryVoltage > 0,
           point.batteryVoltage < configuration.lowBatteryVoltage {
            matches.append(RuleMatch(
                kind: .lowBatteryVoltage,
                severity: .warning,
                value: point.batteryVoltage,
                threshold: configuration.lowBatteryVoltage,
                unit: "V",
                debounce: configuration.lowBatteryDuration
            ))
        }
        if configuration.lowFuelPressureEnabled,
           point.rpm >= configuration.lowFuelPressureMinimumRPM,
           point.fuelPressureBar > 0,
           point.fuelPressureBar < configuration.lowFuelPressureBar {
            matches.append(RuleMatch(
                kind: .lowFuelPressure,
                severity: .critical,
                value: point.fuelPressureBar,
                threshold: configuration.lowFuelPressureBar,
                unit: "bar",
                debounce: configuration.lowFuelPressureDuration
            ))
        }
        return matches
    }
}

@MainActor
final class TelemetryIncidentRecorder: ObservableObject {
    @Published private(set) var pendingIncidentCount = 0
    var onIncidentStored: ((Int) -> Void)?

    private let context: ModelContext
    private let locationTracker: LocationTrackingService
    private var vehicleID: UUID
    private var engine = IncidentCaptureEngine()
    private let alertRules: VehicleAlertRuleStore
    private var lastSessionID: UUID?

    init(
        container: ModelContainer,
        locationTracker: LocationTrackingService,
        alertRules: VehicleAlertRuleStore
    ) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.locationTracker = locationTracker
        self.alertRules = alertRules
        vehicleID = LocalVehicleIdentity.resolve()
        alertRules.activateVehicle(vehicleID)
        refreshPendingCount()
    }

    func activateVehicle(_ id: UUID) {
        guard id != vehicleID else { return }
        persist(engine.finishActiveCaptures(), sessionID: lastSessionID)
        vehicleID = id
        alertRules.activateVehicle(id)
        lastSessionID = nil
        engine.reset()
        refreshPendingCount()
    }

    func record(_ snapshot: TelemetrySnapshot, sessionID: UUID, at timestamp: Date = .now) {
        lastSessionID = sessionID
        engine.updateConfiguration(alertRules.rules(for: vehicleID).incidentConfiguration)
        let location = freshLocation(at: timestamp)
        let point = CapturedTelemetryPoint(snapshot: snapshot, timestamp: timestamp, location: location)
        persist(engine.ingest(point), sessionID: sessionID)
    }

    func finish(sessionID: UUID?) {
        persist(engine.finishActiveCaptures(), sessionID: sessionID ?? lastSessionID)
        try? context.save()
    }

    private func persist(_ completed: [IncidentCaptureEngine.CompletedIncident], sessionID: UUID?) {
        guard let sessionID else { return }
        for capture in completed {
            context.insert(DriveIncident(
                id: capture.id,
                vehicleID: vehicleID,
                sessionID: sessionID,
                kind: capture.kind,
                severity: capture.severity,
                triggeredAt: capture.triggeredAt,
                thresholdValue: capture.thresholdValue,
                triggerValue: capture.triggerValue,
                triggerUnit: capture.triggerUnit,
                conditionDuration: capture.conditionDuration,
                samples: capture.samples
            ))
        }
        if !completed.isEmpty {
            try? context.save()
            try? HistoryLocalStore.enforceRetention(in: context)
            refreshPendingCount()
            completed.forEach { onIncidentStored?($0.samples.count) }
        }
    }

    private func freshLocation(at timestamp: Date) -> RecordedLocation? {
        guard locationTracker.isEnabled,
              let location = locationTracker.latestLocation,
              abs(timestamp.timeIntervalSince(location.timestamp)) <= 30 else { return nil }
        return location
    }

    private func refreshPendingCount() {
        let descriptor = FetchDescriptor<DriveIncident>(predicate: #Predicate { $0.syncStateRaw != "synced" })
        pendingIncidentCount = (try? context.fetchCount(descriptor)) ?? 0
    }
}

private extension VehicleAlertRules {
    var incidentConfiguration: IncidentCaptureEngine.Configuration {
        var configuration = IncidentCaptureEngine.Configuration.standard
        configuration.cooldown = TimeInterval(cooldownSeconds)
        configuration.lowOilPressureEnabled = lowOilPressureEnabled
        configuration.lowOilPressureBar = minimumOilPressureBar
        configuration.lowOilMinimumRPM = lowOilMinimumRPM
        configuration.lowOilDuration = lowOilDurationSeconds
        configuration.leanUnderBoostEnabled = leanUnderBoostEnabled
        configuration.leanAFR = maximumAFR
        configuration.leanMinimumBoostBar = leanMinimumBoostBar
        configuration.leanDuration = leanDurationSeconds
        configuration.overboostEnabled = overboostEnabled
        configuration.overboostBar = maximumBoostBar
        configuration.overboostDuration = overboostDurationSeconds
        configuration.highCoolantTemperatureEnabled = highCoolantTemperatureEnabled
        configuration.coolantTemperatureCelsius = maximumCoolantCelsius
        configuration.coolantDuration = coolantDurationSeconds
        configuration.highOilTemperatureEnabled = highOilTemperatureEnabled
        configuration.oilTemperatureCelsius = maximumOilTemperatureCelsius
        configuration.oilTemperatureDuration = oilTemperatureDurationSeconds
        configuration.lowBatteryVoltageEnabled = lowBatteryVoltageEnabled
        configuration.lowBatteryVoltage = minimumBatteryVoltage
        configuration.lowBatteryMinimumRPM = lowBatteryMinimumRPM
        configuration.lowBatteryDuration = lowBatteryDurationSeconds
        configuration.lowFuelPressureEnabled = lowFuelPressureEnabled
        configuration.lowFuelPressureBar = minimumFuelPressureBar
        configuration.lowFuelPressureMinimumRPM = lowFuelPressureMinimumRPM
        configuration.lowFuelPressureDuration = lowFuelPressureDurationSeconds
        return configuration
    }
}
