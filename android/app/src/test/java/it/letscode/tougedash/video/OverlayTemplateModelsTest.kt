package it.letscode.tougedash.video

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class OverlayTemplateModelsTest {
    private val json = Json { encodeDefaults = true }

    @Test
    fun `keeps independent portrait and landscape positions`() {
        val original = VideoOverlayTemplateDefinition(OverlayStyle.RACE)
            .positioned(portrait = true, x = .25f, y = -.55f, scale = .8f)
            .positioned(portrait = false, x = -.3f, y = .6f, scale = .9f)

        val restored = json.decodeFromString<VideoOverlayTemplateDefinition>(json.encodeToString(original))

        assertEquals(.25f, restored.x(portrait = true), .001f)
        assertEquals(-.55f, restored.y(portrait = true), .001f)
        assertEquals(-.3f, restored.x(portrait = false), .001f)
        assertEquals(.6f, restored.y(portrait = false), .001f)
        assertEquals(.9f, restored.scale, .001f)
    }
}
