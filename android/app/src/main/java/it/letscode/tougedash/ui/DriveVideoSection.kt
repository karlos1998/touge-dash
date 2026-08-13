@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.ui

import android.net.Uri
import android.graphics.Color as AndroidColor
import android.graphics.Paint as AndroidPaint
import android.graphics.Typeface
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
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
import it.letscode.tougedash.ui.theme.TougeOrange
import it.letscode.tougedash.ui.theme.TougeRed
import it.letscode.tougedash.video.OverlayStyle
import it.letscode.tougedash.video.OverlayElementKind
import it.letscode.tougedash.video.OverlayElementScale
import it.letscode.tougedash.video.OverlayPosition
import it.letscode.tougedash.video.VideoOverlayElement
import it.letscode.tougedash.video.VideoOverlayTemplate
import it.letscode.tougedash.video.VideoOverlayTemplateDefinition
import kotlinx.coroutines.delay
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Polyline
import kotlin.math.roundToInt
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.abs

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
        Column {
            Text("VIDEO + TELEMETRY", color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Text(appText("Synchronized drive footage", "Nagrania zsynchronizowane z przejazdem"), fontWeight = FontWeight.Black)
        }
        Button(
            onClick = { picker.launch("video/*") },
            modifier = Modifier.fillMaxWidth().padding(top = 10.dp).heightIn(min = 44.dp)
        ) {
            Icon(Icons.Default.VideoLibrary, null, Modifier.size(18.dp))
            Text(appText(" Use my video", " Użyj mojego filmu"))
        }
        if (task.operation != null) {
            Card(Modifier.fillMaxWidth().padding(top = 10.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                Column(Modifier.padding(12.dp)) {
                    Text(localizedVideoOperation(task.operation!!), fontWeight = FontWeight.Bold)
                    LinearProgressIndicator(progress = { task.progress }, modifier = Modifier.fillMaxWidth().padding(top = 7.dp))
                    Text("${(task.progress * 100).roundToInt()}%${if (task.totalBytes > 0) "  •  ${videoBytes(task.transferredBytes)} / ${videoBytes(task.totalBytes)}" else ""}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 10.sp)
                    if (task.completed && task.outputWidth > 0) {
                        val codec = if (task.outputVideoMimeType?.contains("hevc", ignoreCase = true) == true) "HEVC" else "H.264"
                        val bitrate = task.outputVideoBitrate.takeIf { it > 0 }?.let { " • %.1f Mb/s".format(it / 1_000_000.0) }.orEmpty()
                        Text(
                            "$codec • ${task.outputWidth}×${task.outputHeight}$bitrate${if (task.outputHasAudio) " • audio" else ""}",
                            color = TougeCyan,
                            fontSize = 10.sp
                        )
                    }
                    task.error?.let { Text(it, color = TougeRed) }
                    if (task.completed || task.error != null) TextButton(onClick = container.videoRepository::clearTask) { Text(appText("Close", "Zamknij")) }
                    else if (task.operation == "Rendering telemetry HUD") TextButton(onClick = container.videoRepository::cancelExport) { Text(appText("Cancel export", "Anuluj eksport"), color = TougeRed) }
                }
            }
        }
        VideoGroup(appText("RECORDED BY TOUGE DASH", "NAGRANE PRZEZ TOUGE DASH"), videos.filter { it.sourceKind == "CAMERA" }, editing = { editing = it }, delete = container.videoRepository::delete)
        VideoGroup(appText("GALLERY EDITS", "PROJEKTY Z GALERII"), videos.filter { it.sourceKind == "GALLERY" }, editing = { editing = it }, delete = container.videoRepository::delete)
        if (videos.isEmpty() && task.operation == null) Text(appText("Record a drive with the phone camera or attach footage from a dashcam. The source video stays local on this device.", "Nagraj przejazd kamerą telefonu albo dodaj film z wideorejestratora. Film źródłowy pozostaje lokalnie na tym urządzeniu."), color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 12.dp))
    }
    editing?.let { project -> VideoAlignmentEditor(project, driveDuration, samples, container, { editing = null }, { changed -> container.videoRepository.update(changed); editing = changed }) }
}

