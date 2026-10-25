package it.letscode.tougedash.video

import it.letscode.tougedash.model.TelemetryMetric
import org.junit.Assert.*
import org.junit.Test

class VideoOverlayGeometryTest {
    @Test fun `every widget remains inside portrait landscape and tiny previews at every size`() {
        for ((width, height) in listOf(1920 to 1080, 1080 to 1920, 320 to 180, 180 to 320)) {
            OverlayElementKind.entries.forEach { kind ->
                val element = VideoOverlayElement(metric = TelemetryMetric.SPEED, kind = kind, scale = OverlayElementScale.EXTRA_LARGE,
                    sizeMultiplier = 2.5f, landscapePosition = OverlayPosition(.95f, .95f), portraitPosition = OverlayPosition(.05f, .05f))
                val bounds = element.bounds(width, height)
                assertTrue("$kind: $bounds", bounds.left >= 0 && bounds.top >= 0)
                assertTrue(bounds.left + bounds.width <= width + .01 && bounds.top + bounds.height <= height + .01)
            }
        }
    }
    @Test fun `digital widget uses the same reference footprint as ios`() {
        val element = VideoOverlayElement(metric = TelemetryMetric.SPEED, landscapePosition = OverlayPosition(.5f, .5f))
        val bounds = element.bounds(390, 220)
        assertEquals(94f, bounds.width, .001f)
        assertEquals(56f, bounds.height, .001f)
    }
    @Test fun `full hd mode never upscales and preserves orientation`() {
        assertEquals(1920 to 1080, DriveVideoExportQuality.FAST_FULL_HD.dimensions(3840, 2160))
        assertEquals(1080 to 1920, DriveVideoExportQuality.FAST_FULL_HD.dimensions(2160, 3840))
        assertEquals(1280 to 720, DriveVideoExportQuality.FAST_FULL_HD.dimensions(1280, 720))
        assertEquals(3840 to 2160, DriveVideoExportQuality.ORIGINAL.dimensions(3840, 2160))
    }
}
