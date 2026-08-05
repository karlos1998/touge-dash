@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.ui

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
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
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougeOrange
import it.letscode.tougedash.ui.theme.TougePanel
import it.letscode.tougedash.ui.theme.TougeRed
import it.letscode.tougedash.video.OverlayStyle
import it.letscode.tougedash.video.VideoOverlayTemplateDefinition
import kotlinx.coroutines.delay
import kotlin.math.abs
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
                    Text(task.operation!!, fontWeight = FontWeight.Bold)
                    LinearProgressIndicator(progress = { task.progress }, modifier = Modifier.fillMaxWidth().padding(top = 7.dp))
                    Text("${(task.progress * 100).roundToInt()}%${if (task.totalBytes > 0) "  •  ${videoBytes(task.transferredBytes)} / ${videoBytes(task.totalBytes)}" else ""}", color = TougeMuted, fontSize = 10.sp)
                    task.error?.let { Text(it, color = TougeRed) }
                    if (task.completed || task.error != null) TextButton(onClick = container.videoRepository::clearTask) { Text(appText("Close", "Zamknij")) }
                }
            }
        }
        VideoGroup("RECORDED BY TOUGE DASH", videos.filter { it.sourceKind == "CAMERA" }, editing = { editing = it }, delete = container.videoRepository::delete)
        VideoGroup("GALLERY EDITS", videos.filter { it.sourceKind == "GALLERY" }, editing = { editing = it }, delete = container.videoRepository::delete)
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
                    Text(video.sourceDisplayName ?: if (video.sourceKind == "CAMERA") "Drive recording" else "Gallery video", fontWeight = FontWeight.Bold)
                    Text("${videoDuration(video.durationSeconds)}  •  ${videoBytes(video.fileSizeBytes)}  •  ${video.pixelWidth}×${video.pixelHeight}", color = TougeMuted, fontSize = 11.sp)
                }
                IconButton(onClick = { delete(video) }) { Icon(Icons.Default.Delete, null, tint = TougeRed) }
            }
        }
    }
}

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
    val portraitVideo = initial.pixelHeight > initial.pixelWidth
    var previewSize by remember { mutableStateOf(IntSize.Zero) }
    LaunchedEffect(templates, templateId) {
        templates.firstOrNull { it.entity.id == templateId }?.let { overlayDefinition = it.definition }
    }
    val player = remember(initial.id) { ExoPlayer.Builder(context).build().apply { setMediaItem(MediaItem.fromUri(initial.localUri)); prepare(); seekTo((initial.videoTrimStartSeconds * 1000).toLong()) } }
    var position by remember { mutableLongStateOf((initial.videoTrimStartSeconds * 1000).toLong()) }
    DisposableEffect(player) { onDispose { player.release() } }
    LaunchedEffect(player) { while (true) { position = player.currentPosition; if (position / 1000.0 >= value.videoTrimStartSeconds + value.exportDurationSeconds) { player.pause(); player.seekTo((value.videoTrimStartSeconds * 1000).toLong()) }; delay(50) } }
    val telemetrySecond = value.telemetryTrimStartSeconds + (position / 1000.0 - value.videoTrimStartSeconds).coerceAtLeast(0.0)
    val first = samples.firstOrNull()?.recordedAt ?: 0
    val sample = samples.minByOrNull { abs(it.recordedAt - (first + telemetrySecond * 1000).toLong()) }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(appText("Align video with telemetry", "Dopasuj film do telemetrii")) },
        text = {
            Column {
                Box(Modifier.fillMaxWidth().height(220.dp).background(Color.Black).onSizeChanged { previewSize = it }) {
                    AndroidView(factory = { PlayerView(it).apply { useController = false; this.player = player } }, modifier = Modifier.fillMaxWidth().height(220.dp))
                    sample?.let {
                        val x = overlayDefinition.x(portraitVideo)
                        val y = overlayDefinition.y(portraitVideo)
                        HudPreview(
                            it,
                            overlayDefinition.style,
                            Modifier
                                .align(Alignment.Center)
                                .fillMaxWidth(.86f)
                                .graphicsLayer {
                                    translationX = x * previewSize.width * .42f
                                    translationY = y * previewSize.height * .42f
                                    scaleX = overlayDefinition.scale
                                    scaleY = overlayDefinition.scale
                                }
                                .pointerInput(previewSize, portraitVideo, x, y) {
                                    detectDragGestures { change, drag ->
                                        change.consume()
                                        if (previewSize.width > 0 && previewSize.height > 0) {
                                            overlayDefinition = overlayDefinition.positioned(
                                                portraitVideo,
                                                (x + drag.x / (previewSize.width * .42f)).coerceIn(-1f, 1f),
                                                (y + drag.y / (previewSize.height * .42f)).coerceIn(-1f, 1f)
                                            )
                                        }
                                    }
                                }
                        )
                    }
                    IconButton(onClick = { if (player.isPlaying) player.pause() else { if (position / 1000.0 !in value.videoTrimStartSeconds..(value.videoTrimStartSeconds + value.exportDurationSeconds)) player.seekTo((value.videoTrimStartSeconds * 1000).toLong()); player.play() } }, modifier = Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = .45f), RoundedCornerShape(30.dp))) {
                        Icon(if (player.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow, null, tint = Color.White)
                    }
                }
                Text("VIDEO START  ${videoDuration(value.videoTrimStartSeconds)}", color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
                Slider(value.videoTrimStartSeconds.toFloat(), { new -> value = value.copy(videoTrimStartSeconds = new.toDouble()); player.seekTo((new * 1000).toLong()) }, valueRange = 0f..(value.durationSeconds - value.exportDurationSeconds).coerceAtLeast(.01).toFloat())
                Text("TELEMETRY START  ${videoDuration(value.telemetryTrimStartSeconds)} of ${videoDuration(driveDuration)}", color = TougeMint, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Slider(value.telemetryTrimStartSeconds.toFloat(), { value = value.copy(telemetryTrimStartSeconds = it.toDouble()) }, valueRange = 0f..(driveDuration - value.exportDurationSeconds).coerceAtLeast(.01).toFloat())
                val maxDuration = minOf(value.durationSeconds - value.videoTrimStartSeconds, driveDuration - value.telemetryTrimStartSeconds).coerceAtLeast(.1)
                Text("EXPORT LENGTH  ${videoDuration(value.exportDurationSeconds)}", color = TougeOrange, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Slider(value.exportDurationSeconds.coerceAtMost(maxDuration).toFloat(), { value = value.copy(exportDurationSeconds = it.toDouble()) }, valueRange = .1f..maxDuration.coerceAtLeast(.11).toFloat())
                Text(appText("HUD TEMPLATE", "SZABLON HUD"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    templates.forEach { item ->
                        FilterChip(
                            selected = templateId == item.entity.id,
                            onClick = { templateId = item.entity.id; overlayDefinition = item.definition; value = value.copy(overlayTemplateId = item.entity.id) },
                            label = { Text(item.entity.name) }
                        )
                    }
                }
                Text(appText("Drag the HUD on the preview or fine-tune its position below.", "Przeciągnij HUD palcem na podglądzie albo dopasuj pozycję poniżej."), color = TougeMuted, fontSize = 10.sp)
                Text("${appText("Horizontal position", "Pozycja pozioma")}: ${"%.2f".format(overlayDefinition.x(portraitVideo))}", fontSize = 10.sp)
                Slider(overlayDefinition.x(portraitVideo), { overlayDefinition = overlayDefinition.positioned(portraitVideo, it, overlayDefinition.y(portraitVideo)) }, valueRange = -1f..1f)
                Text("${appText("Vertical position", "Pozycja pionowa")}: ${"%.2f".format(overlayDefinition.y(portraitVideo))}", fontSize = 10.sp)
                Slider(overlayDefinition.y(portraitVideo), { overlayDefinition = overlayDefinition.positioned(portraitVideo, overlayDefinition.x(portraitVideo), it) }, valueRange = -1f..1f)
                Text("${appText("HUD size", "Rozmiar HUD")}: ${"%.0f".format(overlayDefinition.scale * 100)}%", fontSize = 10.sp)
                Slider(overlayDefinition.scale, { overlayDefinition = overlayDefinition.positioned(portraitVideo, overlayDefinition.x(portraitVideo), overlayDefinition.y(portraitVideo), it) }, valueRange = .55f..1.2f)
                OutlinedButton(
                    onClick = { templates.firstOrNull { it.entity.id == templateId }?.let { container.videoRepository.updateOverlayTemplate(it.copy(definition = overlayDefinition)) } },
                    modifier = Modifier.fillMaxWidth()
                ) { Text(appText("Save layout in this template", "Zapisz układ w tym szablonie")) }
                Text(appText("The upper timeline is the selected video. The lower one chooses the matching fragment of the recorded drive.", "Górna oś to wybrany film. Dolna wybiera pasujący fragment zapisanego przejazdu."), color = TougeMuted, fontSize = 10.sp)
            }
        },
        confirmButton = {
            Button(onClick = { save(value.copy(overlayTemplateId = templateId)); container.videoRepository.export(value.copy(overlayTemplateId = templateId), samples, overlayDefinition); dismiss() }) { Icon(Icons.Default.Download, null); Text(appText(" Export to gallery", " Eksportuj do galerii")) }
        },
        dismissButton = { TextButton(onClick = { save(value.copy(overlayTemplateId = templateId)); dismiss() }) { Text(appText("Save project", "Zapisz projekt")) } }
    )
}

@Composable
private fun HudPreview(sample: TelemetrySampleEntity, style: OverlayStyle, modifier: Modifier = Modifier) {
    val background = when (style) { OverlayStyle.UNDERGROUND -> Color.Black.copy(alpha = .75f); else -> Color(0xDD071014) }
    Row(modifier.background(background).padding(8.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Column { Text("${sample.speedKph.toInt()}", fontSize = 30.sp, fontWeight = FontWeight.Black); Text("KM/H", color = TougeCyan, fontSize = 8.sp) }
        Column { Text("RPM ${sample.rpm.toInt()}", fontWeight = FontWeight.Black); Text("BOOST %.2f bar".format(sample.boostBar), color = TougeMint, fontSize = 11.sp) }
        Column { Text("OIL %.1f bar".format(sample.oilPressureBar), color = TougeOrange, fontSize = 11.sp); Text("%.0f°C / WATER %.0f°C".format(sample.oilTemperatureCelsius, sample.coolantCelsius), fontSize = 10.sp) }
    }
}

private fun videoDuration(seconds: Double): String { val value = seconds.coerceAtLeast(0.0).roundToInt(); return "%d:%02d".format(value / 60, value % 60) }
private fun videoBytes(value: Long): String = when { value >= 1_073_741_824 -> "%.1f GB".format(value / 1_073_741_824.0); value >= 1_048_576 -> "%.1f MB".format(value / 1_048_576.0); else -> "%.0f kB".format(value / 1024.0) }
