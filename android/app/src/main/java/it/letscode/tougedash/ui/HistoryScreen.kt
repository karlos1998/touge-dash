package it.letscode.tougedash.ui

import android.content.Intent
import android.graphics.Paint as AndroidPaint
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.NoteAdd
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.intl.Locale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import it.letscode.tougedash.data.local.AnnotationEntity
import it.letscode.tougedash.data.local.DriveSessionEntity
import it.letscode.tougedash.data.local.IncidentEntity
import it.letscode.tougedash.data.local.SyncState
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import it.letscode.tougedash.data.local.AccelerationAttemptEntity
import it.letscode.tougedash.data.local.VideoProjectEntity
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.history.CapturedTelemetryPoint
import it.letscode.tougedash.history.DriveShareRange
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougeOrange
import it.letscode.tougedash.ui.theme.TougePanel
import it.letscode.tougedash.ui.theme.TougeRed
import kotlinx.coroutines.launch
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import org.osmdroid.config.Configuration
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Polyline
import java.text.DateFormat
import java.util.Date
import java.util.UUID
import kotlin.math.roundToInt
import kotlin.math.abs
import it.letscode.tougedash.performance.AccelerationType

@Composable
fun HistoryScreen(container: AppContainer, selectedId: String?, select: (String) -> Unit, back: () -> Unit) {
    if (selectedId == null) SessionList(container, select) else SessionDetail(container, selectedId, back)
}

@Composable
private fun SessionList(container: AppContainer, select: (String) -> Unit) {
    val sessions by container.historyRepository.sessions.collectAsState(initial = emptyList())
    val videos by container.historyRepository.videos.collectAsState(initial = emptyList())
    val localArchiveBytes by container.historyRepository.storageBytes.collectAsState(initial = 0L)
    val activeSession by container.historyRepository.activeSession.collectAsState()
    val connection by container.runtime.connection.collectAsState()
    var deleteSession by remember { mutableStateOf<DriveSessionEntity?>(null) }
    var showSplitConfirmation by remember { mutableStateOf(false) }
    val canSplit = connection.state == ConnectionState.Connected && activeSession != null
    Column(Modifier.fillMaxSize()) {
        Text(appText("DRIVE ARCHIVE", "ARCHIWUM PRZEJAZDÓW"), color = TougeCyan, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 18.dp, top = 18.dp))
        Text(appText("History", "Historia"), fontSize = 34.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(horizontal = 18.dp))
        if (canSplit) {
            ManualSessionSplitCard(activeSession!!.sampleCount) { showSplitConfirmation = true }
        }
        if (sessions.isEmpty()) {
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Icon(Icons.Default.DirectionsCar, null, Modifier.size(54.dp), tint = TougeMuted)
                Text(appText("No recorded drives yet", "Nie ma jeszcze zapisanych przejazdów"), color = TougeMuted, modifier = Modifier.padding(top = 14.dp))
            }
        } else LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(sessions, key = { it.id }) { session ->
                SessionRow(session, sessionTags(container, session), videos.filter { it.sessionId == session.id }, select) { deleteSession = session }
            }
            item { LocalArchiveStorageFooter(localArchiveBytes) }
        }
    }
    if (showSplitConfirmation) {
        AlertDialog(
            onDismissRequest = { showSplitConfirmation = false },
            title = { Text(appText("Split the current drive?", "Podziel bieżący przejazd?")) },
            text = {
                Text(
                    appText(
                        "Existing data will remain in the first drive. Bluetooth will stay connected and subsequent samples will be recorded as a new drive. An active video and acceleration measurement will be split at the same point.",
                        "Dotychczasowe dane pozostaną w pierwszym przejeździe. Bluetooth pozostanie połączony, a kolejne próbki trafią do nowego przejazdu. Aktywne nagranie i trwający pomiar przyspieszenia zostaną rozdzielone w tym samym miejscu."
                    ),
                    color = TougeMuted
                )
            },
            confirmButton = {
                Button(onClick = {
                    container.runtime.requestDriveSplit()
                    showSplitConfirmation = false
                }) { Text(appText("Save and start a new drive", "Zapisz i rozpocznij nowy")) }
            },
            dismissButton = {
                TextButton(onClick = { showSplitConfirmation = false }) { Text(appText("Cancel", "Anuluj")) }
            }
        )
    }
    deleteSession?.let { session ->
        AlertDialog(
            onDismissRequest = { deleteSession = null },
            title = { Text(appText("Delete this drive?", "Usunąć ten przejazd?")) },
            text = { Text(appText("Telemetry, incident reports, notes and local source videos assigned to this drive will be removed from this device.", "Telemetria, raporty incydentów, notatki i lokalne filmy źródłowe przypisane do przejazdu zostaną usunięte z urządzenia."), color = TougeMuted) },
            confirmButton = { Button(onClick = {
                container.applicationScope.launch {
                    container.videoRepository.deleteForSession(session.id)
                    container.dao.deleteSessionCascade(session.id)
                }
                deleteSession = null
            }) { Text(appText("Delete", "Usuń")) } },
            dismissButton = { TextButton(onClick = { deleteSession = null }) { Text(appText("Cancel", "Anuluj")) } }
        )
    }
}

