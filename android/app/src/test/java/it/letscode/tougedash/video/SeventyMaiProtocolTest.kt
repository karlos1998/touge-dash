package it.letscode.tougedash.video

import java.util.TimeZone
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class SeventyMaiProtocolTest {
    private val utc = TimeZone.getTimeZone("UTC")
    @Test fun `pairing and signed requests match the ios verified wire fixtures`() {
        assertTrue(SeventyMaiProtocol.bindUrl("123456789").endsWith("&-signkey=e8c46806a6317270f185fdf1903498d6"))
        assertTrue(SeventyMaiProtocol.confirmationUrl("1700000000").endsWith("&-signkey=bbbf6a64712098c543a59a4aad97bb3f"))
        assertEquals("http://192.168.0.1/cgi-bin/getfilelist.cgi?&-start=1&-end=100&-type=0&-timestamp=1700000000&-signkey=cb960cbc06237f1c58be011bb185d00c",
            SeventyMaiProtocol.signedUrl("getfilelist.cgi", listOf("start" to "1", "end" to "100", "type" to "0"), 1700000000, "TOKEN"))
    }
    @Test fun `camera clock offset and centisecond duration map clips onto the drive`() {
        val clip = SeventyMaiProtocol.clip(Json.parseToJsonElement("""{"name":"NO20260813-080500.mp4","path":"/DCIM/Normal","duration":"6000","size":"42"}""").jsonObject, 300000, utc)!!
        val expected = SeventyMaiProtocol.parseDate("20260813-080000", utc)!!
        assertEquals(expected, clip.startedAt)
        assertEquals(60000L, clip.durationMillis)
        assertEquals(listOf(clip), SeventyMaiProtocol.matchingClips(listOf(clip), expected + 1000, expected + 30000))
        assertTrue(SeventyMaiProtocol.matchingClips(listOf(clip), clip.endedAt, clip.endedAt + 1000).isEmpty())
    }
    @Test fun `next filename repairs m300 firmware reporting 60 seconds for a 3 minute clip`() {
        val first = SeventyMaiClip("DCIM", "a.mp4", 10, 1000, 60000)
        val second = first.copy(name = "b.mp4", startedAt = 181000)
        val matching = SeventyMaiProtocol.matchingClips(listOf(second, first), 121000, 182000)
        assertEquals(180000L, matching.first().durationMillis)
        assertEquals(2, matching.size)
    }
    @Test fun `camera profiles select normal front and rear recording channels`() {
        assertEquals("0", SeventyMaiCameraModel.M300.recordingType(false))
        assertEquals("4", SeventyMaiCameraModel.A810.recordingType(false))
        assertEquals("8", SeventyMaiCameraModel.A810.recordingType(true))
    }
    @Test fun `file URLs escape names without escaping the camera directory separators`() {
        assertEquals("http://192.168.0.1/DCIM/Normal/clip%20one.mp4", SeventyMaiProtocol.fileUrl(SeventyMaiClip("/DCIM/Normal/", "clip one.mp4", 0, 0, 60000)))
    }
}
