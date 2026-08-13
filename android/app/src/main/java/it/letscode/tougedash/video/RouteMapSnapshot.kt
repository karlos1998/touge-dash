package it.letscode.tougedash.video

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Point
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.drawing.MapSnapshot
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

data class RouteMapPoint(val recordedAt: Long, val x: Float, val y: Float)

data class RouteMapPose(
    val x: Float,
    val y: Float,
    val headingDegrees: Float,
    val passedPointCount: Int
)

class RouteMapSnapshot(
    val bitmap: Bitmap,
    sourcePoints: List<RouteMapPoint>,
    val detailedBitmap: Bitmap? = null,
    sourceDetailedPoints: List<RouteMapPoint> = emptyList()
) {
    val points: List<RouteMapPoint> = compacted(sourcePoints)
    val detailedPoints: List<RouteMapPoint> = compacted(sourceDetailedPoints)

    fun usesDetailedLayer(mapZoom: Float): Boolean =
        mapZoom > 1.85f && detailedBitmap != null && detailedPoints.isNotEmpty()

    fun bitmapFor(mapZoom: Float): Bitmap =
        if (usesDetailedLayer(mapZoom)) detailedBitmap!! else bitmap

    fun pointsFor(mapZoom: Float): List<RouteMapPoint> =
        if (usesDetailedLayer(mapZoom)) detailedPoints else points

    fun poseAt(recordedAt: Long, mapZoom: Float = 1f): RouteMapPose? {
        val selectedPoints = pointsFor(mapZoom)
        if (selectedPoints.isEmpty()) return null
        val motion = interpolatedMotion(recordedAt, selectedPoints)
        var dx = motion.vx
        var dy = motion.vy
        if (kotlin.math.hypot(dx, dy) < .000001f) {
            val before = interpolatedMotion(recordedAt - 1_500, selectedPoints)
            val after = interpolatedMotion(recordedAt + 1_500, selectedPoints)
            dx = after.x - before.x
            dy = after.y - before.y
        }
        val heading = if (kotlin.math.hypot(dx, dy) >= .000001f) {
            Math.toDegrees(kotlin.math.atan2(dy.toDouble(), dx.toDouble())).toFloat()
        } else -90f
        val passed = selectedPoints.indexOfFirst { it.recordedAt > recordedAt }
            .let { if (it < 0) selectedPoints.size else it }
        return RouteMapPose(motion.x, motion.y, heading, passed.coerceIn(1, selectedPoints.size))
    }

    private data class Motion(val x: Float, val y: Float, val vx: Float, val vy: Float)

    /** Keeps camera position and velocity continuous between asynchronous GPS updates. */
    private fun interpolatedMotion(recordedAt: Long, points: List<RouteMapPoint>): Motion {
        if (points.size == 1) return Motion(points[0].x, points[0].y, 0f, 0f)
        val found = points.binarySearchBy(recordedAt) { it.recordedAt }
        val upper = if (found >= 0) found else -found - 1
        if (upper <= 0) {
            val velocity = velocityAt(0, points)
            return Motion(points.first().x, points.first().y, velocity.first, velocity.second)
        }
        if (upper >= points.size) {
            val velocity = velocityAt(points.lastIndex, points)
            return Motion(points.last().x, points.last().y, velocity.first, velocity.second)
        }
        val startIndex = upper - 1
        val start = points[startIndex]
        val end = points[upper]
        val durationSeconds = (end.recordedAt - start.recordedAt) / 1_000f
        if (durationSeconds <= 0f) {
            val velocity = velocityAt(upper, points)
            return Motion(end.x, end.y, velocity.first, velocity.second)
        }
        val fraction = ((recordedAt - start.recordedAt) / (durationSeconds * 1_000f)).coerceIn(0f, 1f)
        val fraction2 = fraction * fraction
        val fraction3 = fraction2 * fraction
        val segmentX = end.x - start.x
        val segmentY = end.y - start.y
        val startVelocity = limitedTangent(velocityAt(startIndex, points), segmentX, segmentY, durationSeconds)
        val endVelocity = limitedTangent(velocityAt(upper, points), segmentX, segmentY, durationSeconds)
        val m0x = startVelocity.first * durationSeconds
        val m0y = startVelocity.second * durationSeconds
        val m1x = endVelocity.first * durationSeconds
        val m1y = endVelocity.second * durationSeconds
        val h00 = 2 * fraction3 - 3 * fraction2 + 1
        val h10 = fraction3 - 2 * fraction2 + fraction
        val h01 = -2 * fraction3 + 3 * fraction2
        val h11 = fraction3 - fraction2
        val x = h00 * start.x + h10 * m0x + h01 * end.x + h11 * m1x
        val y = h00 * start.y + h10 * m0y + h01 * end.y + h11 * m1y
        val dh00 = 6 * fraction2 - 6 * fraction
        val dh10 = 3 * fraction2 - 4 * fraction + 1
        val dh01 = -6 * fraction2 + 6 * fraction
        val dh11 = 3 * fraction2 - 2 * fraction
        val vx = (dh00 * start.x + dh10 * m0x + dh01 * end.x + dh11 * m1x) / durationSeconds
        val vy = (dh00 * start.y + dh10 * m0y + dh01 * end.y + dh11 * m1y) / durationSeconds
        return Motion(x, y, vx, vy)
    }

    private fun velocityAt(index: Int, points: List<RouteMapPoint>): Pair<Float, Float> {
        val before = points[(index - 1).coerceAtLeast(0)]
        val after = points[(index + 1).coerceAtMost(points.lastIndex)]
        val durationSeconds = (after.recordedAt - before.recordedAt) / 1_000f
        if (durationSeconds <= 0f) return 0f to 0f
        return (after.x - before.x) / durationSeconds to (after.y - before.y) / durationSeconds
    }

    private fun limitedTangent(
        velocity: Pair<Float, Float>,
        segmentX: Float,
        segmentY: Float,
        durationSeconds: Float
    ): Pair<Float, Float> {
        val segmentLength = kotlin.math.hypot(segmentX, segmentY)
        if (segmentLength <= .0000001f || durationSeconds <= 0f) return 0f to 0f
        if (velocity.first * segmentX + velocity.second * segmentY <= 0f) return 0f to 0f
        val maximum = 2f * segmentLength / durationSeconds
        val speed = kotlin.math.hypot(velocity.first, velocity.second)
        if (speed <= maximum) return velocity
        val ratio = maximum / speed
        return velocity.first * ratio to velocity.second * ratio
    }

    private companion object {
        fun compacted(source: List<RouteMapPoint>): List<RouteMapPoint> = buildList(source.size) {
            source.forEach { point ->
                val previous = lastOrNull()
                if (previous == null) {
                    add(point)
                } else if (point.recordedAt > previous.recordedAt &&
                    kotlin.math.hypot(point.x - previous.x, point.y - previous.y) > .000001f
                ) {
                    // Location updates are copied into faster telemetry samples; keep one copy only.
                    add(point)
                }
            }
        }
    }
}

