@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
package it.letscode.tougedash.video

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.media.MediaMetadataRetriever
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.*
import it.letscode.tougedash.data.local.DriveSessionEntity
import it.letscode.tougedash.data.local.VideoProjectEntity
import it.letscode.tougedash.data.local.TougeDashDao
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class SeventyMaiImportState(
    val busy: Boolean = false, val stage: String = "", val progress: Float = 0f,
    val receivedBytes: Long = 0, val totalBytes: Long = 0, val scan: SeventyMaiScan? = null,
    val error: String? = null, val projectId: String? = null
)

class SeventyMaiImporter(private val context: Context, private val scope: CoroutineScope, private val dao: TougeDashDao, private val createClient: (Context) -> SeventyMaiClient = { SeventyMaiClient(it) }) {
    private val mutableState = MutableStateFlow(SeventyMaiImportState())
    val state = mutableState.asStateFlow()
    private var job: Job? = null
    private var client: SeventyMaiClient? = null
    fun cancel() { job?.cancel() }
    fun clear() { if (!mutableState.value.busy) mutableState.value = SeventyMaiImportState() }
    fun scan(session: DriveSessionEntity, model: SeventyMaiCameraModel, rear: Boolean) {
        if (mutableState.value.busy) return
        mutableState.value = SeventyMaiImportState(busy = true, stage = "AUTHORIZE")
        job = scope.launch(Dispatchers.IO) {
            try {
                val active = createClient(context).also { client = it }
                val scan = active.scan(model, rear, session.startedAt, session.endedAt) { mutableState.value = mutableState.value.copy(stage = it) }
                mutableState.value = SeventyMaiImportState(scan = scan, stage = "READY")
            } catch (cancelled: CancellationException) { mutableState.value = SeventyMaiImportState(); throw cancelled }
            catch (error: Exception) { mutableState.value = mutableState.value.copy(busy = false, error = error.message ?: error.javaClass.simpleName) }
        }
    }
    fun download(session: DriveSessionEntity) {
        if (mutableState.value.busy) return
        val scan = mutableState.value.scan ?: return
        val active = client ?: return
        mutableState.value = mutableState.value.copy(busy = true, error = null, stage = "DOWNLOAD", progress = 0f)
        job = scope.launch(Dispatchers.Main) {
            val id = UUID.randomUUID().toString()
            val output = File(File(context.filesDir, "drive-videos").apply { mkdirs() }, "70mai-$id.mp4")
            val identity = scan.clips.joinToString("|") { it.id } + "|${session.startedAt}|${session.endedAt}"
            val directory = File(context.cacheDir, "70mai/${SeventyMaiProtocol.md5(identity)}").apply { mkdirs() }
            try {
                ContextCompat.startForegroundService(context, Intent(context, VideoExportService::class.java))
                active.album(true, scan.key)
                val local = mutableListOf<Pair<SeventyMaiClip, File>>()
                scan.clips.forEachIndexed { index, clip ->
                    val file = File(directory, "$index.mp4")
                    mutableState.value = mutableState.value.copy(stage = "DOWNLOAD:${index + 1}/${scan.clips.size}")
                    active.download(clip, file) { received, total ->
                        mutableState.value = mutableState.value.copy(receivedBytes = received, totalBytes = total,
                            progress = (index + if (total > 0) received.toFloat() / total else 0f) / scan.clips.size)
                    }
                    local += clip to file
                }
                mutableState.value = mutableState.value.copy(stage = "JOIN", progress = 0f)
                val prepared = withContext(Dispatchers.IO) { prepareClips(local, session) }
                val sequence = EditedMediaItemSequence.Builder(emptyList<EditedMediaItem>())
                var cursor = 0L
                var hasGaps = false
                val dimensions = withContext(Dispatchers.IO) { inspect(prepared.parts.first().file) }
                val blackImage = File(directory, "gap.png")
                prepared.parts.forEach { part ->
                    val gap = part.outputStart - cursor
                    if (gap > 50) {
                        hasGaps = true
                        if (!blackImage.exists()) {
                            val bitmap = android.graphics.Bitmap.createBitmap(2, 2, android.graphics.Bitmap.Config.ARGB_8888)
                            bitmap.eraseColor(android.graphics.Color.BLACK)
                            withContext(Dispatchers.IO) { blackImage.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) } }
                            bitmap.recycle()
                        }
                        sequence.addItem(EditedMediaItem.Builder(MediaItem.Builder().setUri(Uri.fromFile(blackImage)).setImageDurationMs(gap).build())
                            .setFrameRate(30).setRemoveAudio(true).setEffects(Effects(emptyList(), listOf(androidx.media3.effect.Presentation.createForWidthAndHeight(dimensions.width, dimensions.height, androidx.media3.effect.Presentation.LAYOUT_SCALE_TO_FIT)))).build())
                    }
                    sequence.addItem(EditedMediaItem.Builder(MediaItem.Builder().setUri(Uri.fromFile(part.file))
                        .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionMs(part.sourceStart).setEndPositionMs(part.sourceStart + part.duration).build()).build()).build())
                    cursor = part.outputStart + part.duration
                }
                val composition = Composition.Builder(sequence.build()).setTransmuxAudio(!hasGaps).setTransmuxVideo(!hasGaps).experimentalSetForceAudioTrack(hasGaps).build()
                join(composition, output)
                val metadata = withContext(Dispatchers.IO) { inspect(output) }
                dao.upsertVideo(VideoProjectEntity(
                    id = id, sessionId = session.id, sourceKind = "DASH_CAMERA", localUri = Uri.fromFile(output).toString(),
                    sourceDisplayName = "${scan.model.title}${if (scan.model.rearCamera) if (scan.rear) context.videoText(" · Rear", " · Tył") else context.videoText(" · Front", " · Przód") else ""} · ${scan.clips.size}",
                    durationSeconds = metadata.durationMillis / 1000.0, fileSizeBytes = output.length(), pixelWidth = metadata.width,
                    pixelHeight = metadata.height, framesPerSecond = metadata.fps, hasAudio = metadata.audio,
                    telemetryTrimStartSeconds = (prepared.startedAt - session.startedAt).coerceAtLeast(0) / 1000.0,
                    exportDurationSeconds = minOf(metadata.durationMillis, session.endedAt - prepared.startedAt).coerceAtLeast(0) / 1000.0,
                    overlayTemplateId = "RACE"
                ))
                directory.deleteRecursively()
                mutableState.value = mutableState.value.copy(stage = "DONE", progress = 1f, projectId = id)
            } catch (cancelled: CancellationException) {
                output.delete(); mutableState.value = SeventyMaiImportState(busy = true, scan = scan); throw cancelled
            } catch (error: Exception) {
                android.util.Log.e("TougeDashVideo", "70mai import failed", error)
                output.delete(); mutableState.value = mutableState.value.copy(error = error.message ?: error.javaClass.simpleName)
            } finally {
                withContext(NonCancellable + Dispatchers.IO) { runCatching { active.album(false, scan.key) } }
                mutableState.value = mutableState.value.copy(busy = false)
                context.stopService(Intent(context, VideoExportService::class.java))
            }
        }
    }
    private data class Part(val file: File, val sourceStart: Long, val duration: Long, val outputStart: Long)
    private data class Prepared(val startedAt: Long, val parts: List<Part>)
    private fun prepareClips(files: List<Pair<SeventyMaiClip, File>>, session: DriveSessionEntity): Prepared {
        val start = maxOf(session.startedAt, files.first().first.startedAt)
        var cursor = 0L
        val parts = files.mapNotNull { (clip, file) ->
            val actual = inspect(file).durationMillis
            val clipStart = maxOf(session.startedAt, clip.startedAt)
            val clipEnd = minOf(session.endedAt, clip.startedAt + actual)
            val expectedCursor = clipStart - start
            val overlap = maxOf(0L, cursor - expectedCursor)
            val sourceStart = (clipStart - clip.startedAt + overlap).coerceAtLeast(0)
            val duration = minOf(clipEnd - clipStart - overlap, actual - sourceStart)
            if (duration <= 0) null else {
                val outputStart = maxOf(cursor, expectedCursor)
                cursor = outputStart + duration
                Part(file, sourceStart, duration, outputStart)
            }
        }
        require(parts.isNotEmpty()) { "70mai: no playable recording overlaps this drive" }
        return Prepared(start, parts)
    }
    private suspend fun join(composition: Composition, output: File) = coroutineScope {
        var transformer: Transformer? = null
        val progress = launch {
            val holder = ProgressHolder()
            while (true) {
                if (transformer?.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) mutableState.value = mutableState.value.copy(progress = holder.progress / 100f)
                delay(250)
            }
        }
        try {
            suspendCancellableCoroutine<Unit> { continuation ->
                val active = Transformer.Builder(context).setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC).addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) { if (continuation.isActive) continuation.resume(Unit) }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) { if (continuation.isActive) continuation.resumeWithException(exportException) }
                }).build()
                transformer = active
                continuation.invokeOnCancellation { android.os.Handler(android.os.Looper.getMainLooper()).post { active.cancel() } }
                active.start(composition, output.path)
            }
        } finally {
            progress.cancel()
            if (!currentCoroutineContext().isActive) transformer?.cancel()
        }
    }
    private data class Metadata(val durationMillis: Long, val width: Int, val height: Int, val fps: Double, val audio: Boolean)
    private fun inspect(file: File): Metadata = MediaMetadataRetriever().run {
        try {
            setDataSource(file.path)
            val width = extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val duration = extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            require(duration > 0 && width > 0 && height > 0) { "70mai: invalid MP4" }
            Metadata(duration, if (rotation % 180 == 0) width else height, if (rotation % 180 == 0) height else width,
                extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull() ?: 30.0,
                extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes")
        } finally { release() }
    }
}
