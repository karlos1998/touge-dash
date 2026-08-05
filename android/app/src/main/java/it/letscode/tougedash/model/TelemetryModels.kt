package it.letscode.tougedash.model

import kotlinx.serialization.Serializable

@Serializable
data class TelemetrySnapshot(
    val rpm: Double = 0.0,
    val boostBar: Double = 0.0,
    val mapKpa: Double = 0.0,
    val throttlePercent: Double = 0.0,
    val coolantCelsius: Double = 0.0,
    val intakeCelsius: Double = 0.0,
    val oilTemperatureCelsius: Double = 0.0,
    val oilPressureBar: Double = 0.0,
    val fuelPressureBar: Double = 0.0,
    val afr: Double = 0.0,
    val lambda: Double = 0.0,
    val batteryVoltage: Double = 0.0,
    val ignitionDegrees: Double = 0.0,
    val injectorDutyPercent: Double = 0.0,
    val speedKph: Double = 0.0,
    val checkEngineMask: Int = 0,
    val updatedAt: Long = System.currentTimeMillis()
) {
    val isFresh: Boolean get() = System.currentTimeMillis() - updatedAt < 2_500
    val hasCheckEngine: Boolean get() = checkEngineMask != 0

    companion object {
        val Preview = TelemetrySnapshot(
            rpm = 6_420.0, boostBar = 1.18, mapKpa = 219.0, throttlePercent = 84.0,
            coolantCelsius = 91.0, intakeCelsius = 34.0, oilTemperatureCelsius = 104.0,
            oilPressureBar = 4.2, fuelPressureBar = 3.4, afr = 12.4, lambda = 0.84,
            batteryVoltage = 13.8, ignitionDegrees = 18.5, injectorDutyPercent = 67.0,
            speedKph = 128.0
        )
    }
}

@Serializable
data class RecordedLocation(
    val latitude: Double,
    val longitude: Double,
    val horizontalAccuracy: Double,
    val altitude: Double,
    val timestamp: Long
)

enum class ConnectionState { Idle, Scanning, Connecting, Connected, Reconnecting, BluetoothOff, PermissionRequired, Failed }

data class TelemetryConnection(
    val state: ConnectionState = ConnectionState.Idle,
    val deviceName: String? = null,
    val hardwareId: String? = null,
    val message: String? = null,
    val validFrames: Long = 0,
    val badChecksums: Long = 0,
    val droppedBytes: Long = 0
)

enum class TelemetryMetric(
    val shortName: String,
    val unit: String,
    val defaultMin: Double,
    val defaultMax: Double,
    val precision: Int
) {
    RPM("RPM", "rpm", 0.0, 10_000.0, 0),
    BOOST("BOOST", "bar", -1.0, 2.0, 2),
    MAP("MAP", "kPa", 0.0, 300.0, 0),
    THROTTLE("TPS", "%", 0.0, 100.0, 0),
    COOLANT("COOLANT", "°C", 0.0, 130.0, 0),
    INTAKE("IAT", "°C", -20.0, 100.0, 0),
    OIL_TEMPERATURE("OIL TEMP", "°C", 0.0, 150.0, 0),
    OIL_PRESSURE("OIL P", "bar", 0.0, 10.0, 1),
    FUEL_PRESSURE("FUEL", "bar", 0.0, 10.0, 1),
    AFR("AFR", "AFR", 8.0, 20.0, 1),
    LAMBDA("LAMBDA", "λ", 0.5, 1.5, 2),
    BATTERY_VOLTAGE("BATTERY", "V", 8.0, 16.0, 1),
    IGNITION("IGN", "°", -20.0, 60.0, 1),
    INJECTOR_DUTY("INJ", "%", 0.0, 100.0, 0),
    SPEED("SPEED", "km/h", 0.0, 300.0, 0);

    fun value(snapshot: TelemetrySnapshot): Double = when (this) {
        RPM -> snapshot.rpm
        BOOST -> snapshot.boostBar
        MAP -> snapshot.mapKpa
        THROTTLE -> snapshot.throttlePercent
        COOLANT -> snapshot.coolantCelsius
        INTAKE -> snapshot.intakeCelsius
        OIL_TEMPERATURE -> snapshot.oilTemperatureCelsius
        OIL_PRESSURE -> snapshot.oilPressureBar
        FUEL_PRESSURE -> snapshot.fuelPressureBar
        AFR -> snapshot.afr
        LAMBDA -> snapshot.lambda
        BATTERY_VOLTAGE -> snapshot.batteryVoltage
        IGNITION -> snapshot.ignitionDegrees
        INJECTOR_DUTY -> snapshot.injectorDutyPercent
        SPEED -> snapshot.speedKph
    }
}
