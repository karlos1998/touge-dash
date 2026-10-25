package it.letscode.tougedash.history

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class DriveSegmentLength(val minutes: Int) { FIFTEEN_MINUTES(15), THIRTY_MINUTES(30), ONE_HOUR(60) }

class DriveSegmentSettings(context: Context) {
    private val preferences = context.getSharedPreferences("drive-segments", Context.MODE_PRIVATE)
    private val mutableLength = MutableStateFlow(DriveSegmentLength.entries.firstOrNull { it.minutes == preferences.getInt("minutes", 30) } ?: DriveSegmentLength.THIRTY_MINUTES)
    val length = mutableLength.asStateFlow()
    fun update(length: DriveSegmentLength) {
        mutableLength.value = length
        preferences.edit().putInt("minutes", length.minutes).apply()
    }
    fun shouldSplit(startedAt: Long, now: Long) = now - startedAt >= mutableLength.value.minutes * 60_000L
}
