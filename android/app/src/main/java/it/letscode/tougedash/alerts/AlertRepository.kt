package it.letscode.tougedash.alerts

import it.letscode.tougedash.data.local.AlertConfigurationEntity
import it.letscode.tougedash.data.local.TougeDashDao
import it.letscode.tougedash.model.VehicleAlertRules
import it.letscode.tougedash.model.validated
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class AlertRepository(private val dao: TougeDashDao, private val json: Json) {
    data class Conflict(val rules: VehicleAlertRules, val revision: Int, val updatedAt: Long, val updatedByDisplayName: String?)
    private val conflicts = MutableStateFlow<Map<String, Conflict>>(emptyMap())

    fun configuration(hardwareId: String): Flow<AlertConfigurationEntity?> = dao.alertConfiguration(hardwareId)
    fun conflict(hardwareId: String): Flow<Conflict?> = conflicts.map { it[hardwareId] }

    fun rules(hardwareId: String): Flow<VehicleAlertRules> = dao.alertConfiguration(hardwareId).map { entity ->
        entity?.let { runCatching { json.decodeFromString<VehicleAlertRules>(it.rulesJson) }.getOrNull() } ?: VehicleAlertRules()
    }

    suspend fun save(hardwareId: String, rules: VehicleAlertRules) {
        val previous = dao.alertConfigurationOnce(hardwareId)
        dao.upsertAlertConfiguration(
            AlertConfigurationEntity(
                hardwareId, json.encodeToString(rules.validated()), revision = previous?.revision ?: 1,
                dirty = true, updatedAt = System.currentTimeMillis(), updatedByDisplayName = previous?.updatedByDisplayName
            )
        )
        clearConflict(hardwareId)
    }

    fun setConflict(hardwareId: String, conflict: Conflict) {
        conflicts.value = conflicts.value + (hardwareId to conflict)
    }

    suspend fun acceptRemote(hardwareId: String) {
        val remote = conflicts.value[hardwareId] ?: return
        dao.upsertAlertConfiguration(
            AlertConfigurationEntity(
                vehicleHardwareId = hardwareId,
                rulesJson = json.encodeToString(remote.rules.validated()),
                revision = remote.revision,
                dirty = false,
                updatedAt = remote.updatedAt,
                updatedByDisplayName = remote.updatedByDisplayName
            )
        )
        clearConflict(hardwareId)
    }

    suspend fun keepLocal(hardwareId: String) {
        val remote = conflicts.value[hardwareId] ?: return
        val local = dao.alertConfigurationOnce(hardwareId) ?: return
        dao.upsertAlertConfiguration(local.copy(revision = remote.revision, dirty = true))
        clearConflict(hardwareId)
    }

    private fun clearConflict(hardwareId: String) {
        conflicts.value = conflicts.value - hardwareId
    }

}