@Composable
private fun VideoGroup(title: String, videos: List<VideoProjectEntity>, editing: (VideoProjectEntity) -> Unit, delete: (VideoProjectEntity) -> Unit) {
    if (videos.isEmpty()) return
    Text(title, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 9.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp, bottom = 5.dp))
    videos.forEach { video ->
        Card(Modifier.fillMaxWidth().padding(vertical = 4.dp).clickable { editing(video) }, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Movie, null, Modifier.size(34.dp), tint = TougeCyan)
                Column(Modifier.padding(start = 10.dp).weight(1f)) {
                    Text(video.sourceDisplayName ?: if (video.sourceKind == "CAMERA") appText("Drive recording", "Nagranie przejazdu") else appText("Gallery video", "Film z galerii"), fontWeight = FontWeight.Bold)
                    Text("${videoDuration(video.durationSeconds)}  •  ${videoBytes(video.fileSizeBytes)}  •  ${video.pixelWidth}×${video.pixelHeight}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 11.sp)
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
    var deletingElementId by remember { mutableStateOf<String?>(null) }
    var widgetMenuOpen by remember { mutableStateOf(false) }
    var elementBounds by remember { mutableStateOf<Map<String, Rect>>(emptyMap()) }
    val portraitVideo = initial.pixelHeight > initial.pixelWidth
    var previewSize by remember { mutableStateOf(IntSize.Zero) }
    LaunchedEffect(templates, templateId) {
        (templates.firstOrNull { it.entity.id == templateId } ?: templates.firstOrNull())?.let {
            if (templateId != it.entity.id) {
                templateId = it.entity.id
                value = value.copy(overlayTemplateId = it.entity.id)
            }
            overlayDefinition = it.definition.copy(elements = it.definition.resolvedElements())
            selectedElementId = overlayDefinition.elements.firstOrNull()?.id
        }
    }
    val player = remember(initial.id) { ExoPlayer.Builder(context).build().apply { setMediaItem(MediaItem.fromUri(initial.localUri)); prepare(); seekTo((initial.videoTrimStartSeconds * 1000).toLong()) } }
    var position by remember { mutableLongStateOf((initial.videoTrimStartSeconds * 1000).toLong()) }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(player) {
        while (true) {
            position = player.currentPosition
            val rangeStartMs = (value.videoTrimStartSeconds * 1000).toLong()
            val rangeEndMs = ((value.videoTrimStartSeconds + value.exportDurationSeconds) * 1000).toLong()
            if (position > rangeEndMs + 50) {
                player.pause()
                player.seekTo(rangeStartMs)
                position = rangeStartMs
            }
            delay(if (player.isPlaying) 33 else 80)
        }
    }
    val telemetrySecond = value.telemetryTrimStartSeconds + (position / 1000.0 - value.videoTrimStartSeconds).coerceAtLeast(0.0)
    val first = samples.firstOrNull()?.recordedAt ?: 0
    val previewRecordedAt = (first + telemetrySecond * 1000).toLong()
    val sample = samples.nearestTo(previewRecordedAt)
    val transformElement: (String, Float, Float, Float) -> Unit = { id, dx, dy, zoom ->
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
    val currentOverlayDefinition by rememberUpdatedState(overlayDefinition)
    val currentTransformElement by rememberUpdatedState(transformElement)
    val currentElementBounds by rememberUpdatedState(elementBounds)
    val preview: @Composable BoxScope.() -> Unit = {
        AndroidView(
            factory = { PlayerView(it).apply { useController = false; this.player = player } },
            modifier = Modifier.fillMaxSize()
        )
        sample?.let { current ->
            EditableHudPreview(
                sample = current,
                samples = samples,
                routeTimestamp = previewRecordedAt,
                definition = overlayDefinition,
                portrait = portraitVideo,
                canvasSize = previewSize,
                selectedElementId = selectedElementId,
                select = { selectedElementId = it },
                elementBoundsChanged = { id, bounds ->
                    if (elementBounds[id] != bounds) elementBounds = elementBounds + (id to bounds)
                },
                mapZoom = { id, delta ->
                    overlayDefinition = overlayDefinition.copy(elements = overlayDefinition.elements.map { element ->
                        if (element.id == id) element.withMapZoom(element.mapZoom + delta) else element
                    })
                    selectedElementId = id
                },
                requestDelete = { deletingElementId = it }
            )
        }
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .padding(10.dp)
        ) {
            IconButton(
                onClick = { widgetMenuOpen = true },
                modifier = Modifier
                    .size(38.dp)
                    .background(Color.Black.copy(alpha = .62f), androidx.compose.foundation.shape.CircleShape)
                    .border(1.dp, TougeCyan.copy(alpha = .82f), androidx.compose.foundation.shape.CircleShape)
            ) {
                Icon(Icons.Default.Add, appText("Add widget", "Dodaj widget"), tint = Color.White)
            }
            androidx.compose.material3.DropdownMenu(
                expanded = widgetMenuOpen,
                onDismissRequest = { widgetMenuOpen = false }
            ) {
                templates.forEach { template ->
                    template.definition.resolvedElements().forEach { source ->
                        androidx.compose.material3.DropdownMenuItem(
                            text = {
                                Column {
                                    Text(widgetKindName(source.kind), fontWeight = FontWeight.Bold)
                                    Text(
                                        template.entity.name + if (source.kind.isRouteMap) "" else " · ${source.metric.shortName}",
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        fontSize = 10.sp
                                    )
                                }
                            },
                            onClick = {
                                val widget = source.copy(id = java.util.UUID.randomUUID().toString())
                                overlayDefinition = overlayDefinition.copy(elements = overlayDefinition.elements + widget)
                                selectedElementId = widget.id
                                widgetMenuOpen = false
                            }
                        )
                    }
                }
            }
        }
        IconButton(
            onClick = {
                if (player.isPlaying) player.pause()
                else {
                    if (position / 1000.0 !in value.videoTrimStartSeconds..(value.videoTrimStartSeconds + value.exportDurationSeconds)) {
                        player.seekTo((value.videoTrimStartSeconds * 1000).toLong())
                    }
                    player.play()
                }
            },
            modifier = Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = .45f), RoundedCornerShape(30.dp))
        ) {
            Icon(if (player.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, null, tint = Color.White)
        }
    }
    val controls: @Composable () -> Unit = {
        Column(
            Modifier.fillMaxWidth().verticalScroll(androidx.compose.foundation.rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)
        ) {
            Text(appText("CHOOSE CLIP TO EXPORT", "WYBIERZ FRAGMENT DO EKSPORTU"), color = TougeOrange, fontSize = 10.sp, fontWeight = FontWeight.Black)
            Row(Modifier.fillMaxWidth().padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(videoDuration(value.exportDurationSeconds), fontSize = 20.sp, fontWeight = FontWeight.Black)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Text(
                    "${videoDuration(value.videoTrimStartSeconds)} – ${videoDuration(value.videoTrimStartSeconds + value.exportDurationSeconds)}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            Row(
                Modifier.fillMaxWidth().padding(top = 9.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = {
                        if (player.isPlaying) player.pause()
                        else {
                            val startMs = (value.videoTrimStartSeconds * 1000).toLong()
                            val endMs = ((value.videoTrimStartSeconds + value.exportDurationSeconds) * 1000).toLong()
                            if (position !in startMs..endMs) {
                                player.seekTo(startMs)
                                position = startMs
                            }
                            player.play()
                        }
                    },
                    modifier = Modifier.size(54.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .12f), RoundedCornerShape(11.dp))
                ) {
                    Icon(if (player.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, null)
                }
                VideoTrimRangeSelector(
                    totalDuration = value.durationSeconds,
                    start = value.videoTrimStartSeconds,
                    end = value.videoTrimStartSeconds + value.exportDurationSeconds,
                    cursor = position / 1000.0,
                    speedValues = samples.map { it.speedKph },
                    startChanged = { requested ->
                        val oldStart = value.videoTrimStartSeconds
                        val oldEnd = oldStart + value.exportDurationSeconds
                        val newStart = requested.coerceIn(0.0, (oldEnd - .1).coerceAtLeast(0.0))
                        val delta = newStart - oldStart
                        val newDuration = oldEnd - newStart
                        val newTelemetryStart = (value.telemetryTrimStartSeconds + delta)
                            .coerceIn(0.0, (driveDuration - newDuration).coerceAtLeast(0.0))
                        value = value.copy(
                            videoTrimStartSeconds = newStart,
                            telemetryTrimStartSeconds = newTelemetryStart,
                            exportDurationSeconds = newDuration
                        )
                        player.pause()
                        val target = (newStart * 1000).toLong()
                        player.seekTo(target)
                        position = target
                    },
                    endChanged = { requested ->
                        val maximumEnd = minOf(
                            value.durationSeconds,
                            value.videoTrimStartSeconds + driveDuration - value.telemetryTrimStartSeconds
                        )
                        val newEnd = requested.coerceIn(value.videoTrimStartSeconds + .1, maximumEnd.coerceAtLeast(value.videoTrimStartSeconds + .1))
                        value = value.copy(exportDurationSeconds = newEnd - value.videoTrimStartSeconds)
                        player.pause()
                        val target = (newEnd * 1000).toLong()
                        player.seekTo(target)
                        position = target
                    },
                    cursorChanged = { requested ->
                        val target = (requested.coerceIn(value.videoTrimStartSeconds, value.videoTrimStartSeconds + value.exportDurationSeconds) * 1000).toLong()
                        player.pause()
                        player.seekTo(target)
                        position = target
                    },
                    modifier = Modifier.weight(1f).height(76.dp)
                )
            }
            Text(
                appText(
                    "Drag the yellow handles to trim. Drag the white line to inspect the selected clip.",
                    "Przeciągnij żółte uchwyty, aby przyciąć film. Białą kreską szybko przejrzysz wybrany fragment."
                ),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 10.sp,
                modifier = Modifier.padding(top = 6.dp, bottom = 14.dp)
            )

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .045f))) {
                Column(Modifier.fillMaxWidth().padding(12.dp)) {
                    Text(appText("MATCH TELEMETRY TO VIDEO", "DOPASUJ PARAMETRY DO FILMU"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    Text(
                        "${appText("Telemetry", "Dane")}: ${videoDuration(value.telemetryTrimStartSeconds)} – ${videoDuration(value.telemetryTrimStartSeconds + value.exportDurationSeconds)}",
                        color = TougeMint,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(top = 5.dp)
                    )
                    Slider(
                        value.telemetryTrimStartSeconds.toFloat(),
                        {
                            value = value.copy(telemetryTrimStartSeconds = it.toDouble())
                            position = position.coerceIn(
                                (value.videoTrimStartSeconds * 1000).toLong(),
                                ((value.videoTrimStartSeconds + value.exportDurationSeconds) * 1000).toLong()
                            )
                        },
                        valueRange = 0f..(driveDuration - value.exportDurationSeconds).coerceAtLeast(.01).toFloat()
                    )
                }
            }

            Text(appText("HUD TEMPLATE", "SZABLON HUD"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                templates.forEach { item ->
                    FilterChip(
                        selected = templateId == item.entity.id,
                        onClick = {
                            templateId = item.entity.id
                            overlayDefinition = item.definition.copy(elements = item.definition.resolvedElements())
                            selectedElementId = overlayDefinition.elements.firstOrNull()?.id
                            value = value.copy(overlayTemplateId = item.entity.id)
                        },
                        label = { Text(item.entity.name) }
                    )
                }
            }
            Text(appText("Drag HUD elements and pinch with two fingers to resize. Tap a widget to reveal its remove button. Portrait and landscape layouts are stored separately.", "Przeciągaj elementy HUD i uszczypnij dwoma palcami, aby zmienić rozmiar. Stuknij widget, aby pokazać przycisk usuwania. Układ pionowy i poziomy zapisuje się osobno."), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 10.sp)
            OutlinedButton(
                onClick = { templates.firstOrNull { it.entity.id == templateId }?.let { container.videoRepository.updateOverlayTemplate(it.copy(definition = overlayDefinition)) } },
                modifier = Modifier.fillMaxWidth()
            ) { Text(appText("Save layout in this template", "Zapisz układ w tym szablonie")) }
            OutlinedButton(
                onClick = { editingTemplate = templates.firstOrNull { it.entity.id == templateId }?.copy(definition = overlayDefinition) },
                modifier = Modifier.fillMaxWidth()
            ) { Icon(Icons.Default.Tune, null); Text(appText(" Edit HUD parameters", " Edytuj parametry HUD")) }
        }
    }
    Dialog(
        onDismissRequest = dismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
    ) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = dismiss) { Icon(Icons.Default.Close, appText("Close", "Zamknij")) }
                    Column(Modifier.weight(1f)) {
                        Text(appText("VIDEO + TELEMETRY", "WIDEO + TELEMETRIA"), color = TougeCyan, fontSize = 9.sp, fontWeight = FontWeight.Black)
                        Text(appText("Align and arrange HUD", "Dopasuj film i ustaw HUD"), fontWeight = FontWeight.Black)
                    }
                    TextButton(onClick = { save(value.copy(overlayTemplateId = templateId)); dismiss() }) {
                        Text(appText("Save", "Zapisz"))
                    }
                }
                BoxWithConstraints(
                    Modifier.fillMaxWidth().weight(1f).background(Color.Black),
                    contentAlignment = Alignment.Center
                ) {
                    val aspect = initial.pixelWidth.coerceAtLeast(1).toFloat() / initial.pixelHeight.coerceAtLeast(1)
                    val stageModifier = if (maxWidth.value / maxHeight.value > aspect) {
                        Modifier.fillMaxHeight().aspectRatio(aspect)
                    } else {
                        Modifier.fillMaxWidth().aspectRatio(aspect)
                    }
                    Box(
                        stageModifier
                            .background(Color.Black)
                            .onSizeChanged { previewSize = it }
                            .pointerInput(portraitVideo, previewSize) {
                                awaitEachGesture {
                                    val down = awaitFirstDown(requireUnconsumed = false)
                                    val activeElementID = currentElementBounds.elementIDAt(
                                        down.position,
                                        currentOverlayDefinition.elements.mapTo(mutableSetOf()) { it.id }
                                    )
                                        ?: return@awaitEachGesture
                                    selectedElementId = activeElementID
                                    var hasPressedPointers = true
                                    while (hasPressedPointers) {
                                        val event = awaitPointerEvent()
                                        val pressedPointers = event.changes.count { it.pressed }
                                        val previouslyPressedPointers = event.changes.count { it.previousPressed }
                                        // One finger moves the locked widget. Once another finger joins,
                                        // only their distance changes its size, so it cannot drift toward
                                        // the second widget under that finger.
                                        val pan = if (pressedPointers == 1 && previouslyPressedPointers == 1) {
                                            event.calculatePan()
                                        } else {
                                            Offset.Zero
                                        }
                                        val zoom = if (pressedPointers >= 2 && previouslyPressedPointers >= 2) {
                                            event.calculateZoom()
                                        } else {
                                            1f
                                        }
                                        if (pan != Offset.Zero || zoom != 1f) {
                                            currentTransformElement(activeElementID, pan.x, pan.y, zoom)
                                            event.changes.forEach { change ->
                                                if (change.pressed) change.consume()
                                            }
                                        }
                                        hasPressedPointers = event.changes.any { it.pressed }
                                    }
                                }
                            },
                        content = preview
                    )
                }
                Box(Modifier.fillMaxWidth().heightIn(max = 440.dp).background(MaterialTheme.colorScheme.surface)) { controls() }
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = { save(value.copy(overlayTemplateId = templateId)); dismiss() },
                        modifier = Modifier.weight(1f)
                    ) { Text(appText("Save project", "Zapisz projekt")) }
                    Button(
                        onClick = {
                            val exportValue = value.copy(overlayTemplateId = templateId)
                            save(exportValue)
                            container.videoRepository.export(exportValue, samples, overlayDefinition)
                            dismiss()
                        },
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(Icons.Default.Download, null)
                        Text(appText(" Export", " Eksportuj"))
                    }
                }
            }
        }
    }
    deletingElementId?.let { id ->
        AlertDialog(
            onDismissRequest = { deletingElementId = null },
            icon = { Icon(Icons.Default.Delete, null, tint = TougeRed) },
            title = { Text(appText("Remove widget?", "Usunąć widget?")) },
            text = { Text(appText("It will disappear from this video layout. You can add it again with +.", "Zniknie z układu tego filmu. Zawsze możesz dodać go ponownie przyciskiem +.")) },
            confirmButton = {
                TextButton(onClick = {
                    overlayDefinition = overlayDefinition.withoutElement(id)
                    if (selectedElementId == id) selectedElementId = null
                    deletingElementId = null
                }) { Text(appText("Remove", "Usuń"), color = TougeRed) }
            },
            dismissButton = {
                TextButton(onClick = { deletingElementId = null }) { Text(appText("Cancel", "Anuluj")) }
            }
        )
    }
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