@Composable
private fun LocalArchiveStorageFooter(storageBytes: Long) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = .025f), RoundedCornerShape(8.dp))
            .padding(horizontal = 15.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.Storage, null, tint = TougeCyan, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
            Text(appText("LOCAL ARCHIVE", "LOKALNE ARCHIWUM"), fontSize = 9.sp, fontWeight = FontWeight.Black)
            Text(
                appText("Drive telemetry and videos on this device", "Telemetria i filmy z przejazdów na tym urządzeniu"),
                color = TougeMuted,
                fontSize = 10.sp
            )
        }
        Text(bytes(storageBytes), color = TougeMint, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun ManualSessionSplitCard(sampleCount: Int, split: () -> Unit) {
    TougePanelSurface(TougeCyan, Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp)) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(42.dp).background(TougeCyan.copy(alpha = .13f), RoundedCornerShape(10.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.ContentCut, null, tint = TougeCyan)
                }
                Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                    Text(appText("CURRENT DRIVE", "BIEŻĄCY PRZEJAZD"), fontSize = 11.sp, fontWeight = FontWeight.Black)
                    Text(
                        appText("$sampleCount samples · recording", "$sampleCount próbek · zapis trwa"),
                        color = TougeMuted,
                        fontSize = 12.sp
                    )
                }
                Box(Modifier.size(8.dp).background(TougeMint, RoundedCornerShape(50)))
            }
            Text(
                appText(
                    "Finish the current recording without disconnecting EMULOGGER. The next sample will start a separate drive.",
                    "Zamknij bieżący zapis bez rozłączania EMULOGGERA. Następna próbka rozpocznie osobny przejazd."
                ),
                color = TougeMuted,
                fontSize = 11.sp,
                modifier = Modifier.padding(top = 12.dp)
            )
            Button(onClick = split, modifier = Modifier.fillMaxWidth().padding(top = 12.dp)) {
                Icon(Icons.Default.ContentCut, null, Modifier.size(17.dp))
                Text(appText("Save and start a new drive", "Zapisz i rozpocznij nowy"), modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

@Composable
private fun SessionRow(session: DriveSessionEntity, tags: List<it.letscode.tougedash.cloud.CloudSyncRepository.DriveTag>, videos: List<VideoProjectEntity>, select: (String) -> Unit, delete: (DriveSessionEntity) -> Unit) {
    val accent = when (session.syncState) {
        SyncState.SYNCED -> TougeMint
        SyncState.FAILED -> TougeRed
        SyncState.UPLOADING -> TougeCyan
        else -> TougeOrange
    }
    TougePanelSurface(accent, Modifier.fillMaxWidth().clickable { select(session.id) }) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Text(session.customName ?: DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(session.startedAt)), fontWeight = FontWeight.Bold)
                    if (session.customName != null) Text(DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(session.startedAt)), color = TougeMuted, fontSize = 10.sp)
                    Text("${duration(session.endedAt - session.startedAt)}  •  ${session.sampleCount} ${appText("samples", "próbek")}", color = TougeMuted, fontSize = 12.sp)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SyncBadge(session)
                    IconButton(onClick = { delete(session) }) { Icon(Icons.Default.Delete, appText("Delete drive", "Usuń przejazd"), tint = TougeRed) }
                }
            }
            if (tags.isNotEmpty()) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                tags.forEach { tag -> DriveTagChip(tag) }
            }
            if (videos.isNotEmpty()) {
                Row(
                    Modifier.padding(top = 9.dp).background(TougeCyan.copy(alpha = .1f), RoundedCornerShape(6.dp)).padding(horizontal = 9.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Videocam, null, tint = TougeCyan, modifier = Modifier.size(16.dp))
                    Text(
                        appText(
                            "${videos.size} ${if (videos.size == 1) "recording" else "recordings"} · ${bytes(videos.sumOf { it.fileSizeBytes })}",
                            "${videos.size} ${if (videos.size == 1) "nagranie" else "nagrania"} · ${bytes(videos.sumOf { it.fileSizeBytes })}"
                        ),
                        color = TougeCyan,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(start = 6.dp)
                    )
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                MiniValue(appText("MAX BOOST", "MAX DOŁADOWANIE"), "${"%.2f".format(session.maxBoostBar)} bar", TougeCyan)
                MiniValue(appText("MAX OIL", "MAX OLEJ"), "${session.maxOilTemperatureCelsius.roundToInt()}°C", TougeOrange)
                MiniValue(appText("MAX COOLANT", "MAX PŁYN"), "${session.maxCoolantCelsius.roundToInt()}°C", TougeMint)
            }
            if (session.syncState == SyncState.UPLOADING || session.syncProgress > 0f && session.syncProgress < 1f) {
                LinearProgressIndicator(progress = { session.syncProgress }, modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
                Text("${(session.syncProgress * 100).roundToInt()}%  •  ${bytes(session.syncBytesSent)} / ${bytes(session.syncBytesTotal)}", color = TougeMuted, fontSize = 10.sp)
            }
            session.syncError?.let { Text(it, color = TougeRed, fontSize = 11.sp, modifier = Modifier.padding(top = 7.dp)) }
        }
    }
}

@Composable
private fun SyncBadge(session: DriveSessionEntity) {
    val (icon, color, text) = when (session.syncState) {
        SyncState.SYNCED -> Triple(Icons.Default.CloudDone, TougeMint, appText("SYNCED", "ZSYNCHRONIZOWANO"))
        SyncState.FAILED -> Triple(Icons.Default.Error, TougeRed, appText("ERROR", "BŁĄD"))
        SyncState.UPLOADING -> Triple(Icons.Default.CloudDone, TougeCyan, appText("SYNCING", "SYNCHRONIZACJA"))
        else -> Triple(Icons.Default.CloudOff, TougeOrange, appText("LOCAL", "LOKALNIE"))
    }
    Row(verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, Modifier.size(16.dp), tint = color); Text(text, color = color, fontSize = 9.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 4.dp)) }
}

@Composable
private fun MiniValue(title: String, value: String, color: Color) {
    Column { Text(title, color = TougeMuted, fontSize = 8.sp, fontWeight = FontWeight.Bold); Text(value, color = color, fontWeight = FontWeight.Black) }
}

@Composable
private fun SessionDetail(container: AppContainer, id: String, back: () -> Unit) {
    val session by container.historyRepository.session(id).collectAsState(initial = null)
    val samples by container.historyRepository.samples(id).collectAsState(initial = emptyList())
    val rawSamples by container.historyRepository.rawSamples(id).collectAsState(initial = emptyList())
    val incidents by container.historyRepository.incidents(id).collectAsState(initial = emptyList())
    val annotations by container.historyRepository.annotations(id).collectAsState(initial = emptyList())
    val accelerationAttempts by container.historyRepository.accelerationAttempts(id).collectAsState(initial = emptyList())
    var scrubber by remember(id) { mutableFloatStateOf(0f) }
    var noteDialog by remember { mutableStateOf(false) }
    var selectedIncident by remember(id) { mutableStateOf<IncidentEntity?>(null) }
    var showMetadata by remember(id) { mutableStateOf(false) }
    var showShare by remember(id) { mutableStateOf(false) }
    // chartEligible is only an optimization for long drives. Never let a bad or
    // incomplete eligibility set make an otherwise valid drive look empty.
    val chartSamples = if (samples.size >= 2 || rawSamples.isEmpty()) samples else rawSamples
    val selected = session?.let { nearestSample(chartSamples, it.startedAt + ((it.endedAt - it.startedAt) * scrubber).toLong()) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 30.dp)) {
        item {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null) }
                Column(Modifier.weight(1f)) {
                    Text(appText("DRIVE REPORT", "RAPORT PRZEJAZDU"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    Text(session?.let { it.customName ?: DateFormat.getDateTimeInstance().format(Date(it.startedAt)) } ?: "…", fontWeight = FontWeight.Black)
                }
                if (session != null) {
                    IconButton(onClick = { showMetadata = true }) { Icon(Icons.Default.Edit, appText("Edit name and tags", "Edytuj nazwę i tagi"), tint = TougeCyan) }
                    IconButton(onClick = { showShare = true }) { Icon(Icons.Default.Share, appText("Share drive", "Udostępnij przejazd"), tint = TougeMint) }
                }
                IconButton(onClick = { noteDialog = true }) { Icon(Icons.AutoMirrored.Filled.NoteAdd, null, tint = TougeMint) }
            }
        }
        if (session == null) item { Box(Modifier.fillMaxWidth().height(300.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        else {
            item { SessionSummary(session!!) }
            val detailTags = sessionTags(container, session!!)
            if (detailTags.isNotEmpty()) item {
                Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    detailTags.forEach { DriveTagChip(it) }
                }
            }
            if (session!!.syncState == SyncState.FAILED) item {
                Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp)) {
                    Text(session!!.syncError ?: appText("Synchronization failed", "Synchronizacja nie powiodła się"), color = TougeRed, fontSize = 11.sp)
                    Button(onClick = { container.cloudSyncRepository.schedule() }, modifier = Modifier.fillMaxWidth().padding(top = 7.dp)) { Text(appText("Retry synchronization", "Ponów synchronizację")) }
                }
            }
            if (incidents.isNotEmpty()) item { IncidentSection(incidents, session!!.startedAt) { incident ->
                scrubber = ((incident.triggeredAt - session!!.startedAt).toFloat() / (session!!.endedAt - session!!.startedAt).coerceAtLeast(1)).coerceIn(0f, 1f)
                selectedIncident = incident
            } }
            if (accelerationAttempts.isNotEmpty()) item { AccelerationSection(accelerationAttempts, session!!.startedAt) { attempt ->
                scrubber = ((attempt.startedAt - session!!.startedAt).toFloat() / (session!!.endedAt - session!!.startedAt).coerceAtLeast(1)).coerceIn(0f, 1f)
            } }
            if (chartSamples.isEmpty()) item { MissingTelemetryCard(session!!.sampleCount) }
            else {
                item {
                    TelemetryCursor(selected, session!!.startedAt)
                    Slider(scrubber, { scrubber = it }, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp))
                    Text(appText("Move the time cursor; the page remains vertically scrollable", "Przesuwaj kursor czasu; stronę nadal możesz przewijać pionowo"), color = TougeMuted, fontSize = 10.sp, modifier = Modifier.padding(horizontal = 18.dp))
                }
                val updateCursor: (Long) -> Unit = { timestamp ->
                    scrubber = ((timestamp - session!!.startedAt).toFloat() / (session!!.endedAt - session!!.startedAt).coerceAtLeast(1)).coerceIn(0f, 1f)
                }
                item { TelemetryChart(appText("Boost / oil pressure", "Doładowanie / ciśnienie oleju"), chartSamples, selected, session!!.startedAt, session!!.endedAt, accelerationAttempts, listOf(TelemetryMetric.BOOST to TougeCyan, TelemetryMetric.OIL_PRESSURE to TougeMint), updateCursor) }
                item { TelemetryChart(appText("Temperatures", "Temperatury"), chartSamples, selected, session!!.startedAt, session!!.endedAt, accelerationAttempts, listOf(TelemetryMetric.OIL_TEMPERATURE to TougeOrange, TelemetryMetric.COOLANT to TougeCyan), updateCursor) }
                item { TelemetryChart("EGT", chartSamples, selected, session!!.startedAt, session!!.endedAt, accelerationAttempts, listOf(TelemetryMetric.EGT1 to TougeOrange, TelemetryMetric.EGT2 to TougeRed), updateCursor) }
                item { TelemetryChart(appText("RPM / speed", "Obroty / prędkość"), chartSamples, selected, session!!.startedAt, session!!.endedAt, accelerationAttempts, listOf(TelemetryMetric.RPM to TougeRed, TelemetryMetric.SPEED to TougeMint), updateCursor) }
            }
            if (annotations.isNotEmpty()) item { AnnotationSection(annotations, session!!.startedAt) }
            item { DriveVideoSection(container, session!!, rawSamples, scrubber) }
            if (chartSamples.any { it.latitude != null && it.longitude != null }) item { RouteMap(chartSamples) }
        }
    }
    if (noteDialog && session != null) AddNoteDialog { body ->
        noteDialog = false
        if (body != null) container.applicationScope.launch {
            val timestamp = selected?.recordedAt ?: session!!.startedAt
            container.dao.upsertAnnotation(AnnotationEntity(UUID.randomUUID().toString(), session!!.vehicleHardwareId, id, recordedAt = timestamp, body = body))
        }
    }
    selectedIncident?.let { incident -> IncidentReportDialog(incident, container) { selectedIncident = null } }
    if (showMetadata && session != null) DriveMetadataDialog(container, session!!, { showMetadata = false })
    if (showShare && session != null) DriveShareDialog(container, session!!, rawSamples, { showShare = false })
}

