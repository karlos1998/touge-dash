@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.video

import android.content.ContentValues
import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.media3.common.MediaItem
import androidx.media3.effect.OverlayEffect
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import it.letscode.tougedash.data.local.TougeDashDao
import it.letscode.tougedash.data.local.VideoProjectEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

data class VideoTaskState(
    val operation: String? = null,
    val progress: Float = 0f,
    val transferredBytes: Long = 0,
    val totalBytes: Long = 0,
    val projectId: String? = null,
    val error: String? = null,
    val completed: Boolean = false
)

class VideoRepository(
    private val context: Context,
    private val dao: TougeDashDao,
    private val scope: CoroutineScope
) {
    private val mutableTask = MutableStateFlow(VideoTaskState())
    val task = mutableTask.asStateFlow()
    private var transformer: Transformer? = null

    fun importFromGallery(sessionId: String, driveDurationSeconds: Double, uri: Uri) {
        scope.launch {
            val id = UUID.randomUUID().toString()
            runCatching {
                val directory = File(context.filesDir, "drive-videos").apply { mkdirs() }
                val target = File(directory, "gallery-$id.mp4")
                val total = context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length.coerceAtLeast(0) } ?: 0
                mutableTask.value = VideoTaskState("Copying video from gallery", totalBytes = total, projectId = id)
                withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri).use { input ->
                        requireNotNull(input) { "Cannot open selected video" }
                        target.outputStream().use { output ->
                            val buffer = ByteArray(512 * 1024)
                            var copied = 0L
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                output.write(buffer, 0, count)
                                copied += count
                                mutableTask.value = mutableTask.value.copy(
                                    transferredBytes = copied,
                                    progress = if (total > 0) (copied.toFloat() / total).coerceIn(0f, 1f) else 0f
                                )
                            }
                        }
                    }
                }
                val meta = metadata(Uri.fromFile(target))
                val exportDuration = minOf(meta.durationSeconds, driveDurationSeconds).coerceAtLeast(.1)
                dao.upsertVideo(
                    VideoProjectEntity(
                        id = id, sessionId = sessionId, sourceKind = "GALLERY", localUri = Uri.fromFile(target).toString(),
                        sourceDisplayName = displayName(uri), durationSeconds = meta.durationSeconds,
                        fileSizeBytes = target.length(), pixelWidth = meta.width, pixelHeight = meta.height,
                        framesPerSecond = meta.fps, hasAudio = meta.hasAudio, exportDurationSeconds = exportDuration,
                        overlayTemplateId = OverlayStyle.RACE.name
                    )
                )
                mutableTask.value = mutableTask.value.copy(progress = 1f, completed = true)
            }.onFailure { mutableTask.value = mutableTask.value.copy(error = it.message ?: "Import failed") }
        }
    }

    fun update(project: VideoProjectEntity) { scope.launch { dao.upsertVideo(project) } }

    fun registerCameraRecording(sessionId: String, file: File, cameraName: String, hasAudio: Boolean) {
        scope.launch(Dispatchers.IO) {
            runCatching {
                val meta = metadata(Uri.fromFile(file))
                val id = UUID.randomUUID().toString()
                dao.upsertVideo(
                    VideoProjectEntity(
                        id = id, sessionId = sessionId, sourceKind = "CAMERA", localUri = Uri.fromFile(file).toString(),
                        sourceDisplayName = cameraName, durationSeconds = meta.durationSeconds, fileSizeBytes = file.length(),
                        pixelWidth = meta.width, pixelHeight = meta.height, framesPerSecond = meta.fps,
                        hasAudio = hasAudio, exportDurationSeconds = meta.durationSeconds,
                        overlayTemplateId = OverlayStyle.RACE.name
                    )
                )
            }.onFailure { mutableTask.value = VideoTaskState(error = it.message ?: "Could not index recording") }
        }
    }

    fun delete(project: VideoProjectEntity) {
        scope.launch(Dispatchers.IO) {
            Uri.parse(project.localUri).path?.let(::File)?.takeIf(File::exists)?.delete()
            dao.deleteVideo(project.id)
        }
    }

    fun clearTask() { mutableTask.value = VideoTaskState() }

    fun export(project: VideoProjectEntity, samples: List<TelemetrySampleEntity>, style: OverlayStyle, x: Float = 0f, y: Float = -.72f) {
        scope.launch(Dispatchers.Main) {
            val directory = File(context.cacheDir, "exports").apply { mkdirs() }
            val output = File(directory, "touge-${UUID.randomUUID()}.mp4")
            val clipping = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs((project.videoTrimStartSeconds * 1000).toLong())
                .setEndPositionMs(((project.videoTrimStartSeconds + project.exportDurationSeconds) * 1000).toLong())
                .build()
            val item = MediaItem.Builder().setUri(project.localUri).setClippingConfiguration(clipping).build()
            val overlay = TelemetryBitmapOverlay(samples, project.telemetryTrimStartSeconds, style, x, y)
            val edited = EditedMediaItem.Builder(item).setEffects(Effects(emptyList(), listOf(OverlayEffect(listOf(overlay))))).build()
            mutableTask.value = VideoTaskState("Rendering telemetry HUD", projectId = project.id)
            transformer = Transformer.Builder(context).addListener(object : Transformer.Listener {
                override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                    scope.launch(Dispatchers.IO) {
                        runCatching { saveToGallery(output) }
                            .onSuccess { mutableTask.value = mutableTask.value.copy(progress = 1f, completed = true, transferredBytes = output.length(), totalBytes = output.length()) }
                            .onFailure { mutableTask.value = mutableTask.value.copy(error = it.message ?: "Could not save video") }
                        output.delete()
                    }
                }

                override fun onError(composition: androidx.media3.transformer.Composition, exportResult: ExportResult, exportException: ExportException) {
                    mutableTask.value = mutableTask.value.copy(error = exportException.message ?: "Video export failed")
                    output.delete()
                }
            }).build().also { it.start(edited, output.absolutePath) }
            val holder = ProgressHolder()
            while (transformer != null && !mutableTask.value.completed && mutableTask.value.error == null) {
                if (transformer?.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) mutableTask.value = mutableTask.value.copy(progress = holder.progress / 100f)
                delay(250)
            }
        }
    }

    fun cancelExport() { transformer?.cancel(); transformer = null; mutableTask.value = VideoTaskState() }

    private fun saveToGallery(file: File): Uri {
        val name = "TougeDash-${SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())}.mp4"
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Touge Dash")
            put(MediaStore.Video.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
            put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis())
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val uri = requireNotNull(context.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values))
        context.contentResolver.openOutputStream(uri).use { output -> requireNotNull(output); file.inputStream().use { it.copyTo(output) } }
        context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
        return uri
    }

    private fun displayName(uri: Uri): String? = context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
    }

    private data class Metadata(val durationSeconds: Double, val width: Int, val height: Int, val fps: Double, val hasAudio: Boolean)
    private fun metadata(uri: Uri): Metadata = MediaMetadataRetriever().run {
        setDataSource(context, uri)
        try {
            Metadata(
                (extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDoubleOrNull() ?: 0.0) / 1000,
                extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0,
                extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0,
                extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull() ?: 30.0,
                extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            )
        } finally { release() }
    }
}
