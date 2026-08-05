package it.letscode.tougedash.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.LocalGasStation
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.ui.theme.TougeBackground
import it.letscode.tougedash.ui.theme.TougeBlue
import it.letscode.tougedash.ui.theme.TougeCyan

internal class CutCornerShape(
    private val cut: Dp = 16.dp,
    private val roundedCorner: Dp = 12.dp
) : Shape {
    override fun createOutline(size: androidx.compose.ui.geometry.Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val corner = with(density) { roundedCorner.toPx() }.coerceAtMost(minOf(size.width, size.height) * .18f)
        val diagonal = with(density) { cut.toPx() }.coerceAtMost(minOf(size.width, size.height) * .3f)
        val path = Path().apply {
            moveTo(0f, corner)
            quadraticTo(0f, 0f, corner, 0f)
            lineTo(size.width - diagonal, 0f)
            lineTo(size.width, diagonal)
            lineTo(size.width, size.height - corner)
            quadraticTo(size.width, size.height, size.width - corner, size.height)
            lineTo(diagonal, size.height)
            lineTo(0f, size.height - diagonal)
            close()
        }
        return Outline.Generic(path)
    }
}

@Composable
internal fun DashboardBackdrop(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxSize().background(TougeBackground)) {
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(TougeBlue.copy(alpha = .17f), Color.Transparent),
                    center = Offset(size.width * .92f, -size.height * .04f),
                    radius = maxOf(size.width, size.height) * .62f
                ),
                radius = maxOf(size.width, size.height) * .62f,
                center = Offset(size.width * .92f, -size.height * .04f)
            )
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(TougeCyan.copy(alpha = .08f), Color.Transparent),
                    center = Offset(-size.width * .08f, size.height * .92f),
                    radius = maxOf(size.width, size.height) * .54f
                ),
                radius = maxOf(size.width, size.height) * .54f,
                center = Offset(-size.width * .08f, size.height * .92f)
            )
            repeat(5) { index ->
                val x = size.width * (.16f + index * .21f)
                drawLine(
                    color = TougeCyan.copy(alpha = if (index == 0) .075f else .025f),
                    start = Offset(x + size.height * .38f, -size.height * .08f),
                    end = Offset(x - size.height * .18f, size.height * 1.08f),
                    strokeWidth = if (index == 0) 2f else 1f
                )
            }
            drawRect(
                brush = Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .38f)))
            )
        }
        content()
    }
}

@Composable
internal fun TougePanelSurface(
    accent: Color,
    modifier: Modifier = Modifier,
    warning: Boolean = false,
    cut: Dp = 16.dp,
    content: @Composable BoxScope.() -> Unit
) {
    val shape = CutCornerShape(cut)
    val edge = if (warning) Color(0xFFFF3B40).copy(alpha = .62f) else Color.White.copy(alpha = .085f)
    val colors = if (warning) {
        listOf(Color(0xFF281216), Color(0xFF0A1015))
    } else {
        listOf(Color(0xFF0E171D), Color(0xFF080F14))
    }
    Box(
        modifier
            .background(Brush.linearGradient(colors), shape)
            .border(1.dp, edge, shape)
    ) {
        content()
        Box(
            Modifier
                .align(Alignment.TopStart)
                .offset(x = 16.dp)
                .width(54.dp)
                .height(2.dp)
                .background(if (warning) Color(0xFFFF3B40) else accent.copy(alpha = .82f))
        )
    }
}

@Composable
internal fun TelemetryGlyph(metric: TelemetryMetric, tint: Color, modifier: Modifier = Modifier) {
    Icon(metricIcon(metric), contentDescription = null, modifier = modifier, tint = tint)
}

private fun metricIcon(metric: TelemetryMetric): ImageVector = when (metric) {
    TelemetryMetric.BOOST -> Icons.Default.Air
    TelemetryMetric.RPM, TelemetryMetric.SPEED -> Icons.Default.Speed
    TelemetryMetric.COOLANT, TelemetryMetric.INTAKE, TelemetryMetric.OIL_TEMPERATURE -> Icons.Default.Thermostat
    TelemetryMetric.BATTERY_VOLTAGE -> Icons.Default.BatteryChargingFull
    TelemetryMetric.FUEL_PRESSURE -> Icons.Default.LocalGasStation
    TelemetryMetric.THROTTLE, TelemetryMetric.IGNITION -> Icons.Default.Tune
    TelemetryMetric.OIL_PRESSURE, TelemetryMetric.INJECTOR_DUTY -> Icons.Default.WaterDrop
    TelemetryMetric.AFR, TelemetryMetric.LAMBDA, TelemetryMetric.MAP -> Icons.AutoMirrored.Filled.ShowChart
}
