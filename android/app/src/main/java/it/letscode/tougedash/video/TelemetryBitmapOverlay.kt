@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.video

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
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
    height: Int,
    private val routeMap: RouteMapSnapshot? = null,
    private val telemetryOriginMillis: Long = samples.firstOrNull()?.recordedAt ?: 0L,
    private val maximumFramesPerSecond: Int = 30,
    private val timestampLabel: String = "TELEMETRY TIME",
    private val locale: java.util.Locale = java.util.Locale.getDefault(),
    maximumBitmapLongEdge: Int = 3840
) : BitmapOverlay() {
    private val bitmapSize = overlayBitmapSize(width, height, maximumBitmapLongEdge)
    private var outputWidth = width.takeIf { it > 0 } ?: 1920
    private var outputHeight = height.takeIf { it > 0 } ?: 1080
    private val bitmapWidth = bitmapSize.first
    private val bitmapHeight = bitmapSize.second
    private val bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = if (android.os.Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.create("sans-serif", Typeface.NORMAL), 900, false) else Typeface.create("sans-serif", Typeface.BOLD) }
    private val elements = definition.resolvedElements()
    private var lastBucket = Long.MIN_VALUE
    private var panelAccent = Color.CYAN
    private val timestampFormatter = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val bucket = presentationTimeUs * maximumFramesPerSecond / 1_000_000
        if (bucket == lastBucket) return bitmap
        lastBucket = bucket
        bitmap.eraseColor(Color.TRANSPARENT)
        val target = telemetryOriginMillis + ((telemetryStartSeconds + presentationTimeUs / 1_000_000.0) * 1000).toLong()
        val sample = nearestSample(target) ?: return bitmap
        elements.forEach { drawElement(sample, target, it) }
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

    override fun configure(videoSize: androidx.media3.common.util.Size) {
        outputWidth = videoSize.width
        outputHeight = videoSize.height
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = OverlaySettings.Builder()
        .setBackgroundFrameAnchor(0f, 0f)
        .setOverlayFrameAnchor(0f, 0f)
        .setScale(outputWidth.toFloat() / bitmapWidth, outputHeight.toFloat() / bitmapHeight)
        .build()

    companion object {
        private val DARK_MAP_FILTER = android.graphics.ColorMatrixColorFilter(floatArrayOf(
            -.22f, -.22f, -.22f, 0f, 175f,
            -.20f, -.20f, -.20f, 0f, 164f,
            -.18f, -.18f, -.18f, 0f, 155f,
            0f, 0f, 0f, 1f, 0f
        ))
    }

    private fun drawElement(sample: TelemetrySampleEntity, targetTime: Long, element: VideoOverlayElement) {
        val bounds = element.bounds(bitmapWidth, bitmapHeight)
        val nativeSize = when (element.kind) {
            OverlayElementKind.DIGITAL -> 94f to 56f
            OverlayElementKind.TELEMETRY_TIMESTAMP -> 460f to 125f
            OverlayElementKind.GAUGE -> 112f to 112f
            OverlayElementKind.BAR -> 190f to 48f
            OverlayElementKind.SPEED_CLUSTER -> 210f to 210f
            OverlayElementKind.OIL_CLUSTER -> 192f to 192f
            OverlayElementKind.NEON_TACH -> 296f to 240f
            OverlayElementKind.STREET_SHIFT_TACH -> 304f to 240f
            OverlayElementKind.BLACKLIST_TACH, OverlayElementKind.CARBON_TACH -> 236f to 236f
            else -> if (element.kind.isCircularRouteMap) 385f to 385f else 535f to 340f
        }
        panelAccent = element.accent.colorInt()
        canvas.save()
        canvas.translate(bounds.centerX, bounds.centerY)
        canvas.scale(bounds.width / nativeSize.first, bounds.height / nativeSize.second)
        val cx = 0f
        val cy = 0f
        val scale = 1f
        when (element.kind) {
            OverlayElementKind.DIGITAL -> drawDigital(sample, element, cx, cy, scale)
            OverlayElementKind.TELEMETRY_TIMESTAMP -> drawTimestamp(targetTime, element, cx, cy, scale)
            OverlayElementKind.GAUGE -> drawGauge(sample, element, cx, cy, scale)
            OverlayElementKind.BAR -> drawBar(sample, element, cx, cy, scale)
            OverlayElementKind.SPEED_CLUSTER -> drawSpeedCluster(sample, element, cx, cy, scale)
            OverlayElementKind.OIL_CLUSTER -> drawOilCluster(sample, element, cx, cy, scale)
            OverlayElementKind.NEON_TACH -> drawNeonTach(sample, element, cx, cy, scale)
            OverlayElementKind.BLACKLIST_TACH -> drawBlacklistTach(sample, element, cx, cy, scale)
            OverlayElementKind.CARBON_TACH -> drawCarbonTach(sample, element, cx, cy, scale)
            OverlayElementKind.STREET_SHIFT_TACH -> drawStreetShiftTach(sample, element, cx, cy, scale)
            OverlayElementKind.ROUTE_MAP,
            OverlayElementKind.ROUTE_MAP_CIRCULAR,
            OverlayElementKind.ROUTE_MAP_FOLLOW,
            OverlayElementKind.ROUTE_MAP_LIGHT,
            OverlayElementKind.ROUTE_MAP_LIGHT_CIRCULAR,
            OverlayElementKind.ROUTE_MAP_AMBER -> drawRouteMap(targetTime, element, cx, cy, scale)
        }
        canvas.restore()
    }

    private fun drawRouteMap(targetTime: Long, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val circular = element.kind.isCircularRouteMap
        val width = (if (circular) 385f else 535f) * scale
        val height = (if (circular) 385f else 340f) * scale
        val rect = RectF(cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2)
        val radius = if (circular) width / 2 else 28f * scale
        val pose = routeMap?.poseAt(targetTime, element.mapZoom)
        var mapRotation = 0f
        val clippingPath = Path().apply {
            if (circular) addOval(rect, Path.Direction.CW)
            else addRoundRect(rect, radius, radius, Path.Direction.CW)
        }
        fun drawMarker(x: Float, y: Float, angle: Float) {
            canvas.save()
            canvas.rotate(angle, x, y)
            val marker = 18f * scale
            val arrow = Path().apply {
                moveTo(x, y - marker)
                lineTo(x + marker * .68f, y + marker * .78f)
                lineTo(x, y + marker * .46f)
                lineTo(x - marker * .68f, y + marker * .78f)
                close()
            }
            paint.style = Paint.Style.FILL
            paint.color = Color.WHITE
            paint.setShadowLayer(15f * scale, 0f, 0f, element.accent.colorInt())
            canvas.drawPath(arrow, paint)
            paint.clearShadowLayer()
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 4f * scale
            paint.color = element.accent.colorInt()
            canvas.drawPath(arrow, paint)
            canvas.restore()
        }
        canvas.save()
        canvas.clipPath(clippingPath)
        paint.style = Paint.Style.FILL
        paint.color = 0xf0051116.toInt()
        canvas.drawRect(rect, paint)
        var mapContentRect = RectF(rect)
        routeMap?.let { snapshot ->
            paint.alpha = 255
            val mapBitmap = snapshot.bitmapFor(element.mapZoom)
            val adjustedZoom = if (snapshot.usesDetailedLayer(element.mapZoom)) element.mapZoom / 2f else element.mapZoom
            val imageScale = maxOf(rect.width() / mapBitmap.width, rect.height() / mapBitmap.height) * 2.35f * adjustedZoom.coerceIn(.65f, 3.5f)
            val contentWidth = mapBitmap.width * imageScale
            val contentHeight = mapBitmap.height * imageScale
            if (pose != null) {
                mapContentRect = RectF(
                    rect.centerX() - pose.x * contentWidth,
                    rect.centerY() - pose.y * contentHeight,
                    rect.centerX() + (1f - pose.x) * contentWidth,
                    rect.centerY() + (1f - pose.y) * contentHeight
                )
                mapRotation = -90f - pose.headingDegrees
                canvas.save()
                canvas.rotate(mapRotation, rect.centerX(), rect.centerY())
            }
            paint.colorFilter = if (element.kind.usesLightMap || !snapshot.sourceIsLight) null else DARK_MAP_FILTER
            canvas.drawBitmap(mapBitmap, null, mapContentRect, paint)
            paint.colorFilter = null
            if (pose != null) canvas.restore()
        } ?: run {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.5f * scale
            paint.color = element.accent.colorInt() and 0x22ffffff
            val spacing = 48f * scale
            var x = rect.left
            while (x <= rect.right) { canvas.drawLine(x, rect.top, x, rect.bottom, paint); x += spacing }
            var y = rect.top
            while (y <= rect.bottom) { canvas.drawLine(rect.left, y, rect.right, y, paint); y += spacing }
        }
        paint.style = Paint.Style.FILL
        paint.color = when {
            element.kind == OverlayElementKind.ROUTE_MAP_AMBER -> 0x55f28b22
            element.kind.usesLightMap -> 0x10ffffff
            routeMap == null -> 0x22000000
            else -> 0x66000000
        }
        canvas.drawRect(rect, paint)

        routeMap?.takeIf { it.pointsFor(element.mapZoom).isNotEmpty() }?.let { snapshot ->
            fun mapped(point: RouteMapPoint) = android.graphics.PointF(
                mapContentRect.left + point.x * mapContentRect.width(),
                mapContentRect.top + point.y * mapContentRect.height()
            )
            val mappedPoints = snapshot.pointsFor(element.mapZoom).map(::mapped)
            fun stroke(points: List<android.graphics.PointF>, color: Int, strokeWidth: Float) {
                if (points.size < 2) return
                paint.style = Paint.Style.STROKE
                paint.strokeCap = Paint.Cap.ROUND
                paint.strokeJoin = Paint.Join.ROUND
                paint.strokeWidth = strokeWidth
                paint.color = color
                canvas.drawPath(Path().apply {
                    moveTo(points.first().x, points.first().y)
                    points.drop(1).forEach { lineTo(it.x, it.y) }
                }, paint)
            }
            if (pose != null) {
                canvas.save()
                canvas.rotate(mapRotation, rect.centerX(), rect.centerY())
            }
            stroke(mappedPoints, 0xc9000000.toInt(), 14f * scale)
            stroke(mappedPoints, 0x88ffffff.toInt(), 6f * scale)

            pose?.let { currentPose ->
                val travelled = mappedPoints.take(currentPose.passedPointCount).toMutableList().apply {
                    add(android.graphics.PointF(
                        mapContentRect.left + currentPose.x * mapContentRect.width(),
                        mapContentRect.top + currentPose.y * mapContentRect.height()
                    ))
                }
                stroke(travelled, element.accent.colorInt() and 0x66ffffff, 18f * scale)
                stroke(travelled, element.accent.colorInt(), 8f * scale)
            }
            if (pose != null) canvas.restore()
            if (pose != null) drawMarker(rect.centerX(), rect.centerY(), 0f)
        }
        canvas.restore()

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 10f * scale
        paint.color = 0xdd000000.toInt()
        if (circular) canvas.drawOval(rect, paint) else canvas.drawRoundRect(rect, radius, radius, paint)
        paint.strokeWidth = 3f * scale
        paint.color = element.accent.colorInt()
        if (circular) canvas.drawOval(rect, paint) else canvas.drawRoundRect(rect, radius, radius, paint)
        paint.style = Paint.Style.FILL

        if (routeMap == null) centered("NO GPS", rect.centerX(), rect.centerY() + 7f * scale, 21f * scale, 0xffffa03d.toInt())
        centered("© OpenStreetMap", rect.centerX(), rect.bottom - (if (circular) 27f else 12f) * scale, 10f * scale, 0xbbffffff.toInt())
    }

    private fun drawTimestamp(timestamp: Long, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        panel(cx - 230 * scale, cy - 62.5f * scale, cx + 230 * scale, cy + 62.5f * scale, 22f * scale)
        text(timestampLabel, cx - 205 * scale, cy - 28 * scale, 16.25f * scale, element.accent.colorInt())
        text(timestampFormatter.format(java.util.Date(timestamp)), cx - 205 * scale, cy + 25 * scale, 35f * scale, Color.WHITE)
        paint.color = element.accent.colorInt()
        canvas.drawRect(cx - 205 * scale, cy - 62.5f * scale, cx - 110 * scale, cy - 57.5f * scale, paint)
    }

    private fun drawDigital(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val left = cx - 47f
        val top = cy - 28f
        panel(left, top, cx + 47f, cy + 28f, 7f)
        val value = element.metric.sampleValue(sample)
        val formatted = format(element.metric, value)
        text(formatted, left + 9, top + 24, 19f, Color.WHITE)
        paint.textSize = 19f
        val valueWidth = paint.measureText(formatted)
        text(element.metric.unit, left + 13 + valueWidth, top + 24, 7f, element.accent.colorInt())
        text(element.metric.shortName, left + 9, top + 46, 7f, element.accent.colorInt())
        if (definition.style != OverlayStyle.MINIMAL) {
            pill(left + 9, top + 49, left + 85, top + 51.5f, 0x26ffffff)
            pill(left + 9, top + 49, left + 9 + maxOf(2f, 76 * progress(element.metric, value)), top + 51.5f, element.accent.colorInt())
        }
    }

    private fun drawGauge(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        paint.style = Paint.Style.FILL
        paint.color = if (definition.style == OverlayStyle.MINIMAL) 0x47000000 else 0x85000000.toInt()
        canvas.drawCircle(cx, cy, 56f, paint)
        val radius = 48.44f
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 6.048f
        paint.strokeCap = Paint.Cap.ROUND
        val rect = RectF(cx - radius, cy - radius, cx + radius, cy + radius)
        paint.color = 0x24ffffff
        canvas.drawArc(rect, 135f, 270f, false, paint)
        val value = element.metric.sampleValue(sample)
        val progress = progress(element.metric, value)
        paint.color = element.accent.colorInt()
        canvas.drawArc(rect, 135f, 270f * progress, false, paint)
        drawDialNeedle(cx, cy, radius, 135f, 270f, progress, element.metric, element.accent.colorInt(), .48f)
        centered(element.metric.shortName, cx, cy + 16f, 6.5f, element.accent.colorInt())
        val textSize = when (element.metric) { TelemetryMetric.SPEED -> 18f; TelemetryMetric.BOOST -> 16f; else -> 20f }
        centered(format(element.metric, value), cx, cy + 20 + textSize, textSize, Color.WHITE)
        centered(element.metric.unit, cx, cy + 49, 6f, 0xa6ffffff.toInt())
    }

    private fun drawBar(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val left = cx - 95f
        val top = cy - 24f
        panel(left, top, cx + 95f, cy + 24f, 7f)
        val value = element.metric.sampleValue(sample)
        val progress = progress(element.metric, value)
        text(element.metric.shortName, left + 10, top + 14, 7f, element.accent.colorInt())
        val valueText = format(element.metric, value)
        paint.textSize = 6f
        val unitWidth = paint.measureText(element.metric.unit)
        paint.textSize = 14f
        val valueWidth = paint.measureText(valueText)
        text(valueText, left + 180 - valueWidth - unitWidth - 4, top + 17, 14f, Color.WHITE)
        text(element.metric.unit, left + 180 - unitWidth, top + 16, 6f, 0xa6ffffff.toInt())
        val barLeft = left + 10
        val barTop = top + 34
        if (definition.style == OverlayStyle.UNDERGROUND && element.metric == TelemetryMetric.RPM) {
            val width = (170f - 22f) / 12
            repeat(12) { index ->
                val color = when {
                    (index + 1) / 12f > progress -> 0x1fffffff
                    index >= 10 -> DashboardAccent.RED.colorInt()
                    index >= 7 -> DashboardAccent.ORANGE.colorInt()
                    else -> element.accent.colorInt()
                }
                pill(barLeft + index * (width + 2), barTop, barLeft + index * (width + 2) + width, barTop + 6, color)
            }
        } else {
            pill(barLeft, barTop, barLeft + 170, barTop + 6, 0x24ffffff)
            pill(barLeft, barTop, barLeft + maxOf(2f, 170 * progress), barTop + 6, element.accent.colorInt())
        }
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
        centered("BOOST ${"%.1f".format(locale, sample.boostBar)}", cx, cy + 62f * scale, 11f * scale, 0xff43e8a8.toInt())
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
        centered("OIL P  ${"%.1f".format(locale, sample.oilPressureBar)} bar", cx, cy + 45f * scale, 13f * scale, 0xddffffff.toInt())
    }

    private fun drawNeonTach(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val radius = 120f * scale
        val mainCx = cx + 28f * scale
        circlePanel(mainCx, cy, radius, 0xe6040a0f.toInt(), 0xaa18bfff.toInt(), 3f * scale)
        drawStyledTach(mainCx, cy, radius * .84f, 140f, 260f, progress(TelemetryMetric.RPM, sample.rpm), TelemetryMetric.RPM, 0xff18bfff.toInt(), Color.WHITE, scale)
        centered("RPM ×1000", mainCx, cy - 27f * scale, 12f * scale, 0xff79dfff.toInt())
        centered(sample.speedKph.toInt().toString(), mainCx, cy + 28f * scale, 48f * scale, 0xff13bdf5.toInt())
        centered("KM/H", mainCx, cy + 49f * scale, 11f * scale, Color.WHITE)
        val boost = progress(TelemetryMetric.BOOST, sample.boostBar)
        val podCx = cx - 105f * scale
        val podCy = cy + 61f * scale
        val podRadius = 42f * scale
        circlePanel(podCx, podCy, podRadius, 0xf0040a0f.toInt(), 0x8843e8a8.toInt(), 2f * scale)
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = 7f * scale
        paint.color = 0x4427d7e5
        val boostRect = RectF(podCx - podRadius * .72f, podCy - podRadius * .72f, podCx + podRadius * .72f, podCy + podRadius * .72f)
        canvas.drawArc(boostRect, 135f, 270f, false, paint)
        paint.color = 0xff26e76f.toInt()
        canvas.drawArc(boostRect, 135f, 270f * boost, false, paint)
        paint.style = Paint.Style.FILL
        centered("BOOST", podCx, podCy - 9f * scale, 8f * scale, 0xff7ef5a5.toInt())
        centered("%.1f".format(locale, sample.boostBar), podCx, podCy + 9f * scale, 15f * scale, Color.WHITE)
        centered("BAR", podCx, podCy + 21f * scale, 6f * scale, 0xbbffffff.toInt())
    }

    private fun drawBlacklistTach(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val radius = 118f * scale
        circlePanel(cx, cy, radius, 0xe70a0b0d.toInt(), 0x889aa3aa.toInt(), 2f * scale)
        drawStyledTach(cx, cy, radius * .86f, 145f, 250f, progress(TelemetryMetric.RPM, sample.rpm), TelemetryMetric.RPM, 0xffd62e2e.toInt(), 0xfff4f4f1.toInt(), scale, redline = true)
        centered("RPM ×1000", cx, cy - 29f * scale, 11f * scale, 0xffd9d9d4.toInt())
        val speedWidth = 94f * scale
        val speedTop = cy + 20f * scale
        pill(cx - speedWidth / 2, speedTop, cx + speedWidth / 2, speedTop + 35f * scale, 0xff178ccc.toInt())
        centered(sample.speedKph.toInt().toString(), cx, speedTop + 26f * scale, 27f * scale, Color.WHITE)
        centered("KM/H", cx, speedTop + 48f * scale, 10f * scale, 0xffb8dff5.toInt())
        centered("BOOST", cx - 76f * scale, cy + 64f * scale, 8f * scale, 0xffd9d9d4.toInt())
        centered("%.1f bar".format(locale, sample.boostBar), cx - 76f * scale, cy + 80f * scale, 11f * scale, Color.WHITE)
    }

    private fun drawCarbonTach(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val radius = 118f * scale
        circlePanel(cx, cy, radius, 0xe616130d.toInt(), 0xffd9a342.toInt(), 2f * scale)
        canvas.save()
        canvas.clipPath(Path().apply { addCircle(cx, cy, radius - 3f * scale, Path.Direction.CW) })
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f * scale
        for (offset in -150..150 step 16) {
            paint.color = if ((offset / 16) % 2 == 0) 0x222b2418 else 0x22100e0a
            canvas.drawLine(cx - radius, cy + offset * scale, cx + offset * scale, cy - radius, paint)
        }
        canvas.restore()
        drawStyledTach(cx, cy, radius * .84f, 145f, 250f, progress(TelemetryMetric.RPM, sample.rpm), TelemetryMetric.RPM, 0xffe4a441.toInt(), 0xffffe2a2.toInt(), scale)
        centered("RPM ×1000", cx, cy - 27f * scale, 11f * scale, 0xffffd58a.toInt())
        val box = RectF(cx - 48f * scale, cy + 15f * scale, cx + 48f * scale, cy + 53f * scale)
        paint.style = Paint.Style.FILL
        paint.color = 0xffd7a353.toInt()
        canvas.drawRoundRect(box, 7f * scale, 7f * scale, paint)
        centered(sample.speedKph.toInt().toString(), cx, cy + 43f * scale, 29f * scale, 0xff20170c.toInt())
        centered("KM/H", cx, cy + 68f * scale, 11f * scale, Color.WHITE)
        centered("OIL  ${sample.oilTemperatureCelsius.toInt()}°C", cx, cy + 86f * scale, 10f * scale, 0xffffcf77.toInt())
    }

    private fun drawStreetShiftTach(sample: TelemetrySampleEntity, element: VideoOverlayElement, cx: Float, cy: Float, scale: Float) {
        val radius = 120f * scale
        val mainCx = cx - 32f * scale
        circlePanel(mainCx, cy, radius, 0xd9080a08.toInt(), 0xfff2a04b.toInt(), 4f * scale)
        drawStyledTach(mainCx, cy, radius * .82f, 145f, 250f, progress(TelemetryMetric.RPM, sample.rpm), TelemetryMetric.RPM, 0xfff0a04b.toInt(), Color.WHITE, scale, redline = true)
        val throttle = progress(TelemetryMetric.THROTTLE, sample.throttlePercent)
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.BUTT
        paint.strokeWidth = 10f * scale
        val outer = RectF(mainCx - radius * .93f, cy - radius * .93f, mainCx + radius * .93f, cy + radius * .93f)
        paint.color = 0x334bd320
        canvas.drawArc(outer, 35f, 110f, false, paint)
        paint.color = 0xff91ec37.toInt()
        canvas.drawArc(outer, 35f, 110f * throttle, false, paint)
        paint.style = Paint.Style.FILL
        centered("RPM ×1000", mainCx, cy - 29f * scale, 11f * scale, 0xffffcb91.toInt())
        val sideCx = cx + 103f * scale
        centered("GEAR", sideCx, cy - 51f * scale, 8f * scale, 0xffffc27d.toInt())
        val gearRect = RectF(sideCx - 31f * scale, cy - 43f * scale, sideCx + 31f * scale, cy - 5f * scale)
        paint.color = 0xffe7a85e.toInt()
        canvas.drawRoundRect(gearRect, 6f * scale, 6f * scale, paint)
        centered("–", sideCx, cy - 14f * scale, 27f * scale, 0xff24170a.toInt())
        val speedRect = RectF(sideCx - 38f * scale, cy + 19f * scale, sideCx + 38f * scale, cy + 60f * scale)
        paint.color = 0xffe7a85e.toInt()
        canvas.drawRoundRect(speedRect, 6f * scale, 6f * scale, paint)
        centered(sample.speedKph.toInt().toString(), sideCx, cy + 50f * scale, 27f * scale, 0xff24170a.toInt())
        centered("KM/H", sideCx, cy + 74f * scale, 9f * scale, Color.WHITE)
        centered("THROTTLE ${sample.throttlePercent.toInt()}%", mainCx, cy + 82f * scale, 10f * scale, 0xff9bea4a.toInt())
    }

    private fun circlePanel(cx: Float, cy: Float, radius: Float, fill: Int, stroke: Int, strokeWidth: Float) {
        paint.style = Paint.Style.FILL
        paint.color = fill
        canvas.drawCircle(cx, cy, radius, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = strokeWidth
        paint.color = stroke
        canvas.drawCircle(cx, cy, radius - strokeWidth / 2, paint)
        paint.style = Paint.Style.FILL
    }

    private fun drawStyledTach(
        cx: Float,
        cy: Float,
        radius: Float,
        start: Float,
        sweep: Float,
        progress: Float,
        metric: TelemetryMetric,
        needleColor: Int,
        tickColor: Int,
        scale: Float,
        redline: Boolean = false
    ) {
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.SQUARE
        for (index in 0..40) {
            val fraction = index / 40f
            val angle = Math.toRadians((start + sweep * fraction).toDouble())
            val major = index % 4 == 0
            val length = (if (major) 14f else 7f) * scale
            paint.strokeWidth = (if (major) 3.2f else 1.5f) * scale
            paint.color = if (redline && fraction > .78f) 0xffdf3030.toInt() else if (major) tickColor else (tickColor and 0x00ffffff) or 0x66000000
            canvas.drawLine(
                cx + cos(angle).toFloat() * (radius - length),
                cy + sin(angle).toFloat() * (radius - length),
                cx + cos(angle).toFloat() * radius,
                cy + sin(angle).toFloat() * radius,
                paint
            )
        }
        val range = definition.range(metric)
        val divisions = if (metric == TelemetryMetric.RPM) (range.endInclusive / 1_000).toInt().coerceIn(4, 12) else 10
        for (index in 0..divisions) {
            val angle = Math.toRadians((start + sweep * index / divisions.toFloat()).toDouble())
            val value = range.start + (range.endInclusive - range.start) * index / divisions.toDouble()
            centered(scaleLabel(value, metric), cx + cos(angle).toFloat() * radius * .72f, cy + sin(angle).toFloat() * radius * .72f + 4f * scale, 10f * scale, tickColor)
        }
        val needle = Math.toRadians((start + sweep * progress).toDouble())
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = 4f * scale
        paint.color = needleColor
        canvas.drawLine(cx - cos(needle).toFloat() * radius * .13f, cy - sin(needle).toFloat() * radius * .13f, cx + cos(needle).toFloat() * radius * .72f, cy + sin(needle).toFloat() * radius * .72f, paint)
        paint.style = Paint.Style.FILL
        paint.color = 0xff151719.toInt()
        canvas.drawCircle(cx, cy, 8f * scale, paint)
        paint.color = tickColor
        canvas.drawCircle(cx, cy, 3f * scale, paint)
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
        TelemetryMetric.BOOST -> "%.1f".format(locale, value)
        else -> value.toInt().toString()
    }

    private fun panel(left: Float, top: Float, right: Float, bottom: Float, radius: Float) {
        paint.style = Paint.Style.FILL
        paint.color = if (definition.style == OverlayStyle.MINIMAL) 0x6b000000 else 0xad000000.toInt()
        canvas.drawRoundRect(left, top, right, bottom, radius, radius, paint)
        if (definition.style == OverlayStyle.UNDERGROUND) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.2f
            paint.color = (panelAccent and 0xffffff) or 0xbf000000.toInt()
            canvas.drawRoundRect(left, top, right, bottom, radius, radius, paint)
            paint.style = Paint.Style.FILL
        } else if (definition.style == OverlayStyle.RACE) {
            paint.color = panelAccent
            canvas.drawRect(left + 9f, top, left + 9f + minOf((right - left) * .34f, 34f), top + 2f, paint)
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
        1 -> "%.1f".format(locale, value)
        else -> "%.2f".format(locale, value)
    }

    private fun DashboardAccent.colorInt(): Int = when (this) {
        DashboardAccent.CYAN -> 0xff0de0f0.toInt()
        DashboardAccent.MINT -> 0xff36e89e.toInt()
        DashboardAccent.BLUE -> 0xff297aff.toInt()
        DashboardAccent.ICE -> 0xff61bfff.toInt()
        DashboardAccent.ORANGE -> 0xffff7830.toInt()
        DashboardAccent.YELLOW -> 0xffffc430.toInt()
        DashboardAccent.RED -> 0xffff3840.toInt()
        DashboardAccent.WHITE -> Color.WHITE
    }

    private fun TelemetryMetric.sampleValue(value: TelemetrySampleEntity): Double = when (this) {
        TelemetryMetric.RPM -> value.rpm
        TelemetryMetric.BOOST -> value.boostBar
        TelemetryMetric.MAP -> value.mapKpa
        TelemetryMetric.THROTTLE -> value.throttlePercent
        TelemetryMetric.COOLANT -> value.coolantCelsius
        TelemetryMetric.INTAKE -> value.intakeCelsius
        TelemetryMetric.EGT1 -> value.egt1Celsius
        TelemetryMetric.EGT2 -> value.egt2Celsius
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