private enum class VideoTrimDragTarget { START, END, CURSOR }

@Composable
private fun VideoTrimRangeSelector(
    totalDuration: Double,
    start: Double,
    end: Double,
    cursor: Double,
    speedValues: List<Double>,
    startChanged: (Double) -> Unit,
    endChanged: (Double) -> Unit,
    cursorChanged: (Double) -> Unit,
    modifier: Modifier = Modifier
) {
    val currentStart by rememberUpdatedState(start)
    val currentEnd by rememberUpdatedState(end)
    val currentStartChanged by rememberUpdatedState(startChanged)
    val currentEndChanged by rememberUpdatedState(endChanged)
    val currentCursorChanged by rememberUpdatedState(cursorChanged)
    val density = LocalDensity.current
    val handleWidthPx = with(density) { 24.dp.toPx() }
    val minimumDuration = minOf(1.0, totalDuration.coerceAtLeast(.1))
    val safeTotal = totalDuration.coerceAtLeast(.1)
    var trackSize by remember { mutableStateOf(IntSize.Zero) }

    Canvas(
        modifier
            .background(Color.Black, RoundedCornerShape(10.dp))
            .onSizeChanged { trackSize = it }
            .pointerInput(safeTotal) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val width = trackSize.width.coerceAtLeast(1).toFloat()
                    val startX = (currentStart / safeTotal * width).toFloat()
                    val endX = (currentEnd / safeTotal * width).toFloat()
                    val target = when {
                        abs(down.position.x - startX) <= handleWidthPx -> VideoTrimDragTarget.START
                        abs(down.position.x - endX) <= handleWidthPx -> VideoTrimDragTarget.END
                        else -> VideoTrimDragTarget.CURSOR
                    }

                    fun update(x: Float) {
                        val seconds = (x.coerceIn(0f, width) / width * safeTotal).toDouble()
                        when (target) {
                            VideoTrimDragTarget.START -> currentStartChanged(
                                seconds.coerceIn(0.0, (currentEnd - minimumDuration).coerceAtLeast(0.0))
                            )
                            VideoTrimDragTarget.END -> currentEndChanged(
                                seconds.coerceIn(currentStart + minimumDuration, safeTotal)
                            )
                            VideoTrimDragTarget.CURSOR -> currentCursorChanged(
                                seconds.coerceIn(currentStart, currentEnd)
                            )
                        }
                    }

                    update(down.position.x)
                    down.consume()
                    var pressed = true
                    while (pressed) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull() ?: break
                        update(change.position.x)
                        change.consume()
                        pressed = event.changes.any { it.pressed }
                    }
                }
            }
    ) {
        val width = size.width.coerceAtLeast(1f)
        val left = (width * (start / safeTotal).toFloat()).coerceIn(0f, width)
        val right = (width * (end / safeTotal).toFloat()).coerceIn(left, width)
        val cursorX = (width * (cursor.coerceIn(start, end) / safeTotal).toFloat()).coerceIn(left, right)

        drawRect(Color.White.copy(alpha = .08f))
        if (speedValues.size > 1) {
            val maximum = speedValues.maxOrNull()?.coerceAtLeast(1.0) ?: 1.0
            val path = Path()
            speedValues.forEachIndexed { index, value ->
                val x = width * index / (speedValues.size - 1).toFloat()
                val y = size.height * (1f - (value / maximum).toFloat().coerceIn(0f, 1f))
                if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            drawPath(path, TougeMint.copy(alpha = .72f), style = Stroke(width = 2.dp.toPx()))
        }

        drawRect(Color.Black.copy(alpha = .67f), size = Size(left, size.height))
        drawRect(
            Color.Black.copy(alpha = .67f),
            topLeft = Offset(right, 0f),
            size = Size((width - right).coerceAtLeast(0f), size.height)
        )
        drawRoundRect(
            TougeOrange,
            topLeft = Offset(left, 0f),
            size = Size((right - left).coerceAtLeast(1f), size.height),
            cornerRadius = CornerRadius(8.dp.toPx()),
            style = Stroke(width = 3.dp.toPx())
        )

        val handleHalf = handleWidthPx / 2
        drawRoundRect(
            TougeOrange,
            topLeft = Offset((left - handleHalf).coerceIn(0f, (width - handleWidthPx).coerceAtLeast(0f)), 0f),
            size = Size(handleWidthPx, size.height),
            cornerRadius = CornerRadius(7.dp.toPx())
        )
        drawRoundRect(
            TougeOrange,
            topLeft = Offset((right - handleHalf).coerceIn(0f, (width - handleWidthPx).coerceAtLeast(0f)), 0f),
            size = Size(handleWidthPx, size.height),
            cornerRadius = CornerRadius(7.dp.toPx())
        )
        drawLine(Color.Black, Offset(left - 3.dp.toPx(), size.height / 2), Offset(left + 3.dp.toPx(), size.height / 2), 3.dp.toPx())
        drawLine(Color.Black, Offset(right - 3.dp.toPx(), size.height / 2), Offset(right + 3.dp.toPx(), size.height / 2), 3.dp.toPx())
        drawLine(Color.White, Offset(cursorX, 5.dp.toPx()), Offset(cursorX, size.height - 5.dp.toPx()), 4.dp.toPx())
        drawCircle(Color.White, radius = 5.dp.toPx(), center = Offset(cursorX, 7.dp.toPx()))
    }
}

