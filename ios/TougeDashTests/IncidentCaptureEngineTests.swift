import XCTest
@testable import TougeDash

final class IncidentCaptureEngineTests: XCTestCase {
    func testNotificationEvaluatorTriggersEveryConfiguredRuleAfterItsDebounce() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let scenarios: [(EngineAlertKind, VehicleAlertRules, TelemetrySnapshot, TimeInterval)] = [
            (.lowOilPressure, Self.isolatedRules { $0.lowOilPressureEnabled = true },
             Self.telemetry(rpm: 4_000, oilPressure: 1.0), 0.75),
            (.leanUnderBoost, Self.isolatedRules { $0.leanUnderBoostEnabled = true },
             Self.telemetry(boost: 0.8, afr: 14.2), 0.5),
            (.overboost, Self.isolatedRules { $0.overboostEnabled = true },
             Self.telemetry(boost: 1.8), 0.5),
            (.highCoolantTemperature, Self.isolatedRules { $0.highCoolantTemperatureEnabled = true },
             Self.telemetry(coolant: 115), 2),
            (.highOilTemperature, Self.isolatedRules { $0.highOilTemperatureEnabled = true },
             Self.telemetry(oilTemperature: 125), 2),
            (.lowFuelPressure, Self.isolatedRules { $0.lowFuelPressureEnabled = true },
             Self.telemetry(rpm: 3_000, fuelPressure: 2.0), 1),
            (.lowBatteryVoltage, Self.isolatedRules { $0.lowBatteryVoltageEnabled = true },
             Self.telemetry(rpm: 1_500, battery: 10.8), 3),
        ]

