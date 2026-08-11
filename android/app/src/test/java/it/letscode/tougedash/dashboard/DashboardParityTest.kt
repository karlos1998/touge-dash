package it.letscode.tougedash.dashboard

import it.letscode.tougedash.model.DashboardDefinition
import it.letscode.tougedash.model.DashboardTemplate
import it.letscode.tougedash.model.DashboardWidget
import it.letscode.tougedash.model.DashboardWidgetKind
import it.letscode.tougedash.ui.dashboardDisplayKind
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DashboardParityTest {
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }

    @Test
    fun `factory layout contains the same ten cards as ios`() {
        val widgets = DashboardTemplate.factory().definition.widgets

        assertEquals(10, widgets.size)
        assertEquals(12, widgets[1].landscapeSpan)
        assertEquals(listOf("MAP", "RPM"), widgets.filter { it.portraitSpan == 0 }.map { it.metrics.first().name })
        assertEquals(0, DashboardTemplate.factory().definition.pageOrder)
    }

    @Test
    fun `cloud json uses ios enum values and field names`() {
        val encoded = json.encodeToString(DashboardTemplate.factory().definition)

        assertTrue(encoded.contains("\"kind\":\"hero\""))
        assertTrue(encoded.contains("\"metrics\":[\"boost\",\"map\",\"throttle\",\"rpm\"]"))
        assertTrue(encoded.contains("\"accent\":\"cyan\""))
        assertTrue(encoded.contains("\"chartDuration\""))
    }

    @Test
    fun `control card uses the same optional schema as ios`() {
        val widget = DashboardWidget(
            kind = DashboardWidgetKind.ECU_ROTARY,
            metrics = emptyList(),
            portraitSpan = 6,
            landscapeSpan = 4,
            portraitOrder = 0,
            controlChannel = 6
        )
        val encoded = json.encodeToString(widget)

        assertTrue(encoded.contains("\"kind\":\"ecuRotary\""))
        assertTrue(encoded.contains("\"controlChannel\":6"))
        assertEquals(widget, json.decodeFromString<DashboardWidget>(encoded))
    }

    @Test
    fun `legacy uppercase android json remains readable`() {
        val current = json.encodeToString(DashboardTemplate.factory().definition)
        val legacy = current
            .replace("\"hero\"", "\"HERO\"")
            .replace("\"boost\"", "\"BOOST\"")
            .replace("\"cyan\"", "\"CYAN\"")
            .replace("\"chartDuration\"", "\"chartDurationSeconds\"")

        val decoded = json.decodeFromString<DashboardDefinition>(normalizeLegacyDashboardJson(legacy))

        assertEquals(DashboardTemplate.factory().definition.widgets.size, decoded.widgets.size)
        assertEquals(DashboardTemplate.factory().definition.widgets.first().kind, decoded.widgets.first().kind)
    }

    @Test
    fun `dashboard page order is optional for old cloud records`() {
        val current = json.encodeToString(DashboardTemplate.factory().definition)
        val legacy = current.replace(Regex(",?\\\"pageOrder\\\":0"), "")

        val decoded = json.decodeFromString<DashboardDefinition>(legacy)

        assertEquals(null, decoded.pageOrder)
        assertEquals(10, decoded.widgets.size)
    }

    @Test
    fun `hero card adapts its presentation to available portrait width`() {
        val hero = DashboardTemplate.factory().definition.widgets.first()

        assertEquals(DashboardWidgetKind.HERO, dashboardDisplayKind(hero.copy(portraitSpan = 12), landscape = false))
        assertEquals(DashboardWidgetKind.VALUE, dashboardDisplayKind(hero.copy(portraitSpan = 6), landscape = false))
        assertEquals(DashboardWidgetKind.COMPACT, dashboardDisplayKind(hero.copy(portraitSpan = 4), landscape = false))
    }
}
