@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.ui

import android.net.Uri
import it.letscode.tougedash.R
import androidx.compose.material3.Switch
import androidx.compose.ui.platform.LocalConfiguration
import it.letscode.tougedash.video.TelemetryBitmapOverlay
import it.letscode.tougedash.video.VideoTimeline
import it.letscode.tougedash.video.DriveVideoExportQuality
import it.letscode.tougedash.video.RouteMapSnapshot
import it.letscode.tougedash.video.createRouteMapSnapshot
import it.letscode.tougedash.video.bounds
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
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
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
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
import org.osmdroid.util.GeoPoint
import kotlin.math.roundToInt
import kotlin.math.abs

@Composable
fun DriveVideoSection(container: AppContainer, session: DriveSessionEntity, samples: List<TelemetrySampleEntity>, scrubber: Float, onScrub: (Long) -> Unit = {}) {
    val videos by container.historyRepository.videos(session.id).collectAsState(initial = emptyList())
    val task by container.videoRepository.task.collectAsState()
    val cameraTask by container.seventyMaiImporter.state.collectAsState()
    var editing by remember(session.id) { mutableStateOf<VideoProjectEntity?>(null) }
    var deleting by remember { mutableStateOf<VideoProjectEntity?>(null) }
    var cameraImport by remember { mutableStateOf(false) }
    var selectedRecordingId by remember { mutableStateOf<String?>(null) }
    val captured = videos.filter { it.sourceKind == "CAMERA" }
    val external = videos.filter { it.sourceKind != "CAMERA" }
    val selectedRecording = captured.firstOrNull { it.id == selectedRecordingId } ?: captured.firstOrNull()
    val driveDuration = (session.endedAt - session.startedAt).coerceAtLeast(1) / 1000.0
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri?.let { container.videoRepository.importFromGallery(session.id, driveDuration, it) }
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        VideoSectionPanel(TougeCyan) {
            Text(appText("APP RECORDINGS", "NAGRANIA Z APLIKACJI"), color = TougeCyan, fontSize = 11.sp, fontWeight = FontWeight.Black)
            Text(appText("Touge Dash camera · automatically synchronized with the drive", "Kamera Touge Dash · automatyczna synchronizacja z przejazdem"), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
            if (captured.isEmpty()) {
                Text(appText("No Touge Dash camera recording", "Brak nagrania z kamery Touge Dash"), Modifier.padding(top = 14.dp), fontWeight = FontWeight.Bold)
                Text(appText("This drive contains telemetry; in-app video recording was inactive.", "Ten przejazd zachował telemetrię, ale nagrywanie w aplikacji nie było aktywne."), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                selectedRecording?.let { recording ->
                    SynchronizedDrivePlayer(recording, session, scrubber, onScrub)
                    Button(onClick = { editing = recording }, modifier = Modifier.fillMaxWidth()) { Text(appText("Export video", "Eksport filmu")) }
                }
                VideoGroup(appText("RECORDINGS", "NAGRANIA"), captured, editing = { selectedRecordingId = it.id }, delete = { deleting = it })
            }
        }
        VideoSectionPanel(TougeMint) {
            Text(appText("EDIT YOUR OWN VIDEO", "MONTAŻ Z WŁASNEGO FILMU"), color = TougeMint, fontSize = 11.sp, fontWeight = FontWeight.Black)
            Text(appText("Separate projects · manual telemetry alignment", "Osobne projekty · ręczne dopasowanie telemetrii"), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { picker.launch("video/*") }, enabled = !container.videoRepository.isBusy && !cameraTask.busy, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Default.VideoLibrary, null, Modifier.size(18.dp))
                    Text(appText(" Library", " Biblioteka"))
                }
                OutlinedButton(onClick = { container.seventyMaiImporter.clear(); cameraImport = true }, enabled = !container.videoRepository.isBusy, modifier = Modifier.weight(1f)) { Text("70mai") }
            }
            if (cameraTask.busy) TextButton(onClick = { cameraImport = true }) { Text(appText("70mai import in progress…", "Trwa import 70mai…")) }
            if (external.isEmpty()) {
                Text(appText("No video edit for this drive yet", "Nie masz jeszcze montażu dla tego przejazdu"), Modifier.padding(top = 10.dp), fontWeight = FontWeight.Bold)
                Text(appText("Choose a video, match a telemetry fragment and export a copy with a HUD.", "Wybierz film, wskaż odpowiadający mu fragment danych i wyeksportuj gotową kopię z HUD-em."), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
            } else VideoGroup(appText("VIDEO PROJECTS", "PROJEKTY FILMÓW"), external, editing = { editing = it }, delete = { deleting = it })
            Text(appText("A local working copy keeps your project editable. Videos are not uploaded to the cloud.", "Lokalna kopia robocza pozwala wrócić do edycji projektu. Filmy nie trafiają do chmury."), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 11.sp)
        }
        if (task.operation != null || task.error != null) VideoSectionPanel(TougeCyan) {
            Text(localizedVideoOperation(task.operation ?: ""), fontWeight = FontWeight.Bold)
            LinearProgressIndicator(progress = { task.progress }, modifier = Modifier.fillMaxWidth())
            Text("${(task.progress * 100).roundToInt()}%${if (task.totalBytes > 0) " · ${videoBytes(task.transferredBytes)} / ${videoBytes(task.totalBytes)}" else ""}", fontSize = 11.sp)
            if (task.completed && task.outputWidth > 0) Text("${task.outputWidth}×${task.outputHeight} · ${if (task.outputVideoMimeType?.contains("hevc") == true) "HEVC" else "H.264"}${if (task.outputHasAudio) " · audio" else ""}", color = TougeCyan)
            task.error?.let { Text(it, color = TougeRed) }
            TextButton(onClick = { if (task.completed || task.error != null) container.videoRepository.clearTask() else container.videoRepository.cancelExport() }) {
                Text(if (task.completed || task.error != null) appText("Close", "Zamknij") else appText("Cancel", "Anuluj"))
            }
        }
    }
    if (cameraImport) SeventyMaiImportDialog(container, session) { cameraImport = false }
    deleting?.let { project ->
        AlertDialog(onDismissRequest = { deleting = null }, title = { Text(appText("Delete video?", "Usunąć film?")) },
            text = { Text(appText("The local source and project will be deleted. Drive telemetry remains available.", "Lokalny film źródłowy i projekt zostaną usunięte. Telemetria przejazdu pozostanie dostępna.")) },
            confirmButton = { TextButton(onClick = { container.videoRepository.delete(project); deleting = null }) { Text(appText("Delete", "Usuń"), color = TougeRed) } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(appText("Cancel", "Anuluj")) } })
    }
    editing?.let { project -> VideoAlignmentEditor(project, session, driveDuration, samples, container, { editing = null }, container.videoRepository::update) }
}

