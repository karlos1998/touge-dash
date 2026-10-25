package it.letscode.tougedash.video

import kotlin.math.max
import kotlin.math.min

/** Same 390 × 220 reference canvas and widget footprints as the iOS exporter. */
data class VideoOverlayBounds(val left: Float, val top: Float, val width: Float, val height: Float) {
    val centerX get() = left + width / 2
    val centerY get() = top + height / 2
}

fun VideoOverlayElement.bounds(width: Int, height: Int): VideoOverlayBounds {
    val base = max(.48f, min(width / 390f, height / 220f)) * effectiveScale
    val (w, h) = referenceSize()
    val safeWidth = min(w * base, width * .94f)
    val safeHeight = min(h * base, height * .94f)
    val position = position(height > width)
    val cx = (position.x * width).coerceIn(safeWidth / 2, width - safeWidth / 2)
    val cy = (position.y * height).coerceIn(safeHeight / 2, height - safeHeight / 2)
    return VideoOverlayBounds(cx - safeWidth / 2, cy - safeHeight / 2, safeWidth, safeHeight)
}

internal fun VideoOverlayElement.referenceSize(): Pair<Float, Float> = when (kind) {
    OverlayElementKind.DIGITAL -> 94f to 56f
    OverlayElementKind.TELEMETRY_TIMESTAMP -> 184f to 50f
    OverlayElementKind.GAUGE -> 112f to 112f
    OverlayElementKind.BAR -> 190f to 48f
    OverlayElementKind.SPEED_CLUSTER -> 126f to 126f
    OverlayElementKind.OIL_CLUSTER -> 116f to 116f
    OverlayElementKind.NEON_TACH -> 184f to 150f
    OverlayElementKind.STREET_SHIFT_TACH -> 190f to 150f
    OverlayElementKind.BLACKLIST_TACH, OverlayElementKind.CARBON_TACH -> 150f to 150f
    OverlayElementKind.ROUTE_MAP, OverlayElementKind.ROUTE_MAP_LIGHT, OverlayElementKind.ROUTE_MAP_AMBER -> 214f to 136f
    OverlayElementKind.ROUTE_MAP_CIRCULAR, OverlayElementKind.ROUTE_MAP_FOLLOW, OverlayElementKind.ROUTE_MAP_LIGHT_CIRCULAR -> 154f to 154f
}
