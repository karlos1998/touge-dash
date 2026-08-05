package it.letscode.tougedash.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.model.VehicleAlertRules
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougeOrange
import kotlinx.coroutines.launch

@Composable
fun AlertsScreen(container: AppContainer, hardwareId: String) {
    val stored by container.alertRepository.rules(hardwareId).collectAsState(initial = VehicleAlertRules())
    var rules by remember(hardwareId) { mutableStateOf(stored) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(stored) { rules = stored; container.incidentEngine.rules = stored }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Text(appText("ENGINE PROTECTION", "OCHRONA SILNIKA"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(appText("Alert center", "Centrum alertów"), fontSize = 34.sp, fontWeight = FontWeight.Black)
            Text(appText("Limits are assigned to this vehicle and work offline while a drive is being recorded.", "Progi są przypisane do tego auta i działają offline podczas zapisu przejazdu."), color = TougeMuted)
        }
        item {
            Row(Modifier.fillMaxWidth().background(TougeMint.copy(alpha = .08f), CutCornerShape(9.dp)).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Security, null, tint = TougeMint)
                Column(Modifier.padding(start = 12.dp)) { Text(appText("READ-ONLY DATA ANALYSIS", "WYŁĄCZNIE ANALIZA DANYCH"), color = TougeMint, fontWeight = FontWeight.Bold, fontSize = 11.sp); Text(appText("Changing these limits never writes anything to the ECU or EMULOGGER.", "Zmiana progów nigdy nie zapisuje niczego do ECU ani EMULOGGERA."), color = TougeMuted, fontSize = 12.sp) }
            }
        }
        item { AlertRuleCard(appText("Oil pressure", "Ciśnienie oleju"), appText("Alarm only above the configured engine speed.", "Alarm tylko powyżej zadanych obrotów silnika."), rules.lowOilPressureEnabled, { rules = rules.copy(lowOilPressureEnabled = it) }, TougeMint, listOf(
            RuleField(appText("MINIMUM", "MINIMUM"), rules.minimumOilPressureBar, "bar") { rules = rules.copy(minimumOilPressureBar = it) },
            RuleField(appText("FROM RPM", "OD OBROTÓW"), rules.lowOilMinimumRpm, "rpm") { rules = rules.copy(lowOilMinimumRpm = it) },
            RuleField(appText("FOR", "PRZEZ"), rules.lowOilDurationSeconds, "s") { rules = rules.copy(lowOilDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Lean mixture under boost", "Uboga mieszanka pod doładowaniem"), appText("AFR is checked only after reaching boost.", "AFR jest sprawdzany dopiero po osiągnięciu doładowania."), rules.leanUnderBoostEnabled, { rules = rules.copy(leanUnderBoostEnabled = it) }, TougeOrange, listOf(
            RuleField("MAX AFR", rules.maximumAfr, "AFR") { rules = rules.copy(maximumAfr = it) },
            RuleField("FROM BOOST", rules.leanMinimumBoostBar, "bar") { rules = rules.copy(leanMinimumBoostBar = it) },
            RuleField("FOR", rules.leanDurationSeconds, "s") { rules = rules.copy(leanDurationSeconds = it) }
        )) }
        item { AlertRuleCard("Overboost", appText("Maximum permitted boost for this setup.", "Maksymalne dopuszczalne doładowanie dla tego auta."), rules.overboostEnabled, { rules = rules.copy(overboostEnabled = it) }, Color.Red, listOf(
            RuleField("MAXIMUM", rules.maximumBoostBar, "bar") { rules = rules.copy(maximumBoostBar = it) }, RuleField("FOR", rules.overboostDurationSeconds, "s") { rules = rules.copy(overboostDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Coolant temperature", "Temperatura płynu"), appText("Critical engine coolant warning.", "Krytyczne ostrzeżenie temperatury płynu."), rules.highCoolantTemperatureEnabled, { rules = rules.copy(highCoolantTemperatureEnabled = it) }, Color.Red, listOf(
            RuleField("MAXIMUM", rules.maximumCoolantCelsius, "°C") { rules = rules.copy(maximumCoolantCelsius = it) }, RuleField("FOR", rules.coolantDurationSeconds, "s") { rules = rules.copy(coolantDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Oil temperature", "Temperatura oleju"), appText("Critical engine oil warning.", "Krytyczne ostrzeżenie temperatury oleju."), rules.highOilTemperatureEnabled, { rules = rules.copy(highOilTemperatureEnabled = it) }, TougeOrange, listOf(
            RuleField("MAXIMUM", rules.maximumOilTemperatureCelsius, "°C") { rules = rules.copy(maximumOilTemperatureCelsius = it) }, RuleField("FOR", rules.oilTemperatureDurationSeconds, "s") { rules = rules.copy(oilTemperatureDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Battery voltage", "Napięcie akumulatora"), appText("Checked only while the engine is running.", "Sprawdzane wyłącznie podczas pracy silnika."), rules.lowBatteryVoltageEnabled, { rules = rules.copy(lowBatteryVoltageEnabled = it) }, TougeCyan, listOf(
            RuleField("MINIMUM", rules.minimumBatteryVoltage, "V") { rules = rules.copy(minimumBatteryVoltage = it) }, RuleField("FROM RPM", rules.lowBatteryMinimumRpm, "rpm") { rules = rules.copy(lowBatteryMinimumRpm = it) }, RuleField("FOR", rules.lowBatteryDurationSeconds, "s") { rules = rules.copy(lowBatteryDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Fuel pressure", "Ciśnienie paliwa"), appText("Disabled by default; enable after confirming the EMU channel.", "Domyślnie wyłączone; włącz po potwierdzeniu kanału w EMU."), rules.lowFuelPressureEnabled, { rules = rules.copy(lowFuelPressureEnabled = it) }, TougeOrange, listOf(
            RuleField("MINIMUM", rules.minimumFuelPressureBar, "bar") { rules = rules.copy(minimumFuelPressureBar = it) }, RuleField("FROM RPM", rules.lowFuelPressureMinimumRpm, "rpm") { rules = rules.copy(lowFuelPressureMinimumRpm = it) }, RuleField("FOR", rules.lowFuelPressureDurationSeconds, "s") { rules = rules.copy(lowFuelPressureDurationSeconds = it) }
        )) }
        item {
            Button(onClick = { scope.launch { container.alertRepository.save(hardwareId, rules); container.incidentEngine.rules = rules } }, Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Icon(Icons.Default.CheckCircle, null); Text(appText(" Save limits for this vehicle", " Zapisz progi dla tego auta"))
            }
        }
    }
}

private data class RuleField(val label: String, val value: Double, val unit: String, val changed: (Double) -> Unit)

@Composable
private fun AlertRuleCard(title: String, subtitle: String, enabled: Boolean, toggle: (Boolean) -> Unit, accent: Color, fields: List<RuleField>) {
    TougePanelSurface(accent, Modifier.fillMaxWidth()) {
        Column(Modifier.padding(15.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) { Text(title, fontWeight = FontWeight.Black, fontSize = 19.sp); Text(subtitle, color = TougeMuted, fontSize = 12.sp) }
                Switch(enabled, toggle)
            }
            if (enabled) Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                fields.forEach { field ->
                    var text by remember(field.value) { mutableStateOf(field.value.toDisplay()) }
                    OutlinedTextField(text, { input -> text = input; input.replace(',', '.').toDoubleOrNull()?.let(field.changed) }, label = { Text(field.label, fontSize = 8.sp) }, suffix = { Text(field.unit, color = accent, fontSize = 9.sp) }, singleLine = true, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

private fun Double.toDisplay(): String = if (this % 1.0 == 0.0) toInt().toString() else toString()