@Composable
private fun MissingTelemetryCard(sampleCount: Int) {
    TougePanelSurface(TougeOrange, Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 7.dp)) {
        Column(Modifier.padding(14.dp)) {
            Text(
                appText("TELEMETRY UNAVAILABLE", "BRAK DANYCH TELEMETRYCZNYCH"),
                color = TougeOrange,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                if (sampleCount > 0) appText(
                    "This drive contains a $sampleCount-sample summary, but its sample data was not preserved. Drives recorded after the update will display the timeline and charts correctly.",
                    "Ten przejazd ma podsumowanie obejmujące $sampleCount próbek, ale same dane próbek nie zostały zachowane. Przejazdy nagrane po aktualizacji będą poprawnie wyświetlać oś czasu i wykresy."
                ) else appText(
                    "No telemetry samples were recorded for this drive.",
                    "Dla tego przejazdu nie zapisano próbek telemetrycznych."
                ),
                color = TougeMuted,
                fontSize = 11.sp,
                modifier = Modifier.padding(top = 6.dp)
            )
        }
    }
}

@Composable
private fun SessionSummary(session: DriveSessionEntity) {
    TougePanelSurface(TougeCyan, Modifier.fillMaxWidth().padding(14.dp)) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                MiniValue(appText("DURATION", "CZAS"), duration(session.endedAt - session.startedAt), TougeCyan)
                MiniValue(appText("SAMPLES", "PRÓBKI"), session.sampleCount.toString(), TougeMint)
                MiniValue(appText("DISTANCE", "DYSTANS"), "%.1f km".format(session.distanceMeters / 1000), TougeOrange)
            }
            Spacer(Modifier.height(12.dp)); SyncBadge(session)
            if (session.syncProgress > 0 && session.syncProgress < 1) LinearProgressIndicator(progress = { session.syncProgress }, modifier = Modifier.fillMaxWidth().padding(top = 10.dp))
        }
    }
}

@Composable
private fun TelemetryCursor(sample: TelemetrySampleEntity?, startedAt: Long) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        listOf(
            Triple(appText("TIME", "CZAS"), sample?.let { duration(it.recordedAt - startedAt) } ?: "—", TougeCyan),
            Triple(appText("BOOST", "DOŁADOWANIE"), sample?.let { "%.2f bar".format(it.boostBar) } ?: "—", TougeCyan),
            Triple(appText("OIL", "OLEJ"), sample?.let { "${it.oilTemperatureCelsius.roundToInt()}°C" } ?: "—", TougeOrange),
            Triple(appText("SPEED", "PRĘDKOŚĆ"), sample?.let { "${it.speedKph.roundToInt()} km/h" } ?: "—", TougeMint)
        ).forEach { MiniValue(it.first, it.second, it.third) }
    }
}

