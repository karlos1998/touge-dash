package it.letscode.tougedash.telemetry

import android.content.Context

enum class TelemetryOverlayMode {
    COMPACT,
    EXPANDED;

    fun toggled(): TelemetryOverlayMode = when (this) {
        COMPACT -> EXPANDED
        EXPANDED -> COMPACT
    }
}

data class TelemetryOverlayPosition(val x: Int, val y: Int)

object TelemetryOverlayPreferences {
    private const val PREFERENCES = "telemetry-overlay"
    private const val ENABLED = "enabled"
    private const val MODE = "mode"
    private const val X = "x"
    private const val Y = "y"

    fun isEnabled(context: Context): Boolean = preferences(context).getBoolean(ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        preferences(context).edit().putBoolean(ENABLED, enabled).apply()
    }

    fun mode(context: Context): TelemetryOverlayMode = runCatching {
        TelemetryOverlayMode.valueOf(
            preferences(context).getString(MODE, TelemetryOverlayMode.COMPACT.name)
                ?: TelemetryOverlayMode.COMPACT.name
        )
    }.getOrDefault(TelemetryOverlayMode.COMPACT)

    fun setMode(context: Context, mode: TelemetryOverlayMode) {
        preferences(context).edit().putString(MODE, mode.name).apply()
    }

    fun position(context: Context, defaultY: Int): TelemetryOverlayPosition {
        val values = preferences(context)
        return TelemetryOverlayPosition(
            x = values.getInt(X, 16),
            y = values.getInt(Y, defaultY)
        )
    }

    fun setPosition(context: Context, position: TelemetryOverlayPosition) {
        preferences(context).edit()
            .putInt(X, position.x)
            .putInt(Y, position.y)
            .apply()
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
}
