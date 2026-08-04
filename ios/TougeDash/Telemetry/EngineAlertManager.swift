@preconcurrency import UserNotifications
import Foundation

struct EngineAlertEvaluation: Equatable, Sendable {
    let active: [EngineAlertEvent]
    let triggered: [EngineAlertEvent]
}

struct EngineAlertEvaluator: Sendable {
    private struct Condition: Sendable {
        let kind: EngineAlertKind
        let severity: EngineAlertSeverity
        let value: Double
        let threshold: Double
        let unit: String
        let debounce: TimeInterval
    }

    private var conditionStartedAt: [EngineAlertKind: Date] = [:]
    private var activeEvents: [EngineAlertKind: EngineAlertEvent] = [:]
    private var lastTriggeredAt: [EngineAlertKind: Date] = [:]

    mutating func evaluate(
        _ snapshot: TelemetrySnapshot,
        rules: VehicleAlertRules,
        now: Date = .now
    ) -> EngineAlertEvaluation {
        let rules = rules.validated()
        let conditions = matchingConditions(snapshot, rules: rules)
        let matchingKinds = Set(conditions.map(\.kind))

        for kind in EngineAlertKind.allCases where !matchingKinds.contains(kind) {
            conditionStartedAt.removeValue(forKey: kind)
            activeEvents.removeValue(forKey: kind)
        }

        var triggered: [EngineAlertEvent] = []
        for condition in conditions {
            if activeEvents[condition.kind] != nil { continue }
            let startedAt = conditionStartedAt[condition.kind] ?? now
            conditionStartedAt[condition.kind] = startedAt
            guard now.timeIntervalSince(startedAt) >= condition.debounce else { continue }
            guard lastTriggeredAt[condition.kind].map({
                now.timeIntervalSince($0) >= TimeInterval(rules.cooldownSeconds)
            }) ?? true else { continue }

            let event = EngineAlertEvent(
                id: UUID(),
                kind: condition.kind,
                severity: condition.severity,
                value: condition.value,
                threshold: condition.threshold,
                unit: condition.unit,
                triggeredAt: now
            )
            activeEvents[condition.kind] = event
            lastTriggeredAt[condition.kind] = now
            triggered.append(event)
        }

        return EngineAlertEvaluation(
            active: activeEvents.values.sorted { $0.kind.rawValue < $1.kind.rawValue },
            triggered: triggered.sorted { $0.kind.rawValue < $1.kind.rawValue }
        )
    }

    private func matchingConditions(
        _ snapshot: TelemetrySnapshot,
        rules: VehicleAlertRules
    ) -> [Condition] {
        var matches: [Condition] = []
        if rules.lowOilPressureEnabled,
           snapshot.rpm >= rules.lowOilMinimumRPM,
           snapshot.oilPressureBar > 0,
           snapshot.oilPressureBar < rules.minimumOilPressureBar {
            matches.append(Condition(
                kind: .lowOilPressure, severity: .critical,
                value: snapshot.oilPressureBar, threshold: rules.minimumOilPressureBar,
                unit: "bar", debounce: rules.lowOilDurationSeconds
            ))
        }
        if rules.leanUnderBoostEnabled,
           snapshot.boostBar >= rules.leanMinimumBoostBar,
           snapshot.afr > rules.maximumAFR {
            matches.append(Condition(
                kind: .leanUnderBoost, severity: .critical,
                value: snapshot.afr, threshold: rules.maximumAFR,
                unit: "AFR", debounce: rules.leanDurationSeconds
            ))
        }
        if rules.overboostEnabled, snapshot.boostBar > rules.maximumBoostBar {
            matches.append(Condition(
                kind: .overboost, severity: .critical,
                value: snapshot.boostBar, threshold: rules.maximumBoostBar,
                unit: "bar", debounce: rules.overboostDurationSeconds
            ))
        }
        if rules.highCoolantTemperatureEnabled,
           snapshot.coolantCelsius >= rules.maximumCoolantCelsius {
            matches.append(Condition(
                kind: .highCoolantTemperature, severity: .critical,
                value: snapshot.coolantCelsius, threshold: rules.maximumCoolantCelsius,
                unit: "°C", debounce: rules.coolantDurationSeconds
            ))
        }
        if rules.highOilTemperatureEnabled,
           snapshot.oilTemperatureCelsius >= rules.maximumOilTemperatureCelsius {
            matches.append(Condition(
                kind: .highOilTemperature, severity: .critical,
                value: snapshot.oilTemperatureCelsius, threshold: rules.maximumOilTemperatureCelsius,
                unit: "°C", debounce: rules.oilTemperatureDurationSeconds
            ))
        }
        if rules.lowFuelPressureEnabled,
           snapshot.rpm >= rules.lowFuelPressureMinimumRPM,
           snapshot.fuelPressureBar > 0,
           snapshot.fuelPressureBar < rules.minimumFuelPressureBar {
            matches.append(Condition(
                kind: .lowFuelPressure, severity: .critical,
                value: snapshot.fuelPressureBar, threshold: rules.minimumFuelPressureBar,
                unit: "bar", debounce: rules.lowFuelPressureDurationSeconds
            ))
        }
        if rules.lowBatteryVoltageEnabled,
           snapshot.rpm >= rules.lowBatteryMinimumRPM,
           snapshot.batteryVoltage > 0,
           snapshot.batteryVoltage < rules.minimumBatteryVoltage {
            matches.append(Condition(
                kind: .lowBatteryVoltage, severity: .warning,
                value: snapshot.batteryVoltage, threshold: rules.minimumBatteryVoltage,
                unit: "V", debounce: rules.lowBatteryDurationSeconds
            ))
        }
        return matches
    }
}

