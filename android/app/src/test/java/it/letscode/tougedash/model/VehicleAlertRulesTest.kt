package it.letscode.tougedash.model

import org.junit.Assert.assertEquals
import org.junit.Test

class VehicleAlertRulesTest {
    @Test
    fun `invalid values are clamped to the same ranges as ios`() {
        val value = VehicleAlertRules(
            cooldownSeconds = 1,
            minimumOilPressureBar = -4.0,
            maximumAfr = 90.0,
            maximumBoostBar = 12.0,
            maximumCoolantCelsius = 20.0,
            maximumOilTemperatureCelsius = 500.0
        ).validated()

        assertEquals(30, value.cooldownSeconds)
        assertEquals(.1, value.minimumOilPressureBar, .001)
        assertEquals(25.0, value.maximumAfr, .001)
        assertEquals(5.0, value.maximumBoostBar, .001)
        assertEquals(70.0, value.maximumCoolantCelsius, .001)
        assertEquals(200.0, value.maximumOilTemperatureCelsius, .001)
    }
}
