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
    private val routeMap: RouteMapSnapshot? = null
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
        definition.resolvedElements().forEach { drawElement(sample, target, it) }
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

    private fun drawElement(sample: TelemetrySampleEntity, targetTime: Long, element: VideoOverlayElement) {
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
            canvas.drawBitmap(mapBitmap, null, mapContentRect, paint)
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
        centered("%.1f".format(sample.boostBar), podCx, podCy + 9f * scale, 15f * scale, Color.WHITE)
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
        centered("%.1f bar".format(sample.boostBar), cx - 76f * scale, cy + 80f * scale, 11f * scale, Color.WHITE)
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
