package it.letscode.tougedash.video

import org.junit.Assert.*
import org.junit.Test

class VideoTimelineTest {
    @Test fun `trimming preserves synchronization instead of clamping the telemetry independently`() {
        val timeline = VideoTimeline(10.0, 2.0, 20.0)
        val trimmed = timeline.trimStart(0.0)
        assertEquals(8.0, trimmed.videoStart, .0001)
        assertEquals(0.0, trimmed.telemetryStart, .0001)
        assertEquals(timeline.telemetryAt(15.0), trimmed.telemetryAt(15.0), .0001)
    }
    @Test fun `trim end respects both video and telemetry boundaries`() {
        val timeline = VideoTimeline(10.0, 25.0, 5.0).trimEnd(50.0, 40.0, 35.0)
        assertEquals(10.0, timeline.duration, .0001)
        assertEquals(35.0, timeline.telemetryAt(timeline.videoStart + timeline.duration), .0001)
    }
    @Test fun `invalid persisted alignment cannot export outside the source`() {
        assertEquals(VideoTimeline(0.0, 5.0, 0.0), VideoTimeline(Double.NaN, 99.0, Double.POSITIVE_INFINITY).normalized(12.0, 5.0))
    }
    @Test fun `video and chart cursor positions round trip across an offset`() {
        val timeline = VideoTimeline(7.3, 102.8, 6.0)
        assertEquals(11.4, timeline.videoAt(timeline.telemetryAt(11.4)), .0001)
    }
}
