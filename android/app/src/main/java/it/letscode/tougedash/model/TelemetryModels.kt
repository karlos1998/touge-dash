package it.letscode.tougedash.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName

@Serializable
data class TelemetrySnapshot(
    val rpm: Double = 0.0,
    val boostBar: Double = 0.0,
    val mapKpa: Double = 0.0,
    val throttlePercent: Double = 0.0,
    val coolantCelsius: Double = 0.0,
    val intakeCelsius: Double = 0.0,
    val egt1Celsius: Double = 0.0,
    val egt2Celsius: Double = 0.0,
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
    val droppedBytes: Long = 0,
    val receivedPackets: Long = 0,
    val receivedBytes: Long = 0,
    val lastPacketHex: String? = null
)

@Serializable
enum class TelemetryMetric(
    val shortName: String,
    val unit: String,
    val defaultMin: Double,
    val defaultMax: Double,
    val precision: Int
) {
    @SerialName("rpm") RPM("RPM", "rpm", 0.0, 10_000.0, 0),
    @SerialName("boost") BOOST("BOOST", "bar", -1.0, 2.0, 2),
    @SerialName("map") MAP("MAP", "kPa", 0.0, 300.0, 0),
    @SerialName("throttle") THROTTLE("TPS", "%", 0.0, 100.0, 0),
    @SerialName("coolant") COOLANT("COOLANT", "°C", 0.0, 130.0, 0),
    @SerialName("intake") INTAKE("IAT", "°C", -20.0, 100.0, 0),
    @SerialName("egt1") EGT1("EGT 1", "°C", 0.0, 1_100.0, 0),
    @SerialName("egt2") EGT2("EGT 2", "°C", 0.0, 1_100.0, 0),
    @SerialName("oilTemperature") OIL_TEMPERATURE("OIL TEMP", "°C", 0.0, 150.0, 0),
    @SerialName("oilPressure") OIL_PRESSURE("OIL P", "bar", 0.0, 10.0, 1),
    @SerialName("fuelPressure") FUEL_PRESSURE("FUEL", "bar", 0.0, 10.0, 1),
    @SerialName("afr") AFR("AFR", "AFR", 8.0, 20.0, 1),
    @SerialName("lambda") LAMBDA("LAMBDA", "λ", 0.5, 1.5, 2),
    @SerialName("batteryVoltage") BATTERY_VOLTAGE("BATTERY", "V", 8.0, 16.0, 1),
    @SerialName("ignition") IGNITION("IGN", "°", -20.0, 60.0, 1),
    @SerialName("injectorDuty") INJECTOR_DUTY("INJ", "%", 0.0, 100.0, 0),
    @SerialName("speed") SPEED("SPEED", "km/h", 0.0, 300.0, 0);

    fun value(snapshot: TelemetrySnapshot): Double = when (this) {
        RPM -> snapshot.rpm
        BOOST -> snapshot.boostBar
        MAP -> snapshot.mapKpa
        THROTTLE -> snapshot.throttlePercent
        COOLANT -> snapshot.coolantCelsius
        INTAKE -> snapshot.intakeCelsius
        EGT1 -> snapshot.egt1Celsius
        EGT2 -> snapshot.egt2Celsius
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
