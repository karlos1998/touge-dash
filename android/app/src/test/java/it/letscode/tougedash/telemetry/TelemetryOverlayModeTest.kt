package it.letscode.tougedash.telemetry

import org.junit.Assert.assertEquals
import org.junit.Test

class TelemetryOverlayModeTest {
    @Test
    fun compactAndExpandedModesToggleWithoutCreatingAHiddenRuntimeState() {
        assertEquals(TelemetryOverlayMode.EXPANDED, TelemetryOverlayMode.COMPACT.toggled())
        assertEquals(TelemetryOverlayMode.COMPACT, TelemetryOverlayMode.EXPANDED.toggled())
    }
}
