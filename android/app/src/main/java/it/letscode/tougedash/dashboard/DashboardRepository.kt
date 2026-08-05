package it.letscode.tougedash.dashboard

import it.letscode.tougedash.data.local.DashboardTemplateEntity
import it.letscode.tougedash.data.local.TougeDashDao
import it.letscode.tougedash.model.DashboardDefinition
import it.letscode.tougedash.model.DashboardTemplate
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

class DashboardRepository(private val dao: TougeDashDao, private val json: Json) {
    val templates: Flow<List<DashboardTemplate>> = dao.templates().map { values -> values.mapNotNull(::decode) }
    val selected: Flow<DashboardTemplate> = dao.selectedTemplate().map { decode(it) ?: DashboardTemplate.factory() }

    suspend fun select(id: String) = dao.selectTemplate(id)

    suspend fun save(template: DashboardTemplate, select: Boolean = false) {
        dao.upsertTemplate(template.entity(selected = select))
        if (select) dao.selectTemplate(template.id)
    }

    suspend fun duplicate(template: DashboardTemplate): DashboardTemplate {
        val copy = template.copy(id = UUID.randomUUID().toString(), name = "${template.name} copy", modifiedAt = System.currentTimeMillis())
        save(copy, select = true)
        return copy
    }

    suspend fun create(name: String = "Dashboard"): DashboardTemplate {
        val value = DashboardTemplate.factory().copy(id = UUID.randomUUID().toString(), name = name, modifiedAt = System.currentTimeMillis())
        save(value, select = true)
        return value
    }

    suspend fun delete(template: DashboardTemplate) {
        save(template.copy(deletedAt = System.currentTimeMillis(), modifiedAt = System.currentTimeMillis()))
        dao.selectTemplate(DashboardTemplate.FACTORY_ID)
    }

    private fun decode(entity: DashboardTemplateEntity?): DashboardTemplate? = entity?.let {
        runCatching {
            DashboardTemplate(it.id, it.schemaVersion, it.name, json.decodeFromString<DashboardDefinition>(it.definitionJson), it.modifiedAt, it.deletedAt)
        }.getOrNull()
    }

    private fun DashboardTemplate.entity(selected: Boolean) = DashboardTemplateEntity(
        id = id, name = name, definitionJson = json.encodeToString(definition), schemaVersion = schemaVersion,
        modifiedAt = modifiedAt, deletedAt = deletedAt, selected = selected, dirty = true
    )
}
