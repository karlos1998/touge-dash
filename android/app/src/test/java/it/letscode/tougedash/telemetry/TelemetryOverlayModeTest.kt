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

    @Test
    fun dragDismissTargetArmsOnlyInsideItsCaptureRadius() {
        val target = OverlayCoordinate(200f, 700f)

        assertTrue(
            TelemetryOverlayDismissGesture.shouldDismiss(
                TelemetryOverlayDismissGesture.distance(OverlayCoordinate(240f, 730f), target),
                72f
            )
        )
        assertFalse(
            TelemetryOverlayDismissGesture.shouldDismiss(
                TelemetryOverlayDismissGesture.distance(OverlayCoordinate(280f, 700f), target),
                72f
            )
        )
    }

    @Test
    fun dragDismissTargetGrowsSmoothlyAsBubbleApproaches() {
        assertEquals(0f, TelemetryOverlayDismissGesture.proximity(220f, 190f, 72f), 0.001f)
        assertEquals(1f, TelemetryOverlayDismissGesture.proximity(60f, 190f, 72f), 0.001f)
        val middle = TelemetryOverlayDismissGesture.proximity(131f, 190f, 72f)
        assertTrue(middle in 0.49f..0.51f)
    }
}
