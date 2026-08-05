package it.letscode.tougedash.telemetry

import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetrySnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class TimedTelemetry(val recordedAt: Long, val snapshot: TelemetrySnapshot)

object TelemetryRuntime {
    private val mutableSnapshot = MutableStateFlow(TelemetrySnapshot())
    val snapshot = mutableSnapshot.asStateFlow()
    private val mutableConnection = MutableStateFlow(TelemetryConnection())
    val connection = mutableConnection.asStateFlow()
    private val mutableDiagnostics = MutableStateFlow<List<String>>(emptyList())
    val diagnostics = mutableDiagnostics.asStateFlow()
    private val mutableChartPoints = MutableStateFlow<List<TimedTelemetry>>(emptyList())
    val chartPoints = mutableChartPoints.asStateFlow()
    private var lastChartPointAt = 0L

    internal fun updateSnapshot(value: TelemetrySnapshot) {
        mutableSnapshot.value = value
        // Dashboard charts do not need the full recording frequency. Keeping 5 Hz here
        // avoids copying a 6,000-element list ten times per second on long drives.
        if (value.updatedAt - lastChartPointAt >= 200) {
            lastChartPointAt = value.updatedAt
            mutableChartPoints.value = (mutableChartPoints.value + TimedTelemetry(value.updatedAt, value))
                .dropWhile { value.updatedAt - it.recordedAt > 600_000 }
        }
    }
    internal fun updateConnection(value: TelemetryConnection) { mutableConnection.value = value }
    internal fun diagnostic(value: String) {
        mutableDiagnostics.value = (listOf("${System.currentTimeMillis()}: $value") + mutableDiagnostics.value).take(100)
    }
}
