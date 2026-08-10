package it.letscode.tougedash.history

import it.letscode.tougedash.data.local.IncidentEntity
import it.letscode.tougedash.data.local.SyncState
import it.letscode.tougedash.data.local.TougeDashDao
import it.letscode.tougedash.model.ActiveAlert
import it.letscode.tougedash.model.IncidentKind
import it.letscode.tougedash.model.IncidentSeverity
import it.letscode.tougedash.model.RecordedLocation
import it.letscode.tougedash.model.TelemetrySnapshot
import it.letscode.tougedash.model.VehicleAlertRules
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

@Serializable
data class CapturedTelemetryPoint(
    val id: String = UUID.randomUUID().toString(),
    val recordedAt: Long,
    val rpm: Double,
    val boostBar: Double,
    val mapKpa: Double,
    val throttlePercent: Double,
    val coolantCelsius: Double,
    val intakeCelsius: Double,
    val egt1Celsius: Double = 0.0,
    val egt2Celsius: Double = 0.0,
    val oilTemperatureCelsius: Double,
    val oilPressureBar: Double,
    val fuelPressureBar: Double,
    val afr: Double,
    val lambda: Double,
    val batteryVoltage: Double,
    val ignitionDegrees: Double,
    val injectorDutyPercent: Double,
    val speedKph: Double,
    val checkEngineMask: Int,
    val latitude: Double?,
    val longitude: Double?,
    val horizontalAccuracy: Double?,
    val altitude: Double?
)