        for (kind, rules, snapshot, debounce) in scenarios {
            var evaluator = EngineAlertEvaluator()
            XCTAssertTrue(evaluator.evaluate(snapshot, rules: rules, now: start).triggered.isEmpty)
            let result = evaluator.evaluate(
                snapshot,
                rules: rules,
                now: start.addingTimeInterval(debounce + 0.01)
            )
            XCTAssertEqual(result.triggered.map(\.kind), [kind], "Missing notification for \(kind)")
            XCTAssertEqual(result.active.map(\.kind), [kind])
        }
    }

    func testNotificationEvaluatorRespectsCooldownWithoutLosingActiveState() {
        var rules = Self.isolatedRules { $0.overboostEnabled = true }
        rules.cooldownSeconds = 30
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let overboost = Self.telemetry(boost: 1.8)
        let safe = Self.telemetry(boost: 0.2)
        var evaluator = EngineAlertEvaluator()

        _ = evaluator.evaluate(overboost, rules: rules, now: start)
        XCTAssertEqual(
            evaluator.evaluate(overboost, rules: rules, now: start.addingTimeInterval(0.6)).triggered.count,
            1
        )
        XCTAssertTrue(evaluator.evaluate(safe, rules: rules, now: start.addingTimeInterval(1)).active.isEmpty)
        _ = evaluator.evaluate(overboost, rules: rules, now: start.addingTimeInterval(2))
        XCTAssertTrue(
            evaluator.evaluate(overboost, rules: rules, now: start.addingTimeInterval(3)).triggered.isEmpty
        )
        XCTAssertEqual(
            evaluator.evaluate(overboost, rules: rules, now: start.addingTimeInterval(31)).triggered.count,
            1
        )
    }

    private static func isolatedRules(_ configure: (inout VehicleAlertRules) -> Void) -> VehicleAlertRules {
        var rules = VehicleAlertRules.standard
        rules.lowOilPressureEnabled = false
        rules.leanUnderBoostEnabled = false
        rules.overboostEnabled = false
        rules.highCoolantTemperatureEnabled = false
        rules.highOilTemperatureEnabled = false
        rules.lowBatteryVoltageEnabled = false
        rules.lowFuelPressureEnabled = false
        configure(&rules)
        return rules
    }

    private static func telemetry(
        rpm: Double = 1_000,
        boost: Double = 0,
        coolant: Double = 90,
        oilTemperature: Double = 100,
        oilPressure: Double = 4,
        fuelPressure: Double = 3.5,
        afr: Double = 12.5,
        battery: Double = 13.8
    ) -> TelemetrySnapshot {
        TelemetrySnapshot(
            rpm: rpm,
            boostBar: boost,
            coolantCelsius: coolant,
            oilTemperatureCelsius: oilTemperature,
            oilPressureBar: oilPressure,
            fuelPressureBar: fuelPressure,
            afr: afr,
            batteryVoltage: battery
        )
    }

    func testLowOilPressureReportContainsPreAndPostTriggerSamplesAtTwentyFiveHertz() {
        var configuration = IncidentCaptureEngine.Configuration.standard
        configuration.preTriggerDuration = 0.4
        configuration.postTriggerDuration = 0.4
        configuration.cooldown = 10
        var engine = IncidentCaptureEngine(configuration: configuration)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var completed: [IncidentCaptureEngine.CompletedIncident] = []

        for index in 0..<12 {
            completed += engine.ingest(point(at: start.addingTimeInterval(Double(index) * 0.041)))
        }
        for index in 12..<36 {
            completed += engine.ingest(point(
                at: start.addingTimeInterval(Double(index) * 0.041),
                rpm: 4_200,
                oilPressure: 1.1
            ))
        }
        for index in 36..<52 {
            completed += engine.ingest(point(at: start.addingTimeInterval(Double(index) * 0.041)))
        }

        XCTAssertEqual(completed.count, 1)
        let incident = try! XCTUnwrap(completed.first)
        XCTAssertEqual(incident.kind, .lowOilPressure)
        XCTAssertEqual(incident.severity, .critical)
        XCTAssertEqual(incident.triggerValue, 1.1, accuracy: 0.001)
        XCTAssertEqual(incident.thresholdValue, 1.5, accuracy: 0.001)
        XCTAssertLessThanOrEqual(incident.samples.first!.timestamp, incident.triggeredAt.addingTimeInterval(-0.35))
        XCTAssertGreaterThanOrEqual(incident.samples.last!.timestamp, incident.triggeredAt.addingTimeInterval(0.4))
        XCTAssertEqual(incident.samples.count, Set(incident.samples.map(\.id)).count)
    }

    func testAllRequestedSafetyRulesTrigger() {
        XCTAssertEqual(trigger { snapshot in
            snapshot.rpm = 4_000
            snapshot.oilPressureBar = 1
        }, .lowOilPressure)
        XCTAssertEqual(trigger { snapshot in
            snapshot.boostBar = 0.8
            snapshot.afr = 14.2
        }, .leanUnderBoost)
        XCTAssertEqual(trigger { $0.boostBar = 1.8 }, .overboost)
        XCTAssertEqual(trigger { $0.coolantCelsius = 112 }, .highCoolantTemperature)
        XCTAssertEqual(trigger { $0.oilTemperatureCelsius = 125 }, .highOilTemperature)
        XCTAssertEqual(trigger { snapshot in
            snapshot.rpm = 2_000
            snapshot.batteryVoltage = 10.9
        }, .lowBatteryVoltage)
        XCTAssertEqual(trigger(configure: { $0.lowFuelPressureEnabled = true }) { snapshot in
            snapshot.rpm = 3_000
            snapshot.fuelPressureBar = 2.0
        }, .lowFuelPressure)
    }

    func testDisabledRuleAndCustomThresholdAreRespected() {
        XCTAssertNil(trigger(configure: { configuration in
            configuration.overboostEnabled = false
        }) { $0.boostBar = 2.2 })

        XCTAssertNil(trigger(configure: { configuration in
            configuration.overboostBar = 2.0
        }) { $0.boostBar = 1.8 })

        XCTAssertEqual(trigger(configure: { configuration in
            configuration.overboostBar = 1.7
        }) { $0.boostBar = 1.8 }, .overboost)
    }

    func testCustomRulesDriveSharedDashboardAndWatchWarningState() {
        var rules = VehicleAlertRules.standard
        rules.maximumCoolantCelsius = 125
        rules.maximumOilTemperatureCelsius = 135
        rules.maximumBoostBar = 2
        var snapshot = safeSnapshot
        snapshot.coolantCelsius = 112
        snapshot.oilTemperatureCelsius = 124
        snapshot.boostBar = 1.8

        var configured = rules.applyingWarningState(to: snapshot)
        XCTAssertFalse(configured.hasTemperatureWarning)
        XCTAssertFalse(configured.hasCriticalWarning)
        XCTAssertFalse(WatchTelemetryPayload(snapshot: configured).hasTemperatureWarning)

        snapshot.coolantCelsius = 126
        configured = rules.applyingWarningState(to: snapshot)
        XCTAssertTrue(configured.hasCoolantWarning)
        XCTAssertTrue(configured.hasCriticalWarning)
        XCTAssertTrue(WatchTelemetryPayload(snapshot: configured).hasTemperatureWarning)
    }

    private func trigger(
        configure: (inout IncidentCaptureEngine.Configuration) -> Void = { _ in },
        mutate: (inout TelemetrySnapshot) -> Void
    ) -> IncidentKind? {
        var configuration = IncidentCaptureEngine.Configuration.standard
        configuration.preTriggerDuration = 0.1
        configuration.postTriggerDuration = 0.1
        configuration.cooldown = 10
        configure(&configuration)
        var engine = IncidentCaptureEngine(configuration: configuration)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var completed: [IncidentCaptureEngine.CompletedIncident] = []
        for index in 0..<110 {
            var snapshot = safeSnapshot
            mutate(&snapshot)
            completed += engine.ingest(CapturedTelemetryPoint(
                snapshot: snapshot,
                timestamp: start.addingTimeInterval(Double(index) * 0.041)
            ))
        }
        completed += engine.finishActiveCaptures()
        return completed.first?.kind
    }

    private func point(
        at timestamp: Date,
        rpm: Double = 2_000,
        oilPressure: Double = 3.5
    ) -> CapturedTelemetryPoint {
        var snapshot = safeSnapshot
        snapshot.rpm = rpm
        snapshot.oilPressureBar = oilPressure
        return CapturedTelemetryPoint(snapshot: snapshot, timestamp: timestamp)
    }

    private var safeSnapshot: TelemetrySnapshot {
        var snapshot = TelemetrySnapshot.preview
        snapshot.rpm = 2_000
        snapshot.boostBar = 0.1
        snapshot.afr = 12.5
        snapshot.oilPressureBar = 3.5
        snapshot.oilTemperatureCelsius = 95
        snapshot.coolantCelsius = 90
        snapshot.batteryVoltage = 13.8
        snapshot.fuelPressureBar = 3.5
        return snapshot
    }
}

