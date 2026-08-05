package it.letscode.tougedash.car

import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetrySnapshot
import it.letscode.tougedash.model.VehicleAlertRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TelemetryCarDashboardTest {
    @Test
    fun prioritizesEngineHealthInsteadOfRpm() {
        val dashboard = TelemetryCarDashboardFactory.create(
            snapshot = snapshot(),
            connection = connection(),
            rules = VehicleAlertRules(),
            language = "en"
        )

        assertEquals(
            listOf("oil-pressure", "oil-temperature", "coolant", "boost", "afr", "fuel-pressure"),
            dashboard.cards.map { it.id }
        )
        assertTrue(dashboard.cards.none { it.id == "rpm" })
        assertEquals("4.2 bar", dashboard.cards.first().value)
    }

    @Test
    fun criticalOilAndCoolantValuesChangeDashboardState() {
        val dashboard = TelemetryCarDashboardFactory.create(
            snapshot = snapshot(oilPressureBar = 0.8, coolantCelsius = 114.0),
            connection = connection(),
            rules = VehicleAlertRules(),
            language = "pl"
        )

        assertTrue(dashboard.hasCriticalWarning)
        assertEquals("Touge Dash • OSTRZEŻENIE", dashboard.title)
        assertEquals(CarMetricTone.CRITICAL, dashboard.cards.first { it.id == "oil-pressure" }.tone)
        assertEquals(CarMetricTone.CRITICAL, dashboard.cards.first { it.id == "coolant" }.tone)
    }

    @Test
    fun disabledFuelPressureRuleDoesNotCreateWarning() {
        val dashboard = TelemetryCarDashboardFactory.create(
            snapshot = snapshot(fuelPressureBar = 0.5),
            connection = connection(),
            rules = VehicleAlertRules(lowFuelPressureEnabled = false),
            language = "en"
        )

        assertFalse(dashboard.hasCriticalWarning)
        assertEquals(CarMetricTone.NORMAL, dashboard.cards.first { it.id == "fuel-pressure" }.tone)
    }

    @Test
    fun disconnectedStateIsClearlyLabelled() {
        val dashboard = TelemetryCarDashboardFactory.create(
            snapshot = snapshot(),
            connection = TelemetryConnection(state = ConnectionState.Scanning),
            rules = VehicleAlertRules(),
            language = "pl"
        )

        assertFalse(dashboard.isLive)
        assertEquals("Touge Dash • OFFLINE", dashboard.title)
        assertEquals("Szukanie EMULOGGERA", dashboard.connectionLabel)
    }

    private fun snapshot(
        oilPressureBar: Double = 4.2,
        coolantCelsius: Double = 91.0,
        fuelPressureBar: Double = 3.4
    ) = TelemetrySnapshot(
        rpm = 4_500.0,
        boostBar = 1.18,
        coolantCelsius = coolantCelsius,
        oilTemperatureCelsius = 104.0,
        oilPressureBar = oilPressureBar,
        fuelPressureBar = fuelPressureBar,
        afr = 12.4,
        updatedAt = System.currentTimeMillis()
    )

    private fun connection() = TelemetryConnection(
        state = ConnectionState.Connected,
        deviceName = "EMULOGGER",
        hardwareId = "00:11:22:33:44:55"
    )
}