@MainActor
final class EngineAlertManager: NSObject, UNUserNotificationCenterDelegate {
    private let notificationCenter = UNUserNotificationCenter.current()
    private var evaluator = EngineAlertEvaluator()
    private let criticalAlertsEnabled: Bool

    override init() {
        criticalAlertsEnabled = Self.criticalAlertsEnabledByBuild
        super.init()
        notificationCenter.delegate = self
        var options: UNAuthorizationOptions = [.alert, .sound]
        if criticalAlertsEnabled { options.insert(.criticalAlert) }
        notificationCenter.requestAuthorization(options: options) { _, _ in }
    }

    func evaluate(
        _ snapshot: TelemetrySnapshot,
        rules: VehicleAlertRules,
        now: Date = .now
    ) -> EngineAlertEvaluation {
        let result = evaluator.evaluate(snapshot, rules: rules, now: now)
        if !result.triggered.isEmpty { postNotification(for: result.triggered) }
        return result
    }

    private func postNotification(for events: [EngineAlertEvent]) {
        let isCritical = events.contains { $0.severity == .critical }
        let content = UNMutableNotificationContent()
        content.title = localized(isCritical ? "Touge Dash — krytyczny alert silnika" : "Touge Dash — ostrzeżenie silnika")
        content.body = warningDescription(for: events)
        if isCritical, criticalAlertsEnabled {
            content.sound = .defaultCritical
            content.interruptionLevel = .critical
        } else {
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        }
        content.relevanceScore = 1
        content.threadIdentifier = "touge-dash-engine-alerts"
        content.userInfo = ["alertEventIds": events.map(\.id.uuidString)]

        let identifier = "touge-dash-engine-alert-" + events.map { $0.kind.rawValue }.joined(separator: "-")
        notificationCenter.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private func warningDescription(for events: [EngineAlertEvent]) -> String {
        let warnings = events.map { event in
            "\(title(for: event.kind)): \(formatted(event.value, unit: event.unit))"
        }
        let isCritical = events.contains { $0.severity == .critical }
        let instruction = isCritical
            ? localized("Zjedź w bezpieczne miejsce, zatrzymaj auto i sprawdź silnik.")
            : localized("Sprawdź parametry instalacji i silnika.")
        return warnings.joined(separator: " • ") + ". " + instruction
    }

    private func title(for kind: EngineAlertKind) -> String {
        switch kind {
        case .lowOilPressure: localized("Niskie ciśnienie oleju")
        case .leanUnderBoost: localized("Uboga mieszanka pod boostem")
        case .overboost: localized("Przekroczone doładowanie")
        case .highCoolantTemperature: localized("Wysoka temperatura płynu")
        case .highOilTemperature: localized("Wysoka temperatura oleju")
        case .lowFuelPressure: localized("Niskie ciśnienie paliwa")
        case .lowBatteryVoltage: localized("Niskie napięcie")
        }
    }

    private func formatted(_ value: Double, unit: String) -> String {
        let precision = unit == "bar" || unit == "V" || unit == "AFR" ? 1 : 0
        return value.formatted(.number.precision(.fractionLength(precision))) + " " + unit
    }

    private static var criticalAlertsEnabledByBuild: Bool {
        if let enabled = Bundle.main.object(forInfoDictionaryKey: "TougeDashCriticalAlertsEnabled") as? Bool {
            return enabled
        }
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TougeDashCriticalAlertsEnabled") as? String else {
            return false
        }
        return (value as NSString).boolValue
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