@Composable
private fun VideoSectionPanel(accent: Color, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    TougePanelSurface(accent, Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
private fun SynchronizedDrivePlayer(project: VideoProjectEntity, session: DriveSessionEntity, scrubber: Float, onScrub: (Long) -> Unit) {
    val context = LocalContext.current
    val timeline = remember(project) { VideoTimeline.from(project) }
    val player = remember(project.id) { ExoPlayer.Builder(context).build().apply { setMediaItem(MediaItem.fromUri(project.localUri)); prepare() } }
    val latestScrub by rememberUpdatedState(onScrub)
    var lastReported by remember(project.id) { mutableLongStateOf(Long.MIN_VALUE) }
    DisposableEffect(player) { onDispose { player.release() } }
    val selected = session.startedAt + ((session.endedAt - session.startedAt) * scrubber).toLong()
    LaunchedEffect(selected) {
        if (lastReported == Long.MIN_VALUE || kotlin.math.abs(selected - lastReported) > 250) {
            val seconds = timeline.videoAt((selected - session.startedAt) / 1000.0).coerceIn(timeline.videoStart, timeline.videoStart + timeline.duration)
            player.seekTo((seconds * 1000).toLong())
        }
    }
    LaunchedEffect(player, timeline) {
        var previous = -1L
        while (true) {
            val position = player.currentPosition
            if (position != previous && (player.isPlaying || kotlin.math.abs(position - previous) > 250)) {
                lastReported = session.startedAt + (timeline.telemetryAt(position / 1000.0) * 1000).toLong()
                latestScrub(lastReported)
                previous = position
            }
            delay(100)
        }
    }
    AndroidView(factory = { (android.view.LayoutInflater.from(it).inflate(R.layout.drive_video_player, null) as PlayerView).apply { useController = true; this.player = player } }, modifier = Modifier.fillMaxWidth().aspectRatio(project.pixelWidth.coerceAtLeast(1).toFloat() / project.pixelHeight.coerceAtLeast(1)))
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
    session: DriveSessionEntity,
    driveDuration: Double,
    samples: List<TelemetrySampleEntity>,
    container: AppContainer,
    dismiss: () -> Unit,
    save: (VideoProjectEntity) -> Unit
) {
    val context = LocalContext.current
    var pendingExport by remember { mutableStateOf<(() -> Unit)?>(null) }
    val galleryPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) pendingExport?.invoke()
        pendingExport = null
    }
    var thumbnails by remember(initial.id) { mutableStateOf<List<android.graphics.Bitmap>>(emptyList()) }
    LaunchedEffect(initial.id) {
        thumbnails = runCatching { it.letscode.tougedash.video.loadVideoTimelineThumbnails(context, Uri.parse(initial.localUri), initial.durationSeconds) }.getOrDefault(emptyList())
    }
    val editorConfiguration = LocalConfiguration.current
    val landscapeEditor = editorConfiguration.screenWidthDp > editorConfiguration.screenHeightDp
    var value by remember(initial.id) { mutableStateOf(VideoTimeline.from(initial).normalized(initial.durationSeconds, driveDuration).applyTo(initial)) }
    var addsOverlay by remember(initial.id) { mutableStateOf(true) }
    val exportPreferences = remember { context.getSharedPreferences("video-export", 0) }
    var exportQuality by remember { mutableStateOf(runCatching { DriveVideoExportQuality.valueOf(exportPreferences.getString("quality", "FAST_FULL_HD")!!) }.getOrDefault(DriveVideoExportQuality.FAST_FULL_HD)) }
    var loadedTemplateId by remember(initial.id) { mutableStateOf<String?>(null) }
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
            if (loadedTemplateId != templateId) {
                overlayDefinition = if (loadedTemplateId == null) {
                    initial.overlayDefinitionJson?.let { draft -> runCatching { container.json.decodeFromString<VideoOverlayTemplateDefinition>(draft) }.getOrNull() }
                        ?: it.definition.copy(elements = it.definition.resolvedElements())
                } else it.definition.copy(elements = it.definition.resolvedElements())
                loadedTemplateId = templateId
                selectedElementId = null
            }
        }
    }
    var previewReady by remember(initial.id) { mutableStateOf(false) }
    var playbackError by remember(initial.id) { mutableStateOf<String?>(null) }
    val player = remember(initial.id) { ExoPlayer.Builder(context).build().apply { setMediaItem(MediaItem.fromUri(initial.localUri)); prepare(); seekTo((initial.videoTrimStartSeconds * 1000).toLong()) } }
    var position by remember { mutableLongStateOf((initial.videoTrimStartSeconds * 1000).toLong()) }
    DisposableEffect(player) {
        val listener = object : androidx.media3.common.Player.Listener {
            override fun onRenderedFirstFrame() { previewReady = true }
            override fun onPlayerError(error: androidx.media3.common.PlaybackException) { playbackError = error.localizedMessage }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener); player.release() }
    }
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
    val first = session.startedAt
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
            factory = { (android.view.LayoutInflater.from(it).inflate(R.layout.drive_video_player, null) as PlayerView).apply { this.player = player } },
            modifier = Modifier.fillMaxSize()
        )
        if (previewReady) Box(Modifier.size(1.dp).testTag("video-ready"))
        playbackError?.let { Text(it, color = TougeRed, modifier = Modifier.align(Alignment.Center)) }
        if (addsOverlay) sample?.let { current ->
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
        if (addsOverlay) Box(
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
                androidx.compose.material3.DropdownMenuItem(
                    text = { Text(appText("Telemetry date and time", "Data i czas telemetrii")) },
                    onClick = {
                        val widget = VideoOverlayElement(metric = TelemetryMetric.SPEED, kind = OverlayElementKind.TELEMETRY_TIMESTAMP, landscapePosition = OverlayPosition(.5f, .11f), portraitPosition = OverlayPosition(.5f, .1f))
                        overlayDefinition = overlayDefinition.copy(elements = overlayDefinition.elements + widget, allowsEmptyLayout = true)
                        selectedElementId = widget.id
                        widgetMenuOpen = false
                    }
                )
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
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
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
                    speedValues = emptyList(),
                    thumbnails = thumbnails,
                    startChanged = { requested ->
                        value = VideoTimeline.from(value).trimStart(requested).applyTo(value)
                        val newStart = value.videoTrimStartSeconds
                        player.pause()
                        val target = (newStart * 1000).toLong()
                        player.seekTo(target)
                        position = target
                    },
                    endChanged = { requested ->
                        value = VideoTimeline.from(value).trimEnd(requested, value.durationSeconds, driveDuration).applyTo(value)
                        val newEnd = value.videoTrimStartSeconds + value.exportDurationSeconds
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
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        listOf(-10.0, -1.0, 1.0, 10.0).forEach { delta ->
                            TextButton(onClick = {
                                value = value.copy(telemetryTrimStartSeconds = (value.telemetryTrimStartSeconds + delta).coerceIn(0.0, (driveDuration - value.exportDurationSeconds).coerceAtLeast(0.0)))
                            }) { Text("${if (delta > 0) "+" else ""}${delta.toInt()} s") }
                        }
                    }
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

            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(appText("Render telemetry on video", "Nanieś parametry na film"), Modifier.weight(1f), fontWeight = FontWeight.Bold)
                Switch(addsOverlay, { addsOverlay = it })
            }
            Text(appText("EXPORT QUALITY", "JAKOŚĆ EKSPORTU"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                DriveVideoExportQuality.entries.forEach { quality ->
                    FilterChip(exportQuality == quality, {
                        exportQuality = quality
                        exportPreferences.edit().putString("quality", quality.name).apply()
                    }, label = { Text(if (quality == DriveVideoExportQuality.FAST_FULL_HD) appText("Fast · 1080p", "Szybki · 1080p") else appText("Original resolution", "Oryginalna rozdzielczość")) })
                }
            }
            Text(if (exportQuality == DriveVideoExportQuality.FAST_FULL_HD) appText("Faster export and smaller file, still in high quality", "Szybszy eksport i mniejszy plik, nadal w wysokiej jakości") else appText("Full camera resolution and longer rendering time", "Pełna rozdzielczość kamery i dłuższy czas renderowania"), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (addsOverlay) {
            Text(appText("HUD TEMPLATE", "SZABLON HUD"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp))
            var templateMenu by remember { mutableStateOf(false) }
            Box {
                OutlinedButton(onClick = { templateMenu = true }, modifier = Modifier.fillMaxWidth()) { Text(templates.firstOrNull { it.entity.id == templateId }?.entity?.name ?: "HUD") }
                androidx.compose.material3.DropdownMenu(templateMenu, { templateMenu = false }) {
                    templates.forEach { item ->
                        androidx.compose.material3.DropdownMenuItem(text = { Text(item.entity.name) }, onClick = {
                            templateId = item.entity.id
                            overlayDefinition = item.definition.copy(elements = item.definition.resolvedElements())
                            selectedElementId = null
                            value = value.copy(overlayTemplateId = item.entity.id)
                            templateMenu = false
                        })
                    }
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
    }
    val stage: @Composable (Modifier) -> Unit = { stageModifier ->
        BoxWithConstraints(
                    stageModifier.background(Color.Black),
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
                            .testTag("hud-preview")
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
    }
    Dialog(
        onDismissRequest = dismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)
    ) {
        val dialogView = androidx.compose.ui.platform.LocalView.current
        val background = MaterialTheme.colorScheme.background.toArgb()
        androidx.compose.runtime.SideEffect {
            (dialogView.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window?.apply {
                setLayout(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
                setBackgroundDrawable(android.graphics.drawable.ColorDrawable(background))
            }
        }
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
                    TextButton(onClick = { save(value.copy(overlayTemplateId = templateId, overlayDefinitionJson = container.json.encodeToString(overlayDefinition))); dismiss() }) {
                        Text(appText("Save", "Zapisz"))
                    }
                }
                if (landscapeEditor) {
                    Row(Modifier.fillMaxWidth().weight(1f)) {
                        stage(Modifier.weight(1.45f).fillMaxHeight())
                        Box(Modifier.weight(1f).fillMaxHeight().verticalScroll(androidx.compose.foundation.rememberScrollState())) { controls() }
                    }
                } else {
                    Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(androidx.compose.foundation.rememberScrollState())) {
                        val aspect = initial.pixelWidth.coerceAtLeast(1).toFloat() / initial.pixelHeight.coerceAtLeast(1)
                        stage(Modifier.fillMaxWidth().aspectRatio(aspect).heightIn(max = 560.dp))
                        controls()
                    }
                }
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = { save(value.copy(overlayTemplateId = templateId, overlayDefinitionJson = container.json.encodeToString(overlayDefinition))); dismiss() },
                        modifier = Modifier.weight(1f)
                    ) { Text(appText("Save project", "Zapisz projekt")) }
                    Button(
                        onClick = {
                            val exportValue = value.copy(overlayTemplateId = templateId, overlayDefinitionJson = container.json.encodeToString(overlayDefinition))
                            save(exportValue)
                            val begin = {
                                container.videoRepository.export(exportValue, samples, overlayDefinition, addsOverlay, exportQuality, session.startedAt)
                                dismiss()
                            }
                            if (android.os.Build.VERSION.SDK_INT < 29 && androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                pendingExport = begin
                                galleryPermission.launch(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
                            } else begin()
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
    modifier: Modifier = Modifier,
    thumbnails: List<android.graphics.Bitmap> = emptyList()
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
        thumbnails.forEachIndexed { index, thumbnail ->
            val left = width * index / thumbnails.size
            val right = width * (index + 1) / thumbnails.size
            drawContext.canvas.nativeCanvas.drawBitmap(thumbnail, null, android.graphics.RectF(left, 0f, right, size.height), null)
        }
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
    OverlayElementKind.TELEMETRY_TIMESTAMP -> appText("Telemetry date and time", "Data i czas telemetrii")
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
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return
    val context = LocalContext.current
    val density = LocalDensity.current
    val timestampLabel = appText("TELEMETRY TIME", "CZAS TELEMETRII")
    val locale = LocalAppLocale.current
    var routeMap by remember(samples) { mutableStateOf<RouteMapSnapshot?>(null) }
    val needsMap = definition.elements.any { it.kind.isRouteMap }
    val needsDetailedMap = definition.elements.any { it.kind.isRouteMap && it.mapZoom > 1.85f }
    LaunchedEffect(samples, needsMap, needsDetailedMap) {
        if (needsMap) routeMap = createRouteMapSnapshot(context, samples, includesDetailedLayer = needsDetailedMap)
    }
    val renderer = remember(samples, definition, canvasSize, routeMap, timestampLabel) {
        TelemetryBitmapOverlay(samples, 0.0, definition, canvasSize.width, canvasSize.height, routeMap, telemetryOriginMillis = 0L, timestampLabel = timestampLabel, locale = locale)
    }
    // Render through the actual export implementation. Selection controls are the only editor-only layer.
    Canvas(Modifier.fillMaxSize()) {
        val frame = renderer.getBitmap(routeTimestamp * 1000)
        drawContext.canvas.nativeCanvas.drawBitmap(frame, null, android.graphics.Rect(0, 0, size.width.toInt(), size.height.toInt()), null)
    }
    definition.elements.forEach { element ->
        val bounds = element.bounds(canvasSize.width, canvasSize.height)
        val rect = Rect(bounds.left, bounds.top, bounds.left + bounds.width, bounds.top + bounds.height)
        LaunchedEffect(element.id, rect) { elementBoundsChanged(element.id, rect) }
        Box(
            Modifier.offset { androidx.compose.ui.unit.IntOffset(bounds.left.roundToInt(), bounds.top.roundToInt()) }
                .testTag("hud-widget-${element.kind.name}-${element.metric.name}")
                .size(with(density) { bounds.width.toDp() }, with(density) { bounds.height.toDp() })
                .border(if (selectedElementId == element.id) 1.dp else 0.dp, if (selectedElementId == element.id) Color.White else Color.Transparent, RoundedCornerShape(8.dp))
                .clickable { select(element.id) }
        ) {
            if (selectedElementId == element.id) {
                IconButton(onClick = { requestDelete(element.id) }, modifier = Modifier.align(Alignment.TopEnd).size(30.dp).background(TougeRed, androidx.compose.foundation.shape.CircleShape)) {
                    Icon(Icons.Default.Delete, appText("Remove widget", "Usuń widget"), tint = Color.White, modifier = Modifier.size(16.dp))
                }
                if (element.kind.isRouteMap) Row(Modifier.align(Alignment.BottomCenter).background(Color.Black.copy(alpha = .8f), RoundedCornerShape(20.dp)), verticalAlignment = Alignment.CenterVertically) {
                    MapZoomButton("−") { mapZoom(element.id, -.15f) }
                    Text("%.1f".format(element.mapZoom), color = Color.White, fontSize = 9.sp)
                    MapZoomButton("+") { mapZoom(element.id, .15f) }
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
                                IconButton(onClick = { value = value.copy(definition = value.definition.withoutElement(element.id)) }) { Icon(Icons.Default.Delete, null, tint = TougeRed) }
                            }
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                OverlayElementKind.entries.forEach { kind -> FilterChip(element.kind == kind, { value = value.withElement(element.copy(kind = kind)) }, label = { Text(widgetKindName(kind)) }) }
                            }
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                OverlayElementScale.entries.forEach { scale -> FilterChip(element.scale == scale, { value = value.withElement(element.copy(scale = scale)) }, label = { Text(when (scale) {
                                    OverlayElementScale.SMALL -> appText("Small", "Mały")
                                    OverlayElementScale.MEDIUM -> appText("Medium", "Średni")
                                    OverlayElementScale.LARGE -> appText("Large", "Duży")
                                    OverlayElementScale.EXTRA_LARGE -> appText("Extra large", "Bardzo duży")
                                }) }) }
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
        confirmButton = { Button(enabled = value.entity.name.isNotBlank(), onClick = { save(value) }) { Text(appText("Save HUD", "Zapisz HUD")) } },
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

private fun videoDuration(seconds: Double): String { val tenths = (seconds.coerceAtLeast(0.0) * 10).toLong(); return "%d:%02d.%d".format(tenths / 600, tenths / 10 % 60, tenths % 10) }
private fun videoBytes(value: Long): String = when { value >= 1_073_741_824 -> "%.1f GB".format(value / 1_073_741_824.0); value >= 1_048_576 -> "%.1f MB".format(value / 1_048_576.0); else -> "%.0f kB".format(value / 1024.0) }

@Composable
private fun localizedVideoOperation(value: String): String = when (value) {
    "Copying video from gallery" -> appText("Copying video from gallery", "Kopiowanie filmu z galerii")
    "Saving video to gallery" -> appText("Saving video to gallery", "Zapisywanie filmu w galerii")
    "Rendering telemetry HUD" -> appText("Rendering telemetry HUD", "Renderowanie HUD-u z telemetrią")
    else -> value
}