@MainActor
final class VehicleAlertRuleStoreTests: XCTestCase {
    func testOfflineRulesPersistAndDetectNewerOnlineRevision() {
        let suiteName = "VehicleAlertRuleStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let vehicleID = UUID()
        let store = VehicleAlertRuleStore(defaults: defaults)
        var localRules = VehicleAlertRules.standard
        localRules.maximumBoostBar = 1.9

        store.saveLocally(localRules, for: vehicleID)
        XCTAssertTrue(store.record(for: vehicleID).dirty)

        store.applyRemote(remote(vehicleID: vehicleID, revision: 2, maximumBoostBar: 1.7), to: vehicleID)
        XCTAssertEqual(store.record(for: vehicleID).conflict?.revision, 2)
        XCTAssertEqual(store.record(for: vehicleID).rules.maximumBoostBar, 1.9)

        store.keepLocalAfterConflict(for: vehicleID)
        XCTAssertEqual(store.record(for: vehicleID).revision, 2)
        XCTAssertTrue(store.record(for: vehicleID).dirty)

        store.markUploaded(remote(vehicleID: vehicleID, revision: 3, maximumBoostBar: 1.9), for: vehicleID)
        let restored = VehicleAlertRuleStore(defaults: defaults).record(for: vehicleID)
        XCTAssertEqual(restored.revision, 3)
        XCTAssertFalse(restored.dirty)
        XCTAssertNil(restored.conflict)
        XCTAssertEqual(restored.rules.maximumBoostBar, 1.9)
    }

    private func remote(
        vehicleID: UUID,
        revision: Int,
        maximumBoostBar: Double
    ) -> CloudVehicleAlertConfiguration {
        CloudVehicleAlertConfiguration(
            vehicleId: vehicleID,
            revision: revision,
            cooldownSeconds: 300,
            lowOilPressureEnabled: true,
            minimumOilPressureBar: 1.5,
            lowOilMinimumRpm: 3_000,
            lowOilDurationSeconds: 0.75,
            leanUnderBoostEnabled: true,
            maximumAfr: 13.5,
            leanMinimumBoostBar: 0.5,
            leanDurationSeconds: 0.5,
            overboostEnabled: true,
            maximumBoostBar: maximumBoostBar,
            overboostDurationSeconds: 0.5,
            highCoolantTemperatureEnabled: true,
            maximumCoolantCelsius: 110,
            coolantDurationSeconds: 2,
            highOilTemperatureEnabled: true,
            maximumOilTemperatureCelsius: 120,
            oilTemperatureDurationSeconds: 2,
            lowBatteryVoltageEnabled: true,
            minimumBatteryVoltage: 11.5,
            lowBatteryMinimumRpm: 800,
            lowBatteryDurationSeconds: 3,
            lowFuelPressureEnabled: false,
            minimumFuelPressureBar: 2.5,
            lowFuelPressureMinimumRpm: 1_500,
            lowFuelPressureDurationSeconds: 1,
            updatedByAccountId: nil,
            updatedByDisplayName: "Mechanic",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
