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
import kotlin.math.cos
import kotlin.math.sin

@Serializable
enum class OverlayStyle { MINIMAL, RACE, UNDERGROUND }

class TelemetryBitmapOverlay(
    private val samples: List<TelemetrySampleEntity>,
    private val telemetryStartSeconds: Double,
    private val definition: VideoOverlayTemplateDefinition,
    width: Int,
    height: Int
) : BitmapOverlay() {
    private val bitmapSize = overlayBitmapSize(width, height)
    private val bitmapWidth = bitmapSize.first
    private val bitmapHeight = bitmapSize.second
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
            OverlayElementKind.SPEED_CLUSTER -> drawSpeedCluster(sample, element, cx, cy, scale)
            OverlayElementKind.OIL_CLUSTER -> drawOilCluster(sample, element, cx, cy, scale)
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
        val progress = progress(element.metric, metricValue)
        paint.color = element.accent.colorInt()
        canvas.drawArc(rect, 145f, 250f * progress, false, paint)
        drawDialNeedle(cx, cy, radius * .72f, 145f, 250f, progress, element.metric, element.accent.colorInt(), scale)
        paint.style = Paint.Style.FILL
        centered(format(element.metric, metricValue), cx, cy + 12f * scale, 43f * scale, Color.WHITE)
        centered(element.metric.shortName, cx, cy + 43f * scale, 16f * scale, element.accent.colorInt())
    }

    private fun drawBar(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val width = 500f * scale
        val height = 85f * scale
        panel(cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2, 17f * scale)
        val value = element.metric.sampleValue(sample)
        val progress = progress(element.metric, value)
        val left = cx - width * .43f
        val right = cx + width * .43f
        pill(left, cy + 12f * scale, right, cy + 29f * scale, 0x55394a53)
        pill(left, cy + 12f * scale, left + (right - left) * progress, cy + 29f * scale, element.accent.colorInt())
        text(element.metric.shortName, left, cy - 7f * scale, 18f * scale, 0xff91a5ae.toInt())
        rightText("${format(element.metric, value)} ${element.metric.unit}", right, cy - 7f * scale, 26f * scale, Color.WHITE)
    }

    private fun drawSpeedCluster(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val radius = 105f * scale
        panel(cx - radius, cy - radius, cx + radius, cy + radius, radius)
        val progress = progress(TelemetryMetric.SPEED, sample.speedKph)
        drawDialNeedle(cx, cy, radius * .78f, 150f, 240f, progress, TelemetryMetric.SPEED, element.accent.colorInt(), scale)
        centered("RPM ${sample.rpm.toInt()}", cx, cy - 22f * scale, 14f * scale, 0xbbffffff.toInt())
        centered(sample.speedKph.toInt().toString(), cx, cy + 21f * scale, 50f * scale, Color.WHITE)
        centered("km/h", cx, cy + 42f * scale, 13f * scale, element.accent.colorInt())
        val boost = progress(TelemetryMetric.BOOST, sample.boostBar)
        val left = cx - 45f * scale
        val right = cx + 45f * scale
        centered("BOOST ${"%.1f".format(sample.boostBar)}", cx, cy + 62f * scale, 11f * scale, 0xff43e8a8.toInt())
        pill(left, cy + 69f * scale, right, cy + 75f * scale, 0x55394a53)
        pill(left, cy + 69f * scale, left + (right - left) * boost, cy + 75f * scale, 0xff43e8a8.toInt())
    }

    private fun drawOilCluster(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val radius = 96f * scale
        panel(cx - radius, cy - radius, cx + radius, cy + radius, radius)
        val progress = progress(TelemetryMetric.OIL_TEMPERATURE, sample.oilTemperatureCelsius)
        drawDialNeedle(cx, cy, radius * .76f, 150f, 240f, progress, TelemetryMetric.OIL_TEMPERATURE, element.accent.colorInt(), scale)
        centered("OIL TEMP", cx, cy - 20f * scale, 14f * scale, element.accent.colorInt())
        centered("${sample.oilTemperatureCelsius.toInt()}°", cx, cy + 19f * scale, 45f * scale, Color.WHITE)
        centered("OIL P  ${"%.1f".format(sample.oilPressureBar)} bar", cx, cy + 45f * scale, 13f * scale, 0xddffffff.toInt())
    }

    private fun drawDialNeedle(
        cx: Float,
        cy: Float,
        radius: Float,
        start: Float,
        sweep: Float,
        progress: Float,
        metric: TelemetryMetric,
        accent: Int,
        scale: Float
    ) {
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        for (index in 0..24) {
            val angle = Math.toRadians((start + sweep * index / 24f).toDouble())
            val length = (if (index % 4 == 0) 12f else 7f) * scale
            paint.strokeWidth = (if (index % 4 == 0) 2.6f else 1.4f) * scale
            paint.color = if (index % 4 == 0) 0xeeffffff.toInt() else 0x66ffffff
            canvas.drawLine(
                cx + cos(angle).toFloat() * (radius - length),
                cy + sin(angle).toFloat() * (radius - length),
                cx + cos(angle).toFloat() * radius,
                cy + sin(angle).toFloat() * radius,
                paint
            )
        }
        val range = definition.range(metric)
        for (index in 0..6) {
            val angle = Math.toRadians((start + sweep * index / 6f).toDouble())
            val labelRadius = radius * .68f
            val labelValue = range.start + (range.endInclusive - range.start) * index / 6.0
            centered(
                scaleLabel(labelValue, metric),
                cx + cos(angle).toFloat() * labelRadius,
                cy + sin(angle).toFloat() * labelRadius + 3f * scale,
                9f * scale,
                0xbbffffff.toInt()
            )
        }
        val needle = Math.toRadians((start + sweep * progress).toDouble())
        paint.color = accent
        paint.strokeWidth = 3.5f * scale
        canvas.drawLine(cx, cy, cx + cos(needle).toFloat() * radius * .72f, cy + sin(needle).toFloat() * radius * .72f, paint)
        paint.style = Paint.Style.FILL
        paint.color = Color.WHITE
        canvas.drawCircle(cx, cy, 5f * scale, paint)
    }

    private fun progress(metric: TelemetryMetric, value: Double): Float {
        val range = definition.range(metric)
        return ((value - range.start) / (range.endInclusive - range.start).coerceAtLeast(.0001)).coerceIn(0.0, 1.0).toFloat()
    }

    private fun scaleLabel(value: Double, metric: TelemetryMetric): String = when (metric) {
        TelemetryMetric.RPM -> "${(value / 1_000).toInt()}k"
        TelemetryMetric.BOOST -> "%.1f".format(value)
        else -> value.toInt().toString()
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