@Composable
private fun TelemetryChart(
    title: String,
    samples: List<TelemetrySampleEntity>,
    selected: TelemetrySampleEntity?,
    startedAt: Long,
    endedAt: Long,
    attempts: List<AccelerationAttemptEntity>,
    series: List<Pair<TelemetryMetric, Color>>,
    selectTimestamp: (Long) -> Unit
) {
    val language = Locale.current.language
    val sessionDuration = (endedAt - startedAt).coerceAtLeast(1)
    val sharedScale = series.map { it.first.unit }.distinct().size == 1
    val domains = remember(samples, series) {
        if (sharedScale) {
            val domain = chartDomain(series.flatMap { (metric, _) -> samples.map { metric.from(it) } }, series.map { it.first })
            series.associate { it.first to domain }
        } else series.associate { (metric, _) -> metric to chartDomain(samples.map { metric.from(it) }, listOf(metric)) }
    }
    val selectAtFraction: (Float) -> Unit = { fraction ->
        selectTimestamp(startedAt + (sessionDuration * fraction.coerceIn(0f, 1f)).toLong())
    }
    TougePanelSurface(series.firstOrNull()?.second ?: TougeCyan, Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 7.dp)) {
        Column(Modifier.padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(title.uppercase(), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text(series.joinToString("  ") { it.first.localizedName(language) }, color = TougeMuted, fontSize = 9.sp)
            }
            Canvas(
                Modifier
                    .fillMaxWidth()
                    .height(210.dp)
                    .padding(top = 8.dp)
                    .pointerInput(startedAt, endedAt) {
                        detectTapGestures { point ->
                            val left = 43.dp.toPx()
                            val right = if (sharedScale || series.size == 1) 8.dp.toPx() else 43.dp.toPx()
                            selectAtFraction((point.x - left) / (size.width - left - right).coerceAtLeast(1f))
                        }
                    }
            ) {
                if (samples.size < 2) return@Canvas
                val left = 43.dp.toPx()
                val right = if (sharedScale || series.size == 1) 8.dp.toPx() else 43.dp.toPx()
                val top = 7.dp.toPx()
                val bottom = 28.dp.toPx()
                val plotWidth = (size.width - left - right).coerceAtLeast(1f)
                val plotHeight = (size.height - top - bottom).coerceAtLeast(1f)
                val labelPaint = AndroidPaint(AndroidPaint.ANTI_ALIAS_FLAG).apply {
                    color = android.graphics.Color.argb(180, 185, 204, 211)
                    textSize = 8.dp.toPx()
                    typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
                }
                repeat(4) { index ->
                    val fraction = index / 3f
                    val y = top + plotHeight * fraction
                    drawLine(Color.White.copy(alpha = .07f), Offset(left, y), Offset(left + plotWidth, y), 1.dp.toPx())
                    val primaryDomain = domains.getValue(series.first().first)
                    val primaryValue = primaryDomain.second - (primaryDomain.second - primaryDomain.first) * fraction
                    labelPaint.textAlign = AndroidPaint.Align.RIGHT
                    labelPaint.color = series.first().second.toArgbWithAlpha(.82f)
                    drawContext.canvas.nativeCanvas.drawText(axisValue(primaryValue, series.first().first, primaryDomain), left - 5.dp.toPx(), y + labelPaint.textSize * .35f, labelPaint)
                    if (!sharedScale && series.size > 1) {
                        val secondaryDomain = domains.getValue(series[1].first)
                        val secondaryValue = secondaryDomain.second - (secondaryDomain.second - secondaryDomain.first) * fraction
                        labelPaint.textAlign = AndroidPaint.Align.LEFT
                        labelPaint.color = series[1].second.toArgbWithAlpha(.82f)
                        drawContext.canvas.nativeCanvas.drawText(axisValue(secondaryValue, series[1].first, secondaryDomain), left + plotWidth + 5.dp.toPx(), y + labelPaint.textSize * .35f, labelPaint)
                    }
                }
                repeat(3) { index ->
                    val fraction = index / 2f
                    val x = left + plotWidth * fraction
                    drawLine(Color.White.copy(alpha = .045f), Offset(x, top), Offset(x, top + plotHeight), 1.dp.toPx())
                    labelPaint.textAlign = when (index) { 0 -> AndroidPaint.Align.LEFT; 2 -> AndroidPaint.Align.RIGHT; else -> AndroidPaint.Align.CENTER }
                    labelPaint.color = android.graphics.Color.argb(175, 185, 204, 211)
                    drawContext.canvas.nativeCanvas.drawText(duration((sessionDuration * fraction).toLong()), x, size.height - 5.dp.toPx(), labelPaint)
                }
                attempts.forEach { attempt ->
                    val startX = left + ((attempt.startedAt - startedAt).toFloat() / sessionDuration).coerceIn(0f, 1f) * plotWidth
                    val endX = left + ((attempt.endedAt - startedAt).toFloat() / sessionDuration).coerceIn(0f, 1f) * plotWidth
                    drawRect(accelerationColor(attempt.type).copy(alpha = .12f), topLeft = Offset(startX, top), size = androidx.compose.ui.geometry.Size((endX - startX).coerceAtLeast(2f), plotHeight))
                }
                series.forEach { (metric, color) ->
                    val domain = domains.getValue(metric)
                    val path = Path()
                    samples.forEachIndexed { index, sample ->
                        val value = metric.from(sample)
                        val x = left + ((sample.recordedAt - startedAt).toFloat() / sessionDuration).coerceIn(0f, 1f) * plotWidth
                        val y = top + plotHeight * (1 - ((value - domain.first) / (domain.second - domain.first)).toFloat().coerceIn(0f, 1f))
                        if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    drawPath(path, color, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round))
                }
                selected?.let {
                    val x = left + ((it.recordedAt - startedAt).toFloat() / sessionDuration).coerceIn(0f, 1f) * plotWidth
                    drawLine(Color.White.copy(alpha = .78f), Offset(x, top), Offset(x, top + plotHeight), 1.dp.toPx())
                }
            }
            selected?.let { point ->
                Row(
                    Modifier.fillMaxWidth().padding(top = 4.dp).background(Color.White.copy(alpha = .035f), RoundedCornerShape(6.dp)).padding(horizontal = 9.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    MiniValue(appText("TIME", "CZAS"), duration(point.recordedAt - startedAt), TougeCyan)
                    series.forEach { (metric, color) ->
                        MiniValue(metric.localizedName(language), "${metricValue(metric.from(point), metric)} ${metric.unit}", color)
                    }
                }
            }
        }
    }
}

private fun chartDomain(values: List<Double>, metrics: List<TelemetryMetric>): Pair<Double, Double> {
    val finite = values.filter(Double::isFinite)
    val minimum = finite.minOrNull() ?: 0.0
    val maximum = finite.maxOrNull() ?: 1.0
    val minimumSpan = metrics.maxOfOrNull { metric ->
        when (metric) {
            TelemetryMetric.BOOST, TelemetryMetric.OIL_PRESSURE, TelemetryMetric.FUEL_PRESSURE -> .1
            TelemetryMetric.RPM -> 1_000.0
            TelemetryMetric.SPEED -> 20.0
            TelemetryMetric.EGT1, TelemetryMetric.EGT2 -> 100.0
            TelemetryMetric.OIL_TEMPERATURE, TelemetryMetric.COOLANT, TelemetryMetric.INTAKE -> 10.0
            else -> 1.0
        }
    } ?: 1.0
    val span = (maximum - minimum).coerceAtLeast(minimumSpan) * 1.1
    val center = (minimum + maximum) / 2.0
    var lower = center - span / 2.0
    var upper = center + span / 2.0
    if (minimum >= 0 && metrics.all { it.defaultMin >= 0 } && lower < 0) {
        upper -= lower
        lower = 0.0
    }
    return lower to upper
}

private fun nearestSample(samples: List<TelemetrySampleEntity>, timestamp: Long): TelemetrySampleEntity? {
    if (samples.isEmpty()) return null
    val index = samples.binarySearchBy(timestamp) { it.recordedAt }
    if (index >= 0) return samples[index]
    val insertion = -index - 1
    val before = samples.getOrNull(insertion - 1)
    val after = samples.getOrNull(insertion)
    return when {
        before == null -> after
        after == null -> before
        abs(timestamp - before.recordedAt) <= abs(after.recordedAt - timestamp) -> before
        else -> after
    }
}

private fun axisValue(value: Double, metric: TelemetryMetric, domain: Pair<Double, Double>): String = when {
    metric == TelemetryMetric.BOOST || metric == TelemetryMetric.OIL_PRESSURE || metric == TelemetryMetric.FUEL_PRESSURE -> "%.2f".format(value)
    domain.second - domain.first < 2 -> "%.1f".format(value)
    else -> value.roundToInt().toString()
}

private fun metricValue(value: Double, metric: TelemetryMetric): String = "%.${metric.precision}f".format(value)