@Composable
private fun widgetKindName(kind: OverlayElementKind) = when (kind) {
    OverlayElementKind.DIGITAL -> appText("Digital value", "Wartość cyfrowa")
    OverlayElementKind.GAUGE -> appText("Gauge", "Zegar")
    OverlayElementKind.BAR -> appText("Telemetry bar", "Pasek telemetrii")
    OverlayElementKind.SPEED_CLUSTER -> appText("Speed cluster", "Zespół prędkości")
    OverlayElementKind.OIL_CLUSTER -> appText("Oil cluster", "Zespół oleju")
    OverlayElementKind.NEON_TACH -> "Neon Tach"
    OverlayElementKind.BLACKLIST_TACH -> "Blacklist Tach"
    OverlayElementKind.CARBON_TACH -> "Carbon Tach"
    OverlayElementKind.STREET_SHIFT_TACH -> "Street Shift Tach"
    OverlayElementKind.ROUTE_MAP -> appText("Route minimap", "Minimapa trasy")
    OverlayElementKind.ROUTE_MAP_CIRCULAR -> appText("Circular route minimap", "Okrągła minimapa trasy")
    OverlayElementKind.ROUTE_MAP_FOLLOW -> appText("Follow minimap", "Minimapa śledząca")
    OverlayElementKind.ROUTE_MAP_LIGHT -> appText("Light street map", "Jasna mapa ulic")
    OverlayElementKind.ROUTE_MAP_LIGHT_CIRCULAR -> appText("Circular light map", "Okrągła jasna mapa")
    OverlayElementKind.ROUTE_MAP_AMBER -> appText("Amber map", "Bursztynowa mapa")
}

@Composable
private fun GaugeScaleSlider(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    unit: String,
    step: Float = 5f,
    changed: (Float) -> Unit
) {
    val snapped = { raw: Float -> (raw / step).roundToInt() * step }
    Text("$label: ${if (step < 1f) "%.1f".format(value) else value.roundToInt()} $unit", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 10.sp)
    Slider(value, { changed(snapped(it).coerceIn(range)) }, valueRange = range)
}

