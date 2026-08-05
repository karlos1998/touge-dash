package it.letscode.tougedash.alerts

import it.letscode.tougedash.data.local.AlertConfigurationEntity
import it.letscode.tougedash.data.local.TougeDashDao
import it.letscode.tougedash.model.VehicleAlertRules
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class AlertRepository(private val dao: TougeDashDao, private val json: Json) {
    fun rules(hardwareId: String): Flow<VehicleAlertRules> = dao.alertConfiguration(hardwareId).map { entity ->
        entity?.let { runCatching { json.decodeFromString<VehicleAlertRules>(it.rulesJson) }.getOrNull() } ?: VehicleAlertRules()
    }

    suspend fun save(hardwareId: String, rules: VehicleAlertRules) {
        val previous = dao.alertConfigurationOnce(hardwareId)
        dao.upsertAlertConfiguration(
            AlertConfigurationEntity(
                hardwareId, json.encodeToString(rules), revision = previous?.revision ?: 1,
                dirty = true, updatedAt = System.currentTimeMillis(), updatedByDisplayName = previous?.updatedByDisplayName
            )
        )
    }
}
