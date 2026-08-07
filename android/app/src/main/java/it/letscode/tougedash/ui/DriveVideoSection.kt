@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import it.letscode.tougedash.data.local.DriveSessionEntity
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import it.letscode.tougedash.data.local.VideoProjectEntity
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.model.DashboardAccent
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougeOrange
import it.letscode.tougedash.ui.theme.TougePanel
import it.letscode.tougedash.ui.theme.TougeRed
import it.letscode.tougedash.video.OverlayStyle
import it.letscode.tougedash.video.OverlayElementKind
import it.letscode.tougedash.video.OverlayElementScale
import it.letscode.tougedash.video.OverlayPosition
import it.letscode.tougedash.video.VideoOverlayElement
import it.letscode.tougedash.video.VideoOverlayTemplate
import it.letscode.tougedash.video.VideoOverlayTemplateDefinition
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

@Composable
fun DriveVideoSection(container: AppContainer, session: DriveSessionEntity, samples: List<TelemetrySampleEntity>, scrubber: Float) {
    val videos by container.historyRepository.videos(session.id).collectAsState(initial = emptyList())
    val task by container.videoRepository.task.collectAsState()
    var editing by remember { mutableStateOf<VideoProjectEntity?>(null) }
    val driveDuration = (session.endedAt - session.startedAt).coerceAtLeast(1) / 1000.0
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri?.let { container.videoRepository.importFromGallery(session.id, driveDuration, it) }
    }
    Column(Modifier.fillMaxWidth().padding(14.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column { Text("VIDEO + TELEMETRY", color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold); Text(appText("Synchronized drive footage", "Nagrania zsynchronizowane z przejazdem"), fontWeight = FontWeight.Black) }
            Button(onClick = { picker.launch("video/*") }) { Icon(Icons.Default.VideoLibrary, null); Text(appText(" Use my video", " Użyj mojego filmu")) }
        }
        if (task.operation != null) {
            Card(Modifier.fillMaxWidth().padding(top = 10.dp), colors = CardDefaults.cardColors(containerColor = TougePanel)) {
                Column(Modifier.padding(12.dp)) {
                    Text(localizedVideoOperation(task.operation!!), fontWeight = FontWeight.Bold)
                    LinearProgressIndicator(progress = { task.progress }, modifier = Modifier.fillMaxWidth().padding(top = 7.dp))
                    Text("${(task.progress * 100).roundToInt()}%${if (task.totalBytes > 0) "  •  ${videoBytes(task.transferredBytes)} / ${videoBytes(task.totalBytes)}" else ""}", color = TougeMuted, fontSize = 10.sp)
                    task.error?.let { Text(it, color = TougeRed) }
                    if (task.completed || task.error != null) TextButton(onClick = container.videoRepository::clearTask) { Text(appText("Close", "Zamknij")) }
                    else if (task.operation == "Rendering telemetry HUD") TextButton(onClick = container.videoRepository::cancelExport) { Text(appText("Cancel export", "Anuluj eksport"), color = TougeRed) }
                }
            }
        }
        VideoGroup(appText("RECORDED BY TOUGE DASH", "NAGRANE PRZEZ TOUGE DASH"), videos.filter { it.sourceKind == "CAMERA" }, editing = { editing = it }, delete = container.videoRepository::delete)
        VideoGroup(appText("GALLERY EDITS", "PROJEKTY Z GALERII"), videos.filter { it.sourceKind == "GALLERY" }, editing = { editing = it }, delete = container.videoRepository::delete)
        if (videos.isEmpty() && task.operation == null) Text(appText("Record a drive with the phone camera or attach footage from a dashcam. The source video stays local on this device.", "Nagraj przejazd kamerą telefonu albo dodaj film z wideorejestratora. Film źródłowy pozostaje lokalnie na tym urządzeniu."), color = TougeMuted, modifier = Modifier.padding(top = 12.dp))
    }
    editing?.let { project -> VideoAlignmentEditor(project, driveDuration, samples, container, { editing = null }, { changed -> container.videoRepository.update(changed); editing = changed }) }
}