@Composable
private fun BoxScope.EditableHudPreview(
    sample: TelemetrySampleEntity,
    samples: List<TelemetrySampleEntity>,
    routeTimestamp: Long,
    definition: VideoOverlayTemplateDefinition,
    portrait: Boolean,
    canvasSize: IntSize,
    selectedElementId: String?,
    select: (String) -> Unit,
    elementBoundsChanged: (String, Rect) -> Unit,
    mapZoom: (String, Float) -> Unit,
    requestDelete: (String) -> Unit
) {
    val density = LocalDensity.current
    val previewWidthDp = with(density) { canvasSize.width.toDp().value }
    val fitScale = (previewWidthDp / if (portrait) 430f else 760f).coerceIn(.34f, .9f)
    definition.elements.forEach { element ->
        val position = element.position(portrait)
        Box(
            Modifier
                .align(Alignment.TopStart)
                .graphicsLayer {
                    translationX = position.x * canvasSize.width - 55.dp.toPx()
                    translationY = position.y * canvasSize.height - 33.dp.toPx()
                    val previewScale = (fitScale * element.effectiveScale).coerceIn(.24f, 1.5f)
                    scaleX = previewScale
                    scaleY = previewScale
                }
                .onGloballyPositioned { elementBoundsChanged(element.id, it.boundsInParent()) }
        ) {
            HudElementPreview(
                sample = sample,
                samples = samples,
                routeTimestamp = routeTimestamp,
                element = element,
                definition = definition,
                style = definition.style,
                selected = selectedElementId == element.id,
                modifier = Modifier.clickable { select(element.id) }
            )
            if (selectedElementId == element.id) {
                IconButton(
                    onClick = { requestDelete(element.id) },
                    modifier = Modifier
                        .align(
                            if (position.y < .3f) {
                                if (position.x < .3f) Alignment.BottomEnd else Alignment.BottomStart
                            } else {
                                if (position.x < .3f) Alignment.TopEnd else Alignment.TopStart
                            }
                        )
                        .offset(
                            x = if (position.x < .3f) (-8).dp else 8.dp,
                            y = if (position.y < .3f) (-8).dp else 8.dp
                        )
                        .size(30.dp)
                        .background(TougeRed.copy(alpha = .94f), androidx.compose.foundation.shape.CircleShape)
                        .border(1.dp, Color.White.copy(alpha = .9f), androidx.compose.foundation.shape.CircleShape)
                ) {
                    Icon(Icons.Default.Delete, appText("Remove widget", "Usuń widget"), tint = Color.White, modifier = Modifier.size(16.dp))
                }
            }
            if (element.kind.isRouteMap) {
                Column(
                    Modifier
                        .align(if (position.x > .7f) Alignment.CenterStart else Alignment.CenterEnd)
                        .offset(x = if (position.x > .7f) (-38).dp else 38.dp)
                        .background(Color.Black.copy(alpha = .78f), RoundedCornerShape(40.dp))
                        .border(1.dp, element.accent.color().copy(alpha = .85f), RoundedCornerShape(40.dp))
                        .padding(3.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(1.dp)
                ) {
                    MapZoomButton("+") { mapZoom(element.id, .15f) }
                    Text("%.1f".format(element.mapZoom), color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Black)
                    MapZoomButton("−") { mapZoom(element.id, -.15f) }
                }
            }
        }
    }
}

@Composable
private fun MapZoomButton(label: String, action: () -> Unit) {
    IconButton(
        onClick = action,
        modifier = Modifier.size(26.dp).background(Color.White.copy(alpha = .13f), androidx.compose.foundation.shape.CircleShape)
    ) {
        Text(label, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun HudElementPreview(
    sample: TelemetrySampleEntity,
    samples: List<TelemetrySampleEntity>,
    routeTimestamp: Long,
    element: VideoOverlayElement,
    definition: VideoOverlayTemplateDefinition,
    style: OverlayStyle,
    selected: Boolean,
    modifier: Modifier = Modifier
) {
    val accent = element.accent.color()
    val background = if (style == OverlayStyle.UNDERGROUND) Color.Black.copy(alpha = .82f) else Color(0xE6071014)
    val value = element.metric.sampleValue(sample)
    val circularMap = element.kind.isCircularRouteMap
    val shellShape = if (circularMap) androidx.compose.foundation.shape.CircleShape else RoundedCornerShape(12.dp)
    val shell = modifier
        .background(background, shellShape)
        .border(if (selected) 2.dp else 1.dp, if (selected) Color.White else accent.copy(alpha = .45f), shellShape)
        .padding(horizontal = 12.dp, vertical = 8.dp)
    when (element.kind) {
        OverlayElementKind.DIGITAL -> Column(shell, horizontalAlignment = Alignment.CenterHorizontally) {
            Text(element.metric.localizedName(), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 8.sp, fontWeight = FontWeight.Black)
            Text(element.metric.format(value), color = accent, fontSize = 25.sp, fontWeight = FontWeight.Black)
            Text(element.metric.unit, color = Color.White, fontSize = 8.sp, fontWeight = FontWeight.Bold)
        }
        OverlayElementKind.GAUGE -> Box(shell.size(112.dp), contentAlignment = Alignment.Center) {
            val progress = definition.progress(element.metric, value)
            RacingDial(progress, definition.range(element.metric), element.metric, accent, Modifier.fillMaxSize())
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(element.metric.format(value), fontSize = 21.sp, fontWeight = FontWeight.Black)
                Text(element.metric.shortName, color = accent, fontSize = 8.sp, fontWeight = FontWeight.Black)
            }
        }
        OverlayElementKind.BAR -> Column(shell.fillMaxWidth(.62f)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(element.metric.shortName, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 9.sp, fontWeight = FontWeight.Black)
                Text("${element.metric.format(value)} ${element.metric.unit}", fontWeight = FontWeight.Black)
            }
            val progress = definition.progress(element.metric, value)
            Box(Modifier.fillMaxWidth().height(7.dp).background(Color.White.copy(alpha = .10f), RoundedCornerShape(4.dp))) {
                Box(Modifier.fillMaxWidth(progress.coerceAtLeast(.01f)).height(7.dp).background(accent, RoundedCornerShape(4.dp)))
            }
        }
        OverlayElementKind.SPEED_CLUSTER -> Box(shell.size(132.dp), contentAlignment = Alignment.Center) {
            RacingDial(definition.progress(TelemetryMetric.SPEED, sample.speedKph), definition.range(TelemetryMetric.SPEED), TelemetryMetric.SPEED, accent, Modifier.fillMaxSize())
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(top = 19.dp)) {
                Text("RPM ${sample.rpm.roundToInt()}", color = Color.White.copy(alpha = .72f), fontSize = 7.sp, fontWeight = FontWeight.Black)
                Text(sample.speedKph.roundToInt().toString(), color = Color.White, fontSize = 27.sp, fontWeight = FontWeight.Black)
                Text("km/h", color = accent, fontSize = 7.sp, fontWeight = FontWeight.Black)
                Text("BOOST ${"%.1f".format(sample.boostBar)}", color = TougeMint, fontSize = 6.sp, fontWeight = FontWeight.Black)
                val boost = definition.progress(TelemetryMetric.BOOST, sample.boostBar)
                Box(Modifier.width(54.dp).height(4.dp).background(Color.White.copy(alpha = .13f), RoundedCornerShape(3.dp))) {
                    Box(Modifier.fillMaxWidth(boost.coerceAtLeast(.01f)).height(4.dp).background(TougeMint, RoundedCornerShape(3.dp)))
                }
            }
        }
        OverlayElementKind.OIL_CLUSTER -> Box(shell.size(120.dp), contentAlignment = Alignment.Center) {
            RacingDial(definition.progress(TelemetryMetric.OIL_TEMPERATURE, sample.oilTemperatureCelsius), definition.range(TelemetryMetric.OIL_TEMPERATURE), TelemetryMetric.OIL_TEMPERATURE, accent, Modifier.fillMaxSize())
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(top = 14.dp)) {
                Text("OIL TEMP", color = accent, fontSize = 7.sp, fontWeight = FontWeight.Black)
                Text("${sample.oilTemperatureCelsius.roundToInt()}°", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black)
                Text("OIL P  ${"%.1f".format(sample.oilPressureBar)} bar", color = Color.White.copy(alpha = .78f), fontSize = 7.sp, fontWeight = FontWeight.Black)
            }
        }
        OverlayElementKind.NEON_TACH,
        OverlayElementKind.BLACKLIST_TACH,
        OverlayElementKind.CARBON_TACH,
        OverlayElementKind.STREET_SHIFT_TACH -> ArcadeTachPreview(sample, element.kind, definition, shell)
        OverlayElementKind.ROUTE_MAP,
        OverlayElementKind.ROUTE_MAP_CIRCULAR,
        OverlayElementKind.ROUTE_MAP_FOLLOW,
        OverlayElementKind.ROUTE_MAP_LIGHT,
        OverlayElementKind.ROUTE_MAP_LIGHT_CIRCULAR,
        OverlayElementKind.ROUTE_MAP_AMBER -> NfsRouteMapPreview(samples, routeTimestamp, element.kind, element.mapZoom, accent, circularMap, shell)
    }
}

