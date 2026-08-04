import Foundation
import SwiftData

struct IncidentCaptureEngine: Sendable {
    struct Configuration: Equatable, Sendable {
        var sampleInterval: TimeInterval = 1.0 / 25.0
        var preTriggerDuration: TimeInterval = 30
        var postTriggerDuration: TimeInterval = 60
        var cooldown: TimeInterval = 300
        var lowOilPressureBar = 1.5
        var lowOilMinimumRPM = 3_000.0
        var leanAFR = 13.5
        var leanMinimumBoostBar = 0.5
        var overboostBar = 1.5
        var coolantTemperatureCelsius = 110.0
        var oilTemperatureCelsius = 120.0
        var lowBatteryVoltage = 11.5
        var lowBatteryMinimumRPM = 800.0

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
        var samples: [CapturedTelemetryPoint]
    }

    let configuration: Configuration
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
                samples: preTriggerBuffer
            )
            lastTriggeredAt[match.kind] = point.timestamp
            conditionStartedAt.removeValue(forKey: match.kind)
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

    private func complete(_ capture: ActiveCapture) -> CompletedIncident {
        CompletedIncident(
            id: capture.id,
            kind: capture.match.kind,
            severity: capture.match.severity,
            triggeredAt: capture.triggeredAt,
            thresholdValue: capture.match.threshold,
            triggerValue: capture.match.value,
            triggerUnit: capture.match.unit,
            samples: capture.samples
        )
    }

    private func matchingRules(for point: CapturedTelemetryPoint) -> [RuleMatch] {
        var matches: [RuleMatch] = []
        if point.rpm >= configuration.lowOilMinimumRPM,
           point.oilPressureBar > 0,
           point.oilPressureBar < configuration.lowOilPressureBar {
            matches.append(RuleMatch(
                kind: .lowOilPressure,
                severity: .critical,
                value: point.oilPressureBar,
                threshold: configuration.lowOilPressureBar,
                unit: "bar",
                debounce: 0.75
            ))
        }
        if point.boostBar >= configuration.leanMinimumBoostBar,
           point.afr > configuration.leanAFR {
            matches.append(RuleMatch(
                kind: .leanUnderBoost,
                severity: .critical,
                value: point.afr,
                threshold: configuration.leanAFR,
                unit: "AFR",
                debounce: 0.5
            ))
        }
        if point.boostBar > configuration.overboostBar {
            matches.append(RuleMatch(
                kind: .overboost,
                severity: .critical,
                value: point.boostBar,
                threshold: configuration.overboostBar,
                unit: "bar",
                debounce: 0.5
            ))
        }
        if point.coolantCelsius >= configuration.coolantTemperatureCelsius {
            matches.append(RuleMatch(
                kind: .engineOverheat,
                severity: .critical,
                value: point.coolantCelsius,
                threshold: configuration.coolantTemperatureCelsius,
                unit: "°C",
                debounce: 2
            ))
        } else if point.oilTemperatureCelsius >= configuration.oilTemperatureCelsius {
            matches.append(RuleMatch(
                kind: .engineOverheat,
                severity: .critical,
                value: point.oilTemperatureCelsius,
                threshold: configuration.oilTemperatureCelsius,
                unit: "°C",
                debounce: 2
            ))
        }
        if point.rpm >= configuration.lowBatteryMinimumRPM,
           point.batteryVoltage > 0,
           point.batteryVoltage < configuration.lowBatteryVoltage {
            matches.append(RuleMatch(
                kind: .lowBatteryVoltage,
                severity: .warning,
                value: point.batteryVoltage,
                threshold: configuration.lowBatteryVoltage,
                unit: "V",
                debounce: 3
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
    private var lastSessionID: UUID?

    init(container: ModelContainer, locationTracker: LocationTrackingService) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.locationTracker = locationTracker
        vehicleID = LocalVehicleIdentity.resolve()
        refreshPendingCount()
    }

    func activateVehicle(_ id: UUID) {
        guard id != vehicleID else { return }
        persist(engine.finishActiveCaptures(), sessionID: lastSessionID)
        vehicleID = id
        lastSessionID = nil
        engine.reset()
        refreshPendingCount()
    }

    func record(_ snapshot: TelemetrySnapshot, sessionID: UUID, at timestamp: Date = .now) {
        lastSessionID = sessionID
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
                samples: capture.samples
            ))
        }
        if !completed.isEmpty {
            try? context.save()
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
