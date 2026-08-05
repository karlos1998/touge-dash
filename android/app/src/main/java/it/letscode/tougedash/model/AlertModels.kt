package it.letscode.tougedash.model

import kotlinx.serialization.Serializable

@Serializable
data class VehicleAlertRules(
    val cooldownSeconds: Int = 300,
    val lowOilPressureEnabled: Boolean = true,
    val minimumOilPressureBar: Double = 1.5,
    val lowOilMinimumRpm: Double = 3_000.0,
    val lowOilDurationSeconds: Double = 0.75,
    val leanUnderBoostEnabled: Boolean = true,
    val maximumAfr: Double = 13.5,
    val leanMinimumBoostBar: Double = 0.5,
    val leanDurationSeconds: Double = 0.5,
    val overboostEnabled: Boolean = true,
    val maximumBoostBar: Double = 1.5,
    val overboostDurationSeconds: Double = 0.5,
    val highCoolantTemperatureEnabled: Boolean = true,
    val maximumCoolantCelsius: Double = 110.0,
    val coolantDurationSeconds: Double = 2.0,
    val highOilTemperatureEnabled: Boolean = true,
    val maximumOilTemperatureCelsius: Double = 120.0,
    val oilTemperatureDurationSeconds: Double = 2.0,
    val lowBatteryVoltageEnabled: Boolean = true,
    val minimumBatteryVoltage: Double = 11.5,
    val lowBatteryMinimumRpm: Double = 800.0,
    val lowBatteryDurationSeconds: Double = 3.0,
    val lowFuelPressureEnabled: Boolean = false,
    val minimumFuelPressureBar: Double = 2.5,
    val lowFuelPressureMinimumRpm: Double = 1_500.0,
    val lowFuelPressureDurationSeconds: Double = 1.0
)

enum class IncidentKind {
    LOW_OIL_PRESSURE, LEAN_UNDER_BOOST, OVERBOOST, HIGH_COOLANT_TEMPERATURE,
    HIGH_OIL_TEMPERATURE, LOW_FUEL_PRESSURE, LOW_BATTERY_VOLTAGE, CHECK_ENGINE
}

enum class IncidentSeverity { WARNING, CRITICAL }

data class ActiveAlert(
    val kind: IncidentKind,
    val severity: IncidentSeverity,
    val triggeredAt: Long,
    val value: Double,
    val threshold: Double,
    val unit: String
)