@Composable
private fun NfsRouteMapPreview(
    samples: List<TelemetrySampleEntity>,
    routeTimestamp: Long,
    kind: OverlayElementKind,
    mapZoom: Float,
    accent: Color,
    circular: Boolean,
    modifier: Modifier
) {
    val context = LocalContext.current
    val located = remember(samples) {
        samples.mapNotNull { value ->
            val latitude = value.latitude
            val longitude = value.longitude
            if (latitude == null || longitude == null) null else value to GeoPoint(latitude, longitude)
        }.fold(mutableListOf<Pair<TelemetrySampleEntity, GeoPoint>>()) { result, point ->
            val previous = result.lastOrNull()?.second
            if (previous == null || previous.latitude != point.second.latitude || previous.longitude != point.second.longitude) {
                result += point
            }
            result
        }
    }
    val currentPosition = remember(located, routeTimestamp) { located.interpolatePosition(routeTimestamp) }
    val previousPosition = remember(located, routeTimestamp) { located.interpolatePosition(routeTimestamp - 1_500) }
    val nextPosition = remember(located, routeTimestamp) { located.interpolatePosition(routeTimestamp + 1_500) }
    val travelled = remember(located, routeTimestamp, currentPosition) {
        located.takeWhile { it.first.recordedAt <= routeTimestamp }.map { it.second }.toMutableList().apply {
            currentPosition?.let(::add)
        }
    }
    val points = remember(located) { located.map { it.second } }
    val routeKey = remember(points) { points.firstOrNull()?.let { "${points.size}:${it.latitude}:${it.longitude}:${points.last().latitude}:${points.last().longitude}" } }
    val sizeModifier = if (circular) Modifier.size(172.dp) else Modifier.width(240.dp).height(150.dp)
    val mapShape = if (circular) androidx.compose.foundation.shape.CircleShape else RoundedCornerShape(12.dp)
    Box(modifier.then(sizeModifier).graphicsLayer { shape = mapShape; clip = true }.padding(0.dp)) {
        if (points.isNotEmpty()) {
            AndroidView(
                factory = {
                    Configuration.getInstance().userAgentValue = context.packageName
                    MapView(context).apply {
                        setTileSource(TileSourceFactory.MAPNIK)
                        setMultiTouchControls(false)
                        isClickable = false
                        isFocusable = false
                    }
                },
                update = { map ->
                    val fullRoute = Polyline().apply {
                        outlinePaint.color = AndroidColor.argb(155, 255, 255, 255)
                        outlinePaint.strokeWidth = 7f
                        setPoints(points)
                    }
                    val currentRoute = Polyline().apply {
                        outlinePaint.color = accent.toArgb()
                        outlinePaint.strokeWidth = 10f
                        setPoints(travelled)
                    }
                    map.overlays.clear()
                    map.overlays.add(fullRoute)
                    map.overlays.add(currentRoute)
                    if (currentPosition != null) {
                        map.controller.setCenter(currentPosition)
                        // MapView requests a finer tile level, so this is a real map-camera
                        // zoom rather than scaling the already drawn preview bitmap.
                        map.controller.setZoom(17.5 + kotlin.math.log2(mapZoom.coerceIn(.65f, 3.5f).toDouble()))
                        map.mapOrientation = -(previousPosition?.bearingTo(nextPosition ?: currentPosition)?.toFloat() ?: 0f)
                    } else if (map.tag != routeKey) {
                        map.tag = routeKey
                        map.post {
                            if (points.size > 1) map.zoomToBoundingBox(BoundingBox.fromGeoPointsSafe(points), false, 26)
                            else points.firstOrNull()?.let { map.controller.setCenter(it); map.controller.setZoom(17.0) }
                        }
                    }
                    map.invalidate()
                },
                modifier = Modifier.fillMaxSize()
            )
            val mapTint = when {
                kind == OverlayElementKind.ROUTE_MAP_AMBER -> Color(0x55F28B22)
                kind.usesLightMap -> Color.White.copy(alpha = .05f)
                kind == OverlayElementKind.ROUTE_MAP_CIRCULAR -> Color(0x4A002B24)
                else -> Color.Black.copy(alpha = .37f)
            }
            Box(Modifier.fillMaxSize().background(mapTint))
            Canvas(Modifier.align(Alignment.Center).size(34.dp)) {
                val arrow = androidx.compose.ui.graphics.Path().apply {
                    moveTo(size.width / 2, size.height * .06f)
                    lineTo(size.width * .84f, size.height * .88f)
                    lineTo(size.width / 2, size.height * .69f)
                    lineTo(size.width * .16f, size.height * .88f)
                    close()
                }
                drawPath(arrow, Color.White)
                drawPath(
                    arrow,
                    accent,
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = 3.dp.toPx())
                )
            }
        } else {
            Box(Modifier.fillMaxSize().background(Color(0xF0051116)), contentAlignment = Alignment.Center) {
                Text(appText("NO GPS", "BRAK GPS"), color = TougeOrange, fontSize = 11.sp, fontWeight = FontWeight.Black)
            }
        }
        Text("© OpenStreetMap", color = Color.White.copy(alpha = .72f), fontSize = 6.sp, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = if (circular) 13.dp else 7.dp))
    }
}

