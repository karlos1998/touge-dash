package it.letscode.tougedash.video

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.*
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class SeventyMaiScan(val model: SeventyMaiCameraModel, val rear: Boolean, val key: String, val clockOffsetMillis: Long?, val clips: List<SeventyMaiClip>)

class SeventyMaiCameraException(val resultCode: String) : IOException("70mai: $resultCode")

class SeventyMaiClient(context: Context, private val http: OkHttpClient = wifiClient(context)) {
    private val preferences = context.getSharedPreferences("70mai", 0)
    private val userId = preferences.getString("user", null) ?: UUID.randomUUID().toString().filter(Char::isDigit).take(9).also { preferences.edit().putString("user", it).apply() }
    private val json = Json { ignoreUnknownKeys = true }
    suspend fun scan(model: SeventyMaiCameraModel, rear: Boolean, start: Long, end: Long, progress: (String) -> Unit): SeventyMaiScan {
        progress("AUTHORIZE")
        val bind = result(SeventyMaiProtocol.bindUrl(userId)).jsonObject
        val key = (bind["Token"] ?: bind["token"])?.jsonPrimitive?.content ?: error("70mai: missing token")
        val timestamp = bind["timestamp"]?.jsonPrimitive?.content ?: error("70mai: missing timestamp")
        progress("CONFIRM_ON_CAMERA")
        var confirmed = false
        val deadline = android.os.SystemClock.elapsedRealtime() + 35_000
        while (!confirmed && android.os.SystemClock.elapsedRealtime() < deadline) {
            try { result(SeventyMaiProtocol.confirmationUrl(timestamp)); confirmed = true }
            catch (error: SeventyMaiCameraException) { delay(400) }
        }
        check(confirmed) { "70mai: authorization timed out" }
        progress("READ_CLOCK")
        var best: Pair<Long, Long>? = null
        repeat(3) {
            val sent = System.currentTimeMillis()
            val clock = runCatching { signed("getsystime.cgi", key = key) }.getOrNull()
            val received = System.currentTimeMillis()
            val date = clock?.let { SeventyMaiProtocol.cameraDate(it) }
            if (date != null && (best == null || received - sent < best!!.first)) best = (received - sent) to (date - (sent + (received - sent) / 2))
        }
        if (best == null) {
            val sent = System.currentTimeMillis()
            val clock = runCatching { signed("getAllMenu.cgi", key = key) }.getOrNull()
            val received = System.currentTimeMillis()
            clock?.let { SeventyMaiProtocol.cameraDate(it) }?.let { best = (received - sent) to (it - (sent + (received - sent) / 2)) }
        }
        album(true, key)
        try {
            val clips = mutableListOf<SeventyMaiClip>()
            for (page in 0 until 20) {
                progress("READ_FILES:${page + 1}")
                val raw = signed("getfilelist.cgi", listOf("start" to (page * 100 + 1).toString(), "end" to (page * 100 + 100).toString(), "type" to model.recordingType(rear)), key)
                val rows = when (raw) {
                    JsonNull -> JsonArray(emptyList())
                    is JsonArray -> raw
                    is JsonObject -> listOf("files", "filelist", "list").firstNotNullOfOrNull { raw[it] as? JsonArray } ?: error("70mai: invalid file list")
                    else -> error("70mai: invalid file list")
                }
                clips += rows.mapNotNull { (it as? JsonObject)?.let { row -> SeventyMaiProtocol.clip(row, best?.second) } }
                if (rows.size < 100) break
            }
            val matching = SeventyMaiProtocol.matchingClips(clips, start, end)
            check(matching.isNotEmpty()) { "70mai: no recordings overlap this drive" }
            return SeventyMaiScan(model, rear, key, best?.second, matching)
        } finally { withContext(kotlinx.coroutines.NonCancellable) { runCatching { album(false, key) } } }
    }
    suspend fun album(enabled: Boolean, key: String) { signed("setaccessalbum.cgi", listOf("enable" to if (enabled) "1" else "0"), key) }
    private suspend fun signed(endpoint: String, parameters: List<Pair<String, String>> = emptyList(), key: String) = result(SeventyMaiProtocol.signedUrl(endpoint, parameters, System.currentTimeMillis() / 1000, key))
    private suspend fun result(url: String): JsonElement = withContext(Dispatchers.IO) {
        val raw = request(url).use { response ->
            check(response.isSuccessful) { "70mai: HTTP ${response.code}" }
            val body = requireNotNull(response.body)
            // Camera control responses are small; a corrupt endpoint must not exhaust the app heap.
            val bytes = body.byteStream().use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= 2 * 1024 * 1024) { "70mai: oversized response" }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            json.parseToJsonElement(bytes.decodeToString()).jsonObject
        }
        val code = raw["ResultCode"]?.jsonPrimitive?.content ?: "?"
        if (code != "0") throw SeventyMaiCameraException(code)
        val value = raw["Result"] ?: JsonNull
        if (value is JsonPrimitive && value.isString) runCatching { json.parseToJsonElement(value.content) }.getOrDefault(value) else value
    }
    suspend fun download(clip: SeventyMaiClip, file: File, progress: (Long, Long) -> Unit) = withContext(Dispatchers.IO) {
        if (file.exists() && file.length() > 0 && clip.sizeBytes > 0 && file.length() == clip.sizeBytes) { progress(file.length(), file.length()); return@withContext }
        val partial = File(file.path + ".part")
        try {
            suspendCancellableCoroutine<Unit> { continuation ->
                val call = http.newCall(Request.Builder().url(SeventyMaiProtocol.fileUrl(clip)).build())
                continuation.invokeOnCancellation { call.cancel() }
                call.enqueue(object : Callback {
                    override fun onFailure(call: Call, error: IOException) {
                        if (continuation.isActive) continuation.resumeWithException(error)
                    }
                    override fun onResponse(call: Call, response: Response) {
                        try {
                            response.use {
                                check(response.isSuccessful) { "70mai: HTTP ${response.code}" }
                                val body = requireNotNull(response.body)
                                val expected = body.contentLength().takeIf { it > 0 } ?: clip.sizeBytes
                                body.byteStream().use { input -> partial.outputStream().use { output ->
                                    val buffer = ByteArray(512 * 1024)
                                    var copied = 0L
                                    while (true) {
                                        if (!continuation.isActive) throw kotlinx.coroutines.CancellationException()
                                        val count = input.read(buffer)
                                        if (count < 0) break
                                        output.write(buffer, 0, count)
                                        copied += count
                                        if (continuation.isActive) progress(copied, expected)
                                    }
                                    check(copied > 0 && (expected <= 0 || copied == expected)) { "70mai: incomplete download" }
                                } }
                            }
                            if (continuation.isActive) continuation.resume(Unit)
                        } catch (error: Exception) {
                            if (continuation.isActive) continuation.resumeWithException(error)
                        }
                    }
                })
            }
            ensureActive()
            check(partial.renameTo(file)) { "70mai: cannot store recording" }
        } finally { partial.delete() }
    }
    private suspend fun request(url: String): Response = suspendCancellableCoroutine { continuation ->
        val call = http.newCall(Request.Builder().url(url).build())
        call.timeout().timeout(8, TimeUnit.SECONDS)
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) { if (continuation.isActive) continuation.resumeWithException(e) }
            override fun onResponse(call: Call, response: Response) {
                continuation.resume(response) { _, resource, _ -> resource.close() }
            }
        })
    }
    companion object {
        private fun wifiClient(context: Context): OkHttpClient {
            val connectivity = context.getSystemService(ConnectivityManager::class.java)
            val wifi = connectivity.allNetworks.firstOrNull { connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true }
            return OkHttpClient.Builder().connectTimeout(8, TimeUnit.SECONDS).readTimeout(45, TimeUnit.SECONDS).followRedirects(false)
                .apply { wifi?.let { socketFactory(it.socketFactory) } }.build()
        }
    }
}
