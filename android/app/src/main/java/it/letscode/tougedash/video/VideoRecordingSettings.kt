package it.letscode.tougedash.video

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class DriveVideoQuality { STORAGE_SAVER, FULL_HD, ULTRA_HD }

data class DriveVideoSettings(
    val automaticRecording: Boolean = false,
    val frontCamera: Boolean = false,
    val recordAudio: Boolean = true,
    val quality: DriveVideoQuality = DriveVideoQuality.FULL_HD
)

class VideoRecordingSettings(context: Context) {
    private val preferences = context.getSharedPreferences("drive-video-settings", Context.MODE_PRIVATE)
    private val mutableSettings = MutableStateFlow(load())
    val settings = mutableSettings.asStateFlow()

    val warningAccepted: Boolean get() = preferences.getBoolean(KEY_WARNING, false)

    fun acceptWarning() {
        preferences.edit().putBoolean(KEY_WARNING, true).apply()
    }

    fun update(value: DriveVideoSettings) {
        mutableSettings.value = value
        preferences.edit()
            .putBoolean(KEY_ENABLED, value.automaticRecording)
            .putBoolean(KEY_FRONT, value.frontCamera)
            .putBoolean(KEY_AUDIO, value.recordAudio)
            .putString(KEY_QUALITY, value.quality.name)
            .apply()
    }

    private fun load() = DriveVideoSettings(
        automaticRecording = preferences.getBoolean(KEY_ENABLED, false),
        frontCamera = preferences.getBoolean(KEY_FRONT, false),
        recordAudio = preferences.getBoolean(KEY_AUDIO, true),
        quality = preferences.getString(KEY_QUALITY, null)?.let { runCatching { DriveVideoQuality.valueOf(it) }.getOrNull() }
            ?: DriveVideoQuality.FULL_HD
    )

    private companion object {
        const val KEY_ENABLED = "automatic"
        const val KEY_FRONT = "front"
        const val KEY_AUDIO = "audio"
        const val KEY_QUALITY = "quality"
        const val KEY_WARNING = "experimental-warning-v1"
    }
}
