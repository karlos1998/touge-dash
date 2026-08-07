@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.video

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlaySettings
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import it.letscode.tougedash.model.DashboardAccent
import it.letscode.tougedash.model.TelemetryMetric
import kotlinx.serialization.Serializable
import kotlin.math.min

@Serializable
enum class OverlayStyle { MINIMAL, RACE, UNDERGROUND }

class TelemetryBitmapOverlay(
    private val samples: List<TelemetrySampleEntity>,
    private val telemetryStartSeconds: Double,
    private val definition: VideoOverlayTemplateDefinition,
    width: Int,
    height: Int
) : BitmapOverlay() {
    private val bitmapWidth = width.coerceIn(640, 3840)
    private val bitmapHeight = height.coerceIn(360, 3840)
    private val portrait = bitmapHeight > bitmapWidth
    private val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD) }
    private val firstTime = samples.firstOrNull()?.recordedAt ?: 0L

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        bitmap.eraseColor(Color.TRANSPARENT)
        val target = firstTime + ((telemetryStartSeconds + presentationTimeUs / 1_000_000.0) * 1000).toLong()
        val sample = nearestSample(target) ?: return bitmap
        definition.resolvedElements().forEach { drawElement(sample, it) }
        return bitmap
    }

    private fun nearestSample(target: Long): TelemetrySampleEntity? {
        if (samples.isEmpty()) return null
        val found = samples.binarySearchBy(target) { it.recordedAt }
        if (found >= 0) return samples[found]
        val insertion = -found - 1
        val before = samples.getOrNull(insertion - 1)
        val after = samples.getOrNull(insertion)
        return when {
            before == null -> after
            after == null -> before
            target - before.recordedAt <= after.recordedAt - target -> before
            else -> after
        }
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = OverlaySettings.Builder()
        .setBackgroundFrameAnchor(0f, 0f)
        .setOverlayFrameAnchor(0f, 0f)
        .build()

    private fun drawElement(sample: TelemetrySampleEntity, element: VideoOverlayElement) {
        val position = element.position(portrait)
        val cx = bitmapWidth * position.x
        val cy = bitmapHeight * position.y
        val base = min(bitmapWidth, bitmapHeight) / 1080f
        val scale = element.effectiveScale * base
        when (element.kind) {
            OverlayElementKind.DIGITAL -> drawDigital(sample, element, cx, cy, scale)
            OverlayElementKind.GAUGE -> drawGauge(sample, element, cx, cy, scale)
            OverlayElementKind.BAR -> drawBar(sample, element, cx, cy, scale)
        }
    }

    private fun drawDigital(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val width = 215f * scale
        val height = 105f * scale
        panel(cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2, 18f * scale)
        centered(element.metric.shortName, cx, cy - 20f * scale, 20f * scale, 0xff91a5ae.toInt())
        centered(format(element.metric, element.metric.sampleValue(sample)), cx, cy + 25f * scale, 46f * scale, element.accent.colorInt())
        centered(element.metric.unit.uppercase(), cx, cy + 47f * scale, 13f * scale, Color.WHITE)
    }

    private fun drawGauge(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val radius = 88f * scale
        panel(cx - radius * 1.18f, cy - radius * 1.18f, cx + radius * 1.18f, cy + radius * 1.18f, radius)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 11f * scale
        paint.strokeCap = Paint.Cap.ROUND
        val rect = RectF(cx - radius * .78f, cy - radius * .78f, cx + radius * .78f, cy + radius * .78f)
        paint.color = 0x44394a53
        canvas.drawArc(rect, 145f, 250f, false, paint)
        val metricValue = element.metric.sampleValue(sample)
        val progress = ((metricValue - element.metric.defaultMin) / (element.metric.defaultMax - element.metric.defaultMin)).coerceIn(0.0, 1.0).toFloat()
        paint.color = element.accent.colorInt()
        canvas.drawArc(rect, 145f, 250f * progress, false, paint)
        paint.style = Paint.Style.FILL
        centered(format(element.metric, metricValue), cx, cy + 12f * scale, 43f * scale, Color.WHITE)
        centered(element.metric.shortName, cx, cy + 43f * scale, 16f * scale, element.accent.colorInt())
    }

    private fun drawBar(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val width = 500f * scale
        val height = 85f * scale
        panel(cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2, 17f * scale)
        val value = element.metric.sampleValue(sample)
        val progress = ((value - element.metric.defaultMin) / (element.metric.defaultMax - element.metric.defaultMin)).coerceIn(0.0, 1.0).toFloat()
        val left = cx - width * .43f
        val right = cx + width * .43f
        pill(left, cy + 12f * scale, right, cy + 29f * scale, 0x55394a53)
        pill(left, cy + 12f * scale, left + (right - left) * progress, cy + 29f * scale, element.accent.colorInt())
        text(element.metric.shortName, left, cy - 7f * scale, 18f * scale, 0xff91a5ae.toInt())
        rightText("${format(element.metric, value)} ${element.metric.unit}", right, cy - 7f * scale, 26f * scale, Color.WHITE)
    }

    private fun panel(left: Float, top: Float, right: Float, bottom: Float, radius: Float) {
        paint.style = Paint.Style.FILL
        paint.color = when (definition.style) {
            OverlayStyle.MINIMAL -> 0xa8071014.toInt()
            OverlayStyle.RACE -> 0xd4071014.toInt()
            OverlayStyle.UNDERGROUND -> 0xdc020705.toInt()
        }
        canvas.drawRoundRect(left, top, right, bottom, radius, radius, paint)
        if (definition.style == OverlayStyle.UNDERGROUND) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2f
            paint.color = 0x8839ff14.toInt()
            canvas.drawRoundRect(left, top, right, bottom, radius, radius, paint)
            paint.style = Paint.Style.FILL
        }
    }

    private fun centered(value: String, x: Float, y: Float, size: Float, color: Int) {
        paint.textAlign = Paint.Align.CENTER
        text(value, x, y, size, color)
    }

    private fun rightText(value: String, x: Float, y: Float, size: Float, color: Int) {
        paint.textAlign = Paint.Align.RIGHT
        text(value, x, y, size, color)
    }

    private fun text(value: String, x: Float, y: Float, size: Float, color: Int) {
        paint.textSize = size
        paint.color = color
        paint.style = Paint.Style.FILL
        canvas.drawText(value, x, y, paint)
        paint.textAlign = Paint.Align.LEFT
    }

    private fun pill(left: Float, top: Float, right: Float, bottom: Float, color: Int) {
        paint.color = color
        paint.style = Paint.Style.FILL
        val radius = (bottom - top) / 2
        canvas.drawRoundRect(left, top, right.coerceAtLeast(left + 1), bottom, radius, radius, paint)
    }

    private fun format(metric: TelemetryMetric, value: Double) = when (metric.precision) {
        0 -> value.toInt().toString()
        1 -> "%.1f".format(value)
        else -> "%.2f".format(value)
    }

    private fun DashboardAccent.colorInt(): Int = when (this) {
        DashboardAccent.CYAN -> 0xff27d7e5.toInt()
        DashboardAccent.MINT -> 0xff43e8a8.toInt()
        DashboardAccent.BLUE -> 0xff3d82ff.toInt()
        DashboardAccent.ICE -> 0xff80dcff.toInt()
        DashboardAccent.ORANGE -> 0xffff9d3d.toInt()
        DashboardAccent.YELLOW -> 0xffffc83d.toInt()
        DashboardAccent.RED -> 0xffff352f.toInt()
        DashboardAccent.WHITE -> Color.WHITE
    }

    private fun TelemetryMetric.sampleValue(value: TelemetrySampleEntity): Double = when (this) {
        TelemetryMetric.RPM -> value.rpm
        TelemetryMetric.BOOST -> value.boostBar
        TelemetryMetric.MAP -> value.mapKpa
        TelemetryMetric.THROTTLE -> value.throttlePercent
        TelemetryMetric.COOLANT -> value.coolantCelsius
        TelemetryMetric.INTAKE -> value.intakeCelsius
        TelemetryMetric.OIL_TEMPERATURE -> value.oilTemperatureCelsius
        TelemetryMetric.OIL_PRESSURE -> value.oilPressureBar
        TelemetryMetric.FUEL_PRESSURE -> value.fuelPressureBar
        TelemetryMetric.AFR -> value.afr
        TelemetryMetric.LAMBDA -> value.lambda
        TelemetryMetric.BATTERY_VOLTAGE -> value.batteryVoltage
        TelemetryMetric.IGNITION -> value.ignitionDegrees
        TelemetryMetric.INJECTOR_DUTY -> value.injectorDutyPercent
        TelemetryMetric.SPEED -> value.speedKph
    }
}