@Composable
private fun VideoGroup(title: String, videos: List<VideoProjectEntity>, editing: (VideoProjectEntity) -> Unit, delete: (VideoProjectEntity) -> Unit) {
    if (videos.isEmpty()) return
    Text(title, color = TougeMuted, fontSize = 9.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp, bottom = 5.dp))
    videos.forEach { video ->
        Card(Modifier.fillMaxWidth().padding(vertical = 4.dp).clickable { editing(video) }, colors = CardDefaults.cardColors(containerColor = TougePanel)) {
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Movie, null, Modifier.size(34.dp), tint = TougeCyan)
                Column(Modifier.padding(start = 10.dp).weight(1f)) {
                    Text(video.sourceDisplayName ?: if (video.sourceKind == "CAMERA") appText("Drive recording", "Nagranie przejazdu") else appText("Gallery video", "Film z galerii"), fontWeight = FontWeight.Bold)
                    Text("${videoDuration(video.durationSeconds)}  •  ${videoBytes(video.fileSizeBytes)}  •  ${video.pixelWidth}×${video.pixelHeight}", color = TougeMuted, fontSize = 11.sp)
                }
                IconButton(onClick = { delete(video) }) { Icon(Icons.Default.Delete, null, tint = TougeRed) }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun VideoAlignmentEditor(
    initial: VideoProjectEntity,
    driveDuration: Double,
    samples: List<TelemetrySampleEntity>,
    container: AppContainer,
    dismiss: () -> Unit,
    save: (VideoProjectEntity) -> Unit
) {
    val context = LocalContext.current
    var value by remember(initial.id) { mutableStateOf(initial) }
    val templates by container.videoRepository.overlayTemplates.collectAsState(initial = emptyList())
    var templateId by remember(initial.id) { mutableStateOf(initial.overlayTemplateId ?: "RACE") }
    var overlayDefinition by remember(initial.id) { mutableStateOf(VideoOverlayTemplateDefinition(runCatching { OverlayStyle.valueOf(initial.overlayTemplateId ?: "RACE") }.getOrDefault(OverlayStyle.RACE))) }
    var editingTemplate by remember { mutableStateOf<VideoOverlayTemplate?>(null) }
    var selectedElementId by remember { mutableStateOf<String?>(null) }
    val portraitVideo = initial.pixelHeight > initial.pixelWidth
    var previewSize by remember { mutableStateOf(IntSize.Zero) }
    LaunchedEffect(templates, templateId) {
        templates.firstOrNull { it.entity.id == templateId }?.let {
            overlayDefinition = it.definition.copy(elements = it.definition.resolvedElements())
            selectedElementId = overlayDefinition.elements.firstOrNull()?.id
        }
    }
    val player = remember(initial.id) { ExoPlayer.Builder(context).build().apply { setMediaItem(MediaItem.fromUri(initial.localUri)); prepare(); seekTo((initial.videoTrimStartSeconds * 1000).toLong()) } }
    var position by remember { mutableLongStateOf((initial.videoTrimStartSeconds * 1000).toLong()) }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(player) { while (true) { position = player.currentPosition; if (position / 1000.0 >= value.videoTrimStartSeconds + value.exportDurationSeconds) { player.pause(); player.seekTo((value.videoTrimStartSeconds * 1000).toLong()) }; delay(50) } }
    val telemetrySecond = value.telemetryTrimStartSeconds + (position / 1000.0 - value.videoTrimStartSeconds).coerceAtLeast(0.0)
    val first = samples.firstOrNull()?.recordedAt ?: 0
    val sample = samples.nearestTo((first + telemetrySecond * 1000).toLong())
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(appText("Align video with telemetry", "Dopasuj film do telemetrii")) },
        text = {
            Column {
                Box(Modifier.fillMaxWidth().height(220.dp).background(Color.Black).onSizeChanged { previewSize = it }) {
                    AndroidView(factory = { PlayerView(it).apply { useController = false; this.player = player } }, modifier = Modifier.fillMaxWidth().height(220.dp))
                    sample?.let { current ->
                        EditableHudPreview(
                            sample = current,
                            definition = overlayDefinition,
                            portrait = portraitVideo,
                            canvasSize = previewSize,
                            selectedElementId = selectedElementId,
                            select = { selectedElementId = it },
                            transform = { id, dx, dy, zoom ->
                                overlayDefinition = overlayDefinition.copy(elements = overlayDefinition.elements.map { element ->
                                    if (element.id != id || previewSize.width == 0 || previewSize.height == 0) element
                                    else {
                                        val old = element.position(portraitVideo)
                                        element
                                            .positioned(portraitVideo, OverlayPosition(old.x + dx / previewSize.width, old.y + dy / previewSize.height))
                                            .resized(zoom)
                                    }
                                })
                            }
                        )
                    }
                    IconButton(onClick = { if (player.isPlaying) player.pause() else { if (position / 1000.0 !in value.videoTrimStartSeconds..(value.videoTrimStartSeconds + value.exportDurationSeconds)) player.seekTo((value.videoTrimStartSeconds * 1000).toLong()); player.play() } }, modifier = Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = .45f), RoundedCornerShape(30.dp))) {
                        Icon(if (player.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, null, tint = Color.White)
                    }
                }
                Text("${appText("VIDEO START", "POCZĄTEK FILMU")}  ${videoDuration(value.videoTrimStartSeconds)}", color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
                Slider(value.videoTrimStartSeconds.toFloat(), { new -> value = value.copy(videoTrimStartSeconds = new.toDouble()); player.seekTo((new * 1000).toLong()) }, valueRange = 0f..(value.durationSeconds - value.exportDurationSeconds).coerceAtLeast(.01).toFloat())
                Text("${appText("TELEMETRY START", "POCZĄTEK TELEMETRII")}  ${videoDuration(value.telemetryTrimStartSeconds)} ${appText("of", "z")} ${videoDuration(driveDuration)}", color = TougeMint, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Slider(value.telemetryTrimStartSeconds.toFloat(), { value = value.copy(telemetryTrimStartSeconds = it.toDouble()) }, valueRange = 0f..(driveDuration - value.exportDurationSeconds).coerceAtLeast(.01).toFloat())
                val maxDuration = minOf(value.durationSeconds - value.videoTrimStartSeconds, driveDuration - value.telemetryTrimStartSeconds).coerceAtLeast(.1)
                Text("${appText("EXPORT LENGTH", "DŁUGOŚĆ EKSPORTU")}  ${videoDuration(value.exportDurationSeconds)}", color = TougeOrange, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Slider(value.exportDurationSeconds.coerceAtMost(maxDuration).toFloat(), { value = value.copy(exportDurationSeconds = it.toDouble()) }, valueRange = .1f..maxDuration.coerceAtLeast(.11).toFloat())
                Text(appText("HUD TEMPLATE", "SZABLON HUD"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    templates.forEach { item ->
                        FilterChip(
                            selected = templateId == item.entity.id,
                            onClick = { templateId = item.entity.id; overlayDefinition = item.definition; value = value.copy(overlayTemplateId = item.entity.id) },
                            label = { Text(item.entity.name) }
                        )
                    }
                }
                Text(appText("Tap and drag individual HUD elements on the preview. Portrait and landscape positions are stored separately.", "Dotknij i przeciągaj pojedyncze elementy HUD na podglądzie. Pozycje pionowe i poziome zapisują się osobno."), color = TougeMuted, fontSize = 10.sp)
                OutlinedButton(
                    onClick = { templates.firstOrNull { it.entity.id == templateId }?.let { container.videoRepository.updateOverlayTemplate(it.copy(definition = overlayDefinition)) } },
                    modifier = Modifier.fillMaxWidth()
                ) { Text(appText("Save layout in this template", "Zapisz układ w tym szablonie")) }
                OutlinedButton(
                    onClick = { editingTemplate = templates.firstOrNull { it.entity.id == templateId }?.copy(definition = overlayDefinition) },
                    modifier = Modifier.fillMaxWidth()
                ) { Icon(Icons.Default.Tune, null); Text(appText(" Edit HUD parameters", " Edytuj parametry HUD")) }
                Text(appText("The upper timeline is the selected video. The lower one chooses the matching fragment of the recorded drive.", "Górna oś to wybrany film. Dolna wybiera pasujący fragment zapisanego przejazdu."), color = TougeMuted, fontSize = 10.sp)
            }
        },
        confirmButton = {
            Button(onClick = { save(value.copy(overlayTemplateId = templateId)); container.videoRepository.export(value.copy(overlayTemplateId = templateId), samples, overlayDefinition); dismiss() }) { Icon(Icons.Default.Download, null); Text(appText(" Export to gallery", " Eksportuj do galerii")) }
        },
        dismissButton = { TextButton(onClick = { save(value.copy(overlayTemplateId = templateId)); dismiss() }) { Text(appText("Save project", "Zapisz projekt")) } }
    )
    editingTemplate?.let { current ->
        HudTemplateEditor(
            initial = current,
            dismiss = { editingTemplate = null },
            save = { changed ->
                container.videoRepository.updateOverlayTemplate(changed)
                overlayDefinition = changed.definition
                templateId = changed.entity.id
                editingTemplate = null
            },
            duplicate = { container.videoRepository.duplicateOverlayTemplate(current); editingTemplate = null },
            delete = { container.videoRepository.deleteOverlayTemplate(current); editingTemplate = null }
        )
    }
}

@Composable
private fun BoxScope.EditableHudPreview(
    sample: TelemetrySampleEntity,
    definition: VideoOverlayTemplateDefinition,
    portrait: Boolean,
    canvasSize: IntSize,
    selectedElementId: String?,
    select: (String) -> Unit,
    transform: (String, Float, Float, Float) -> Unit
) {
    definition.elements.forEach { element ->
        val position = element.position(portrait)
        HudElementPreview(
            sample = sample,
            element = element,
            style = definition.style,
            selected = selectedElementId == element.id,
            modifier = Modifier
                .align(Alignment.TopStart)
                .graphicsLayer {
                    translationX = position.x * canvasSize.width - 55.dp.toPx()
                    translationY = position.y * canvasSize.height - 33.dp.toPx()
                    val previewScale = .45f + element.effectiveScale * .32f
                    scaleX = previewScale
                    scaleY = previewScale
                }
                .pointerInput(element.id, canvasSize, portrait) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        select(element.id)
                        transform(element.id, pan.x, pan.y, zoom)
                    }
                }
                .clickable { select(element.id) }
        )
    }
}

