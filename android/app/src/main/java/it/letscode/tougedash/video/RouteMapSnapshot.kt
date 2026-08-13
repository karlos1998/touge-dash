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

data class RouteMapSnapshot(
    val bitmap: Bitmap,
    val points: List<RouteMapPoint>
) {
    fun poseAt(recordedAt: Long): RouteMapPose? {
        if (points.isEmpty()) return null
        val current = interpolatedPosition(recordedAt)
        var before = interpolatedPosition(recordedAt - 1_250)
        var after = interpolatedPosition(recordedAt + 1_250)
        if (kotlin.math.hypot(after.first - before.first, after.second - before.second) < .0005f) {
            before = interpolatedPosition(recordedAt - 3_000)
            after = interpolatedPosition(recordedAt + 3_000)
        }
        val dx = after.first - before.first
        val dy = after.second - before.second
        val heading = if (kotlin.math.hypot(dx, dy) >= .000001f) {
            Math.toDegrees(kotlin.math.atan2(dy.toDouble(), dx.toDouble())).toFloat()
        } else -90f
        val passed = points.indexOfFirst { it.recordedAt > recordedAt }.let { if (it < 0) points.size else it }
        return RouteMapPose(current.first, current.second, heading, passed.coerceIn(1, points.size))
    }

    private fun interpolatedPosition(recordedAt: Long): Pair<Float, Float> {
        if (points.size == 1) return points[0].x to points[0].y
        val found = points.binarySearchBy(recordedAt) { it.recordedAt }
        if (found >= 0) return points[found].x to points[found].y
        val upper = -found - 1
        if (upper <= 0) return points.first().x to points.first().y
        if (upper >= points.size) return points.last().x to points.last().y
        val start = points[upper - 1]
        val end = points[upper]
        val duration = end.recordedAt - start.recordedAt
        if (duration <= 0) return end.x to end.y
        val fraction = ((recordedAt - start.recordedAt).toFloat() / duration).coerceIn(0f, 1f)
        return (start.x + (end.x - start.x) * fraction) to (start.y + (end.y - start.y) * fraction)
    }
}

suspend fun createRouteMapSnapshot(
    context: Context,
    samples: List<TelemetrySampleEntity>
): RouteMapSnapshot? = withContext(Dispatchers.Main) {
    val located = samples.mapNotNull { sample ->
        val latitude = sample.latitude
        val longitude = sample.longitude
        if (latitude == null || longitude == null || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) null
        else sample to GeoPoint(latitude, longitude)
    }
    if (located.isEmpty()) return@withContext null

    val snapshot = withTimeoutOrNull(8_000) {
        suspendCancellableCoroutine { continuation ->
            Configuration.getInstance().userAgentValue = context.packageName
            // Oversampled so map-camera zoom does not scale up the HUD bitmap itself.
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
                map.controller.setZoom((map.zoomLevelDouble - 1.6).coerceAtLeast(map.minZoomLevel))
            } else {
                map.controller.setCenter(geoPoints.first())
                map.controller.setZoom(17.0)
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
                        continuation.resume(bitmap?.let { RouteMapSnapshot(it, projected) })
                    }
                    detach()
                }, MapSnapshot.INCLUDE_FLAGS_ALL, map)
                activeSnapshot = mapSnapshot
                continuation.invokeOnCancellation {
                    detach()
                }
                mapSnapshot.run()
            }
        }
    }
    snapshot ?: fallbackRouteMapSnapshot(located)
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
