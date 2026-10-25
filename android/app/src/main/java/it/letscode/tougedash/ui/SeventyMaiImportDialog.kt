package it.letscode.tougedash.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.data.local.DriveSessionEntity
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.video.SeventyMaiCameraModel

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SeventyMaiImportDialog(container: AppContainer, session: DriveSessionEntity, close: () -> Unit) {
    val context = LocalContext.current
    val state by container.seventyMaiImporter.state.collectAsState()
    var model by remember { mutableStateOf(SeventyMaiCameraModel.M300) }
    var rear by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = close,
        title = { Text(appText("70mai camera", "Kamera 70mai"), fontWeight = FontWeight.Black) },
        text = {
            Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(appText("Turn on camera Wi-Fi and connect this phone to its network. Keep the camera powered while importing.", "Włącz Wi-Fi kamery i połącz telefon z jej siecią. Podczas importu kamera musi pozostać zasilana."))
                OutlinedButton(onClick = { context.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)) }, enabled = !state.busy) { Text(appText("Open Wi-Fi settings", "Otwórz ustawienia Wi-Fi")) }
                Text(appText("CAMERA MODEL", "MODEL KAMERY"), color = MaterialTheme.colorScheme.primary, fontSize = 10.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    SeventyMaiCameraModel.entries.forEach { candidate -> FilterChip(model == candidate, { model = candidate; rear = false; container.seventyMaiImporter.clear() }, enabled = !state.busy, label = { Text(candidate.title) }) }
                }
                if (model.rearCamera) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(!rear, { rear = false; container.seventyMaiImporter.clear() }, enabled = !state.busy, label = { Text(appText("Front", "Przód")) })
                    FilterChip(rear, { rear = true; container.seventyMaiImporter.clear() }, enabled = !state.busy, label = { Text(appText("Rear", "Tył")) })
                }
                if (state.stage.isNotEmpty()) Text(when {
                    state.stage == "AUTHORIZE" -> appText("Connecting to camera…", "Łączenie z kamerą…")
                    state.stage == "CONFIRM_ON_CAMERA" -> appText("Press the camera power button once to authorize this phone.", "Naciśnij raz przycisk zasilania kamery, aby potwierdzić połączenie.")
                    state.stage == "READ_CLOCK" -> appText("Checking camera clock…", "Sprawdzanie zegara kamery…")
                    state.stage.startsWith("READ_FILES") -> appText("Reading recordings…", "Odczytywanie nagrań…")
                    state.stage.startsWith("DOWNLOAD") -> appText("Downloading clips", "Pobieranie klipów") + " " + state.stage.substringAfter(':', "")
                    state.stage == "JOIN" -> appText("Joining clips and preserving their timeline…", "Łączenie klipów z zachowaniem osi czasu…")
                    state.stage == "DONE" -> appText("Video is ready in this drive.", "Film jest gotowy w tym przejeździe.")
                    else -> appText("Ready to import", "Gotowe do importu")
                }, fontWeight = FontWeight.Bold)
                if (state.busy) {
                    LinearProgressIndicator(progress = { state.progress }, modifier = Modifier.fillMaxWidth())
                    if (state.totalBytes > 0) Text("${state.receivedBytes / 1_048_576} / ${state.totalBytes / 1_048_576} MB")
                }
                state.scan?.let { scan ->
                    Text("${scan.clips.size} " + appText("clips overlap this drive", "klipów pokrywa się z przejazdem"))
                    Text(scan.clockOffsetMillis?.let { appText("Camera clock correction", "Korekta zegara kamery") + ": %.1f s".format(it / 1000.0) }
                        ?: appText("Camera clock could not be verified. Check alignment in the editor after importing.", "Nie udało się sprawdzić zegara kamery. Po imporcie sprawdź dopasowanie w edytorze."), fontSize = 11.sp)
                }
                state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Text(appText("Files stay on this device. Completed clips can be reused if you retry the import.", "Pliki pozostają na tym urządzeniu. Ponowienie importu wykorzysta już pobrane klipy."), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        confirmButton = {
            if (state.projectId != null) TextButton(onClick = close) { Text(appText("Done", "Gotowe")) }
            else Button(enabled = !state.busy && !container.videoRepository.isBusy, onClick = {
                if (state.scan == null) container.seventyMaiImporter.scan(session, model, rear) else container.seventyMaiImporter.download(session)
            }) { Text(if (state.scan == null) appText("Find recordings", "Znajdź nagrania") else appText("Import matching clips", "Importuj pasujące klipy")) }
        },
        dismissButton = { TextButton(onClick = { if (state.busy) container.seventyMaiImporter.cancel() else close() }) { Text(if (state.busy) appText("Cancel", "Anuluj") else appText("Close", "Zamknij")) } }
    )
}