suspend fun createRouteMapSnapshot(
    context: Context,
    samples: List<TelemetrySampleEntity>,
    includesDetailedLayer: Boolean = false
): RouteMapSnapshot? = withContext(Dispatchers.Main) {
    val located = samples.mapNotNull { sample ->
        val latitude = sample.latitude
        val longitude = sample.longitude
        if (latitude == null || longitude == null || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) null
        else sample to GeoPoint(latitude, longitude)
    }
    if (located.isEmpty()) return@withContext null

    val overview = withTimeoutOrNull(8_000) { captureRouteMapLayer(context, located, detailed = false) }
        ?: return@withContext fallbackRouteMapSnapshot(located)
    val detailed = if (includesDetailedLayer) {
        withTimeoutOrNull(8_000) { captureRouteMapLayer(context, located, detailed = true) }
    } else null
    RouteMapSnapshot(
        bitmap = overview.bitmap,
        sourcePoints = overview.points,
        detailedBitmap = detailed?.bitmap,
        sourceDetailedPoints = detailed?.points.orEmpty()
    )
}

private data class CapturedRouteMapLayer(
    val bitmap: Bitmap,
    val points: List<RouteMapPoint>
)

private suspend fun captureRouteMapLayer(
    context: Context,
    located: List<Pair<TelemetrySampleEntity, GeoPoint>>,
    detailed: Boolean
): CapturedRouteMapLayer? = suspendCancellableCoroutine { continuation ->
    Configuration.getInstance().userAgentValue = context.packageName
    // Both levels are oversampled. The detailed level uses one finer map-tile zoom.
    val width = 1600
    val height = 1017
    val map = MapView(context).apply {
        setTileSource(TileSourceFactory.MAPNIK)
        setMultiTouchControls(false)
        measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY)
        )
        layout(0, 0, width, height)
    }
    val geoPoints = located.map { it.second }
    if (geoPoints.size > 1) {
        map.zoomToBoundingBox(BoundingBox.fromGeoPointsSafe(geoPoints), false, 42)
        val paddingZoom = if (detailed) .6 else 1.6
        map.controller.setZoom((map.zoomLevelDouble - paddingZoom).coerceAtLeast(map.minZoomLevel))
    } else {
        map.controller.setCenter(geoPoints.first())
        map.controller.setZoom(if (detailed) 18.0 else 17.0)
    }
    map.post {
        val projected = located.map { (sample, geoPoint) ->
            val pixel = map.projection.toPixels(geoPoint, Point())
            RouteMapPoint(
                recordedAt = sample.recordedAt,
                x = (pixel.x / width.toFloat()).coerceIn(0f, 1f),
                y = (pixel.y / height.toFloat()).coerceIn(0f, 1f)
            )
        }
        var activeSnapshot: MapSnapshot? = null
        var detached = false
        fun detach() {
            if (detached) return
            detached = true
            activeSnapshot?.onDetach()
            map.onDetach()
        }
        val mapSnapshot = MapSnapshot({ result ->
            if (continuation.isActive) {
                val bitmap = result.bitmap?.copy(Bitmap.Config.ARGB_8888, false)
                continuation.resume(bitmap?.let { CapturedRouteMapLayer(it, projected) })
            }
            detach()
        }, MapSnapshot.INCLUDE_FLAGS_ALL, map)
        activeSnapshot = mapSnapshot
        continuation.invokeOnCancellation { detach() }
        mapSnapshot.run()
    }
}