class IncidentCaptureEngine(
    private val dao: TougeDashDao,
    private val json: Json,
    private val alertSink: (ActiveAlert) -> Unit,
    private val preSeconds: Int = 30,
    private val postSeconds: Int = 60,
    private val sampleRate: Int = 25
) {
    private data class Match(val kind: IncidentKind, val severity: IncidentSeverity, val value: Double, val threshold: Double, val unit: String, val duration: Double)
    private data class Capture(
        val match: Match,
        val triggeredAt: Long,
        val conditionStartedAt: Long,
        var conditionEndedAt: Long?,
        val points: MutableList<CapturedTelemetryPoint>
    )
    private val ring = ArrayDeque<CapturedTelemetryPoint>()
    private val candidates = mutableMapOf<IncidentKind, Long>()
    private val lastAlerts = mutableMapOf<IncidentKind, Long>()
    private val captures = mutableMapOf<IncidentKind, Capture>()
    var rules = VehicleAlertRules()

    suspend fun record(vehicleId: String, sessionId: String?, snapshot: TelemetrySnapshot, location: RecordedLocation? = null, now: Long = System.currentTimeMillis()) {
        if (sessionId == null) return
        val point = snapshot.toCaptured(now, location)
        ring += point
        while (ring.size > preSeconds * sampleRate) ring.removeFirst()
        captures.values.forEach {
            it.points += point
            if (it.conditionEndedAt == null && !isActive(it.match.kind, snapshot)) it.conditionEndedAt = now
        }

        matches(snapshot).forEach { match ->
            val activeSince = if (isActive(match.kind, snapshot)) candidates.getOrPut(match.kind) { now } else null
            if (activeSince == null) candidates.remove(match.kind)
            val cooldownReady = now - (lastAlerts[match.kind] ?: 0L) >= rules.cooldownSeconds * 1_000L
            if (activeSince != null && now - activeSince >= (match.duration * 1_000).toLong() && cooldownReady && match.kind !in captures) {
                val capture = Capture(match, now, activeSince, null, ring.toMutableList())
                captures[match.kind] = capture
                lastAlerts[match.kind] = now
                alertSink(ActiveAlert(match.kind, match.severity, now, match.value, match.threshold, match.unit))
            }
        }

        val completed = captures.filterValues { now - it.triggeredAt >= postSeconds * 1_000L }.toMap()
        completed.forEach { (kind, capture) ->
            persist(vehicleId, sessionId, capture)
            captures.remove(kind)
        }
    }

    suspend fun finish(vehicleId: String, sessionId: String?) {
        if (sessionId != null) captures.values.toList().forEach { persist(vehicleId, sessionId, it) }
        captures.clear(); candidates.clear(); ring.clear()
    }

    private suspend fun persist(vehicleId: String, sessionId: String, capture: Capture) {
        val trigger = capture.points.minByOrNull { kotlin.math.abs(it.recordedAt - capture.triggeredAt) }
        val first = capture.points.firstOrNull()?.recordedAt ?: capture.triggeredAt
        val last = capture.points.lastOrNull()?.recordedAt ?: capture.triggeredAt
        dao.upsertIncident(
            IncidentEntity(
                id = UUID.randomUUID().toString(), vehicleHardwareId = vehicleId, sessionId = sessionId,
                kind = capture.match.kind.name, severity = capture.match.severity.name,
                triggeredAt = capture.triggeredAt, captureStartedAt = first, captureEndedAt = last,
                sampleCount = capture.points.size,
                sampleRateHz = if (last > first) (capture.points.size - 1) * 1000.0 / (last - first) else sampleRate.toDouble(),
                triggerValue = capture.match.value, thresholdValue = capture.match.threshold,
                triggerUnit = capture.match.unit, triggerRpm = trigger?.rpm ?: 0.0,
                triggerBoostBar = trigger?.boostBar ?: 0.0, triggerAfr = trigger?.afr ?: 0.0,
                triggerSpeedKph = trigger?.speedKph ?: 0.0,
                triggerFuelPressureBar = trigger?.fuelPressureBar ?: 0.0,
                conditionDurationMillis = ((capture.conditionEndedAt ?: last) - capture.conditionStartedAt).coerceAtLeast(0),
                latitude = trigger?.latitude,
                longitude = trigger?.longitude, encodedSamples = json.encodeToString(capture.points),
                syncState = SyncState.PENDING_UPLOAD
            )
        )
    }

    private fun matches(s: TelemetrySnapshot) = listOfNotNull(
        Match(IncidentKind.LOW_OIL_PRESSURE, IncidentSeverity.CRITICAL, s.oilPressureBar, rules.minimumOilPressureBar, "bar", rules.lowOilDurationSeconds).takeIf { rules.lowOilPressureEnabled },
        Match(IncidentKind.LEAN_UNDER_BOOST, IncidentSeverity.WARNING, s.afr, rules.maximumAfr, "AFR", rules.leanDurationSeconds).takeIf { rules.leanUnderBoostEnabled },
        Match(IncidentKind.OVERBOOST, IncidentSeverity.WARNING, s.boostBar, rules.maximumBoostBar, "bar", rules.overboostDurationSeconds).takeIf { rules.overboostEnabled },
        Match(IncidentKind.HIGH_COOLANT_TEMPERATURE, IncidentSeverity.CRITICAL, s.coolantCelsius, rules.maximumCoolantCelsius, "°C", rules.coolantDurationSeconds).takeIf { rules.highCoolantTemperatureEnabled },
        Match(IncidentKind.HIGH_OIL_TEMPERATURE, IncidentSeverity.CRITICAL, s.oilTemperatureCelsius, rules.maximumOilTemperatureCelsius, "°C", rules.oilTemperatureDurationSeconds).takeIf { rules.highOilTemperatureEnabled },
        Match(IncidentKind.LOW_FUEL_PRESSURE, IncidentSeverity.WARNING, s.fuelPressureBar, rules.minimumFuelPressureBar, "bar", rules.lowFuelPressureDurationSeconds).takeIf { rules.lowFuelPressureEnabled },
        Match(IncidentKind.LOW_BATTERY_VOLTAGE, IncidentSeverity.WARNING, s.batteryVoltage, rules.minimumBatteryVoltage, "V", rules.lowBatteryDurationSeconds).takeIf { rules.lowBatteryVoltageEnabled },
        Match(IncidentKind.CHECK_ENGINE, IncidentSeverity.CRITICAL, s.checkEngineMask.toDouble(), 0.0, "CEL", 0.1).takeIf { s.hasCheckEngine }
    )

    private fun isActive(kind: IncidentKind, s: TelemetrySnapshot): Boolean = when (kind) {
        IncidentKind.LOW_OIL_PRESSURE -> s.rpm >= rules.lowOilMinimumRpm && s.oilPressureBar > 0 && s.oilPressureBar < rules.minimumOilPressureBar
        IncidentKind.LEAN_UNDER_BOOST -> s.boostBar >= rules.leanMinimumBoostBar && s.afr > rules.maximumAfr
        IncidentKind.OVERBOOST -> s.boostBar > rules.maximumBoostBar
        IncidentKind.HIGH_COOLANT_TEMPERATURE -> s.coolantCelsius >= rules.maximumCoolantCelsius
        IncidentKind.HIGH_OIL_TEMPERATURE -> s.oilTemperatureCelsius >= rules.maximumOilTemperatureCelsius
        IncidentKind.LOW_FUEL_PRESSURE -> s.rpm >= rules.lowFuelPressureMinimumRpm && s.fuelPressureBar > 0 && s.fuelPressureBar < rules.minimumFuelPressureBar
        IncidentKind.LOW_BATTERY_VOLTAGE -> s.rpm >= rules.lowBatteryMinimumRpm && s.batteryVoltage > 0 && s.batteryVoltage < rules.minimumBatteryVoltage
        IncidentKind.CHECK_ENGINE -> s.hasCheckEngine
    }

    private fun TelemetrySnapshot.toCaptured(now: Long, location: RecordedLocation?) = CapturedTelemetryPoint(
        recordedAt = now, rpm = rpm, boostBar = boostBar, mapKpa = mapKpa,
        throttlePercent = throttlePercent, coolantCelsius = coolantCelsius, intakeCelsius = intakeCelsius,
        egt1Celsius = egt1Celsius, egt2Celsius = egt2Celsius,
        oilTemperatureCelsius = oilTemperatureCelsius, oilPressureBar = oilPressureBar,
        fuelPressureBar = fuelPressureBar, afr = afr, lambda = lambda, batteryVoltage = batteryVoltage,
        ignitionDegrees = ignitionDegrees, injectorDutyPercent = injectorDutyPercent, speedKph = speedKph,
        checkEngineMask = checkEngineMask, latitude = location?.latitude, longitude = location?.longitude,
        horizontalAccuracy = location?.horizontalAccuracy, altitude = location?.altitude
    )
}
