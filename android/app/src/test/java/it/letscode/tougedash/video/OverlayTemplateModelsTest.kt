package it.letscode.tougedash.video

import it.letscode.tougedash.model.TelemetryMetric
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
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

    @Test
    fun `factory hud has independent movable elements for both orientations`() {
        val template = VideoOverlayTemplateDefinition.tougePro()
        val speed = template.elements.first { it.metric.name == "SPEED" }

        assertEquals(6, template.elements.size)
        assertNotEquals(speed.position(false), speed.position(true))
        assertEquals(OverlayElementKind.GAUGE, speed.kind)
    }

    @Test
    fun `free form element survives serialization`() {
        val template = VideoOverlayTemplateDefinition.nightRun()
        val restored = json.decodeFromString<VideoOverlayTemplateDefinition>(json.encodeToString(template))

        assertEquals(template.elements, restored.elements)
        assertEquals(2, restored.layoutVersion)
    }

    @Test
    fun `street legends combines configured performance and oil clusters`() {
        val template = VideoOverlayTemplateDefinition.streetLegends()
        val restored = json.decodeFromString<VideoOverlayTemplateDefinition>(json.encodeToString(template))

        assertEquals(listOf(OverlayElementKind.SPEED_CLUSTER, OverlayElementKind.OIL_CLUSTER), restored.elements.map { it.kind })
        assertEquals(300.0, restored.range(TelemetryMetric.SPEED).endInclusive, 0.0)
        assertEquals(140.0, restored.range(TelemetryMetric.OIL_TEMPERATURE).endInclusive, 0.0)
    }

    @Test
    fun `arcade era presets use recorded telemetry instead of nitrous`() {
        val presets = listOf(
            VideoOverlayTemplateDefinition.neonCircuit(),
            VideoOverlayTemplateDefinition.blacklistClassic(),
            VideoOverlayTemplateDefinition.carbonGold(),
            VideoOverlayTemplateDefinition.streetShift()
        )

        assertEquals(
            listOf(
                OverlayElementKind.NEON_TACH,
                OverlayElementKind.BLACKLIST_TACH,
                OverlayElementKind.CARBON_TACH,
                OverlayElementKind.STREET_SHIFT_TACH
            ),
            presets.map { it.elements.single().kind }
        )
        presets.forEach { assertEquals(it, json.decodeFromString<VideoOverlayTemplateDefinition>(json.encodeToString(it))) }
        assertEquals(10_000.0, presets.first().range(TelemetryMetric.RPM).endInclusive, 0.0)
    }
}
