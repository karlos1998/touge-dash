import Foundation

enum EngineTemperatureLimits {
    static let coolantWarningCelsius = 110.0
    static let oilWarningCelsius = 120.0
    static let coolantResetCelsius = 105.0
    static let oilResetCelsius = 115.0
}

struct WatchTelemetryPayload: Codable, Equatable, Sendable {
    static let contextKey = "tougeDashTelemetry"

    var boostBar: Double
    var afr: Double
    var oilPressureBar: Double
    var oilTemperatureCelsius: Double
    var coolantCelsius: Double
    var rpm: Double
    var hasCriticalWarning: Bool
    var updatedAt: Date

    init(
        boostBar: Double,
        afr: Double,
        oilPressureBar: Double,
        oilTemperatureCelsius: Double,
        coolantCelsius: Double,
        rpm: Double,
        hasCriticalWarning: Bool,
        updatedAt: Date
    ) {
        self.boostBar = boostBar
        self.afr = afr
        self.oilPressureBar = oilPressureBar
        self.oilTemperatureCelsius = oilTemperatureCelsius
        self.coolantCelsius = coolantCelsius
        self.rpm = rpm
        self.hasCriticalWarning = hasCriticalWarning
        self.updatedAt = updatedAt
    }

    static let empty = WatchTelemetryPayload(
        boostBar: 0,
        afr: 0,
        oilPressureBar: 0,
        oilTemperatureCelsius: 0,
        coolantCelsius: 0,
        rpm: 0,
        hasCriticalWarning: false,
        updatedAt: .distantPast
    )

    static let preview = WatchTelemetryPayload(
        boostBar: 1.18,
        afr: 12.4,
        oilPressureBar: 4.2,
        oilTemperatureCelsius: 104,
        coolantCelsius: 91,
        rpm: 6_420,
        hasCriticalWarning: false,
        updatedAt: .now
    )

    var isFresh: Bool {
        Date().timeIntervalSince(updatedAt) < 2.5
    }

    var hasOilPressureWarning: Bool {
        rpm > 1_200 && oilPressureBar > 0 && oilPressureBar < 0.5
    }

    var hasOilTemperatureWarning: Bool {
        oilTemperatureCelsius >= EngineTemperatureLimits.oilWarningCelsius
    }

    var hasCoolantWarning: Bool {
        coolantCelsius >= EngineTemperatureLimits.coolantWarningCelsius
    }

    var hasTemperatureWarning: Bool {
        hasOilTemperatureWarning || hasCoolantWarning
    }

    #if os(iOS)
    init(snapshot: TelemetrySnapshot) {
        boostBar = snapshot.boostBar
        afr = snapshot.afr
        oilPressureBar = snapshot.oilPressureBar
        oilTemperatureCelsius = snapshot.oilTemperatureCelsius
        coolantCelsius = snapshot.coolantCelsius
        rpm = snapshot.rpm
        hasCriticalWarning = snapshot.hasCriticalWarning
        updatedAt = snapshot.updatedAt
    }
    #endif
}
