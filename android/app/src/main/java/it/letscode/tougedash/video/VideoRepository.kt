@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.video

import android.content.ContentValues
import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaCodecInfo
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.media3.common.MediaItem
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.effect.OverlayEffect
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import it.letscode.tougedash.data.local.TougeDashDao
import it.letscode.tougedash.data.local.VideoProjectEntity
import it.letscode.tougedash.data.local.OverlayTemplateEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import it.letscode.tougedash.dashboard.normalizeLegacyDashboardJson

data class VideoTaskState(
    val operation: String? = null,
    val progress: Float = 0f,
    val transferredBytes: Long = 0,
    val totalBytes: Long = 0,
    val projectId: String? = null,
    val error: String? = null,
    val completed: Boolean = false,
    val outputVideoMimeType: String? = null,
    val outputVideoBitrate: Int = 0,
    val outputWidth: Int = 0,
    val outputHeight: Int = 0,
    val outputHasAudio: Boolean = false
)

class VideoRepository(
    private val context: Context,
    private val dao: TougeDashDao,
    private val scope: CoroutineScope
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val mutableTask = MutableStateFlow(VideoTaskState())
    val task = mutableTask.asStateFlow()
    private var transformer: Transformer? = null
    val overlayTemplates = dao.overlayTemplates().map { entities -> entities.mapNotNull(::decodeTemplate) }

    fun ensureOverlayTemplates() {
        scope.launch(Dispatchers.IO) {
            val existingIds = dao.overlayTemplatesOnce().mapTo(mutableSetOf()) { it.id }
            defaultTemplates()
                .filterNot { it.entity.id in existingIds }
                .forEach { dao.upsertOverlayTemplate(it.entity) }
        }
    }

    fun updateOverlayTemplate(template: VideoOverlayTemplate) {
        scope.launch(Dispatchers.IO) {
            dao.upsertOverlayTemplate(template.entity.copy(definitionJson = json.encodeToString(template.definition), modifiedAt = System.currentTimeMillis()))
        }
    }

    fun duplicateOverlayTemplate(template: VideoOverlayTemplate) {
        scope.launch(Dispatchers.IO) {
            val id = UUID.randomUUID().toString()
            val entity = OverlayTemplateEntity(
                id = id,
                name = "${template.entity.name} copy",
                definitionJson = json.encodeToString(template.definition),
                modifiedAt = System.currentTimeMillis(),
                selected = false
            )
            dao.upsertOverlayTemplate(entity)
        }
    }

    fun deleteOverlayTemplate(template: VideoOverlayTemplate) {
        scope.launch(Dispatchers.IO) {
            if (dao.overlayTemplatesOnce().size > 1) dao.deleteOverlayTemplate(template.entity.id)
        }
    }

    fun restoreOverlayTemplates() {
        scope.launch(Dispatchers.IO) {
            dao.overlayTemplatesOnce().forEach { dao.deleteOverlayTemplate(it.id) }
            defaultTemplates().forEach { dao.upsertOverlayTemplate(it.entity) }
        }
    }

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

    suspend fun deleteForSession(sessionId: String) = withContext(Dispatchers.IO) {
        dao.videosOnce(sessionId).forEach { project ->
            Uri.parse(project.localUri).path?.let(::File)?.takeIf(File::exists)?.delete()
        }
    }

    fun clearTask() { mutableTask.value = VideoTaskState() }

    fun export(project: VideoProjectEntity, samples: List<TelemetrySampleEntity>, definition: VideoOverlayTemplateDefinition) {
        scope.launch(Dispatchers.Main) {
            val directory = File(context.cacheDir, "exports").apply { mkdirs() }
            val output = File(directory, "touge-${UUID.randomUUID()}.mp4")
            val clipping = MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs((project.videoTrimStartSeconds * 1000).toLong())
                .setEndPositionMs(((project.videoTrimStartSeconds + project.exportDurationSeconds) * 1000).toLong())
                .build()
            val item = MediaItem.Builder().setUri(project.localUri).setClippingConfiguration(clipping).build()
            val overlay = TelemetryBitmapOverlay(
                samples,
                project.telemetryTrimStartSeconds,
                definition,
                project.pixelWidth,
                project.pixelHeight
            )
            val edited = EditedMediaItem.Builder(item).setEffects(Effects(emptyList(), listOf(OverlayEffect(listOf(overlay))))).build()
            val encodingPlan = VideoExportQuality.plan(project.pixelWidth, project.pixelHeight, project.framesPerSecond)
            val encoderSettings = VideoEncoderSettings.Builder()
                .setBitrate(encodingPlan.bitrate)
                .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
                .setiFrameIntervalSeconds(1f)
                .build()
            val encoderFactory = DefaultEncoderFactory.Builder(context)
                .setRequestedVideoEncoderSettings(encoderSettings)
                .setEnableFallback(true)
                .build()
            mutableTask.value = VideoTaskState("Rendering telemetry HUD", projectId = project.id)
            transformer = Transformer.Builder(context)
                .setVideoMimeType(encodingPlan.mimeType)
                .setEncoderFactory(encoderFactory)
                .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                    transformer = null
                    scope.launch(Dispatchers.IO) {
                        runCatching { saveToGallery(output) }
                            .onSuccess {
                                mutableTask.value = mutableTask.value.copy(
                                    progress = 1f,
                                    completed = true,
                                    transferredBytes = output.length(),
                                    totalBytes = output.length(),
                                    outputVideoMimeType = exportResult.videoMimeType,
                                    outputVideoBitrate = exportResult.averageVideoBitrate,
                                    outputWidth = exportResult.width,
                                    outputHeight = exportResult.height,
                                    outputHasAudio = exportResult.audioMimeType != null
                                )
                            }
                            .onFailure { mutableTask.value = mutableTask.value.copy(error = it.message ?: "Could not save video") }
                        output.delete()
                    }
                }

                override fun onError(composition: androidx.media3.transformer.Composition, exportResult: ExportResult, exportException: ExportException) {
                    transformer = null
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
        var published = false
        try {
            context.contentResolver.openOutputStream(uri).use { output ->
                requireNotNull(output)
                file.inputStream().use { it.copyTo(output) }
            }
            context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
            published = true
            return uri
        } finally {
            if (!published) context.contentResolver.delete(uri, null, null)
        }
    }

    private fun displayName(uri: Uri): String? = context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
    }

    private fun decodeTemplate(entity: OverlayTemplateEntity): VideoOverlayTemplate? = runCatching {
        val definition = json.decodeFromString<VideoOverlayTemplateDefinition>(normalizeLegacyDashboardJson(entity.definitionJson))
        VideoOverlayTemplate(entity, definition)
    }.getOrNull()

    private fun defaultTemplates(): List<VideoOverlayTemplate> = listOf(
        template("RACE", "Touge Pro", VideoOverlayTemplateDefinition.tougePro()),
        template("UNDERGROUND", "Night Run", VideoOverlayTemplateDefinition.nightRun()),
        template("MINIMAL", "Clean Drive", VideoOverlayTemplateDefinition.cleanDrive()),
        template("PORTRAIT_RALLY", "Portrait Rally", VideoOverlayTemplateDefinition.portraitRally()),
        template("STREET_LEGENDS", "Street Legends", VideoOverlayTemplateDefinition.streetLegends()),
        template("NEON_CIRCUIT", "Neon Circuit", VideoOverlayTemplateDefinition.neonCircuit()),
        template("BLACKLIST_CLASSIC", "Blacklist Classic", VideoOverlayTemplateDefinition.blacklistClassic()),
        template("CARBON_GOLD", "Carbon Gold", VideoOverlayTemplateDefinition.carbonGold()),
        template("STREET_SHIFT", "Street Shift", VideoOverlayTemplateDefinition.streetShift())
    )

    private fun template(id: String, name: String, definition: VideoOverlayTemplateDefinition): VideoOverlayTemplate {
        val entity = OverlayTemplateEntity(id, name, json.encodeToString(definition), selected = id == "RACE")
        return VideoOverlayTemplate(entity, definition)
    }

    private data class Metadata(val durationSeconds: Double, val width: Int, val height: Int, val fps: Double, val hasAudio: Boolean)
    private fun metadata(uri: Uri): Metadata = MediaMetadataRetriever().run {
        setDataSource(context, uri)
        try {
            val rawWidth = extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val rawHeight = extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val rotated = rotation % 180 != 0
            Metadata(
                (extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDoubleOrNull() ?: 0.0) / 1000,
                if (rotated) rawHeight else rawWidth,
                if (rotated) rawWidth else rawHeight,
                extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull() ?: 30.0,
                extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            )
        } finally { release() }
    }
}
