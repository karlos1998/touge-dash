package it.letscode.tougedash.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import java.text.DateFormat
import java.util.Date

@Composable
fun AlertsScreen(container: AppContainer, connectedHardwareId: String?) {
    val vehicles by container.dao.vehicles().collectAsState(initial = emptyList())
    var selectedHardwareId by remember { mutableStateOf(connectedHardwareId ?: "local-default") }
    LaunchedEffect(connectedHardwareId, vehicles) {
        selectedHardwareId = connectedHardwareId
            ?: vehicles.firstOrNull { it.localHardwareId == selectedHardwareId }?.localHardwareId
            ?: vehicles.firstOrNull()?.localHardwareId
            ?: "local-default"
    }
    val selectedVehicle = vehicles.firstOrNull { it.localHardwareId == selectedHardwareId }
    val stored by container.alertRepository.rules(selectedHardwareId).collectAsState(initial = VehicleAlertRules())
    val configuration by container.alertRepository.configuration(selectedHardwareId).collectAsState(initial = null)
    val conflict by container.alertRepository.conflict(selectedHardwareId).collectAsState(initial = null)
    var rules by remember(selectedHardwareId) { mutableStateOf(stored) }
    var vehicleMenu by remember { mutableStateOf(false) }
    val canEdit = selectedVehicle == null || selectedVehicle.role == "OWNER" || selectedVehicle.role == "MECHANIC"
    val scope = rememberCoroutineScope()
    LaunchedEffect(stored, selectedHardwareId, connectedHardwareId) {
        rules = stored
        if (selectedHardwareId == connectedHardwareId) container.incidentEngine.rules = stored
    }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Text(appText("ENGINE PROTECTION", "OCHRONA SILNIKA"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(appText("Alert center", "Centrum alertów"), fontSize = 34.sp, fontWeight = FontWeight.Black)
            Text(appText("Limits are assigned to this vehicle and work offline while a drive is being recorded.", "Progi są przypisane do tego auta i działają offline podczas zapisu przejazdu."), color = TougeMuted)
        }
        conflict?.let { remote ->
            item {
                TougePanelSurface(TougeOrange, Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(appText("ALERT LIMITS CHANGED ONLINE", "PROGI ZMIENIONO ONLINE"), color = TougeOrange, fontSize = 10.sp, fontWeight = FontWeight.Black)
                        Text(
                            appText(
                                "${remote.updatedByDisplayName ?: "Another user"} saved a newer revision. Choose which version to keep.",
                                "${remote.updatedByDisplayName ?: "Inny użytkownik"} zapisał nowszą wersję. Wybierz, które ustawienia zachować."
                            ),
                            color = TougeMuted,
                            fontSize = 11.sp
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { scope.launch { container.alertRepository.acceptRemote(selectedHardwareId) } }, modifier = Modifier.weight(1f)) { Text(appText("Use online", "Użyj online")) }
                            Button(onClick = { scope.launch { container.alertRepository.keepLocal(selectedHardwareId); container.cloudSyncRepository.schedule() } }, modifier = Modifier.weight(1f)) { Text(appText("Keep mine", "Zachowaj moje")) }
                        }
                    }
                }
            }
        }
        item {
            TougePanelSurface(TougeCyan, Modifier.fillMaxWidth()) {
                Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(selectedVehicle?.displayName ?: appText("Local configuration", "Konfiguracja lokalna"), fontWeight = FontWeight.Black, fontSize = 18.sp)
                        val status = when {
                            configuration?.dirty == true -> appText("Changes waiting for cloud sync", "Zmiany czekają na synchronizację")
                            configuration?.updatedAt != null -> "${appText("Last change", "Ostatnia zmiana")}: ${configuration?.updatedByDisplayName ?: "Touge Dash"} · ${DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(configuration!!.updatedAt))}"
                            else -> appText("Default Touge Dash limits", "Domyślne progi Touge Dash")
                        }
                        Text(status, color = if (configuration?.dirty == true) TougeOrange else TougeMuted, fontSize = 10.sp)
                    }
                    Text("R${configuration?.revision ?: 1}", color = TougeMuted, fontWeight = FontWeight.Black)
                    if (vehicles.size > 1) {
                        Box {
                            TextButton(onClick = { vehicleMenu = true }) { Text(appText(" CAR ▾", " AUTO ▾")) }
                            DropdownMenu(vehicleMenu, { vehicleMenu = false }) {
                                vehicles.forEach { vehicle -> DropdownMenuItem(text = { Text(vehicle.displayName) }, onClick = { vehicleMenu = false; selectedHardwareId = vehicle.localHardwareId }) }
                            }
                        }
                    }
                }
            }
        }
        if (!canEdit) item { Text(appText("You have read-only access to this vehicle. Only the owner or a mechanic can change its alert limits.", "Masz dostęp tylko do odczytu. Progi może zmienić właściciel albo mechanik."), color = TougeOrange, modifier = Modifier.padding(12.dp)) }
        item {
            Row(Modifier.fillMaxWidth().background(TougeMint.copy(alpha = .08f), CutCornerShape(9.dp)).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Security, null, tint = TougeMint)
                Column(Modifier.padding(start = 12.dp)) { Text(appText("READ-ONLY DATA ANALYSIS", "WYŁĄCZNIE ANALIZA DANYCH"), color = TougeMint, fontWeight = FontWeight.Bold, fontSize = 11.sp); Text(appText("Changing these limits never writes anything to the ECU or EMULOGGER.", "Zmiana progów nigdy nie zapisuje niczego do ECU ani EMULOGGERA."), color = TougeMuted, fontSize = 12.sp) }
            }
        }
        item { AlertRuleCard(appText("Oil pressure", "Ciśnienie oleju"), appText("Alarm only above the configured engine speed.", "Alarm tylko powyżej zadanych obrotów silnika."), rules.lowOilPressureEnabled, { rules = rules.copy(lowOilPressureEnabled = it) }, TougeMint, canEdit, listOf(
            RuleField(appText("MINIMUM", "MINIMUM"), rules.minimumOilPressureBar, "bar") { rules = rules.copy(minimumOilPressureBar = it) },
            RuleField(appText("FROM RPM", "OD OBROTÓW"), rules.lowOilMinimumRpm, "rpm") { rules = rules.copy(lowOilMinimumRpm = it) },
            RuleField(appText("FOR", "PRZEZ"), rules.lowOilDurationSeconds, "s") { rules = rules.copy(lowOilDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Lean mixture under boost", "Uboga mieszanka pod doładowaniem"), appText("AFR is checked only after reaching boost.", "AFR jest sprawdzany dopiero po osiągnięciu doładowania."), rules.leanUnderBoostEnabled, { rules = rules.copy(leanUnderBoostEnabled = it) }, TougeOrange, canEdit, listOf(
            RuleField("MAX AFR", rules.maximumAfr, "AFR") { rules = rules.copy(maximumAfr = it) },
            RuleField("FROM BOOST", rules.leanMinimumBoostBar, "bar") { rules = rules.copy(leanMinimumBoostBar = it) },
            RuleField("FOR", rules.leanDurationSeconds, "s") { rules = rules.copy(leanDurationSeconds = it) }
        )) }
        item { AlertRuleCard("Overboost", appText("Maximum permitted boost for this setup.", "Maksymalne dopuszczalne doładowanie dla tego auta."), rules.overboostEnabled, { rules = rules.copy(overboostEnabled = it) }, Color.Red, canEdit, listOf(
            RuleField("MAXIMUM", rules.maximumBoostBar, "bar") { rules = rules.copy(maximumBoostBar = it) }, RuleField("FOR", rules.overboostDurationSeconds, "s") { rules = rules.copy(overboostDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Coolant temperature", "Temperatura płynu"), appText("Critical engine coolant warning.", "Krytyczne ostrzeżenie temperatury płynu."), rules.highCoolantTemperatureEnabled, { rules = rules.copy(highCoolantTemperatureEnabled = it) }, Color.Red, canEdit, listOf(
            RuleField("MAXIMUM", rules.maximumCoolantCelsius, "°C") { rules = rules.copy(maximumCoolantCelsius = it) }, RuleField("FOR", rules.coolantDurationSeconds, "s") { rules = rules.copy(coolantDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Oil temperature", "Temperatura oleju"), appText("Critical engine oil warning.", "Krytyczne ostrzeżenie temperatury oleju."), rules.highOilTemperatureEnabled, { rules = rules.copy(highOilTemperatureEnabled = it) }, TougeOrange, canEdit, listOf(
            RuleField("MAXIMUM", rules.maximumOilTemperatureCelsius, "°C") { rules = rules.copy(maximumOilTemperatureCelsius = it) }, RuleField("FOR", rules.oilTemperatureDurationSeconds, "s") { rules = rules.copy(oilTemperatureDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Battery voltage", "Napięcie akumulatora"), appText("Checked only while the engine is running.", "Sprawdzane wyłącznie podczas pracy silnika."), rules.lowBatteryVoltageEnabled, { rules = rules.copy(lowBatteryVoltageEnabled = it) }, TougeCyan, canEdit, listOf(
            RuleField("MINIMUM", rules.minimumBatteryVoltage, "V") { rules = rules.copy(minimumBatteryVoltage = it) }, RuleField("FROM RPM", rules.lowBatteryMinimumRpm, "rpm") { rules = rules.copy(lowBatteryMinimumRpm = it) }, RuleField("FOR", rules.lowBatteryDurationSeconds, "s") { rules = rules.copy(lowBatteryDurationSeconds = it) }
        )) }
        item { AlertRuleCard(appText("Fuel pressure", "Ciśnienie paliwa"), appText("Disabled by default; enable after confirming the EMU channel.", "Domyślnie wyłączone; włącz po potwierdzeniu kanału w EMU."), rules.lowFuelPressureEnabled, { rules = rules.copy(lowFuelPressureEnabled = it) }, TougeOrange, canEdit, listOf(
            RuleField("MINIMUM", rules.minimumFuelPressureBar, "bar") { rules = rules.copy(minimumFuelPressureBar = it) }, RuleField("FROM RPM", rules.lowFuelPressureMinimumRpm, "rpm") { rules = rules.copy(lowFuelPressureMinimumRpm = it) }, RuleField("FOR", rules.lowFuelPressureDurationSeconds, "s") { rules = rules.copy(lowFuelPressureDurationSeconds = it) }
        )) }
        item {
            TougePanelSurface(TougeCyan, Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp)) {
                    Text(appText("TIME BETWEEN REPORTS", "ODSTĘP MIĘDZY RAPORTAMI"), color = TougeMuted, fontSize = 9.sp, fontWeight = FontWeight.Black)
                    Text(appText("The same rule will not create another report before this time passes.", "Ta sama reguła nie utworzy kolejnego raportu przed upływem tego czasu."), color = TougeMuted, fontSize = 10.sp)
                    OutlinedTextField(rules.cooldownSeconds.toString(), { input -> input.toIntOrNull()?.let { rules = rules.copy(cooldownSeconds = it) } }, enabled = canEdit, label = { Text(appText("Seconds", "Sekundy")) }, singleLine = true)
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(enabled = canEdit, onClick = { rules = VehicleAlertRules() }, modifier = Modifier.weight(1f)) { Icon(Icons.Default.Restore, null); Text(appText(" Defaults", " Domyślne")) }
                Button(enabled = canEdit && rules != stored, onClick = {
                    scope.launch {
                        container.alertRepository.save(selectedHardwareId, rules)
                        if (selectedHardwareId == connectedHardwareId) container.incidentEngine.rules = rules
                        container.cloudSyncRepository.schedule()
                    }
                }, modifier = Modifier.weight(1f)) {
                    Icon(if (container.authRepository.isAuthenticated) Icons.Default.CloudUpload else Icons.Default.CheckCircle, null)
                    Text(appText(" Save limits", " Zapisz progi"))
                }
            }
        }
    }
}

private data class RuleField(val label: String, val value: Double, val unit: String, val changed: (Double) -> Unit)

@Composable
private fun AlertRuleCard(title: String, subtitle: String, enabled: Boolean, toggle: (Boolean) -> Unit, accent: Color, editable: Boolean, fields: List<RuleField>) {
    TougePanelSurface(accent, Modifier.fillMaxWidth()) {
        Column(Modifier.padding(15.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) { Text(title, fontWeight = FontWeight.Black, fontSize = 19.sp); Text(subtitle, color = TougeMuted, fontSize = 12.sp) }
                Switch(enabled, toggle, enabled = editable)
            }
            if (enabled) Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                fields.forEach { field ->
                    var text by remember(field.value) { mutableStateOf(field.value.toDisplay()) }
                    OutlinedTextField(text, { input -> text = input; input.replace(',', '.').toDoubleOrNull()?.let(field.changed) }, enabled = editable, label = { Text(field.label, fontSize = 8.sp) }, suffix = { Text(field.unit, color = accent, fontSize = 9.sp) }, singleLine = true, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

private fun Double.toDisplay(): String = if (this % 1.0 == 0.0) toInt().toString() else toString()
