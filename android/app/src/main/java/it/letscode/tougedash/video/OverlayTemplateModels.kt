package it.letscode.tougedash.video

import it.letscode.tougedash.data.local.OverlayTemplateEntity
import it.letscode.tougedash.model.DashboardAccent
import it.letscode.tougedash.model.TelemetryMetric
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class OverlayElementKind {
    DIGITAL,
    GAUGE,
    BAR,
    SPEED_CLUSTER,
    OIL_CLUSTER,
    NEON_TACH,
    BLACKLIST_TACH,
    CARBON_TACH,
    STREET_SHIFT_TACH,
    ROUTE_MAP,
    ROUTE_MAP_CIRCULAR,
    ROUTE_MAP_FOLLOW,
    ROUTE_MAP_LIGHT,
    ROUTE_MAP_LIGHT_CIRCULAR,
    ROUTE_MAP_AMBER;

    val isRouteMap: Boolean
        get() = this == ROUTE_MAP || this == ROUTE_MAP_CIRCULAR || this == ROUTE_MAP_FOLLOW ||
            this == ROUTE_MAP_LIGHT || this == ROUTE_MAP_LIGHT_CIRCULAR || this == ROUTE_MAP_AMBER

    val isCircularRouteMap: Boolean
        get() = this == ROUTE_MAP_CIRCULAR || this == ROUTE_MAP_FOLLOW || this == ROUTE_MAP_LIGHT_CIRCULAR

    val usesLightMap: Boolean
        get() = this == ROUTE_MAP_LIGHT || this == ROUTE_MAP_LIGHT_CIRCULAR || this == ROUTE_MAP_AMBER
}

@Serializable
enum class OverlayElementScale(val multiplier: Float) {
    SMALL(.72f), MEDIUM(1f), LARGE(1.36f), EXTRA_LARGE(1.72f)
}

@Serializable
data class OverlayPosition(val x: Float, val y: Float) {
    fun clamped() = OverlayPosition(x.coerceIn(.05f, .95f), y.coerceIn(.05f, .95f))
}

@Serializable
data class VideoOverlayElement(
    val id: String = UUID.randomUUID().toString(),
    val metric: TelemetryMetric,
    val kind: OverlayElementKind = OverlayElementKind.DIGITAL,
    val scale: OverlayElementScale = OverlayElementScale.MEDIUM,
    val sizeMultiplier: Float = 1f,
    val mapZoom: Float = 1f,
    val accent: DashboardAccent = DashboardAccent.CYAN,
    val landscapePosition: OverlayPosition,
    val portraitPosition: OverlayPosition = landscapePosition
) {
    val effectiveScale get() = scale.multiplier * sizeMultiplier.coerceIn(.45f, 2.5f)
    fun position(portrait: Boolean) = (if (portrait) portraitPosition else landscapePosition).clamped()
    fun positioned(portrait: Boolean, position: OverlayPosition) =
        if (portrait) copy(portraitPosition = position.clamped()) else copy(landscapePosition = position.clamped())
    fun resized(zoom: Float) = copy(sizeMultiplier = (sizeMultiplier * zoom).coerceIn(.45f, 2.5f))
    fun withMapZoom(zoom: Float) = copy(mapZoom = zoom.coerceIn(.65f, 1.85f))
}