@Composable
private fun ArcadeTachPreview(
    sample: TelemetrySampleEntity,
    kind: OverlayElementKind,
    definition: VideoOverlayTemplateDefinition,
    modifier: Modifier
) {
    val neon = kind == OverlayElementKind.NEON_TACH
    val blacklist = kind == OverlayElementKind.BLACKLIST_TACH
    val carbon = kind == OverlayElementKind.CARBON_TACH
    val street = kind == OverlayElementKind.STREET_SHIFT_TACH
    val accent = when {
        neon -> Color(0xFF18BFFF)
        blacklist -> Color(0xFFD62E2E)
        carbon -> Color(0xFFE4A441)
        else -> Color(0xFFF0A04B)
    }
    val face = when {
        neon -> Color(0xF0040A0F)
        carbon -> Color(0xF016130D)
        street -> Color(0xE9080A08)
        else -> Color(0xF00A0B0D)
    }
    val width = when { neon -> 184.dp; street -> 190.dp; else -> 150.dp }
    val mainOffset = when { neon -> 17.dp; street -> (-20).dp; else -> 0.dp }
    Box(modifier.width(width).height(150.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val dimension = size.height
            val tachCenter = Offset(
                when { neon -> size.width - dimension / 2; street -> dimension / 2; else -> size.width / 2 },
                size.height / 2
            )
            val radius = dimension * .43f
            drawCircle(face, radius = dimension / 2, center = tachCenter)
            drawCircle(accent.copy(alpha = .7f), radius = dimension / 2 - 1.dp.toPx(), center = tachCenter, style = androidx.compose.ui.graphics.drawscope.Stroke(1.5.dp.toPx()))
            val faceTopLeft = Offset(tachCenter.x - dimension / 2, tachCenter.y - dimension / 2)
            val faceSize = androidx.compose.ui.geometry.Size(dimension, dimension)
            val rpmProgress = definition.progress(TelemetryMetric.RPM, sample.rpm)
            repeat(41) { index ->
                val fraction = index / 40f
                val radians = Math.toRadians(140.0 + 260.0 * fraction)
                val outer = Offset(tachCenter.x + cos(radians).toFloat() * radius, tachCenter.y + sin(radians).toFloat() * radius)
                val major = index % 4 == 0
                val tick = if (major) 9.dp.toPx() else 5.dp.toPx()
                val inner = Offset(tachCenter.x + cos(radians).toFloat() * (radius - tick), tachCenter.y + sin(radians).toFloat() * (radius - tick))
                val redline = (blacklist || street) && fraction > .78f
                drawLine(
                    if (redline) Color(0xFFDF3030) else Color.White.copy(alpha = if (major) .9f else .38f),
                    inner,
                    outer,
                    strokeWidth = if (major) 2.dp.toPx() else 1.dp.toPx()
                )
            }
            val labelPaint = AndroidPaint(AndroidPaint.ANTI_ALIAS_FLAG).apply {
                color = android.graphics.Color.argb(205, 255, 255, 255)
                textAlign = AndroidPaint.Align.CENTER
                textSize = 7.dp.toPx()
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }
            val divisions = (definition.maximumRpm / 1_000).roundToInt().coerceIn(4, 12)
            repeat(divisions + 1) { index ->
                val angle = Math.toRadians(140.0 + 260.0 * index / divisions)
                val labelRadius = radius * .69f
                drawContext.canvas.nativeCanvas.drawText(
                    index.toString(),
                    tachCenter.x + cos(angle).toFloat() * labelRadius,
                    tachCenter.y + sin(angle).toFloat() * labelRadius + labelPaint.textSize * .35f,
                    labelPaint
                )
            }
            drawArc(Color.White.copy(alpha = .12f), 140f, 260f, false, topLeft = faceTopLeft, size = faceSize, style = androidx.compose.ui.graphics.drawscope.Stroke(2.dp.toPx()))
            drawArc(accent.copy(alpha = .55f), 140f, 260f * rpmProgress, false, topLeft = faceTopLeft, size = faceSize, style = androidx.compose.ui.graphics.drawscope.Stroke(3.dp.toPx()))
            val needleAngle = Math.toRadians(140.0 + 260.0 * rpmProgress)
            drawLine(accent, tachCenter, Offset(tachCenter.x + cos(needleAngle).toFloat() * radius * .72f, tachCenter.y + sin(needleAngle).toFloat() * radius * .72f), 2.5.dp.toPx())
            drawCircle(if (carbon) Color(0xFFFFD58A) else Color.White, 3.dp.toPx(), tachCenter)
            if (neon) {
                val boost = definition.progress(TelemetryMetric.BOOST, sample.boostBar)
                val podCenter = Offset(dimension * .17f, dimension * .75f)
                val podRadius = dimension * .173f
                drawCircle(Color(0xFA040A0F), podRadius, podCenter)
                val podArc = androidx.compose.ui.geometry.Size(podRadius * 1.52f, podRadius * 1.52f)
                val podTopLeft = Offset(podCenter.x - podArc.width / 2, podCenter.y - podArc.height / 2)
                drawArc(Color.White.copy(alpha = .12f), 135f, 270f, false, topLeft = podTopLeft, size = podArc, style = androidx.compose.ui.graphics.drawscope.Stroke(4.dp.toPx()))
                drawArc(Color(0xFF26E76F), 135f, 270f * boost, false, topLeft = podTopLeft, size = podArc, style = androidx.compose.ui.graphics.drawscope.Stroke(4.dp.toPx()))
            }
            if (street) {
                val throttle = definition.progress(TelemetryMetric.THROTTLE, sample.throttlePercent)
                drawArc(Color(0xFF91EC37).copy(alpha = .18f), 35f, 110f, false, topLeft = faceTopLeft, size = faceSize, style = androidx.compose.ui.graphics.drawscope.Stroke(6.dp.toPx()))
                drawArc(Color(0xFF91EC37), 35f, 110f * throttle, false, topLeft = faceTopLeft, size = faceSize, style = androidx.compose.ui.graphics.drawscope.Stroke(6.dp.toPx()))
            }
        }
        Text("RPM ×1000", color = if (carbon) Color(0xFFFFD58A) else accent, fontSize = 7.sp, fontWeight = FontWeight.Black, modifier = Modifier.align(Alignment.Center).graphicsLayer { translationX = mainOffset.toPx(); translationY = -29.dp.toPx() })
        when {
            street -> {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.align(Alignment.Center).graphicsLayer { translationX = 65.dp.toPx(); translationY = -24.dp.toPx() }) {
                    Text("GEAR", color = Color(0xFFFFC27D), fontSize = 6.sp, fontWeight = FontWeight.Black)
                    Text("–", color = Color(0xFF24170A), fontSize = 22.sp, fontWeight = FontWeight.Black, modifier = Modifier.width(42.dp).background(Color(0xFFE7A85E), RoundedCornerShape(4.dp)))
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.align(Alignment.Center).graphicsLayer { translationX = 65.dp.toPx(); translationY = 29.dp.toPx() }) {
                    Text(sample.speedKph.roundToInt().toString(), color = Color(0xFF24170A), fontSize = 20.sp, fontWeight = FontWeight.Black, modifier = Modifier.width(54.dp).background(Color(0xFFE7A85E), RoundedCornerShape(4.dp)))
                    Text("KM/H", color = Color.White, fontSize = 6.sp, fontWeight = FontWeight.Black)
                }
                Text("THROTTLE ${sample.throttlePercent.roundToInt()}%", color = Color(0xFF9BEA4A), fontSize = 7.sp, fontWeight = FontWeight.Black, modifier = Modifier.align(Alignment.Center).graphicsLayer { translationX = mainOffset.toPx(); translationY = 58.dp.toPx() })
            }
            neon -> {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.align(Alignment.Center).graphicsLayer { translationX = mainOffset.toPx(); translationY = 23.dp.toPx() }) {
                    Text(sample.speedKph.roundToInt().toString(), color = accent, fontSize = 28.sp, fontWeight = FontWeight.Black)
                    Text("KM/H", color = accent, fontSize = 7.sp, fontWeight = FontWeight.Black)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.align(Alignment.Center).graphicsLayer { translationX = -66.dp.toPx(); translationY = 38.dp.toPx() }) {
                    Text("BOOST", color = Color(0xFF7EF5A5), fontSize = 5.sp, fontWeight = FontWeight.Black)
                    Text("%.1f".format(sample.boostBar), color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    Text("BAR", color = Color.White.copy(alpha = .7f), fontSize = 4.sp, fontWeight = FontWeight.Black)
                }
            }
            else -> {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.align(Alignment.Center).padding(top = 26.dp)) {
                    Text(sample.speedKph.roundToInt().toString(), color = if (blacklist) Color.White else accent, fontSize = 28.sp, fontWeight = FontWeight.Black)
                    Text("KM/H", color = if (carbon) Color.White else accent, fontSize = 7.sp, fontWeight = FontWeight.Black)
                    Text(
                        when {
                            blacklist -> "BOOST ${"%.1f".format(sample.boostBar)} bar"
                            else -> "OIL ${sample.oilTemperatureCelsius.roundToInt()}°C"
                        },
                        color = if (carbon) Color(0xFFFFCF77) else Color.White.copy(alpha = .8f),
                        fontSize = 7.sp,
                        fontWeight = FontWeight.Black
                    )
                }
            }
        }
    }
}

