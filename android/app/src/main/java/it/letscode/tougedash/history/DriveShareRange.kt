package it.letscode.tougedash.history

data class DriveShareRange(val startOffsetMillis: Long, val endOffsetMillis: Long) {
    val durationMillis: Long get() = endOffsetMillis - startOffsetMillis

    companion object {
        fun normalize(driveDurationMillis: Long, startOffsetMillis: Long, endOffsetMillis: Long): DriveShareRange {
            val duration = driveDurationMillis.coerceAtLeast(1)
            val start = startOffsetMillis.coerceIn(0, duration - 1)
            val end = endOffsetMillis.coerceIn(start + 1, duration)
            return DriveShareRange(start, end)
        }
    }
}