@Serializable
data class VideoOverlayTemplateDefinition(
    val style: OverlayStyle,
    // Kept for decoding templates saved by older Android builds.
    val portraitX: Float = 0f,
    val portraitY: Float = -.72f,
    val landscapeX: Float = 0f,
    val landscapeY: Float = -.70f,
    val scale: Float = .92f,
    val maximumSpeedKph: Float = 300f,
    val maximumOilTemperatureCelsius: Float = 140f,
    val maximumRpm: Float = 8_000f,
    val maximumBoostBar: Float = 2f,
    val elements: List<VideoOverlayElement> = emptyList(),
    val layoutVersion: Int = 2
) {
    fun range(metric: TelemetryMetric): ClosedFloatingPointRange<Double> = when (metric) {
        TelemetryMetric.SPEED -> 0.0..maximumSpeedKph.coerceAtLeast(100f).toDouble()
        TelemetryMetric.OIL_TEMPERATURE -> 0.0..maximumOilTemperatureCelsius.coerceAtLeast(80f).toDouble()
        TelemetryMetric.RPM -> 0.0..maximumRpm.coerceAtLeast(4_000f).toDouble()
        TelemetryMetric.BOOST -> metric.defaultMin..maximumBoostBar.coerceAtLeast(.5f).toDouble()
        else -> metric.defaultMin..metric.defaultMax
    }
    fun x(portrait: Boolean) = if (portrait) portraitX else landscapeX
    fun y(portrait: Boolean) = if (portrait) portraitY else landscapeY
    fun positioned(portrait: Boolean, x: Float, y: Float, scale: Float = this.scale) =
        if (portrait) copy(portraitX = x, portraitY = y, scale = scale)
        else copy(landscapeX = x, landscapeY = y, scale = scale)

    fun resolvedElements(): List<VideoOverlayElement> = elements.ifEmpty { legacyElements(style) }

    companion object {
        fun tougePro() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.RACE,
            elements = listOf(
                element(TelemetryMetric.RPM, OverlayElementKind.BAR, OverlayElementScale.LARGE, DashboardAccent.YELLOW, .50f, .09f, .50f, .08f),
                element(TelemetryMetric.SPEED, OverlayElementKind.GAUGE, OverlayElementScale.EXTRA_LARGE, DashboardAccent.ICE, .15f, .76f, .50f, .79f),
                element(TelemetryMetric.BOOST, OverlayElementKind.GAUGE, OverlayElementScale.LARGE, DashboardAccent.CYAN, .85f, .76f, .50f, .43f),
                element(TelemetryMetric.OIL_PRESSURE, accent = DashboardAccent.MINT, lx = .13f, ly = .18f, px = .19f, py = .21f),
                element(TelemetryMetric.OIL_TEMPERATURE, accent = DashboardAccent.ORANGE, lx = .50f, ly = .18f, px = .50f, py = .21f),
                element(TelemetryMetric.COOLANT, accent = DashboardAccent.ICE, lx = .87f, ly = .18f, px = .81f, py = .21f)
            )
        )

        fun nightRun() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.UNDERGROUND,
            elements = listOf(
                element(TelemetryMetric.RPM, OverlayElementKind.BAR, OverlayElementScale.EXTRA_LARGE, DashboardAccent.ORANGE, .50f, .10f, .50f, .08f),
                element(TelemetryMetric.SPEED, OverlayElementKind.GAUGE, OverlayElementScale.EXTRA_LARGE, DashboardAccent.CYAN, .82f, .72f, .50f, .76f),
                element(TelemetryMetric.BOOST, OverlayElementKind.GAUGE, OverlayElementScale.LARGE, DashboardAccent.MINT, .18f, .75f, .50f, .42f),
                element(TelemetryMetric.AFR, accent = DashboardAccent.WHITE, lx = .13f, ly = .20f, px = .23f, py = .20f),
                element(TelemetryMetric.OIL_PRESSURE, accent = DashboardAccent.YELLOW, lx = .87f, ly = .20f, px = .77f, py = .20f)
            )
        )

        fun cleanDrive() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.MINIMAL,
            elements = listOf(
                element(TelemetryMetric.SPEED, scale = OverlayElementScale.EXTRA_LARGE, accent = DashboardAccent.WHITE, lx = .15f, ly = .82f, px = .50f, py = .82f),
                element(TelemetryMetric.BOOST, OverlayElementKind.BAR, OverlayElementScale.LARGE, DashboardAccent.CYAN, .82f, .85f, .50f, .62f),
                element(TelemetryMetric.OIL_TEMPERATURE, accent = DashboardAccent.ORANGE, lx = .87f, ly = .15f, px = .78f, py = .16f),
                element(TelemetryMetric.COOLANT, accent = DashboardAccent.ICE, lx = .13f, ly = .15f, px = .22f, py = .16f)
            )
        )

        fun portraitRally() = tougePro().copy(
            elements = tougePro().elements.map { value ->
                when (value.metric) {
                    TelemetryMetric.SPEED -> value.copy(landscapePosition = OverlayPosition(.50f, .76f), portraitPosition = OverlayPosition(.50f, .77f))
                    TelemetryMetric.BOOST -> value.copy(landscapePosition = OverlayPosition(.17f, .74f), portraitPosition = OverlayPosition(.50f, .40f))
                    else -> value
                }
            }
        )

        fun streetLegends() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.UNDERGROUND,
            elements = listOf(
                element(TelemetryMetric.SPEED, OverlayElementKind.SPEED_CLUSTER, OverlayElementScale.EXTRA_LARGE, DashboardAccent.CYAN, .20f, .72f, .50f, .73f),
                element(TelemetryMetric.OIL_TEMPERATURE, OverlayElementKind.OIL_CLUSTER, OverlayElementScale.LARGE, DashboardAccent.ORANGE, .80f, .72f, .50f, .38f)
            )
        )

        fun neonCircuit() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.UNDERGROUND,
            maximumRpm = 10_000f,
            elements = listOf(
                element(TelemetryMetric.RPM, OverlayElementKind.NEON_TACH, OverlayElementScale.SMALL, DashboardAccent.CYAN, .82f, .73f, .50f, .77f)
            )
        )

        fun blacklistClassic() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.RACE,
            maximumRpm = 10_000f,
            elements = listOf(
                element(TelemetryMetric.RPM, OverlayElementKind.BLACKLIST_TACH, OverlayElementScale.SMALL, DashboardAccent.RED, .82f, .73f, .50f, .77f)
            )
        )

        fun carbonGold() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.RACE,
            maximumRpm = 9_000f,
            elements = listOf(
                element(TelemetryMetric.RPM, OverlayElementKind.CARBON_TACH, OverlayElementScale.SMALL, DashboardAccent.YELLOW, .82f, .73f, .50f, .77f)
            )
        )

        fun streetShift() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.UNDERGROUND,
            maximumRpm = 10_000f,
            elements = listOf(
                element(TelemetryMetric.RPM, OverlayElementKind.STREET_SHIFT_TACH, OverlayElementScale.SMALL, DashboardAccent.ORANGE, .82f, .73f, .50f, .77f)
            )
        )

        fun routeRadar() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.UNDERGROUND,
            maximumRpm = 10_000f,
            elements = listOf(
                element(TelemetryMetric.SPEED, OverlayElementKind.ROUTE_MAP, OverlayElementScale.MEDIUM, DashboardAccent.CYAN, .19f, .24f, .50f, .18f),
                element(TelemetryMetric.RPM, OverlayElementKind.NEON_TACH, OverlayElementScale.SMALL, DashboardAccent.CYAN, .82f, .73f, .50f, .78f)
            )
        )

        fun routeOrbit() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.UNDERGROUND,
            maximumRpm = 9_000f,
            elements = listOf(
                element(TelemetryMetric.SPEED, OverlayElementKind.ROUTE_MAP_CIRCULAR, OverlayElementScale.MEDIUM, DashboardAccent.MINT, .18f, .26f, .50f, .20f),
                element(TelemetryMetric.RPM, OverlayElementKind.CARBON_TACH, OverlayElementScale.SMALL, DashboardAccent.ORANGE, .83f, .73f, .50f, .79f)
            )
        )

        fun pursuitMap() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.RACE,
            maximumRpm = 10_000f,
            elements = listOf(
                element(TelemetryMetric.SPEED, OverlayElementKind.ROUTE_MAP, OverlayElementScale.MEDIUM, DashboardAccent.RED, .81f, .24f, .50f, .20f),
                element(TelemetryMetric.RPM, OverlayElementKind.BLACKLIST_TACH, OverlayElementScale.SMALL, DashboardAccent.RED, .18f, .73f, .50f, .79f)
            )
        )

        fun routeChase() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.UNDERGROUND,
            maximumRpm = 10_000f,
            elements = listOf(
                element(TelemetryMetric.SPEED, OverlayElementKind.ROUTE_MAP_FOLLOW, OverlayElementScale.MEDIUM, DashboardAccent.BLUE, .18f, .26f, .50f, .20f),
                element(TelemetryMetric.RPM, OverlayElementKind.NEON_TACH, OverlayElementScale.SMALL, DashboardAccent.BLUE, .83f, .73f, .50f, .79f)
            )
        )

        fun streetAtlas() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.MINIMAL,
            elements = listOf(
                element(TelemetryMetric.SPEED, OverlayElementKind.ROUTE_MAP_LIGHT, OverlayElementScale.MEDIUM, DashboardAccent.BLUE, .20f, .24f, .50f, .19f)
            )
        )

        fun iceOrbit() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.MINIMAL,
            elements = listOf(
                element(TelemetryMetric.SPEED, OverlayElementKind.ROUTE_MAP_LIGHT_CIRCULAR, OverlayElementScale.MEDIUM, DashboardAccent.ICE, .18f, .26f, .50f, .20f)
            )
        )

        fun amberRun() = VideoOverlayTemplateDefinition(
            style = OverlayStyle.RACE,
            elements = listOf(
                element(TelemetryMetric.SPEED, OverlayElementKind.ROUTE_MAP_AMBER, OverlayElementScale.MEDIUM, DashboardAccent.ORANGE, .80f, .24f, .50f, .19f)
            )
        )

        private fun legacyElements(style: OverlayStyle): List<VideoOverlayElement> = when (style) {
            OverlayStyle.MINIMAL -> cleanDrive().elements
            OverlayStyle.RACE -> tougePro().elements
            OverlayStyle.UNDERGROUND -> nightRun().elements
        }

        private fun element(
            metric: TelemetryMetric,
            kind: OverlayElementKind = OverlayElementKind.DIGITAL,
            scale: OverlayElementScale = OverlayElementScale.MEDIUM,
            accent: DashboardAccent = DashboardAccent.CYAN,
            lx: Float,
            ly: Float,
            px: Float,
            py: Float
        ) = VideoOverlayElement(
            metric = metric,
            kind = kind,
            scale = scale,
            accent = accent,
            landscapePosition = OverlayPosition(lx, ly),
            portraitPosition = OverlayPosition(px, py)
        )
    }
}

data class VideoOverlayTemplate(
    val entity: OverlayTemplateEntity,
    val definition: VideoOverlayTemplateDefinition
)
