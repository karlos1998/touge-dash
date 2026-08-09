package it.letscode.tougedash.video

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VideoExportQualityTest {
    @Test
    fun `overlay bitmap keeps source aspect ratio`() {
        assertEquals(480 to 854, overlayBitmapSize(480, 854))
        assertEquals(2160 to 3840, overlayBitmapSize(2160, 3840))
        assertEquals(3840 to 2160, overlayBitmapSize(7680, 4320))
    }

    @Test
    fun `unknown dimensions use a safe full hd canvas`() {
        assertEquals(1920 to 1080, overlayBitmapSize(0, 0))
    }

    @Test
    fun `quality target scales with resolution and codec efficiency`() {
        val fullHdHevc = VideoExportQuality.targetBitrate(1920, 1080, 30.0, hevc = true)
        val fullHdAvc = VideoExportQuality.targetBitrate(1920, 1080, 30.0, hevc = false)
        val ultraHdHevc = VideoExportQuality.targetBitrate(3840, 2160, 30.0, hevc = true)

        assertTrue(fullHdHevc >= 9_000_000)
        assertTrue(fullHdAvc > fullHdHevc)
        assertTrue(ultraHdHevc > fullHdHevc * 3)
    }
}
