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
    val templates: Flow<List<DashboardTemplate>> = dao.templates().map { values ->
        values.mapNotNull(::decode).sortedWith(pageComparator)
    }
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
        val copy = template.copy(
            id = UUID.randomUUID().toString(),
            name = "${template.name} copy",
            definition = template.definition.copy(pageOrder = visibleTemplates().size),
            modifiedAt = System.currentTimeMillis()
        )
        save(copy, select = true)
        return copy
    }

    suspend fun create(name: String = "Dashboard"): DashboardTemplate {
        val value = DashboardTemplate.factory().copy(
            id = UUID.randomUUID().toString(),
            name = name,
            definition = DashboardTemplate.factory().definition.copy(pageOrder = visibleTemplates().size),
            modifiedAt = System.currentTimeMillis()
        )
        save(value, select = true)
        return value
    }

    suspend fun createPage(source: DashboardTemplate, atStart: Boolean, name: String): DashboardTemplate {
        val pages = visibleTemplates()
        val created = source.copy(
            id = UUID.randomUUID().toString(),
            name = name,
            definition = source.definition.copy(pageOrder = if (atStart) 0 else pages.size),
            modifiedAt = System.currentTimeMillis(),
            deletedAt = null
        )
        val reordered = pages.toMutableList().apply {
            add(if (atStart) 0 else size, created)
        }
        savePageOrder(reordered)
        dao.selectTemplate(created.id)
        return created
    }

    suspend fun delete(template: DashboardTemplate) {
        val pages = visibleTemplates()
        if (pages.size <= 1) return
        val deletedIndex = pages.indexOfFirst { it.id == template.id }.coerceAtLeast(0)
        save(template.copy(deletedAt = System.currentTimeMillis(), modifiedAt = System.currentTimeMillis()))
        val remaining = pages.filterNot { it.id == template.id }
        savePageOrder(remaining)
        dao.selectTemplate(remaining[deletedIndex.coerceAtMost(remaining.lastIndex)].id)
    }

    suspend fun restoreFactory() {
        val existingOrder = visibleTemplates().firstOrNull { it.id == DashboardTemplate.FACTORY_ID }?.definition?.pageOrder ?: 0
        val factory = DashboardTemplate.factory()
        save(factory.copy(definition = factory.definition.copy(pageOrder = existingOrder), modifiedAt = System.currentTimeMillis()), select = true)
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
                it.letscode.tougedash.model.DashboardWidgetKind.PERFORMANCE,
                it.letscode.tougedash.model.DashboardWidgetKind.ECU_SWITCH,
                it.letscode.tougedash.model.DashboardWidgetKind.ECU_ROTARY -> 0
                else -> 1
            }
            val isControl = widget.kind == it.letscode.tougedash.model.DashboardWidgetKind.ECU_SWITCH ||
                widget.kind == it.letscode.tougedash.model.DashboardWidgetKind.ECU_ROTARY
            widget.copy(
                metrics = if (metricLimit == 0) emptyList() else widget.metrics.take(metricLimit).ifEmpty { listOf(it.letscode.tougedash.model.TelemetryMetric.BOOST) },
                portraitSpan = widget.portraitSpan.coerceIn(0, 12),
                landscapeSpan = widget.landscapeSpan.coerceIn(0, 12),
                portraitOrder = widget.portraitOrder.takeIf { it >= 0 } ?: index,
                landscapeOrder = widget.landscapeOrder.takeIf { it >= 0 } ?: index,
                gaugeMinimum = widget.gaugeMinimum?.takeIf { minimum -> widget.gaugeMaximum == null || minimum < widget.gaugeMaximum },
                chartDurationSeconds = widget.chartDurationSeconds?.takeIf { it in setOf(30, 180, 600) },
                controlChannel = if (isControl) (widget.controlChannel ?: 1).coerceIn(1, 8) else null,
                wideKind = if (isControl) null else widget.wideKind
            )
        }
        return copy(
            name = name.trim().take(80).ifEmpty { "Dashboard" },
            definition = DashboardDefinition(normalizedWidgets, definition.pageOrder),
            modifiedAt = System.currentTimeMillis()
        )
    }

    private suspend fun visibleTemplates(): List<DashboardTemplate> = dao.templatesOnce()
        .mapNotNull(::decode)
        .filter { it.deletedAt == null }
        .sortedWith(pageComparator)

    private suspend fun savePageOrder(pages: List<DashboardTemplate>) {
        val now = System.currentTimeMillis()
        pages.forEachIndexed { index, page ->
            save(page.copy(definition = page.definition.copy(pageOrder = index), modifiedAt = now))
        }
    }

    private val pageComparator = compareBy<DashboardTemplate>(
        { it.definition.pageOrder ?: if (it.id == DashboardTemplate.FACTORY_ID) 0 else Int.MAX_VALUE },
        { it.id }
    )
}

internal fun normalizeLegacyDashboardJson(value: String): String {
    val names = mapOf(
        "HERO" to "hero", "GROUP" to "group", "VALUE" to "value", "GAUGE" to "gauge", "CHART" to "chart", "COMPACT" to "compact", "PERFORMANCE" to "performance", "ECU_SWITCH" to "ecuSwitch", "ECU_ROTARY" to "ecuRotary",
        "CYAN" to "cyan", "MINT" to "mint", "BLUE" to "blue", "ICE" to "ice", "ORANGE" to "orange", "YELLOW" to "yellow", "RED" to "red", "WHITE" to "white",
        "RPM" to "rpm", "BOOST" to "boost", "MAP" to "map", "THROTTLE" to "throttle", "COOLANT" to "coolant", "INTAKE" to "intake",
        "OIL_TEMPERATURE" to "oilTemperature", "OIL_PRESSURE" to "oilPressure", "FUEL_PRESSURE" to "fuelPressure", "AFR" to "afr", "LAMBDA" to "lambda",
        "BATTERY_VOLTAGE" to "batteryVoltage", "IGNITION" to "ignition", "INJECTOR_DUTY" to "injectorDuty", "SPEED" to "speed"
    )
    return names.entries.fold(value.replace("\"chartDurationSeconds\"", "\"chartDuration\"")) { result, (old, new) -> result.replace("\"$old\"", "\"$new\"") }
}
