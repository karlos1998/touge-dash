package it.letscode.tougedash.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class DashboardWidgetKind { HERO, GROUP, VALUE, GAUGE, CHART, COMPACT }

@Serializable
enum class DashboardAccent { CYAN, MINT, BLUE, ICE, ORANGE, YELLOW, RED, WHITE }

@Serializable
data class DashboardWidget(
    val id: String = UUID.randomUUID().toString(),
    val kind: DashboardWidgetKind,
    val wideKind: DashboardWidgetKind? = null,
    val title: String? = null,
    val metrics: List<TelemetryMetric>,
    val portraitSpan: Int,
    val landscapeSpan: Int,
    val portraitOrder: Int,
    val landscapeOrder: Int = portraitOrder,
    val gaugeMinimum: Double? = null,
    val gaugeMaximum: Double? = null,
    val chartDurationSeconds: Int? = null,
    val accent: DashboardAccent = DashboardAccent.CYAN
)

@Serializable
data class DashboardDefinition(val widgets: List<DashboardWidget>)

@Serializable
data class DashboardTemplate(
    val id: String = UUID.randomUUID().toString(),
    val schemaVersion: Int = 1,
    val name: String,
    val definition: DashboardDefinition,
    val modifiedAt: Long = System.currentTimeMillis(),
    val deletedAt: Long? = null
) {
    companion object {
        const val FACTORY_ID = "d45d65aa-9d81-47d3-82b5-71c7b6e66a11"

        fun factory() = DashboardTemplate(
            id = FACTORY_ID,
            name = "Factory",
            definition = DashboardDefinition(
                listOf(
                    DashboardWidget(kind = DashboardWidgetKind.HERO, wideKind = DashboardWidgetKind.VALUE, metrics = listOf(TelemetryMetric.BOOST, TelemetryMetric.MAP, TelemetryMetric.THROTTLE, TelemetryMetric.RPM), portraitSpan = 12, landscapeSpan = 4, portraitOrder = 0, landscapeOrder = 1, gaugeMinimum = 0.0, gaugeMaximum = 2.0),
                    DashboardWidget(kind = DashboardWidgetKind.GROUP, title = "Engine health", metrics = listOf(TelemetryMetric.OIL_PRESSURE, TelemetryMetric.OIL_TEMPERATURE, TelemetryMetric.COOLANT), portraitSpan = 12, landscapeSpan = 8, portraitOrder = 1, landscapeOrder = 0, accent = DashboardAccent.MINT),
                    DashboardWidget(kind = DashboardWidgetKind.VALUE, metrics = listOf(TelemetryMetric.AFR), portraitSpan = 6, landscapeSpan = 3, portraitOrder = 2, accent = DashboardAccent.MINT),
                    DashboardWidget(kind = DashboardWidgetKind.VALUE, metrics = listOf(TelemetryMetric.BATTERY_VOLTAGE), portraitSpan = 6, landscapeSpan = 3, portraitOrder = 3, accent = DashboardAccent.YELLOW),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.THROTTLE), portraitSpan = 3, landscapeSpan = 0, portraitOrder = 5),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.INJECTOR_DUTY), portraitSpan = 3, landscapeSpan = 2, portraitOrder = 4, accent = DashboardAccent.ORANGE),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.INTAKE), portraitSpan = 3, landscapeSpan = 2, portraitOrder = 6, accent = DashboardAccent.BLUE),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.FUEL_PRESSURE), portraitSpan = 3, landscapeSpan = 2, portraitOrder = 7, accent = DashboardAccent.MINT)
                )
            ),
            modifiedAt = 1_785_890_400_000
        )
    }
}