private fun Color.toArgbWithAlpha(alpha: Float): Int = android.graphics.Color.argb(
    (alpha.coerceIn(0f, 1f) * 255).roundToInt(),
    (red * 255).roundToInt(),
    (green * 255).roundToInt(),
    (blue * 255).roundToInt()
)

@Composable
private fun AccelerationSection(values: List<AccelerationAttemptEntity>, startedAt: Long, select: (AccelerationAttemptEntity) -> Unit) {
    Column(Modifier.padding(horizontal = 14.dp, vertical = 7.dp)) {
        Text(appText("ACCELERATION MEASUREMENTS", "POMIARY PRZYSPIESZENIA"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        Text(appText("Tap an attempt to move the telemetry cursor to its start.", "Dotknij próby, aby ustawić kursor telemetrii na jej początku."), color = TougeMuted, fontSize = 10.sp)
        AccelerationType.entries.forEach { type ->
            val attempts = values.filter { it.type == type.name }
            if (attempts.isNotEmpty()) {
                val best = attempts.minBy { it.durationMillis }
                Row(Modifier.fillMaxWidth().padding(top = 8.dp).background(accelerationColor(type.name).copy(alpha = .09f), RoundedCornerShape(6.dp)).clickable { select(best) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("${type.label} km/h", color = accelerationColor(type.name), fontWeight = FontWeight.Black)
                        Text("${attempts.size} ${appText("attempts", "prób")} • ${appText("best", "najlepszy")} %.2f s".format(best.durationMillis / 1_000.0), color = TougeMuted, fontSize = 10.sp)
                    }
                    Text("${duration(best.startedAt - startedAt)} → ${duration(best.endedAt - startedAt)}", fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(top = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    attempts.sortedBy { it.startedAt }.forEachIndexed { index, attempt ->
                        Text(
                            "#${index + 1}  %.2f s".format(attempt.durationMillis / 1_000.0),
                            color = if (attempt.id == best.id) Color.Black else Color.White,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Black,
                            modifier = Modifier
                                .background(
                                    if (attempt.id == best.id) accelerationColor(type.name) else accelerationColor(type.name).copy(alpha = .13f),
                                    RoundedCornerShape(5.dp)
                                )
                                .clickable { select(attempt) }
                                .padding(horizontal = 10.dp, vertical = 7.dp)
                        )
                    }
                }
            }
        }
    }
}

private fun accelerationColor(type: String): Color = when (type) {
    AccelerationType.ZERO_TO_100.name -> TougeMint
    AccelerationType.HUNDRED_TO_200.name -> TougeCyan
    else -> TougeOrange
}

@Composable
private fun IncidentSection(values: List<IncidentEntity>, startedAt: Long, select: (IncidentEntity) -> Unit) {
    Column(Modifier.padding(horizontal = 14.dp, vertical = 7.dp)) {
        Text(appText("INCIDENTS", "INCYDENTY"), color = TougeRed, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        values.forEach { incident ->
            Row(Modifier.fillMaxWidth().padding(vertical = 5.dp).background(TougeRed.copy(alpha = .08f), RoundedCornerShape(4.dp)).clickable { select(incident) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Flag, null, tint = TougeRed)
                Column(Modifier.padding(start = 10.dp).weight(1f)) {
                    Text(localizedIncidentKind(incident.kind), fontWeight = FontWeight.Bold)
                    Text("${duration(incident.triggeredAt - startedAt)} • ${incident.triggerValue} ${incident.triggerUnit}", color = TougeMuted, fontSize = 11.sp)
                    if (incident.syncState == SyncState.UPLOADING) LinearProgressIndicator(progress = { incident.syncProgress }, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
                    incident.syncError?.let { Text(it, color = TougeRed, fontSize = 9.sp) }
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(if (incident.severity == "CRITICAL") appText("CRITICAL", "KRYTYCZNY") else appText("WARNING", "OSTRZEŻENIE"), color = TougeRed, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                    Text(if (incident.syncState == SyncState.SYNCED) appText("CLOUD", "CHMURA") else appText("LOCAL", "LOKALNIE"), color = if (incident.syncState == SyncState.SYNCED) TougeMint else TougeOrange, fontSize = 8.sp, fontWeight = FontWeight.Black)
                }
            }
        }
    }
}

@Composable
private fun IncidentReportDialog(incident: IncidentEntity, container: AppContainer, dismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val shareChooserTitle = appText("Send incident report", "Wyślij raport incydentu")
    val points = remember(incident.id, incident.encodedSamples) {
        runCatching { container.json.decodeFromString<List<CapturedTelemetryPoint>>(incident.encodedSamples) }.getOrDefault(emptyList())
    }
    var unit by remember { mutableStateOf("DAYS") }
    var amount by remember { mutableStateOf(7) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var shareUrl by remember { mutableStateOf<String?>(null) }
    var note by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = dismiss,
        title = {
            Column {
                Text(appText("INCIDENT REPORT", "RAPORT INCYDENTU"), color = TougeRed, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text(localizedIncidentKind(incident.kind), fontWeight = FontWeight.Black)
            }
        },
        text = {
            Column(Modifier.heightIn(max = 620.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    MiniValue(appText("TRIGGER", "WARTOŚĆ"), "${incident.triggerValue} ${incident.triggerUnit}", TougeRed)
                    MiniValue(appText("LIMIT", "PRÓG"), "${incident.thresholdValue} ${incident.triggerUnit}", TougeOrange)
                    MiniValue("RPM", incident.triggerRpm.roundToInt().toString(), TougeCyan)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    MiniValue(appText("DURATION", "CZAS TRWANIA"), duration(incident.conditionDurationMillis), TougeRed)
                    MiniValue(appText("FUEL PRESSURE", "CIŚNIENIE PALIWA"), "${"%.2f".format(incident.triggerFuelPressureBar)} bar", TougeMint)
                }
                Text(
                    appText(
                        "${points.size} samples • ${duration(incident.captureEndedAt - incident.captureStartedAt)} capture • 30 s before and up to 60 s after the trigger",
                        "${points.size} próbek • ${duration(incident.captureEndedAt - incident.captureStartedAt)} zapisu • 30 s przed i do 60 s po zdarzeniu"
                    ),
                    color = TougeMuted,
                    fontSize = 10.sp
                )
                IncidentSparkline(points)
                Text(appText("SHARE WITH A MECHANIC", "WYŚLIJ MECHANIKOWI"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text(appText("The link opens only this report and does not require an account.", "Link otwiera wyłącznie ten raport i nie wymaga konta."), color = TougeMuted, fontSize = 11.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    FilterChip(unit == "HOURS", { unit = "HOURS"; amount = amount.coerceIn(1, 168) }, label = { Text(appText("Hours", "Godziny")) })
                    FilterChip(unit == "DAYS", { unit = "DAYS"; amount = amount.coerceIn(1, 365) }, label = { Text(appText("Days", "Dni")) })
                    FilterChip(unit == "FOREVER", { unit = "FOREVER" }, label = { Text(appText("Forever", "Bezterminowo")) })
                }
                if (unit != "FOREVER") Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { amount = (amount - 1).coerceAtLeast(1) }) { Icon(Icons.Default.Remove, null) }
                    Text(amount.toString(), fontWeight = FontWeight.Black, modifier = Modifier.padding(horizontal = 12.dp))
                    IconButton(onClick = { amount = (amount + 1).coerceAtMost(if (unit == "HOURS") 168 else 365) }) { Icon(Icons.Default.Add, null) }
                }
                if (shareUrl == null) Button(
                    enabled = !working && container.authRepository.isAuthenticated,
                    onClick = {
                        scope.launch {
                            working = true; error = null
                            runCatching { container.cloudSyncRepository.createIncidentShare(incident.id, unit, amount.takeUnless { unit == "FOREVER" }) }
                                .onSuccess { shareUrl = it }
                                .onFailure { error = it.message }
                            working = false
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) { if (working) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Icon(Icons.Default.Share, null); Text(if (working) appText(" Creating link…", " Tworzenie linku…") else appText(" Create secure link", " Utwórz bezpieczny link")) }
                else {
                    Text(shareUrl!!, color = TougeMint, fontSize = 10.sp)
                    Button(onClick = {
                        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, shareUrl) }, shareChooserTitle))
                    }, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Share, null); Text(appText(" Send to mechanic", " Wyślij mechanikowi")) }
                }
                if (!container.authRepository.isAuthenticated) Text(appText("Sign in to Touge Dash Cloud before creating a link.", "Zaloguj się do Touge Dash Cloud, aby utworzyć link."), color = TougeOrange, fontSize = 11.sp)
                error?.let { Text(it, color = TougeRed, fontSize = 11.sp) }
                Text(appText("NOTE AT THE TRIGGER", "NOTATKA PRZY ZDARZENIU"), color = TougeMint, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                OutlinedTextField(note, { note = it }, modifier = Modifier.fillMaxWidth(), minLines = 2, placeholder = { Text(appText("What happened here?", "Co wydarzyło się w tym momencie?")) })
                Button(enabled = note.isNotBlank(), onClick = {
                    val body = note.trim(); note = ""
                    scope.launch {
                        container.dao.upsertAnnotation(AnnotationEntity(UUID.randomUUID().toString(), incident.vehicleHardwareId, incident.sessionId, incident.id, incident.triggeredAt, body))
                        container.cloudSyncRepository.schedule()
                    }
                }) { Icon(Icons.AutoMirrored.Filled.NoteAdd, null); Text(appText(" Add note", " Dodaj notatkę")) }
            }
        },
        confirmButton = { TextButton(onClick = dismiss) { Text(appText("Close", "Zamknij")) } }
    )
}

@Composable
private fun IncidentSparkline(points: List<CapturedTelemetryPoint>) {
    Card(colors = CardDefaults.cardColors(containerColor = Color.Black.copy(alpha = .18f))) {
        Column(Modifier.padding(10.dp)) {
            Text(appText("BOOST • OIL PRESSURE • COOLANT", "BOOST • CIŚNIENIE OLEJU • PŁYN"), color = TougeMuted, fontSize = 8.sp, fontWeight = FontWeight.Bold)
            Canvas(Modifier.fillMaxWidth().height(130.dp).padding(top = 8.dp)) {
                if (points.size < 2) return@Canvas
                val series = listOf(
                    points.map { it.boostBar } to TougeCyan,
                    points.map { it.oilPressureBar } to TougeMint,
                    points.map { it.coolantCelsius } to TougeOrange
                )
                series.forEach { (values, color) ->
                    val minimum = values.minOrNull() ?: 0.0
                    val maximum = (values.maxOrNull() ?: 1.0).takeIf { it > minimum } ?: minimum + 1
                    val path = Path()
                    values.forEachIndexed { index, value ->
                        val x = index.toFloat() / values.lastIndex * size.width
                        val y = size.height * (1 - ((value - minimum) / (maximum - minimum)).toFloat())
                        if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    drawPath(path, color, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round))
                }
                val triggerX = points.indexOfFirst { it.recordedAt >= points.first().recordedAt + 30_000 }.takeIf { it >= 0 }?.toFloat()?.div(points.lastIndex)?.times(size.width)
                triggerX?.let { drawLine(TougeRed, Offset(it, 0f), Offset(it, size.height), 1.dp.toPx()) }
            }
        }
    }
}

@Composable
private fun AnnotationSection(values: List<AnnotationEntity>, startedAt: Long) {
    Column(Modifier.padding(14.dp)) {
        Text(appText("NOTES", "NOTATKI"), color = TougeMint, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        values.forEach { Text("${duration(it.recordedAt - startedAt)}  ${it.body}", modifier = Modifier.padding(vertical = 5.dp)) }
    }
}

@Composable
private fun AddNoteDialog(result: (String?) -> Unit) {
    var value by remember { mutableStateOf("") }
    androidx.compose.material3.AlertDialog(onDismissRequest = { result(null) }, title = { Text(appText("Note at current time", "Notatka w tym momencie")) }, text = { OutlinedTextField(value, { value = it }, minLines = 3) }, confirmButton = { Button(onClick = { result(value.trim().takeIf(String::isNotEmpty)) }) { Text(appText("Save", "Zapisz")) } }, dismissButton = { TextButton(onClick = { result(null) }) { Text(appText("Cancel", "Anuluj")) } })
}

@Composable
private fun DriveTagChip(tag: it.letscode.tougedash.cloud.CloudSyncRepository.DriveTag) {
    val color = remember(tag.color) { runCatching { Color(android.graphics.Color.parseColor(tag.color)) }.getOrDefault(TougeCyan) }
    Row(
        Modifier.background(color.copy(alpha = .13f), RoundedCornerShape(50)).padding(horizontal = 9.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Box(Modifier.size(6.dp).background(color, RoundedCornerShape(50)))
        Text(tag.name, color = color, fontSize = 9.sp, fontWeight = FontWeight.Black)
    }
}

private fun sessionTags(container: AppContainer, session: DriveSessionEntity) =
    runCatching {
        container.json.decodeFromString<List<it.letscode.tougedash.cloud.CloudSyncRepository.DriveTag>>(session.tagsJson)
    }.getOrDefault(emptyList())

@Composable
private fun DriveMetadataDialog(container: AppContainer, session: DriveSessionEntity, dismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var name by remember(session.id, session.customName) { mutableStateOf(session.customName.orEmpty()) }
    var tags by remember(session.id) { mutableStateOf<List<it.letscode.tougedash.cloud.CloudSyncRepository.DriveTag>>(emptyList()) }
    var selected by remember(session.id, session.tagsJson) { mutableStateOf(sessionTags(container, session).map { it.id }.toSet()) }
    var newTagName by remember { mutableStateOf("") }
    val palette = listOf("#18D7E3", "#45E6A8", "#FF9D44", "#FF5C58", "#A879FF", "#F5D547")
    var newTagColor by remember { mutableStateOf(palette.first()) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(session.id) {
        if (container.authRepository.isAuthenticated) {
            runCatching { container.cloudSyncRepository.driveTags() }
                .onSuccess { tags = it }
                .onFailure { error = it.message }
        } else tags = sessionTags(container, session)
    }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Column { Text(appText("ORGANIZE HISTORY", "ORGANIZACJA HISTORII"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Black); Text(appText("Drive name and tags", "Nazwa i tagi przejazdu"), fontWeight = FontWeight.Black) } },
        text = {
            Column(Modifier.heightIn(max = 560.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(name, { name = it.take(120) }, label = { Text(appText("Custom name", "Własna nazwa")) }, placeholder = { Text(appText("e.g. Boost run after tuning", "np. Próba boostu po strojeniu")) }, modifier = Modifier.fillMaxWidth())
                Text(appText("DRIVE TAGS", "TAGI PRZEJAZDU"), color = TougeMint, fontSize = 10.sp, fontWeight = FontWeight.Black)
                if (tags.isEmpty()) Text(if (container.authRepository.isAuthenticated) appText("No tags yet. Create the first one below.", "Nie ma jeszcze tagów. Utwórz pierwszy poniżej.") else appText("Sign in to manage reusable tags.", "Zaloguj się, aby zarządzać tagami."), color = TougeMuted, fontSize = 11.sp)
                tags.forEach { tag ->
                    FilterChip(
                        selected = selected.contains(tag.id),
                        onClick = { selected = if (selected.contains(tag.id)) selected - tag.id else selected + tag.id },
                        label = { DriveTagChip(tag) }
                    )
                }
                if (container.authRepository.isAuthenticated) {
                    Text(appText("NEW TAG", "NOWY TAG"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    OutlinedTextField(newTagName, { newTagName = it.take(40) }, label = { Text(appText("Tag name", "Nazwa tagu")) }, modifier = Modifier.fillMaxWidth())
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        palette.forEach { hex ->
                            val color = Color(android.graphics.Color.parseColor(hex))
                            Box(
                                Modifier.size(if (hex == newTagColor) 36.dp else 30.dp)
                                    .background(color, RoundedCornerShape(50))
                                    .clickable { newTagColor = hex }
                            )
                        }
                    }
                    Button(enabled = newTagName.isNotBlank() && !working, onClick = {
                        scope.launch {
                            working = true; error = null
                            runCatching { container.cloudSyncRepository.createDriveTag(newTagName, newTagColor) }
                                .onSuccess { created -> tags = (tags + created).sortedBy { it.name.lowercase() }; selected = selected + created.id; newTagName = "" }
                                .onFailure { error = it.message }
                            working = false
                        }
                    }, modifier = Modifier.fillMaxWidth()) { Text(appText("Create and assign", "Utwórz i przypisz")) }
                }
                error?.let { Text(it, color = TougeRed, fontSize = 11.sp) }
            }
        },
        confirmButton = {
            Button(enabled = !working, onClick = {
                scope.launch {
                    working = true; error = null
                    val assigned = tags.filter { selected.contains(it.id) }
                    container.historyRepository.updateMetadata(session, name, container.json.encodeToString(assigned))
                    if (container.authRepository.isAuthenticated) {
                        runCatching { container.cloudSyncRepository.updateDriveMetadata(session.copy(customName = name.trim().takeIf(String::isNotEmpty), tagsJson = container.json.encodeToString(assigned), metadataDirty = true), name.trim().takeIf(String::isNotEmpty), assigned) }
                            .onSuccess { dismiss() }
                            .onFailure { error = it.message; container.cloudSyncRepository.schedule() }
                    } else dismiss()
                    working = false
                }
            }) { Text(if (working) appText("Saving…", "Zapisywanie…") else appText("Save", "Zapisz")) }
        },
        dismissButton = { TextButton(onClick = dismiss) { Text(appText("Cancel", "Anuluj")) } }
    )
}

@Composable
private fun DriveShareDialog(container: AppContainer, session: DriveSessionEntity, samples: List<TelemetrySampleEntity>, dismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val chooserTitle = appText("Share drive", "Udostępnij przejazd")
    val totalSeconds = ((session.endedAt - session.startedAt).coerceAtLeast(1_000) / 1000f)
    val rangePreferences = remember { context.getSharedPreferences("drive-share-ranges", android.content.Context.MODE_PRIVATE) }
    val rangeKey = session.id
    var fragment by remember { mutableStateOf(rangePreferences.getBoolean("$rangeKey-fragment", false)) }
    var startSeconds by remember { mutableFloatStateOf(rangePreferences.getFloat("$rangeKey-start", 0f).coerceIn(0f, totalSeconds)) }
    var endSeconds by remember(totalSeconds) { mutableFloatStateOf(rangePreferences.getFloat("$rangeKey-end", totalSeconds).coerceIn(1f, totalSeconds)) }
    var unit by remember { mutableStateOf("DAYS") }
    var amount by remember { mutableStateOf(7) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var shareUrl by remember { mutableStateOf<String?>(null) }
    var links by remember { mutableStateOf<List<it.letscode.tougedash.cloud.CloudSyncRepository.DriveShareLink>>(emptyList()) }
    val previewSamples = remember(samples, fragment, startSeconds, endSeconds) {
        if (!fragment) samples else samples.filter {
            val offset = (it.recordedAt - session.startedAt) / 1000f
            offset in startSeconds..endSeconds
        }
    }
    LaunchedEffect(fragment, startSeconds, endSeconds) {
        rangePreferences.edit()
            .putBoolean("$rangeKey-fragment", fragment)
            .putFloat("$rangeKey-start", startSeconds)
            .putFloat("$rangeKey-end", endSeconds)
            .apply()
    }
    LaunchedEffect(session.id, container.authRepository.isAuthenticated) {
        if (container.authRepository.isAuthenticated) {
            runCatching { container.cloudSyncRepository.driveShares(session) }
                .onSuccess { links = it }
                .onFailure { error = it.message }
        }
    }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Column { Text(appText("SHARE A DRIVE", "UDOSTĘPNIJ PRZEJAZD"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Black); Text(session.customName ?: DateFormat.getDateTimeInstance().format(Date(session.startedAt)), fontWeight = FontWeight.Black) } },
        text = {
            Column(Modifier.heightIn(max = 580.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(11.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    FilterChip(!fragment, { fragment = false }, label = { Text(appText("Full drive", "Cały przejazd")) })
                    FilterChip(fragment, { fragment = true }, label = { Text(appText("Selected fragment", "Wybrany fragment")) })
                }
                if (fragment) {
                    Text(appText("Choose the beginning and end like when trimming a video.", "Wybierz początek i koniec tak jak przy przycinaniu filmu."), color = TougeMuted, fontSize = 11.sp)
                    Text("${duration((startSeconds * 1000).toLong())}  →  ${duration((endSeconds * 1000).toLong())}", color = TougeMint, fontWeight = FontWeight.Black)
                    Text(appText("Beginning", "Początek"), fontSize = 10.sp)
                    Slider(startSeconds, { startSeconds = it.coerceAtMost(endSeconds - 1f) }, valueRange = 0f..totalSeconds)
                    Text(appText("End", "Koniec"), fontSize = 10.sp)
                    Slider(endSeconds, { endSeconds = it.coerceAtLeast(startSeconds + 1f) }, valueRange = 0f..totalSeconds)
                }
                if (previewSamples.isNotEmpty()) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        MiniValue(appText("SAMPLES", "PRÓBKI"), previewSamples.size.toString(), TougeCyan)
                        MiniValue(appText("MAX BOOST", "MAX DOŁADOWANIE"), "%.2f bar".format(previewSamples.maxOf { it.boostBar }), TougeMint)
                        MiniValue(appText("MAX SPEED", "MAX PRĘDKOŚĆ"), "${previewSamples.maxOf { it.speedKph }.roundToInt()} km/h", TougeOrange)
                    }
                    Text(
                        appText(
                            "Preview includes ${previewSamples.count { it.latitude != null }} GPS points.",
                            "Podgląd obejmuje ${previewSamples.count { it.latitude != null }} punktów GPS."
                        ),
                        color = TougeMuted,
                        fontSize = 9.sp
                    )
                }
                Text(appText("LINK EXPIRATION", "WAŻNOŚĆ LINKU"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Black)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    FilterChip(unit == "HOURS", { unit = "HOURS"; amount = amount.coerceIn(1, 168) }, label = { Text(appText("Hours", "Godziny")) })
                    FilterChip(unit == "DAYS", { unit = "DAYS"; amount = amount.coerceIn(1, 365) }, label = { Text(appText("Days", "Dni")) })
                    FilterChip(unit == "FOREVER", { unit = "FOREVER" }, label = { Text(appText("Forever", "Bezterminowo")) })
                }
                if (unit != "FOREVER") Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { amount = (amount - 1).coerceAtLeast(1) }) { Icon(Icons.Default.Remove, null) }
                    Text(amount.toString(), fontWeight = FontWeight.Black)
                    IconButton(onClick = { amount = (amount + 1).coerceAtMost(if (unit == "HOURS") 168 else 365) }) { Icon(Icons.Default.Add, null) }
                }
                if (shareUrl != null) {
                    Text(shareUrl!!, color = TougeMint, fontSize = 10.sp)
                    Button(onClick = { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, shareUrl) }, chooserTitle)) }, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Share, null); Text(appText(" Send link", " Wyślij link")) }
                }
                if (links.isNotEmpty()) {
                    Text(appText("ACTIVE LINKS", "AKTYWNE LINKI"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    links.forEach { link ->
                        Row(
                            Modifier.fillMaxWidth().background(Color.White.copy(alpha = .035f), RoundedCornerShape(7.dp)).padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(link.expiresAt ?: appText("No expiration", "Bezterminowo"), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                link.range?.let { Text("${duration(it.startOffsetMillis)} → ${duration(it.endOffsetMillis)}", color = TougeMint, fontSize = 9.sp) }
                            }
                            IconButton(onClick = {
                                scope.launch {
                                    working = true; error = null
                                    runCatching { container.cloudSyncRepository.revokeDriveShare(session, link.id) }
                                        .onSuccess { links = links.filterNot { it.id == link.id } }
                                        .onFailure { error = it.message }
                                    working = false
                                }
                            }) { Icon(Icons.Default.Delete, appText("Revoke link", "Unieważnij link"), tint = TougeRed) }
                        }
                    }
                }
                if (!container.authRepository.isAuthenticated) Text(appText("Sign in to Touge Dash Cloud before creating a link.", "Zaloguj się do Touge Dash Cloud, aby utworzyć link."), color = TougeOrange, fontSize = 11.sp)
                error?.let { Text(it, color = TougeRed, fontSize = 11.sp) }
            }
        },
        confirmButton = {
            if (shareUrl == null) Button(enabled = !working && container.authRepository.isAuthenticated, onClick = {
                scope.launch {
                    working = true; error = null
                    val range = if (fragment) DriveShareRange.normalize(
                        session.endedAt - session.startedAt,
                        (startSeconds * 1000).toLong(),
                        (endSeconds * 1000).toLong()
                    ) else null
                    runCatching { container.cloudSyncRepository.createDriveShare(session, unit, amount.takeUnless { unit == "FOREVER" }, range?.startOffsetMillis, range?.endOffsetMillis) }
                        .onSuccess {
                            shareUrl = it
                            links = runCatching { container.cloudSyncRepository.driveShares(session) }.getOrDefault(links)
                        }
                        .onFailure { error = it.message }
                    working = false
                }
            }) { Text(if (working) appText("Creating link…", "Tworzenie linku…") else appText("Create link", "Utwórz link")) }
        },
        dismissButton = { TextButton(onClick = dismiss) { Text(appText("Close", "Zamknij")) } }
    )
}

@Composable
private fun RouteMap(samples: List<TelemetrySampleEntity>) {
    val context = LocalContext.current
    val points = remember(samples) { samples.mapNotNull { value -> value.latitude?.let { lat -> value.longitude?.let { GeoPoint(lat, it) } } } }
    Card(Modifier.fillMaxWidth().padding(14.dp), colors = CardDefaults.cardColors(containerColor = TougePanel)) {
        Column {
            Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.Map, null, tint = TougeCyan); Text(appText(" ROUTE", " TRASA"), fontWeight = FontWeight.Bold) }
            AndroidView(
                factory = {
                    Configuration.getInstance().userAgentValue = context.packageName
                    MapView(context).apply {
                        setMultiTouchControls(true)
                        overlayManager.add(Polyline().apply { outlinePaint.color = android.graphics.Color.CYAN; outlinePaint.strokeWidth = 7f; setPoints(points) })
                        if (points.isNotEmpty()) controller.setCenter(points[points.size / 2])
                        controller.setZoom(14.0)
                    }
                },
                update = { map -> (map.overlays.filterIsInstance<Polyline>().firstOrNull())?.setPoints(points); map.invalidate() },
                modifier = Modifier.fillMaxWidth().height(260.dp)
            )
        }
    }
}

private fun TelemetryMetric.from(value: TelemetrySampleEntity): Double = when (this) {
    TelemetryMetric.RPM -> value.rpm; TelemetryMetric.BOOST -> value.boostBar; TelemetryMetric.MAP -> value.mapKpa
    TelemetryMetric.THROTTLE -> value.throttlePercent; TelemetryMetric.COOLANT -> value.coolantCelsius; TelemetryMetric.INTAKE -> value.intakeCelsius
    TelemetryMetric.EGT1 -> value.egt1Celsius; TelemetryMetric.EGT2 -> value.egt2Celsius
    TelemetryMetric.OIL_TEMPERATURE -> value.oilTemperatureCelsius; TelemetryMetric.OIL_PRESSURE -> value.oilPressureBar; TelemetryMetric.FUEL_PRESSURE -> value.fuelPressureBar
    TelemetryMetric.AFR -> value.afr; TelemetryMetric.LAMBDA -> value.lambda; TelemetryMetric.BATTERY_VOLTAGE -> value.batteryVoltage
    TelemetryMetric.IGNITION -> value.ignitionDegrees; TelemetryMetric.INJECTOR_DUTY -> value.injectorDutyPercent; TelemetryMetric.SPEED -> value.speedKph
}

private fun duration(ms: Long): String { val total = (ms.coerceAtLeast(0) / 1000); return "%d:%02d".format(total / 60, total % 60) }
private fun bytes(value: Long): String = when { value >= 1_048_576 -> "%.1f MB".format(value / 1_048_576.0); value >= 1024 -> "%.0f kB".format(value / 1024.0); else -> "$value B" }

@Composable
private fun localizedIncidentKind(value: String): String = when (value) {
    "LOW_OIL_PRESSURE" -> appText("Low oil pressure", "Niskie ciśnienie oleju")
    "LEAN_UNDER_BOOST" -> appText("Lean mixture under boost", "Uboga mieszanka pod doładowaniem")
    "OVERBOOST" -> appText("Overboost", "Przekroczone doładowanie")
    "HIGH_COOLANT_TEMPERATURE" -> appText("High coolant temperature", "Wysoka temperatura płynu")
    "HIGH_OIL_TEMPERATURE" -> appText("High oil temperature", "Wysoka temperatura oleju")
    "LOW_FUEL_PRESSURE" -> appText("Low fuel pressure", "Niskie ciśnienie paliwa")
    "LOW_BATTERY_VOLTAGE" -> appText("Low battery voltage", "Niskie napięcie akumulatora")
    "CHECK_ENGINE" -> appText("Check engine", "Błąd silnika")
    else -> value.replace('_', ' ')
}
