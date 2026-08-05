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
        dao.upsertTemplate(template.normalized().entity(selected = select))
        if (select) dao.selectTemplate(template.id)
    }

    suspend fun rename(template: DashboardTemplate, name: String) {
        val normalizedName = name.trim().take(80)
        if (normalizedName.isNotEmpty()) save(template.copy(name = normalizedName, modifiedAt = System.currentTimeMillis()), select = true)
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
        if (template.id == DashboardTemplate.FACTORY_ID) return
        save(template.copy(deletedAt = System.currentTimeMillis(), modifiedAt = System.currentTimeMillis()))
        dao.selectTemplate(DashboardTemplate.FACTORY_ID)
    }

    suspend fun restoreFactory() {
        save(DashboardTemplate.factory().copy(modifiedAt = System.currentTimeMillis()), select = true)
    }

    private fun decode(entity: DashboardTemplateEntity?): DashboardTemplate? = entity?.let {
        runCatching {
            val definition = json.decodeFromString<DashboardDefinition>(normalizeLegacyDashboardJson(it.definitionJson))
            DashboardTemplate(it.id, it.schemaVersion, it.name, definition, it.modifiedAt, it.deletedAt)
        }.getOrNull()
    }

    private fun DashboardTemplate.entity(selected: Boolean) = DashboardTemplateEntity(
        id = id, name = name, definitionJson = json.encodeToString(definition), schemaVersion = schemaVersion,
        modifiedAt = modifiedAt, deletedAt = deletedAt, selected = selected, dirty = true
    )

    private fun DashboardTemplate.normalized(): DashboardTemplate {
        val normalizedWidgets = definition.widgets.mapIndexed { index, widget ->
            val metricLimit = when (widget.kind) {
                it.letscode.tougedash.model.DashboardWidgetKind.HERO -> 4
                it.letscode.tougedash.model.DashboardWidgetKind.GROUP -> 3
                else -> 1
            }
            widget.copy(
                metrics = widget.metrics.take(metricLimit).ifEmpty { listOf(it.letscode.tougedash.model.TelemetryMetric.BOOST) },
                portraitSpan = widget.portraitSpan.coerceIn(0, 12),
                landscapeSpan = widget.landscapeSpan.coerceIn(0, 12),
                portraitOrder = widget.portraitOrder.takeIf { it >= 0 } ?: index,
                landscapeOrder = widget.landscapeOrder.takeIf { it >= 0 } ?: index,
                gaugeMinimum = widget.gaugeMinimum?.takeIf { minimum -> widget.gaugeMaximum == null || minimum < widget.gaugeMaximum },
                chartDurationSeconds = widget.chartDurationSeconds?.takeIf { it in setOf(30, 180, 600) }
            )
        }
        return copy(
            name = name.trim().take(80).ifEmpty { "Dashboard" },
            definition = DashboardDefinition(normalizedWidgets),
            modifiedAt = System.currentTimeMillis()
        )
    }
}

internal fun normalizeLegacyDashboardJson(value: String): String {
    val names = mapOf(
        "HERO" to "hero", "GROUP" to "group", "VALUE" to "value", "GAUGE" to "gauge", "CHART" to "chart", "COMPACT" to "compact",
        "CYAN" to "cyan", "MINT" to "mint", "BLUE" to "blue", "ICE" to "ice", "ORANGE" to "orange", "YELLOW" to "yellow", "RED" to "red", "WHITE" to "white",
        "RPM" to "rpm", "BOOST" to "boost", "MAP" to "map", "THROTTLE" to "throttle", "COOLANT" to "coolant", "INTAKE" to "intake",
        "OIL_TEMPERATURE" to "oilTemperature", "OIL_PRESSURE" to "oilPressure", "FUEL_PRESSURE" to "fuelPressure", "AFR" to "afr", "LAMBDA" to "lambda",
        "BATTERY_VOLTAGE" to "batteryVoltage", "IGNITION" to "ignition", "INJECTOR_DUTY" to "injectorDuty", "SPEED" to "speed"
    )
    return names.entries.fold(value.replace("\"chartDurationSeconds\"", "\"chartDuration\"")) { result, (old, new) -> result.replace("\"$old\"", "\"$new\"") }
}
