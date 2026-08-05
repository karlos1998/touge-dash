package it.letscode.tougedash.video

import it.letscode.tougedash.data.local.OverlayTemplateEntity
import it.letscode.tougedash.model.DashboardAccent
import it.letscode.tougedash.model.TelemetryMetric
import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class OverlayElementKind { DIGITAL, GAUGE, BAR }

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
    val accent: DashboardAccent = DashboardAccent.CYAN,
    val landscapePosition: OverlayPosition,
    val portraitPosition: OverlayPosition = landscapePosition
) {
    fun position(portrait: Boolean) = (if (portrait) portraitPosition else landscapePosition).clamped()
    fun positioned(portrait: Boolean, position: OverlayPosition) =
        if (portrait) copy(portraitPosition = position.clamped()) else copy(landscapePosition = position.clamped())
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
    val elements: List<VideoOverlayElement> = emptyList(),
    val layoutVersion: Int = 2
) {
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
