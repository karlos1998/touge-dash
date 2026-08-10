package it.letscode.tougedash.cloud

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import it.letscode.tougedash.BuildConfig
import it.letscode.tougedash.TougeDashApplication
import it.letscode.tougedash.data.local.AlertConfigurationEntity
import it.letscode.tougedash.data.local.DashboardTemplateEntity
import it.letscode.tougedash.data.local.DriveSessionEntity
import it.letscode.tougedash.data.local.IncidentEntity
import it.letscode.tougedash.data.local.SyncState
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import it.letscode.tougedash.data.local.TougeDashDao
import it.letscode.tougedash.data.local.VehicleEntity
import it.letscode.tougedash.data.local.AccelerationAttemptEntity
import it.letscode.tougedash.performance.AccelerationRuntimeState
import it.letscode.tougedash.history.CapturedTelemetryPoint
import it.letscode.tougedash.model.VehicleAlertRules
import it.letscode.tougedash.alerts.AlertRepository
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.concurrent.TimeUnit

class CloudSyncRepository(
    private val context: Context,
    private val dao: TougeDashDao,
    private val api: CloudAuthRepository,
    private val json: Json,
    private val alerts: AlertRepository
) {
    @Serializable
    data class DriveTag(val id: String, val name: String, val color: String)
    @Serializable
    data class DriveShareRange(val startOffsetMillis: Long, val endOffsetMillis: Long, val durationMillis: Long)
    @Serializable
    data class DriveShareLink(val id: String, val createdAt: String, val expiresAt: String? = null, val range: DriveShareRange? = null)

    suspend fun driveTags(): List<DriveTag> {
        check(api.isAuthenticated) { "Sign in before managing tags." }
        return json.decodeFromString(api.request("/api/v1/drive-tags").toString())
    }

    suspend fun createDriveTag(name: String, color: String): DriveTag {
        check(api.isAuthenticated) { "Sign in before creating a tag." }
        val response = api.request(
            "/api/v1/drive-tags",
            "POST",
            buildJsonObject { put("name", name.trim().take(40)); put("color", color) }
        )
        return json.decodeFromString(response.toString())
    }

    suspend fun updateDriveTag(tag: DriveTag): DriveTag {
        val response = api.request(
            "/api/v1/drive-tags/${tag.id}",
            "PATCH",
            buildJsonObject { put("name", tag.name.trim().take(40)); put("color", tag.color) }
        )
        return json.decodeFromString(response.toString())
    }

    suspend fun deleteDriveTag(tagId: String) {
        api.request("/api/v1/drive-tags/$tagId", "DELETE")
    }

    suspend fun updateDriveMetadata(session: DriveSessionEntity, customName: String?, tags: List<DriveTag>) {
        check(api.isAuthenticated) { "Sign in before editing cloud history." }
        var vehicle = dao.vehicle(session.vehicleHardwareId) ?: error("Vehicle not found.")
        vehicle = discover(vehicle)
        val remoteVehicleId = vehicle.remoteId ?: error("Vehicle has not been synchronized.")
        if (session.remoteId == null || session.syncState != SyncState.SYNCED) {
            check(sync()) { "Synchronize the drive before editing it." }
        }
        api.request(
            "/api/v1/vehicles/$remoteVehicleId/sessions/${session.id}/name",
            "PATCH",
            buildJsonObject { if (customName == null) put("name", JsonNull) else put("name", customName) }
        )
        api.request(
            "/api/v1/vehicles/$remoteVehicleId/sessions/${session.id}/tags",
            "PUT",
            buildJsonObject { put("tagIds", buildJsonArray { tags.forEach { add(JsonPrimitive(it.id)) } }) }
        )
        dao.updateSession(session.copy(customName = customName, tagsJson = json.encodeToString(tags), metadataDirty = false, syncState = SyncState.SYNCED))
    }

    suspend fun createDriveShare(
        session: DriveSessionEntity,
        unit: String,
        amount: Int?,
        startOffsetMillis: Long?,
        endOffsetMillis: Long?
    ): String {
        check(api.isAuthenticated) { "Sign in before sharing a drive." }
        check(sync()) { "Synchronize the drive before sharing it." }
        var vehicle = dao.vehicle(session.vehicleHardwareId) ?: error("Vehicle not found.")
        vehicle = discover(vehicle)
        val remoteVehicleId = vehicle.remoteId ?: error("Vehicle has not been synchronized.")
        val body = buildJsonObject {
            put("unit", unit)
            if (unit != "FOREVER") put("amount", requireNotNull(amount))
            startOffsetMillis?.let { put("startOffsetMillis", it) }
            endOffsetMillis?.let { put("endOffsetMillis", it) }
        }
        val response = api.request(
            "/api/v1/vehicles/$remoteVehicleId/sessions/${session.id}/shares",
            "POST",
            body
        ).jsonObject
        val token = response["token"]?.jsonPrimitive?.content ?: error("Server did not return a share token.")
        return BuildConfig.WEB_BASE_URL.trimEnd('/') + "/shared/drives/" + token
    }

    suspend fun driveShares(session: DriveSessionEntity): List<DriveShareLink> {
        var vehicle = dao.vehicle(session.vehicleHardwareId) ?: error("Vehicle not found.")
        vehicle = discover(vehicle)
        val remoteVehicleId = vehicle.remoteId ?: error("Vehicle has not been synchronized.")
        val response = api.request("/api/v1/vehicles/$remoteVehicleId/sessions/${session.id}/shares")
        return json.decodeFromString(response.toString())
    }

    suspend fun revokeDriveShare(session: DriveSessionEntity, shareId: String) {
        var vehicle = dao.vehicle(session.vehicleHardwareId) ?: error("Vehicle not found.")
        vehicle = discover(vehicle)
        val remoteVehicleId = vehicle.remoteId ?: error("Vehicle has not been synchronized.")
        api.request("/api/v1/vehicles/$remoteVehicleId/sessions/${session.id}/shares/$shareId", "DELETE")
    }
    suspend fun createIncidentShare(incidentId: String, unit: String, amount: Int?): String {
        check(api.isAuthenticated) { "Sign in before sharing a report." }
        check(sync()) { "Synchronize the report before sharing it." }
        val incident = dao.incidentOnce(incidentId) ?: error("Incident report not found.")
        var vehicle = dao.vehicle(incident.vehicleHardwareId) ?: error("Vehicle not found.")
        vehicle = discover(vehicle)
        val remoteVehicleId = vehicle.remoteId ?: error("Vehicle has not been synchronized.")
        val body = buildJsonObject {
            put("unit", unit)
            if (unit != "FOREVER") put("amount", requireNotNull(amount))
        }
        val response = api.request(
            "/api/v1/vehicles/$remoteVehicleId/incidents/${incident.id}/shares",
            "POST",
            body
        ).jsonObject
        val token = response["token"]?.jsonPrimitive?.content ?: error("Server did not return a share token.")
        return BuildConfig.WEB_BASE_URL.trimEnd('/') + "/shared/incidents/" + token
    }

    suspend fun renameVehicle(vehicle: VehicleEntity, displayName: String) {
        val name = displayName.trim().take(120)
        if (name.isBlank()) return
        var updated = vehicle.copy(displayName = name)
        dao.upsertVehicle(updated)
        if (!api.isAuthenticated) return
        updated = discover(updated)
        val remoteId = updated.remoteId ?: return
        runCatching {
            val response = api.request(
                "/api/v1/vehicles/$remoteId",
                "PATCH",
                buildJsonObject { put("displayName", name) }
            ).jsonObject
            dao.upsertVehicle(updated.copy(displayName = response["displayName"]?.jsonPrimitive?.content ?: name))
        }
    }

    suspend fun sync(): Boolean {
        if (!api.isAuthenticated) return true
        return runCatching {
            syncTemplates()
            val vehicles = dao.vehiclesOnce().map { discover(it) }
            vehicles.forEach { vehicle ->
                val remoteId = vehicle.remoteId ?: return@forEach
                dao.pendingSessions(25).filter { it.vehicleHardwareId == vehicle.localHardwareId }.forEach {
                    uploadSession(it, remoteId)
                    if (it.metadataDirty) {
                        val refreshed = dao.sessionOnce(it.id) ?: it
                        val tags = runCatching { json.decodeFromString<List<DriveTag>>(refreshed.tagsJson) }.getOrDefault(emptyList())
                        updateDriveMetadata(refreshed, refreshed.customName, tags)
                    }
                }
                dao.pendingIncidents(25).filter { it.vehicleHardwareId == vehicle.localHardwareId }.forEach { uploadIncident(it, remoteId) }
                dao.pendingAnnotations(100).filter { it.vehicleHardwareId == vehicle.localHardwareId }.forEach { annotation ->
                    val body = buildJsonObject { put("id", annotation.id); annotation.incidentId?.let { put("incidentId", it) }; put("recordedAt", iso(annotation.recordedAt)); put("body", annotation.body) }
                    api.request("/api/v1/vehicles/$remoteId/sessions/${annotation.sessionId}/annotations", "POST", body)
                    dao.updateAnnotation(annotation.copy(syncState = SyncState.SYNCED))
                }
                syncAlertConfiguration(vehicle, remoteId)
            }
            true
        }.getOrElse { false }
    }

    suspend fun publishLive(hardwareId: String, sample: TelemetrySampleEntity, performance: AccelerationRuntimeState) {
        if (!api.isAuthenticated) return
        val local = dao.vehicle(hardwareId) ?: return
        val vehicle = discover(local)
        val remote = vehicle.remoteId ?: return
        val body = buildJsonObject {
            sampleJson(sample, includeId = false).forEach { (key, value) -> put(key, value) }
            performance.active?.let { active ->
                put("activeAcceleration", buildJsonObject {
                    put("type", active.type.name)
                    put("startedAt", iso(active.startedAt))
                    put("elapsedMillis", active.elapsedMillis)
                    put("currentSpeedKph", active.currentSpeedKph)
                    put("progress", active.progress)
                })
            }
            put("recentAccelerationResults", buildJsonArray {
                performance.recentResults.forEach { attempt ->
                    add(buildJsonObject {
                        put("type", attempt.type)
                        put("durationMillis", attempt.durationMillis)
                        put("endedAt", iso(attempt.endedAt))
                    })
                }
            })
        }
        runCatching { api.request("/api/v1/vehicles/$remote/live", "POST", body) }
    }

    fun schedule() {
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        WorkManager.getInstance(context).enqueueUniqueWork(WORK_NOW, ExistingWorkPolicy.KEEP, OneTimeWorkRequestBuilder<CloudSyncWorker>().setConstraints(constraints).build())
    }

    fun schedulePeriodic() {
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK_PERIODIC, ExistingPeriodicWorkPolicy.KEEP, PeriodicWorkRequestBuilder<CloudSyncWorker>(15, TimeUnit.MINUTES).setConstraints(constraints).build())
    }

    private suspend fun discover(vehicle: VehicleEntity): VehicleEntity {
        if (vehicle.remoteId != null) return vehicle
        val response = api.request("/api/v1/vehicles/discover", "POST", buildJsonObject { put("hardwareIdentifier", vehicle.localHardwareId); put("proposedName", vehicle.displayName) }).jsonObject
        val linked = vehicle.copy(remoteId = response["id"]?.jsonPrimitive?.content, displayName = response["displayName"]?.jsonPrimitive?.content ?: vehicle.displayName, role = response["role"]?.jsonPrimitive?.content ?: vehicle.role, accountId = api.session.value?.account?.id)
        dao.upsertVehicle(linked)
        return linked
    }

    private suspend fun uploadSession(session: DriveSessionEntity, vehicleId: String) {
        val samples = dao.samplesOnce(session.id)
        val attempts = dao.accelerationAttemptsOnce(session.id)
        val chunks = if (samples.isEmpty()) listOf(emptyList()) else samples.chunked(2_000)
        val totalBytes = chunks.sumOf { chunk -> sessionPayload(session, chunk, attempts).toString().toByteArray().size.toLong() }
        var sent = 0L
        dao.updateSession(session.copy(syncState = SyncState.UPLOADING, syncBytesTotal = totalBytes, syncBytesSent = 0, syncProgress = 0f, syncError = null))
        runCatching {
            chunks.forEachIndexed { index, chunk ->
                val body = sessionPayload(session, chunk, attempts)
                api.request("/api/v1/vehicles/$vehicleId/sessions/sync", "POST", body)
                sent += body.toString().toByteArray().size
                dao.updateSession(session.copy(syncState = SyncState.UPLOADING, syncBytesTotal = totalBytes, syncBytesSent = sent, syncProgress = (index + 1f) / chunks.size, syncError = null))
            }
            dao.updateSession(session.copy(remoteId = session.id, syncState = SyncState.SYNCED, syncBytesTotal = totalBytes, syncBytesSent = sent, syncProgress = 1f, syncError = null))
        }.onFailure { dao.updateSession(session.copy(syncState = SyncState.FAILED, syncBytesTotal = totalBytes, syncBytesSent = sent, syncProgress = if (totalBytes > 0) sent.toFloat() / totalBytes else 0f, syncError = it.message)) }
    }

    private suspend fun uploadIncident(incident: IncidentEntity, vehicleId: String) {
        val samples = runCatching { json.decodeFromString<List<CapturedTelemetryPoint>>(incident.encodedSamples) }.getOrDefault(emptyList())
        val chunks = if (samples.isEmpty()) listOf(emptyList()) else samples.chunked(2_000)
        runCatching {
            chunks.forEachIndexed { index, values ->
                val body = buildJsonObject {
                    put("id", incident.id); put("sessionId", incident.sessionId); put("type", incident.kind); put("severity", incident.severity)
                    put("triggeredAt", iso(incident.triggeredAt)); put("captureStartedAt", iso(incident.captureStartedAt)); put("captureEndedAt", iso(incident.captureEndedAt)); put("revision", incident.revision)
                    put("sampleCount", incident.sampleCount.coerceAtLeast(1)); put("sampleRateHz", incident.sampleRateHz.coerceAtLeast(.1)); put("triggerValue", incident.triggerValue); put("thresholdValue", incident.thresholdValue); put("triggerUnit", incident.triggerUnit)
                    put("triggerRpm", incident.triggerRpm); put("triggerBoostBar", incident.triggerBoostBar); put("triggerAfr", incident.triggerAfr); put("triggerSpeedKph", incident.triggerSpeedKph)
                    incident.latitude?.let { put("latitude", it) }; incident.longitude?.let { put("longitude", it) }
                    put("samples", buildJsonArray { values.forEach { add(capturedJson(it)) } })
                }
                api.request("/api/v1/vehicles/$vehicleId/incidents/sync", "POST", body)
                dao.updateIncident(incident.copy(syncState = SyncState.UPLOADING, syncProgress = (index + 1f) / chunks.size, syncError = null))
            }
            dao.updateIncident(incident.copy(syncState = SyncState.SYNCED, syncProgress = 1f, syncError = null, remoteId = incident.id))
        }.onFailure { dao.updateIncident(incident.copy(syncState = SyncState.FAILED, syncError = it.message)) }
    }

    private suspend fun syncTemplates() {
        val templates = dao.templatesOnce()
        val body = buildJsonObject { put("templates", buildJsonArray { templates.forEach { item -> add(buildJsonObject { put("id", item.id); put("schemaVersion", item.schemaVersion); put("name", item.name); put("definition", json.parseToJsonElement(item.definitionJson)); put("modifiedAt", iso(item.modifiedAt)); item.deletedAt?.let { put("deletedAt", iso(it)) } }) } }) }
        val response = api.request("/api/v1/dashboard-templates/sync", "POST", body).jsonObject
        val selectedId = templates.firstOrNull { it.selected }?.id
        response["templates"]?.jsonArray?.forEach { value ->
            val item = value.jsonObject
            val id = item.getValue("id").jsonPrimitive.content
            dao.upsertTemplate(
                DashboardTemplateEntity(
                    id = id,
                    name = item.getValue("name").jsonPrimitive.content,
                    definitionJson = item.getValue("definition").toString(),
                    schemaVersion = item.getValue("schemaVersion").jsonPrimitive.content.toInt(),
                    modifiedAt = Instant.parse(item.getValue("modifiedAt").jsonPrimitive.content).toEpochMilli(),
                    deletedAt = item["deletedAt"]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content?.let(Instant::parse)?.toEpochMilli(),
                    selected = id == selectedId,
                    dirty = false
                )
            )
        }
        templates.forEach { dao.markTemplateSynced(it.id) }
    }

    private suspend fun syncAlertConfiguration(vehicle: VehicleEntity, remoteId: String) {
        val local = dao.alertConfigurationOnce(vehicle.localHardwareId)
        val canEdit = vehicle.role == "OWNER" || vehicle.role == "MECHANIC"
        val response = if (local?.dirty == true && canEdit) {
            val rules = json.parseToJsonElement(local.rulesJson).jsonObject
            val body = buildJsonObject {
                put("revision", local.revision)
                rules.forEach { (key, value) -> put(key, value) }
            }
            runCatching { api.request("/api/v1/vehicles/$remoteId/alert-configuration", "PUT", body) }
                .getOrElse {
                    // A mechanic or another device may already have changed this
                    // revision. Preserve the offline draft until the driver chooses.
                    val remote = api.request("/api/v1/vehicles/$remoteId/alert-configuration")
                    val root = remote.jsonObject
                    alerts.setConflict(
                        vehicle.localHardwareId,
                        AlertRepository.Conflict(
                            rules = json.decodeFromString(remote.toString()),
                            revision = root["revision"]?.jsonPrimitive?.content?.toIntOrNull() ?: local.revision,
                            updatedAt = root["updatedAt"]?.jsonPrimitive?.content?.let { value -> Instant.parse(value).toEpochMilli() } ?: System.currentTimeMillis(),
                            updatedByDisplayName = root["updatedByDisplayName"]?.takeUnless { value -> value is JsonNull }?.jsonPrimitive?.content
                        )
                    )
                    return
                }
        } else {
            api.request("/api/v1/vehicles/$remoteId/alert-configuration")
        }
        val root = response.jsonObject
        val rules = json.decodeFromString<VehicleAlertRules>(response.toString())
        dao.upsertAlertConfiguration(
            AlertConfigurationEntity(
                vehicleHardwareId = vehicle.localHardwareId,
                rulesJson = json.encodeToString(rules),
                revision = root["revision"]?.jsonPrimitive?.content?.toIntOrNull() ?: local?.revision ?: 1,
                dirty = false,
                updatedAt = root["updatedAt"]?.jsonPrimitive?.content?.let { Instant.parse(it).toEpochMilli() } ?: System.currentTimeMillis(),
                updatedByDisplayName = root["updatedByDisplayName"]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content
            )
        )
    }

    private fun sessionPayload(
        s: DriveSessionEntity,
        samples: List<TelemetrySampleEntity>,
        attempts: List<AccelerationAttemptEntity>
    ) = buildJsonObject {
        put("id", s.id); put("startedAt", iso(s.startedAt)); put("endedAt", iso(s.endedAt)); put("revision", s.revision); put("sampleCount", s.sampleCount); put("distanceMeters", s.distanceMeters)
        put("maxRpm", s.maxRpm); put("maxSpeedKph", s.maxSpeedKph); put("maxBoostBar", s.maxBoostBar); put("maxCoolantCelsius", s.maxCoolantCelsius); put("maxOilTemperatureCelsius", s.maxOilTemperatureCelsius)
        s.minimumOilPressureBar?.let { put("minimumOilPressureBar", it) }; put("containsLocation", s.containsLocation); put("samples", buildJsonArray { samples.forEach { add(sampleJson(it)) } })
        put("accelerationAttempts", buildJsonArray {
            attempts.forEach { attempt ->
                add(buildJsonObject {
                    put("id", attempt.id); put("type", attempt.type)
                    put("startedAt", iso(attempt.startedAt)); put("endedAt", iso(attempt.endedAt))
                    put("durationMillis", attempt.durationMillis)
                    put("startSpeedKph", attempt.startSpeedKph); put("endSpeedKph", attempt.endSpeedKph)
                    put("source", attempt.source); put("quality", attempt.quality)
                    put("sampleRateHz", attempt.sampleRateHz); put("shiftCount", attempt.shiftCount)
                    put("revision", attempt.revision)
                })
            }
        })
    }

    private fun sampleJson(s: TelemetrySampleEntity, includeId: Boolean = true) = buildJsonObject {
        if (includeId) { put("id", s.id); put("revision", 1) }; put("recordedAt", iso(s.recordedAt)); put("rpm", s.rpm); put("boostBar", s.boostBar); put("mapKpa", s.mapKpa); put("throttlePercent", s.throttlePercent)
        put("coolantCelsius", s.coolantCelsius); put("intakeCelsius", s.intakeCelsius); put("egt1Celsius", s.egt1Celsius); put("egt2Celsius", s.egt2Celsius); put("oilTemperatureCelsius", s.oilTemperatureCelsius); put("oilPressureBar", s.oilPressureBar); put("fuelPressureBar", s.fuelPressureBar)
        put("afr", s.afr); put("lambda", s.lambda); put("batteryVoltage", s.batteryVoltage); put("ignitionDegrees", s.ignitionDegrees); put("injectorDutyPercent", s.injectorDutyPercent); put("speedKph", s.speedKph); put("checkEngineMask", s.checkEngineMask)
        s.latitude?.let { put("latitude", it) }; s.longitude?.let { put("longitude", it) }; s.horizontalAccuracy?.let { put("horizontalAccuracy", it) }; s.altitude?.let { put("altitude", it) }
    }

    private fun capturedJson(s: CapturedTelemetryPoint) = buildJsonObject {
        put("id", s.id); put("recordedAt", iso(s.recordedAt)); put("revision", 1); put("rpm", s.rpm); put("boostBar", s.boostBar); put("mapKpa", s.mapKpa); put("throttlePercent", s.throttlePercent); put("coolantCelsius", s.coolantCelsius); put("intakeCelsius", s.intakeCelsius); put("egt1Celsius", s.egt1Celsius); put("egt2Celsius", s.egt2Celsius); put("oilTemperatureCelsius", s.oilTemperatureCelsius); put("oilPressureBar", s.oilPressureBar); put("fuelPressureBar", s.fuelPressureBar); put("afr", s.afr); put("lambda", s.lambda); put("batteryVoltage", s.batteryVoltage); put("ignitionDegrees", s.ignitionDegrees); put("injectorDutyPercent", s.injectorDutyPercent); put("speedKph", s.speedKph); put("checkEngineMask", s.checkEngineMask); s.latitude?.let { put("latitude", it) }; s.longitude?.let { put("longitude", it) }; s.horizontalAccuracy?.let { put("horizontalAccuracy", it) }; s.altitude?.let { put("altitude", it) }
    }

    private fun iso(value: Long) = Instant.ofEpochMilli(value).toString()
    companion object { private const val WORK_NOW = "touge-cloud-now"; private const val WORK_PERIODIC = "touge-cloud-periodic" }
}

class CloudSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val container = (applicationContext as TougeDashApplication).container
        return if (container.cloudSyncRepository.sync()) Result.success() else Result.retry()
    }
}