private fun fallbackRouteMapSnapshot(
    located: List<Pair<TelemetrySampleEntity, GeoPoint>>
): RouteMapSnapshot {
    val width = 1600
    val height = 1017
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(Color.rgb(5, 16, 21))
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(28, 0, 210, 255)
        strokeWidth = 1f
    }
    for (x in 0..width step 54) canvas.drawLine(x.toFloat(), 0f, x.toFloat(), height.toFloat(), paint)
    for (y in 0..height step 54) canvas.drawLine(0f, y.toFloat(), width.toFloat(), y.toFloat(), paint)
    val minimumLatitude = located.minOf { it.second.latitude }
    val maximumLatitude = located.maxOf { it.second.latitude }
    val minimumLongitude = located.minOf { it.second.longitude }
    val maximumLongitude = located.maxOf { it.second.longitude }
    val latitudeSpan = (maximumLatitude - minimumLatitude).coerceAtLeast(.000001)
    val longitudeSpan = (maximumLongitude - minimumLongitude).coerceAtLeast(.000001)
    val points = located.map { (sample, point) ->
        RouteMapPoint(
            recordedAt = sample.recordedAt,
            x = (.1 + .8 * (point.longitude - minimumLongitude) / longitudeSpan).toFloat(),
            y = (.9 - .8 * (point.latitude - minimumLatitude) / latitudeSpan).toFloat()
        )
    }
    return RouteMapSnapshot(bitmap, points)
}