@Composable
private fun HudElementPreview(
    sample: TelemetrySampleEntity,
    element: VideoOverlayElement,
    style: OverlayStyle,
    selected: Boolean,
    modifier: Modifier = Modifier
) {
    val accent = element.accent.color()
    val background = if (style == OverlayStyle.UNDERGROUND) Color.Black.copy(alpha = .82f) else Color(0xE6071014)
    val value = element.metric.sampleValue(sample)
    val shell = modifier
        .background(background, RoundedCornerShape(12.dp))
        .border(if (selected) 2.dp else 1.dp, if (selected) Color.White else accent.copy(alpha = .45f), RoundedCornerShape(12.dp))
        .padding(horizontal = 12.dp, vertical = 8.dp)
    when (element.kind) {
        OverlayElementKind.DIGITAL -> Column(shell, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(element.metric.localizedName(), color = TougeMuted, fontSize = 8.sp, fontWeight = FontWeight.Black)
            Text(element.metric.format(value), color = accent, fontSize = 25.sp, fontWeight = FontWeight.Black)
            Text(element.metric.unit, color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Bold)
        }
        OverlayElementKind.GAUGE -> Box(shell.size(112.dp), contentAlignment = Alignment.Center) {
            val progress = ((value - element.metric.defaultMin) / (element.metric.defaultMax - element.metric.defaultMin)).coerceIn(0.0, 1.0).toFloat()
            Canvas(Modifier.fillMaxSize()) {
                drawArc(Color.White.copy(alpha = .12f), 150f, 240f, false, style = androidx.compose.ui.graphics.drawscope.Stroke(8.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round))
                drawArc(accent, 150f, 240f * progress, false, style = androidx.compose.ui.graphics.drawscope.Stroke(8.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(element.metric.format(value), fontSize = 21.sp, fontWeight = FontWeight.Black)
                Text(element.metric.shortName, color = accent, fontSize = 8.sp, fontWeight = FontWeight.Black)
            }
        }
        OverlayElementKind.BAR -> Column(shell.fillMaxWidth(.62f)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(element.metric.shortName, color = TougeMuted, fontSize = 9.sp, fontWeight = FontWeight.Black)
                Text("${element.metric.format(value)} ${element.metric.unit}", fontWeight = FontWeight.Black)
            }
            val progress = ((value - element.metric.defaultMin) / (element.metric.defaultMax - element.metric.defaultMin)).coerceIn(0.0, 1.0).toFloat()
            Box(Modifier.fillMaxWidth().height(7.dp).background(Color.White.copy(alpha = .10f), RoundedCornerShape(4.dp))) {
                Box(Modifier.fillMaxWidth(progress.coerceAtLeast(.01f)).height(7.dp).background(accent, RoundedCornerShape(4.dp)))
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HudTemplateEditor(
    initial: VideoOverlayTemplate,
    dismiss: () -> Unit,
    save: (VideoOverlayTemplate) -> Unit,
    duplicate: () -> Unit,
    delete: () -> Unit
) {
    var value by remember(initial.entity.id) {
        mutableStateOf(initial.copy(definition = initial.definition.copy(elements = initial.definition.resolvedElements())))
    }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(appText("Edit video HUD", "Edytuj HUD filmu"), fontWeight = FontWeight.Black) },
        text = {
            Column(Modifier.height(540.dp).verticalScroll(androidx.compose.foundation.rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value.entity.name, { name -> value = value.copy(entity = value.entity.copy(name = name.take(80))) }, label = { Text(appText("Template name", "Nazwa szablonu")) }, singleLine = true)
                Text(appText("STYLE", "STYL"), color = TougeCyan, fontSize = 9.sp, fontWeight = FontWeight.Black)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    OverlayStyle.entries.forEach { style -> FilterChip(value.definition.style == style, { value = value.copy(definition = value.definition.copy(style = style)) }, label = { Text(style.name.lowercase().replaceFirstChar(Char::uppercase)) }) }
                }
                value.definition.elements.forEachIndexed { index, element ->
                    Card(colors = CardDefaults.cardColors(containerColor = TougePanel)) {
                        Column(Modifier.padding(11.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("${index + 1}.", color = element.accent.color(), fontWeight = FontWeight.Black)
                                VideoMetricMenu(element.metric) { metric -> value = value.withElement(element.copy(metric = metric)) }
                                IconButton(onClick = { value = value.copy(definition = value.definition.copy(elements = value.definition.elements.filterNot { it.id == element.id })) }) { Icon(Icons.Default.Delete, null, tint = TougeRed) }
                            }
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                OverlayElementKind.entries.forEach { kind -> FilterChip(element.kind == kind, { value = value.withElement(element.copy(kind = kind)) }, label = { Text(kind.name.lowercase()) }) }
                            }
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                OverlayElementScale.entries.forEach { scale -> FilterChip(element.scale == scale, { value = value.withElement(element.copy(scale = scale)) }, label = { Text(scale.name.lowercase().replace('_', ' ')) }) }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                                DashboardAccent.entries.forEach { accent ->
                                    Box(Modifier.size(if (element.accent == accent) 27.dp else 22.dp).background(accent.color(), androidx.compose.foundation.shape.CircleShape).border(if (element.accent == accent) 2.dp else 0.dp, Color.White, androidx.compose.foundation.shape.CircleShape).clickable { value = value.withElement(element.copy(accent = accent)) })
                                }
                            }
                        }
                    }
                }
                Button(onClick = {
                    val used = value.definition.elements.map { it.metric }.toSet()
                    val metric = TelemetryMetric.entries.firstOrNull { it !in used } ?: TelemetryMetric.SPEED
                    val newElement = VideoOverlayElement(metric = metric, landscapePosition = OverlayPosition(.5f, .5f), portraitPosition = OverlayPosition(.5f, .5f))
                    value = value.copy(definition = value.definition.copy(elements = value.definition.elements + newElement))
                }, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Add, null); Text(appText(" Add parameter", " Dodaj parametr")) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = duplicate, modifier = Modifier.weight(1f)) { Text(appText("Duplicate", "Duplikuj")) }
                    OutlinedButton(onClick = delete, modifier = Modifier.weight(1f)) { Text(appText("Delete", "Usuń"), color = TougeRed) }
                }
            }
        },
        confirmButton = { Button(enabled = value.entity.name.isNotBlank() && value.definition.elements.isNotEmpty(), onClick = { save(value) }) { Text(appText("Save HUD", "Zapisz HUD")) } },
        dismissButton = { TextButton(onClick = dismiss) { Text(appText("Cancel", "Anuluj")) } }
    )
}

