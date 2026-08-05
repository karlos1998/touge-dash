package it.letscode.tougedash.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.NoteAdd
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import it.letscode.tougedash.data.local.AnnotationEntity
import it.letscode.tougedash.data.local.DriveSessionEntity
import it.letscode.tougedash.data.local.IncidentEntity
import it.letscode.tougedash.data.local.SyncState
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougeOrange
import it.letscode.tougedash.ui.theme.TougePanel
import it.letscode.tougedash.ui.theme.TougeRed
import kotlinx.coroutines.launch
import org.osmdroid.config.Configuration
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Polyline
import java.text.DateFormat
import java.util.Date
import java.util.UUID
import kotlin.math.roundToInt

@Composable
fun HistoryScreen(container: AppContainer, selectedId: String?, select: (String) -> Unit, back: () -> Unit) {
    if (selectedId == null) SessionList(container, select) else SessionDetail(container, selectedId, back)
}

@Composable
private fun SessionList(container: AppContainer, select: (String) -> Unit) {
    val sessions by container.historyRepository.sessions.collectAsState(initial = emptyList())
    Column(Modifier.fillMaxSize()) {
        Text(appText("DRIVE ARCHIVE", "ARCHIWUM PRZEJAZDÓW"), color = TougeCyan, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 18.dp, top = 18.dp))
        Text(appText("History", "Historia"), fontSize = 34.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(horizontal = 18.dp))
        if (sessions.isEmpty()) {
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Icon(Icons.Default.DirectionsCar, null, Modifier.size(54.dp), tint = TougeMuted)
                Text(appText("No recorded drives yet", "Nie ma jeszcze zapisanych przejazdów"), color = TougeMuted, modifier = Modifier.padding(top = 14.dp))
            }
        } else LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(sessions, key = { it.id }) { SessionRow(it, select) }
        }
    }
}

@Composable
private fun SessionRow(session: DriveSessionEntity, select: (String) -> Unit) {
    Card(Modifier.fillMaxWidth().clickable { select(session.id) }, colors = CardDefaults.cardColors(containerColor = TougePanel), shape = RoundedCornerShape(4.dp)) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Text(DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(session.startedAt)), fontWeight = FontWeight.Bold)
                    Text("${duration(session.endedAt - session.startedAt)}  •  ${session.sampleCount} samples", color = TougeMuted, fontSize = 12.sp)
                }
                SyncBadge(session)
            }
            Row(Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                MiniValue("BOOST MAX", "${"%.2f".format(session.maxBoostBar)} bar", TougeCyan)
                MiniValue("OIL MAX", "${session.maxOilTemperatureCelsius.roundToInt()}°C", TougeOrange)
                MiniValue("COOLANT MAX", "${session.maxCoolantCelsius.roundToInt()}°C", TougeMint)
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
        SyncState.SYNCED -> Triple(Icons.Default.CloudDone, TougeMint, "SYNCED")
        SyncState.FAILED -> Triple(Icons.Default.Error, TougeRed, "ERROR")
        SyncState.UPLOADING -> Triple(Icons.Default.CloudDone, TougeCyan, "SYNCING")
        else -> Triple(Icons.Default.CloudOff, TougeOrange, "LOCAL")
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
    val incidents by container.historyRepository.incidents(id).collectAsState(initial = emptyList())
    val annotations by container.historyRepository.annotations(id).collectAsState(initial = emptyList())
    var scrubber by remember(id) { mutableFloatStateOf(0f) }
    var noteDialog by remember { mutableStateOf(false) }
    val selected = samples.getOrNull(((samples.lastIndex.coerceAtLeast(0)) * scrubber).roundToInt())
    LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 30.dp)) {
        item {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = back) { Icon(Icons.Default.ArrowBack, null) }
                Column(Modifier.weight(1f)) {
                    Text(appText("DRIVE REPORT", "RAPORT PRZEJAZDU"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    Text(session?.let { DateFormat.getDateTimeInstance().format(Date(it.startedAt)) } ?: "…", fontWeight = FontWeight.Black)
                }
                IconButton(onClick = { noteDialog = true }) { Icon(Icons.Default.NoteAdd, null, tint = TougeMint) }
            }
        }
        if (session == null) item { Box(Modifier.fillMaxWidth().height(300.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        else {
            item { SessionSummary(session!!) }
            if (incidents.isNotEmpty()) item { IncidentSection(incidents, session!!.startedAt) { timestamp -> scrubber = ((timestamp - session!!.startedAt).toFloat() / (session!!.endedAt - session!!.startedAt).coerceAtLeast(1)).coerceIn(0f, 1f) } }
            item {
                TelemetryCursor(selected, session!!.startedAt)
                Slider(scrubber, { scrubber = it }, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp))
                Text(appText("Move the time cursor; the page remains vertically scrollable", "Przesuwaj kursor czasu; stronę nadal możesz przewijać pionowo"), color = TougeMuted, fontSize = 10.sp, modifier = Modifier.padding(horizontal = 18.dp))
            }
            item { TelemetryChart("Boost / oil pressure", samples, selected, listOf(TelemetryMetric.BOOST to TougeCyan, TelemetryMetric.OIL_PRESSURE to TougeMint)) }
            item { TelemetryChart("Temperatures", samples, selected, listOf(TelemetryMetric.OIL_TEMPERATURE to TougeOrange, TelemetryMetric.COOLANT to TougeCyan)) }
            item { TelemetryChart("RPM / speed", samples, selected, listOf(TelemetryMetric.RPM to TougeRed, TelemetryMetric.SPEED to TougeMint)) }
            if (annotations.isNotEmpty()) item { AnnotationSection(annotations, session!!.startedAt) }
            item { DriveVideoSection(container, session!!, samples, scrubber) }
            if (samples.any { it.latitude != null && it.longitude != null }) item { RouteMap(samples) }
        }
    }
    if (noteDialog && session != null) AddNoteDialog { body ->
        noteDialog = false
        if (body != null) container.applicationScope.launch {
            val timestamp = selected?.recordedAt ?: session!!.startedAt
            container.dao.upsertAnnotation(AnnotationEntity(UUID.randomUUID().toString(), session!!.vehicleHardwareId, id, recordedAt = timestamp, body = body))
        }
    }
}

@Composable
private fun SessionSummary(session: DriveSessionEntity) {
    Card(Modifier.fillMaxWidth().padding(14.dp), colors = CardDefaults.cardColors(containerColor = TougePanel)) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                MiniValue("DURATION", duration(session.endedAt - session.startedAt), TougeCyan)
                MiniValue("SAMPLES", session.sampleCount.toString(), TougeMint)
                MiniValue("DISTANCE", "%.1f km".format(session.distanceMeters / 1000), TougeOrange)
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
            Triple("TIME", sample?.let { duration(it.recordedAt - startedAt) } ?: "—", TougeCyan),
            Triple("BOOST", sample?.let { "%.2f bar".format(it.boostBar) } ?: "—", TougeCyan),
            Triple("OIL", sample?.let { "${it.oilTemperatureCelsius.roundToInt()}°C" } ?: "—", TougeOrange),
            Triple("SPEED", sample?.let { "${it.speedKph.roundToInt()} km/h" } ?: "—", TougeMint)
        ).forEach { MiniValue(it.first, it.second, it.third) }
    }
}

