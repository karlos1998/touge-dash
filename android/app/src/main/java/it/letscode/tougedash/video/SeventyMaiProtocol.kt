package it.letscode.tougedash.video

import java.net.URLEncoder
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import kotlinx.serialization.json.*

enum class SeventyMaiCameraModel(val title: String, val rearCamera: Boolean = true) {
    M300("70mai M300", false), M500("70mai M500", false), A200("70mai A200"), A400("70mai A400"),
    A500S("70mai A500S / Pro Plus+"), A510("70mai A510"), A800S("70mai A800S"), A810("70mai A810"), S500("70mai S500");
    fun recordingType(rear: Boolean) = if (rearCamera) { if (rear) "8" else "4" } else "0"
}

data class SeventyMaiClip(val path: String, val name: String, val sizeBytes: Long, val startedAt: Long, val durationMillis: Long) {
    val id get() = "$path/$name"
    val endedAt get() = startedAt + durationMillis
}

/** Wire format deliberately matches the native iOS client, including the leading &-. */
object SeventyMaiProtocol {
    const val HOST = "192.168.0.1"
    private const val SECRET = "73VpsAfdety8FDd0"
    fun md5(value: String) = MessageDigest.getInstance("MD5").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
    private fun escape(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")
    private fun query(parameters: List<Pair<String, String>>) = parameters.joinToString("") { (key, value) -> "&-$key=${escape(value)}" }
    fun bindUrl(user: String) = "http://$HOST/cgi-bin/BindByBanya.cgi?" + query(listOf("usr" to user, "signkey" to md5(user + SECRET)))
    fun confirmationUrl(timestamp: String) = "http://$HOST/cgi-bin/UserconfirmByBanya.cgi?" + query(listOf("timestamp" to timestamp, "signkey" to md5(timestamp + SECRET)))
    fun signedUrl(endpoint: String, parameters: List<Pair<String, String>> = emptyList(), timestamp: Long, key: String): String {
        val unsigned = query(parameters + ("timestamp" to timestamp.toString()))
        return "http://$HOST/cgi-bin/$endpoint?$unsigned&-signkey=${md5("$endpoint?$unsigned$key")}"
    }
    fun fileUrl(clip: SeventyMaiClip): String {
        val segments = (clip.path + "/" + clip.name).split('/').filter(String::isNotEmpty)
        require(segments.none { it == "." || it == ".." }) { "Invalid camera file path" }
        return "http://$HOST/" + segments.joinToString("/") { escape(it) }
    }
    fun parseDate(value: String, timezone: TimeZone = TimeZone.getDefault()): Long? {
        for (pattern in listOf("yyyyMMdd-HHmmss", "yyyyMMddHHmmss", "yyyy-MM-dd HH:mm:ss")) {
            val result = runCatching { SimpleDateFormat(pattern, Locale.US).apply { timeZone = timezone; isLenient = false }.parse(value)?.time }.getOrNull()
            if (result != null) return result
        }
        return null
    }
    fun cameraDate(result: JsonElement, timezone: TimeZone = TimeZone.getDefault()): Long? {
        if (result is JsonPrimitive) return parseDate(result.content, timezone)
        if (result is JsonObject) {
            for (key in listOf("systime", "time", "devts", "Result", "result", "data")) result[key]?.let { cameraDate(it, timezone)?.let { date -> return date } }
        }
        return null
    }
    fun clip(objectValue: JsonObject, clockOffsetMillis: Long?, timezone: TimeZone = TimeZone.getDefault()): SeventyMaiClip? {
        fun string(key: String) = (objectValue[key] as? JsonPrimitive)?.contentOrNull
        val name = string("name")?.takeIf { it.endsWith(".mp4", true) } ?: return null
        val date = string("time")?.let { parseDate(it, timezone) }
            ?: Regex("20\\d{6}-\\d{6}").find(name)?.value?.let { parseDate(it, timezone) } ?: return null
        val duration = string("duration")?.toDoubleOrNull()?.takeIf { it.isFinite() && it > 0 }?.times(10)?.toLong() ?: 60_000L
        return SeventyMaiClip(string("path") ?: "", name, string("size")?.toLongOrNull() ?: 0, date - (clockOffsetMillis ?: 0), duration)
    }
    fun matchingClips(clips: List<SeventyMaiClip>, start: Long, end: Long): List<SeventyMaiClip> {
        val sorted = clips.distinctBy { it.id }.sortedBy { it.startedAt }
        return sorted.mapIndexed { index, clip ->
            val interval = sorted.getOrNull(index + 1)?.startedAt?.minus(clip.startedAt) ?: 0
            if (interval > clip.durationMillis && interval <= 300_000) clip.copy(durationMillis = interval) else clip
        }.filter { it.startedAt < end && it.endedAt > start }
    }
}
