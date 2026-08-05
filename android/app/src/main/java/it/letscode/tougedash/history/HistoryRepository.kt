package it.letscode.tougedash.history

import it.letscode.tougedash.data.local.DriveSessionEntity
import it.letscode.tougedash.data.local.SyncState
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import it.letscode.tougedash.data.local.TougeDashDao
import it.letscode.tougedash.data.local.VehicleEntity
import it.letscode.tougedash.data.local.AccelerationAttemptEntity
import it.letscode.tougedash.model.RecordedLocation
import it.letscode.tougedash.model.TelemetrySnapshot
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

class HistoryRepository(private val dao: TougeDashDao) {
    private val mutex = Mutex()
    private var active: DriveSessionEntity? = null
    private val pending = ArrayList<TelemetrySampleEntity>(25)
    private var previousLocation: RecordedLocation? = null

    val sessions = dao.sessions()
    fun session(id: String) = dao.session(id)
    fun samples(id: String) = dao.chartSamples(id)
    fun rawSamples(id: String) = dao.samples(id)
    fun incidents(id: String) = dao.incidentsForSession(id)
    fun annotations(id: String) = dao.annotations(id)
    fun videos(id: String) = dao.videos(id)
    fun accelerationAttempts(id: String) = dao.accelerationAttempts(id)

    suspend fun ensureVehicle(hardwareId: String, name: String): VehicleEntity {
        val current = dao.vehicle(hardwareId)
        if (current != null) return current
        val created = VehicleEntity(hardwareId, displayName = if (name.contains("sim", true)) "Demo car" else name)
        dao.upsertVehicle(created)
        return created
    }

    suspend fun record(hardwareId: String, deviceName: String, snapshot: TelemetrySnapshot, location: RecordedLocation? = null): String? = mutex.withLock {
        if (!snapshot.isFresh || snapshot.mapKpa <= 0.0) return@withLock active?.id
        ensureVehicle(hardwareId, deviceName)
        val now = System.currentTimeMillis()
        var session = active
        if (session == null) {
            session = DriveSessionEntity(
                id = UUID.randomUUID().toString(),
                vehicleHardwareId = hardwareId,
                startedAt = now,
                endedAt = now,
                modifiedAt = now,
                syncState = SyncState.PENDING_UPLOAD
            )
            dao.upsertSession(session)
            active = session
        }
        val elapsed = now - session.startedAt
        val chartEligible = elapsed <= 90_000 || session.sampleCount % 5 == 0
        pending += snapshot.toEntity(session.id, now, location, chartEligible)
        val distance = if (previousLocation != null && location != null) haversine(previousLocation!!, location) else 0.0
        previousLocation = location ?: previousLocation
        val minimumOil = snapshot.oilPressureBar.takeIf { it > 0 }?.let { current -> session.minimumOilPressureBar?.let { min(it, current) } ?: current }
        session = session.copy(
            endedAt = now,
            modifiedAt = now,
            sampleCount = session.sampleCount + 1,
            distanceMeters = session.distanceMeters + distance,
            maxRpm = max(session.maxRpm, snapshot.rpm),
            maxSpeedKph = max(session.maxSpeedKph, snapshot.speedKph),
            maxBoostBar = max(session.maxBoostBar, snapshot.boostBar),
            maxCoolantCelsius = max(session.maxCoolantCelsius, snapshot.coolantCelsius),
            maxOilTemperatureCelsius = max(session.maxOilTemperatureCelsius, snapshot.oilTemperatureCelsius),
            minimumOilPressureBar = minimumOil,
            containsLocation = session.containsLocation || location != null,
            syncState = SyncState.PENDING_UPLOAD,
            syncError = null
        )
        active = session
        if (pending.size >= 20) flushLocked(session)
        session.id
    }

    suspend fun finish() = mutex.withLock {
        active?.let { flushLocked(it.copy(modifiedAt = System.currentTimeMillis(), syncState = SyncState.PENDING_UPLOAD)) }
        active = null
        pending.clear()
        previousLocation = null
    }

    suspend fun activeSessionId(): String? = mutex.withLock { active?.id }

    suspend fun recordAcceleration(attempt: AccelerationAttemptEntity) = mutex.withLock {
        dao.upsertAccelerationAttempt(attempt)
        val current = active?.takeIf { it.id == attempt.sessionId } ?: dao.sessionOnce(attempt.sessionId)
        current?.copy(
            modifiedAt = System.currentTimeMillis(),
            syncState = SyncState.PENDING_UPLOAD,
            syncError = null,
            revision = current.revision + 1
        )?.let {
            dao.upsertSession(it)
            if (active?.id == it.id) active = it
        }
    }

    private suspend fun flushLocked(session: DriveSessionEntity) {
        if (pending.isNotEmpty()) {
            dao.insertSamples(pending.toList())
            pending.clear()
        }
        dao.upsertSession(session)
    }

    private fun TelemetrySnapshot.toEntity(sessionId: String, now: Long, location: RecordedLocation?, chartEligible: Boolean) =
        TelemetrySampleEntity(
            id = UUID.randomUUID().toString(), sessionId = sessionId, recordedAt = now,
            rpm = rpm, boostBar = boostBar, mapKpa = mapKpa, throttlePercent = throttlePercent,
            coolantCelsius = coolantCelsius, intakeCelsius = intakeCelsius,
            oilTemperatureCelsius = oilTemperatureCelsius, oilPressureBar = oilPressureBar,
            fuelPressureBar = fuelPressureBar, afr = afr, lambda = lambda,
            batteryVoltage = batteryVoltage, ignitionDegrees = ignitionDegrees,
            injectorDutyPercent = injectorDutyPercent, speedKph = speedKph,
            checkEngineMask = checkEngineMask, latitude = location?.latitude,
            longitude = location?.longitude, horizontalAccuracy = location?.horizontalAccuracy,
            altitude = location?.altitude, chartEligible = chartEligible
        )

    private fun haversine(a: RecordedLocation, b: RecordedLocation): Double {
        val earth = 6_371_000.0
        val lat1 = Math.toRadians(a.latitude)
        val lat2 = Math.toRadians(b.latitude)
        val dLat = lat2 - lat1
        val dLon = Math.toRadians(b.longitude - a.longitude)
        val value = kotlin.math.sin(dLat / 2) * kotlin.math.sin(dLat / 2) +
            kotlin.math.cos(lat1) * kotlin.math.cos(lat2) * kotlin.math.sin(dLon / 2) * kotlin.math.sin(dLon / 2)
        return 2 * earth * kotlin.math.asin(kotlin.math.sqrt(value.coerceIn(0.0, 1.0)))
    }
}
