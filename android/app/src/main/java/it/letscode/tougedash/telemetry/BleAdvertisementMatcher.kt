package it.letscode.tougedash.telemetry

import java.nio.charset.StandardCharsets
import java.util.Locale

/** Matches ECUMaster advertisements even when the local name is embedded in vendor data. */
internal object BleAdvertisementMatcher {
    private val markers = listOf("emulogger", "ecumaster", "canbt", "btcan", "edl", "logger", "emu")

    fun matches(
        name: String?,
        advertisesEmuService: Boolean,
        payloads: Iterable<ByteArray>
    ): Boolean {
        if (advertisesEmuService || containsMarker(name.orEmpty())) return true
        return payloads.any { containsMarker(String(it, StandardCharsets.ISO_8859_1)) }
    }

    fun containsMarker(value: String): Boolean {
        val normalized = value.lowercase(Locale.ROOT)
        return markers.any(normalized::contains)
    }
}
