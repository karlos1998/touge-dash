package it.letscode.tougedash.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import java.util.UUID
import it.letscode.tougedash.performance.AccelerationType

@Serializable
enum class DashboardWidgetKind {
    @SerialName("hero") HERO,
    @SerialName("group") GROUP,
    @SerialName("value") VALUE,
    @SerialName("gauge") GAUGE,
    @SerialName("chart") CHART,
    @SerialName("compact") COMPACT,
    @SerialName("performance") PERFORMANCE,
    @SerialName("ecuSwitch") ECU_SWITCH,
    @SerialName("ecuRotary") ECU_ROTARY
}

@Serializable
enum class DashboardAccent {
    @SerialName("cyan") CYAN,
    @SerialName("mint") MINT,
    @SerialName("blue") BLUE,
    @SerialName("ice") ICE,
    @SerialName("orange") ORANGE,
    @SerialName("yellow") YELLOW,
    @SerialName("red") RED,
    @SerialName("white") WHITE
}

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
    @SerialName("chartDuration") val chartDurationSeconds: Int? = null,
    val accelerationTypes: List<AccelerationType> = AccelerationType.entries,
    val controlChannel: Int? = null,
    val accent: DashboardAccent = DashboardAccent.CYAN
)

@Serializable
data class DashboardDefinition(
    val widgets: List<DashboardWidget>,
    val pageOrder: Int? = null
)

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
                widgets = listOf(
                    DashboardWidget(kind = DashboardWidgetKind.HERO, wideKind = DashboardWidgetKind.VALUE, metrics = listOf(TelemetryMetric.BOOST, TelemetryMetric.MAP, TelemetryMetric.THROTTLE, TelemetryMetric.RPM), portraitSpan = 12, landscapeSpan = 4, portraitOrder = 0, landscapeOrder = 1, gaugeMinimum = 0.0, gaugeMaximum = 2.0),
                    DashboardWidget(kind = DashboardWidgetKind.GROUP, title = "Engine health", metrics = listOf(TelemetryMetric.OIL_PRESSURE, TelemetryMetric.OIL_TEMPERATURE, TelemetryMetric.COOLANT), portraitSpan = 12, landscapeSpan = 12, portraitOrder = 1, landscapeOrder = 0, accent = DashboardAccent.MINT),
                    DashboardWidget(kind = DashboardWidgetKind.VALUE, metrics = listOf(TelemetryMetric.AFR), portraitSpan = 6, landscapeSpan = 3, portraitOrder = 2, accent = DashboardAccent.MINT),
                    DashboardWidget(kind = DashboardWidgetKind.VALUE, metrics = listOf(TelemetryMetric.BATTERY_VOLTAGE), portraitSpan = 6, landscapeSpan = 3, portraitOrder = 3, accent = DashboardAccent.YELLOW),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.MAP), portraitSpan = 0, landscapeSpan = 2, portraitOrder = 4, landscapeOrder = 4, accent = DashboardAccent.ICE),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.THROTTLE), portraitSpan = 3, landscapeSpan = 2, portraitOrder = 5, landscapeOrder = 5),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.RPM), portraitSpan = 0, landscapeSpan = 2, portraitOrder = 6, landscapeOrder = 6, accent = DashboardAccent.WHITE),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.INJECTOR_DUTY), portraitSpan = 3, landscapeSpan = 2, portraitOrder = 4, landscapeOrder = 7, accent = DashboardAccent.ORANGE),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.INTAKE), portraitSpan = 3, landscapeSpan = 2, portraitOrder = 6, landscapeOrder = 8, accent = DashboardAccent.BLUE),
                    DashboardWidget(kind = DashboardWidgetKind.COMPACT, metrics = listOf(TelemetryMetric.FUEL_PRESSURE), portraitSpan = 3, landscapeSpan = 2, portraitOrder = 7, landscapeOrder = 9, accent = DashboardAccent.MINT)
                ),
                pageOrder = 0
            ),
            modifiedAt = 1_785_890_400_000
        )
    }
}
