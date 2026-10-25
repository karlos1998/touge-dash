package it.letscode.tougedash.video

import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class VideoOverlayCodecTest {
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }
    @Test fun `all sixteen video templates survive migration including gauge widgets`() {
        val templates = listOf(VideoOverlayTemplateDefinition.tougePro(), VideoOverlayTemplateDefinition.nightRun(), VideoOverlayTemplateDefinition.cleanDrive(), VideoOverlayTemplateDefinition.portraitRally(),
            VideoOverlayTemplateDefinition.streetLegends(), VideoOverlayTemplateDefinition.neonCircuit(), VideoOverlayTemplateDefinition.blacklistClassic(), VideoOverlayTemplateDefinition.carbonGold(),
            VideoOverlayTemplateDefinition.streetShift(), VideoOverlayTemplateDefinition.routeRadar(), VideoOverlayTemplateDefinition.routeOrbit(), VideoOverlayTemplateDefinition.pursuitMap(),
            VideoOverlayTemplateDefinition.routeChase(), VideoOverlayTemplateDefinition.streetAtlas(), VideoOverlayTemplateDefinition.iceOrbit(), VideoOverlayTemplateDefinition.amberRun())
        templates.forEach { template ->
            assertEquals(template, json.decodeFromString<VideoOverlayTemplateDefinition>(normalizeVideoOverlayJson(json.encodeToString(template))))
        }
    }
    @Test fun `uppercase legacy metric and accent migrate without changing the video gauge kind`() {
        val template = VideoOverlayTemplateDefinition.tougePro()
        val legacy = json.encodeToString(template).replace("\"speed\"", "\"SPEED\"").replace("\"cyan\"", "\"CYAN\"")
        val restored = json.decodeFromString<VideoOverlayTemplateDefinition>(normalizeVideoOverlayJson(legacy))
        assertEquals(template, restored)
        assertTrue(restored.elements.any { it.kind == OverlayElementKind.GAUGE })
    }
}
