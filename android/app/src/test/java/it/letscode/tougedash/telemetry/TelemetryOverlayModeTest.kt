package it.letscode.tougedash.telemetry

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TelemetryOverlayModeTest {
    @Test
    fun compactAndExpandedModesToggleWithoutCreatingAHiddenRuntimeState() {
        assertEquals(TelemetryOverlayMode.EXPANDED, TelemetryOverlayMode.COMPACT.toggled())
        assertEquals(TelemetryOverlayMode.COMPACT, TelemetryOverlayMode.EXPANDED.toggled())
    }

    @Test
    fun enabledOverlayIsSuppressedWhileTougeDashIsVisible() {
        assertFalse(
            TelemetryOverlayVisibilityPolicy.shouldShow(
                enabled = true,
                canDrawOverlays = true,
                appVisible = true
            )
        )
        assertTrue(
            TelemetryOverlayVisibilityPolicy.shouldShow(
                enabled = true,
                canDrawOverlays = true,
                appVisible = false
            )
        )
    }

    @Test
    fun overlayRequiresPreferenceAndSystemPermission() {
        assertFalse(TelemetryOverlayVisibilityPolicy.shouldShow(false, true, false))
        assertFalse(TelemetryOverlayVisibilityPolicy.shouldShow(true, false, false))
    }
}
