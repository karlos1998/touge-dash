package it.letscode.tougedash.car

import androidx.car.app.model.GridItem
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TelemetryCarTemplateInstrumentedTest {
    @Test
    fun createsHostCompatibleGridWithAllEngineHealthMetrics() {
        val dashboard = TelemetryCarDashboard(
            title = "Touge Dash • LIVE",
            connectionLabel = "EMULOGGER",
            isLive = true,
            hasCriticalWarning = false,
            cards = listOf(
                CarMetricCard("oil-pressure", "OIL PRESSURE", "4.2 bar"),
                CarMetricCard("oil-temperature", "OIL TEMP", "104 °C"),
                CarMetricCard("coolant", "COOLANT", "91 °C"),
                CarMetricCard("boost", "BOOST", "1.18 bar"),
                CarMetricCard("afr", "AFR", "12.4"),
                CarMetricCard("fuel-pressure", "FUEL PRESSURE", "3.4 bar")
            )
        )

        val template = TelemetryCarTemplateFactory.create(ApplicationProvider.getApplicationContext(), dashboard)
        val items = requireNotNull(template.singleList).items

        assertEquals(6, items.size)
        assertTrue(items.all { it is GridItem && it.image != null })
        assertEquals("Touge Dash • LIVE", template.header?.title.toString())
    }
}