@Composable
private fun RacingDial(
    progress: Float,
    range: ClosedFloatingPointRange<Double>,
    metric: TelemetryMetric,
    accent: Color,
    modifier: Modifier = Modifier
) {
    Canvas(modifier) {
        val stroke = androidx.compose.ui.graphics.drawscope.Stroke(3.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round)
        drawArc(Color.White.copy(alpha = .1f), 150f, 240f, false, style = stroke)
        drawArc(accent.copy(alpha = .48f), 150f, 240f * progress, false, style = stroke)
        val radius = size.minDimension * .43f
        repeat(25) { index ->
            val radians = Math.toRadians((150.0 + index * 10.0))
            val outer = Offset(center.x + cos(radians).toFloat() * radius, center.y + sin(radians).toFloat() * radius)
            val tick = if (index % 4 == 0) 9.dp.toPx() else 5.dp.toPx()
            val inner = Offset(center.x + cos(radians).toFloat() * (radius - tick), center.y + sin(radians).toFloat() * (radius - tick))
            drawLine(Color.White.copy(alpha = if (index % 4 == 0) .9f else .32f), inner, outer, strokeWidth = if (index % 4 == 0) 2.dp.toPx() else 1.dp.toPx())
        }
        val labelPaint = AndroidPaint(AndroidPaint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.argb(190, 255, 255, 255)
            textAlign = AndroidPaint.Align.CENTER
            textSize = 5.dp.toPx()
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        repeat(7) { index ->
            val angle = Math.toRadians(150.0 + index * 40.0)
            val labelRadius = radius * .70f
            val label = scaleLabel(range.start + (range.endInclusive - range.start) * index / 6.0, metric)
            drawContext.canvas.nativeCanvas.drawText(
                label,
                center.x + cos(angle).toFloat() * labelRadius,
                center.y + sin(angle).toFloat() * labelRadius + labelPaint.textSize * .35f,
                labelPaint
            )
        }
        val needleAngle = Math.toRadians((150.0 + 240.0 * progress))
        val needleEnd = Offset(center.x + cos(needleAngle).toFloat() * radius * .7f, center.y + sin(needleAngle).toFloat() * radius * .7f)
        drawLine(accent, center, needleEnd, strokeWidth = 2.5.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round)
        drawCircle(Color.White, radius = 3.dp.toPx(), center = center)
    }
}

private fun scaleLabel(value: Double, metric: TelemetryMetric): String = when (metric) {
    TelemetryMetric.RPM -> "${(value / 1_000).roundToInt()}k"
    TelemetryMetric.BOOST -> "%.1f".format(value)
    else -> value.roundToInt().toString()
}

private fun VideoOverlayTemplateDefinition.progress(metric: TelemetryMetric, value: Double): Float {
    val range = range(metric)
    return ((value - range.start) / (range.endInclusive - range.start).coerceAtLeast(.0001)).coerceIn(0.0, 1.0).toFloat()
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
                Text(appText("GAUGE SCALES", "SKALE ZEGARÓW"), color = TougeCyan, fontSize = 9.sp, fontWeight = FontWeight.Black)
                GaugeScaleSlider(appText("Maximum speed", "Prędkość maks."), value.definition.maximumSpeedKph, 100f..450f, "km/h") {
                    value = value.copy(definition = value.definition.copy(maximumSpeedKph = it))
                }
                GaugeScaleSlider(appText("Maximum oil temperature", "Temperatura oleju maks."), value.definition.maximumOilTemperatureCelsius, 80f..180f, "°C") {
                    value = value.copy(definition = value.definition.copy(maximumOilTemperatureCelsius = it))
                }
                GaugeScaleSlider("RPM max", value.definition.maximumRpm, 4_000f..12_000f, "rpm", 500f) {
                    value = value.copy(definition = value.definition.copy(maximumRpm = it))
                }
                GaugeScaleSlider("Boost max", value.definition.maximumBoostBar, .5f..4f, "bar", .1f) {
                    value = value.copy(definition = value.definition.copy(maximumBoostBar = it))
                }
                value.definition.elements.forEachIndexed { index, element ->
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
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
    TelemetryMetric.EGT1 -> value.egt1Celsius
    TelemetryMetric.EGT2 -> value.egt2Celsius
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

private fun Map<String, Rect>.elementIDAt(point: Offset, validIDs: Set<String>): String? {
    return entries
        .filter { (id, bounds) -> id in validIDs && bounds.contains(point) }
        .minByOrNull { (_, bounds) ->
            val dx = bounds.center.x - point.x
            val dy = bounds.center.y - point.y
            dx * dx + dy * dy
        }
        ?.key
}

private fun List<Pair<TelemetrySampleEntity, GeoPoint>>.interpolatePosition(target: Long): GeoPoint? {
    if (isEmpty()) return null
    if (size == 1 || target <= first().first.recordedAt) return first().second
    if (target >= last().first.recordedAt) return last().second
    val found = binarySearchBy(target) { it.first.recordedAt }
    if (found >= 0) return this[found].second
    val upper = -found - 1
    val before = this[upper - 1]
    val after = this[upper]
    val duration = after.first.recordedAt - before.first.recordedAt
    if (duration <= 0) return after.second
    val fraction = ((target - before.first.recordedAt).toDouble() / duration).coerceIn(0.0, 1.0)
    return GeoPoint(
        before.second.latitude + (after.second.latitude - before.second.latitude) * fraction,
        before.second.longitude + (after.second.longitude - before.second.longitude) * fraction
    )
}

private fun videoDuration(seconds: Double): String { val value = seconds.coerceAtLeast(0.0).roundToInt(); return "%d:%02d".format(value / 60, value % 60) }
private fun videoBytes(value: Long): String = when { value >= 1_073_741_824 -> "%.1f GB".format(value / 1_073_741_824.0); value >= 1_048_576 -> "%.1f MB".format(value / 1_048_576.0); else -> "%.0f kB".format(value / 1024.0) }

@Composable
private fun localizedVideoOperation(value: String): String = when (value) {
    "Copying video from gallery" -> appText("Copying video from gallery", "Kopiowanie filmu z galerii")
    "Rendering telemetry HUD" -> appText("Rendering telemetry HUD", "Renderowanie HUD-u z telemetrią")
    else -> value
}