@Composable
private fun RowScope.VideoMetricMenu(selected: TelemetryMetric, changed: (TelemetryMetric) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(Modifier.padding(start = 8.dp).weight(1f)) {
        OutlinedButton(onClick = { open = true }, modifier = Modifier.fillMaxWidth()) { Text(selected.localizedName()) }
        androidx.compose.material3.DropdownMenu(open, { open = false }) {
            TelemetryMetric.entries.forEach { metric -> androidx.compose.material3.DropdownMenuItem(text = { Text("${metric.localizedName()} · ${metric.unit}") }, onClick = { open = false; changed(metric) }) }
        }
    }
}

private fun VideoOverlayTemplate.withElement(element: VideoOverlayElement) = copy(
    definition = definition.copy(elements = definition.elements.map { if (it.id == element.id) element else it })
)

private fun TelemetryMetric.sampleValue(value: TelemetrySampleEntity): Double = when (this) {
    TelemetryMetric.RPM -> value.rpm
    TelemetryMetric.BOOST -> value.boostBar
    TelemetryMetric.MAP -> value.mapKpa
    TelemetryMetric.THROTTLE -> value.throttlePercent
    TelemetryMetric.COOLANT -> value.coolantCelsius
    TelemetryMetric.INTAKE -> value.intakeCelsius
    TelemetryMetric.OIL_TEMPERATURE -> value.oilTemperatureCelsius
    TelemetryMetric.OIL_PRESSURE -> value.oilPressureBar
    TelemetryMetric.FUEL_PRESSURE -> value.fuelPressureBar
    TelemetryMetric.AFR -> value.afr
    TelemetryMetric.LAMBDA -> value.lambda
    TelemetryMetric.BATTERY_VOLTAGE -> value.batteryVoltage
    TelemetryMetric.IGNITION -> value.ignitionDegrees
    TelemetryMetric.INJECTOR_DUTY -> value.injectorDutyPercent
    TelemetryMetric.SPEED -> value.speedKph
}

private fun List<TelemetrySampleEntity>.nearestTo(target: Long): TelemetrySampleEntity? {
    if (isEmpty()) return null
    val found = binarySearchBy(target) { it.recordedAt }
    if (found >= 0) return this[found]
    val insertion = -found - 1
    val before = getOrNull(insertion - 1)
    val after = getOrNull(insertion)
    return when {
        before == null -> after
        after == null -> before
        target - before.recordedAt <= after.recordedAt - target -> before
        else -> after
    }
}

private fun videoDuration(seconds: Double): String { val value = seconds.coerceAtLeast(0.0).roundToInt(); return "%d:%02d".format(value / 60, value % 60) }
private fun videoBytes(value: Long): String = when { value >= 1_073_741_824 -> "%.1f GB".format(value / 1_073_741_824.0); value >= 1_048_576 -> "%.1f MB".format(value / 1_048_576.0); else -> "%.0f kB".format(value / 1024.0) }

@Composable
private fun localizedVideoOperation(value: String): String = when (value) {
    "Copying video from gallery" -> appText("Copying video from gallery", "Kopiowanie filmu z galerii")
    "Rendering telemetry HUD" -> appText("Rendering telemetry HUD", "Renderowanie HUD-u z telemetrią")
    else -> value
}