@Composable
private fun TelemetryChart(title: String, samples: List<TelemetrySampleEntity>, selected: TelemetrySampleEntity?, series: List<Pair<TelemetryMetric, Color>>) {
    Card(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 7.dp), colors = CardDefaults.cardColors(containerColor = TougePanel)) {
        Column(Modifier.padding(14.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(title.uppercase(), fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text(series.joinToString("  ") { it.first.shortName }, color = TougeMuted, fontSize = 9.sp)
            }
            Canvas(Modifier.fillMaxWidth().height(180.dp).padding(top = 12.dp)) {
                if (samples.size < 2) return@Canvas
                series.forEach { (metric, color) ->
                    val values = samples.map { metric.from(it).toFloat() }
                    val min = values.minOrNull() ?: 0f
                    val max = values.maxOrNull()?.takeIf { it > min } ?: (min + 1f)
                    val path = Path()
                    values.forEachIndexed { index, value ->
                        val x = index.toFloat() / values.lastIndex * size.width
                        val y = size.height * (1 - (value - min) / (max - min))
                        if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    drawPath(path, color, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round))
                }
                selected?.let {
                    val index = samples.binarySearchBy(it.recordedAt) { point -> point.recordedAt }.coerceAtLeast(0)
                    val x = index.toFloat() / samples.lastIndex * size.width
                    drawLine(Color.White.copy(alpha = .7f), Offset(x, 0f), Offset(x, size.height), 1.dp.toPx())
                }
            }
        }
    }
}

@Composable
private fun IncidentSection(values: List<IncidentEntity>, startedAt: Long, select: (Long) -> Unit) {
    Column(Modifier.padding(horizontal = 14.dp, vertical = 7.dp)) {
        Text(appText("INCIDENTS", "INCYDENTY"), color = TougeRed, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        values.forEach { incident ->
            Row(Modifier.fillMaxWidth().padding(vertical = 5.dp).background(TougeRed.copy(alpha = .08f), RoundedCornerShape(4.dp)).clickable { select(incident.triggeredAt) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Flag, null, tint = TougeRed)
                Column(Modifier.padding(start = 10.dp).weight(1f)) { Text(incident.kind.replace('_', ' '), fontWeight = FontWeight.Bold); Text("${duration(incident.triggeredAt - startedAt)} • ${incident.triggerValue} ${incident.triggerUnit}", color = TougeMuted, fontSize = 11.sp) }
                Text(incident.severity, color = TougeRed, fontSize = 9.sp, fontWeight = FontWeight.Bold)
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
    TelemetryMetric.OIL_TEMPERATURE -> value.oilTemperatureCelsius; TelemetryMetric.OIL_PRESSURE -> value.oilPressureBar; TelemetryMetric.FUEL_PRESSURE -> value.fuelPressureBar
    TelemetryMetric.AFR -> value.afr; TelemetryMetric.LAMBDA -> value.lambda; TelemetryMetric.BATTERY_VOLTAGE -> value.batteryVoltage
    TelemetryMetric.IGNITION -> value.ignitionDegrees; TelemetryMetric.INJECTOR_DUTY -> value.injectorDutyPercent; TelemetryMetric.SPEED -> value.speedKph
}

private fun duration(ms: Long): String { val total = (ms.coerceAtLeast(0) / 1000); return "%d:%02d".format(total / 60, total % 60) }
private fun bytes(value: Long): String = when { value >= 1_048_576 -> "%.1f MB".format(value / 1_048_576.0); value >= 1024 -> "%.0f kB".format(value / 1024.0); else -> "$value B" }
