import XCTest
@testable import TougeDash

final class IncidentCaptureEngineTests: XCTestCase {
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
        XCTAssertEqual(trigger { $0.coolantCelsius = 112 }, .engineOverheat)
        XCTAssertEqual(trigger { snapshot in
            snapshot.rpm = 2_000
            snapshot.batteryVoltage = 10.9
        }, .lowBatteryVoltage)
    }

    private func trigger(mutate: (inout TelemetrySnapshot) -> Void) -> IncidentKind? {
        var configuration = IncidentCaptureEngine.Configuration.standard
        configuration.preTriggerDuration = 0.1
        configuration.postTriggerDuration = 0.1
        configuration.cooldown = 10
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
        return snapshot
    }
}
