package it.letscode.tougedash.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.intl.Locale
import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.DashboardTemplate
import it.letscode.tougedash.model.DashboardWidgetKind
import it.letscode.tougedash.model.TelemetryMetric

@Composable
internal fun appText(english: String, polish: String): String =
    if (Locale.current.language == "pl") polish else english

@Composable
internal fun DashboardTemplate.localizedName(): String =
    if (id == DashboardTemplate.FACTORY_ID) appText("Factory", "Fabryczny") else name

@Composable
internal fun ConnectionState.localizedLabel(): String = when (this) {
    ConnectionState.Idle -> appText("Stopped", "Zatrzymano")
    ConnectionState.Scanning -> appText("Scanning", "Skanowanie")
    ConnectionState.Connecting -> appText("Connecting", "Łączenie")
    ConnectionState.Connected -> appText("Connected", "Połączono")
    ConnectionState.Reconnecting -> appText("Reconnecting", "Ponowne łączenie")
    ConnectionState.BluetoothOff -> appText("Bluetooth off", "Bluetooth wyłączony")
    ConnectionState.PermissionRequired -> appText("Permission required", "Wymagane uprawnienie")
    ConnectionState.Failed -> appText("Connection error", "Błąd połączenia")
}

@Composable
internal fun TelemetryMetric.localizedName(): String = localizedName(Locale.current.language)

internal fun TelemetryMetric.localizedName(language: String): String = when (this) {
    TelemetryMetric.BOOST -> if (language == "pl") "DOŁADOWANIE" else "BOOST"
    TelemetryMetric.COOLANT -> if (language == "pl") "PŁYN" else "COOLANT"
    TelemetryMetric.OIL_TEMPERATURE -> if (language == "pl") "TEMP. OLEJU" else "OIL TEMP"
    TelemetryMetric.OIL_PRESSURE -> if (language == "pl") "CIŚN. OLEJU" else "OIL P"
    TelemetryMetric.FUEL_PRESSURE -> if (language == "pl") "PALIWO" else "FUEL"
    TelemetryMetric.BATTERY_VOLTAGE -> if (language == "pl") "AKUMULATOR" else "BATTERY"
    TelemetryMetric.SPEED -> if (language == "pl") "PRĘDKOŚĆ" else "SPEED"
    else -> shortName
}

@Composable
internal fun DashboardWidgetKind.localizedName(): String = when (this) {
    DashboardWidgetKind.HERO -> appText("hero", "główna")
    DashboardWidgetKind.GROUP -> appText("group", "grupa")
    DashboardWidgetKind.VALUE -> appText("value", "wartość")
    DashboardWidgetKind.GAUGE -> appText("gauge", "zegar")
    DashboardWidgetKind.CHART -> appText("chart", "wykres")
    DashboardWidgetKind.COMPACT -> appText("compact", "mała")
    DashboardWidgetKind.PERFORMANCE -> appText("acceleration", "przyspieszenie")
}
