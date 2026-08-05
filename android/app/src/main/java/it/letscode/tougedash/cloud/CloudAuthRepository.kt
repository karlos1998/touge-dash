package it.letscode.tougedash.cloud

import android.content.Context
import android.net.Uri
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import it.letscode.tougedash.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

@Serializable data class CloudAccount(val id: String, val email: String, val displayName: String)
@Serializable data class CloudAuthSession(val accessToken: String, val accessTokenExpiresAt: String, val refreshToken: String, val account: CloudAccount)

class CloudAuthRepository(private val context: Context, private val json: Json) {
    private val client = OkHttpClient.Builder().retryOnConnectionFailure(true).build()
    private val refreshMutex = Mutex()
    private val preferences by lazy {
        val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(context, "touge-cloud", key, EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV, EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
    }
    private val mutableSession = MutableStateFlow(load())
    val session = mutableSession.asStateFlow()
    private val mutableWorking = MutableStateFlow(false)
    val working = mutableWorking.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val error = mutableError.asStateFlow()
    val isAuthenticated get() = mutableSession.value != null

    suspend fun login(email: String, password: String) = authenticate("/api/v1/auth/login", buildJsonObject { put("email", email.trim()); put("password", password) })
    suspend fun register(email: String, password: String, displayName: String) = authenticate("/api/v1/auth/register", buildJsonObject { put("email", email.trim()); put("password", password); put("displayName", displayName.trim()) })
    suspend fun social(provider: String, token: String) = authenticate("/api/v1/auth/social", buildJsonObject {
        put("provider", provider)
        put("token", token)
    })
    suspend fun exchangeHandoff(code: String) = authenticate("/api/v1/auth/mobile-handoff/exchange", buildJsonObject { put("code", code) })

    fun handleUri(uri: Uri?) {
        if (uri?.scheme != "tougedash" || uri.host != "auth") return
        val code: String = uri.getQueryParameter("code") ?: return
        CoroutineScope(Dispatchers.Main).launch { runCatching { exchangeHandoff(code) }.onFailure { mutableError.value = it.message } }
    }

    suspend fun logout() {
        val refresh = mutableSession.value?.refreshToken
        clear()
        if (refresh != null) runCatching { request("/api/v1/auth/logout", "POST", buildJsonObject { put("refreshToken", refresh) }, authorized = false) }
    }

    suspend fun deleteAccount(): Boolean {
        if (mutableSession.value == null) return true
        mutableWorking.value = true
        mutableError.value = null
        return runCatching {
            request("/api/v1/me", "DELETE")
            clear()
            true
        }.onFailure { mutableError.value = it.message }
            .getOrDefault(false)
            .also { mutableWorking.value = false }
    }

    suspend fun request(path: String, method: String = "GET", body: JsonElement? = null, authorized: Boolean = true): JsonElement = withContext(Dispatchers.IO) {
        var response = execute(path, method, body, if (authorized) mutableSession.value?.accessToken else null)
        if (authorized && response.first == 401) {
            refresh()
            response = execute(path, method, body, mutableSession.value?.accessToken)
        }
        if (response.first !in 200..299) {
            val message = runCatching { json.parseToJsonElement(response.second).jsonObject["message"]?.jsonPrimitive?.content }.getOrNull()
            error(message ?: "Server error ${response.first}")
        }
        if (response.second.isBlank()) buildJsonObject { } else json.parseToJsonElement(response.second)
    }

    fun clearError() { mutableError.value = null }
    fun reportError(message: String) { mutableError.value = message }

    private suspend fun authenticate(path: String, body: JsonElement): Boolean {
        mutableWorking.value = true; mutableError.value = null
        return runCatching {
            val value = request(path, "POST", body, authorized = false)
            val authenticated = json.decodeFromString<CloudAuthSession>(value.toString())
            accept(authenticated); true
        }.onFailure { mutableError.value = it.message }.getOrDefault(false).also { mutableWorking.value = false }
    }

    private suspend fun refresh() = refreshMutex.withLock {
        val token = mutableSession.value?.refreshToken ?: error("Session expired")
        val response = withContext(Dispatchers.IO) { execute("/api/v1/auth/refresh", "POST", buildJsonObject { put("refreshToken", token) }, null) }
        if (response.first !in 200..299) { clear(); error("Session expired") }
        accept(json.decodeFromString(response.second))
    }

    private fun execute(path: String, method: String, body: JsonElement?, token: String?): Pair<Int, String> {
        val payload = body?.toString()?.toRequestBody("application/json".toMediaType())
        val request = Request.Builder().url(BuildConfig.API_BASE_URL.trimEnd('/') + path)
            .method(method, if (method == "GET" || method == "DELETE" && body == null) null else payload ?: ByteArray(0).toRequestBody())
            .header("Accept", "application/json")
            .apply { if (token != null) header("Authorization", "Bearer $token") }
            .build()
        return client.newCall(request).execute().use { it.code to (it.body?.string().orEmpty()) }
    }

    private fun accept(value: CloudAuthSession) { mutableSession.value = value; preferences.edit().putString(SESSION, json.encodeToString(value)).apply() }
    private fun load(): CloudAuthSession? = runCatching {
        val raw = preferences.getString(SESSION, null) ?: return@runCatching null
        json.decodeFromString<CloudAuthSession>(raw)
    }.getOrNull()
    private fun clear() { mutableSession.value = null; preferences.edit().remove(SESSION).apply() }
    private fun error(message: String): Nothing { throw IllegalStateException(message) }
    companion object { private const val SESSION = "session" }
}
