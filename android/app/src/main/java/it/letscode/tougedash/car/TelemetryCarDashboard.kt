package it.letscode.tougedash.car

import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetrySnapshot
import it.letscode.tougedash.model.VehicleAlertRules
import java.util.Locale

enum class CarMetricTone { NORMAL, WARNING, CRITICAL }

data class CarMetricCard(
    val id: String,
    val label: String,
    val value: String,
    val tone: CarMetricTone = CarMetricTone.NORMAL
)

data class TelemetryCarDashboard(
    val title: String,
    val connectionLabel: String,
    val isLive: Boolean,
    val hasCriticalWarning: Boolean,
    val cards: List<CarMetricCard>
)

object TelemetryCarDashboardFactory {
    fun create(
        snapshot: TelemetrySnapshot,
        connection: TelemetryConnection,
        rules: VehicleAlertRules,
        language: String
    ): TelemetryCarDashboard {
        val polish = language.lowercase(Locale.ROOT).startsWith("pl")
        val live = connection.state == ConnectionState.Connected && snapshot.isFresh
        val lowOilPressure = rules.lowOilPressureEnabled &&
            snapshot.rpm >= rules.lowOilMinimumRpm &&
            snapshot.oilPressureBar > 0 &&
            snapshot.oilPressureBar < rules.minimumOilPressureBar
        val hotOil = rules.highOilTemperatureEnabled &&
            snapshot.oilTemperatureCelsius >= rules.maximumOilTemperatureCelsius
        val hotCoolant = rules.highCoolantTemperatureEnabled &&
            snapshot.coolantCelsius >= rules.maximumCoolantCelsius
        val overboost = rules.overboostEnabled && snapshot.boostBar > rules.maximumBoostBar
        val lean = rules.leanUnderBoostEnabled &&
            snapshot.boostBar >= rules.leanMinimumBoostBar &&
            snapshot.afr > rules.maximumAfr
        val lowFuel = rules.lowFuelPressureEnabled &&
            snapshot.rpm >= rules.lowFuelPressureMinimumRpm &&
            snapshot.fuelPressureBar > 0 &&
            snapshot.fuelPressureBar < rules.minimumFuelPressureBar
        val critical = lowOilPressure || hotOil || hotCoolant || snapshot.hasCheckEngine

        val connectionLabel = when {
            live -> connection.deviceName ?: "EMULOGGER"
            connection.state == ConnectionState.Connecting || connection.state == ConnectionState.Reconnecting ->
                if (polish) "Łączenie z EMULOGGEREM" else "Connecting to EMULOGGER"
            connection.state == ConnectionState.Scanning ->
                if (polish) "Szukanie EMULOGGERA" else "Searching for EMULOGGER"
            else -> if (polish) "Brak danych na żywo" else "No live data"
        }

        return TelemetryCarDashboard(
            title = when {
                critical -> if (polish) "Touge Dash • OSTRZEŻENIE" else "Touge Dash • WARNING"
                live -> "Touge Dash • LIVE"
                else -> "Touge Dash • OFFLINE"
            },
            connectionLabel = connectionLabel,
            isLive = live,
            hasCriticalWarning = critical,
            cards = listOf(
                CarMetricCard(
                    id = "oil-pressure",
                    label = if (polish) "CIŚNIENIE OLEJU" else "OIL PRESSURE",
                    value = format(snapshot.oilPressureBar, 1, "bar"),
                    tone = if (lowOilPressure) CarMetricTone.CRITICAL else CarMetricTone.NORMAL
                ),
                CarMetricCard(
                    id = "oil-temperature",
                    label = if (polish) "TEMP. OLEJU" else "OIL TEMP",
                    value = format(snapshot.oilTemperatureCelsius, 0, "°C"),
                    tone = if (hotOil) CarMetricTone.CRITICAL else CarMetricTone.NORMAL
                ),
                CarMetricCard(
                    id = "coolant",
                    label = if (polish) "PŁYN CHŁODNICZY" else "COOLANT",
                    value = format(snapshot.coolantCelsius, 0, "°C"),
                    tone = if (hotCoolant) CarMetricTone.CRITICAL else CarMetricTone.NORMAL
                ),
                CarMetricCard(
                    id = "boost",
                    label = "BOOST",
                    value = format(snapshot.boostBar, 2, "bar"),
                    tone = if (overboost) CarMetricTone.WARNING else CarMetricTone.NORMAL
                ),
                CarMetricCard(
                    id = "afr",
                    label = "AFR",
                    value = format(snapshot.afr, 1, ""),
                    tone = if (lean) CarMetricTone.WARNING else CarMetricTone.NORMAL
                ),
                CarMetricCard(
                    id = "fuel-pressure",
                    label = if (polish) "CIŚNIENIE PALIWA" else "FUEL PRESSURE",
                    value = format(snapshot.fuelPressureBar, 1, "bar"),
                    tone = if (lowFuel) CarMetricTone.WARNING else CarMetricTone.NORMAL
                )
            )
        )
    }

    private fun format(value: Double, decimals: Int, unit: String): String {
        val number = when (decimals) {
            0 -> String.format(Locale.US, "%.0f", value)
            1 -> String.format(Locale.US, "%.1f", value)
            else -> String.format(Locale.US, "%.2f", value)
        }
        return if (unit.isBlank()) number else "$number $unit"
    }
}
