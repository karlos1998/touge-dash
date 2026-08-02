import ActivityKit
import Foundation

struct TelemetrySnapshot: Codable, Hashable, Sendable {
    var rpm: Double = 0
    var boostBar: Double = 0
    var mapKPa: Double = 0
    var throttlePercent: Double = 0
    var coolantCelsius: Double = 0
    var intakeCelsius: Double = 0
    var oilTemperatureCelsius: Double = 0
    var oilPressureBar: Double = 0
    var fuelPressureBar: Double = 0
    var afr: Double = 0
    var lambda: Double = 0
    var batteryVoltage: Double = 0
    var ignitionDegrees: Double = 0
    var injectorDutyPercent: Double = 0
    var speedKPH: Double = 0
    var checkEngineMask: UInt16 = 0
    var updatedAt: Date = .now

    static let preview = TelemetrySnapshot(
        rpm: 6_420,
        boostBar: 1.18,
        mapKPa: 219,
        throttlePercent: 84,
        coolantCelsius: 91,
        intakeCelsius: 34,
        oilTemperatureCelsius: 104,
        oilPressureBar: 4.2,
        fuelPressureBar: 3.4,
        afr: 12.4,
        lambda: 0.84,
        batteryVoltage: 13.8,
        ignitionDegrees: 18.5,
        injectorDutyPercent: 67,
        speedKPH: 128,
        checkEngineMask: 0,
        updatedAt: .now
    )

    var isFresh: Bool { Date().timeIntervalSince(updatedAt) < 2.5 }
    var hasCheckEngine: Bool { checkEngineMask != 0 }
    var hasTemperatureWarning: Bool {
        coolantCelsius >= EngineTemperatureLimits.coolantWarningCelsius ||
            oilTemperatureCelsius >= EngineTemperatureLimits.oilWarningCelsius
    }
    var hasCriticalWarning: Bool {
        hasCheckEngine || hasTemperatureWarning ||
            (rpm > 1_200 && oilPressureBar > 0 && oilPressureBar < 0.5) ||
            (rpm > 500 && batteryVoltage > 0 && batteryVoltage < 11.5)
    }
}

struct TelemetryActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var telemetry: TelemetrySnapshot
        var connectionLabel: String
    }

    var vehicleName: String
}

enum SharedTelemetryStore {
    static let appGroup = "group.it.letscode.touge-dash"
    static let snapshotKey = "latestTelemetrySnapshot"

    static func save(_ snapshot: TelemetrySnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> TelemetrySnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(TelemetrySnapshot.self, from: data) else {
            return TelemetrySnapshot()
        }
        return snapshot
    }
}
