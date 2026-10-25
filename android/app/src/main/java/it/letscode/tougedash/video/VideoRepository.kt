@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.video

import android.content.ContentValues
import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaCodecInfo
import android.net.Uri
import android.os.Environment
import android.os.Build
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
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
    val outputHasAudio: Boolean = false,
    val outputUri: String? = null
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
    private var videoJob: Job? = null
    private var exportOutput: File? = null
    val isBusy: Boolean get() = videoJob?.isCompleted == false
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
                name = "${template.entity.name} ${context.videoText("copy", "kopia")}",
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
        if (isBusy) return
        videoJob = scope.launch(Dispatchers.Main) {
            val id = UUID.randomUUID().toString()
            val target = File(File(context.filesDir, "drive-videos").apply { mkdirs() }, "gallery-$id.mp4")
            mutableTask.value = VideoTaskState("Copying video from gallery", projectId = id)
            try {
                val meta = withContext(Dispatchers.IO) {
                    val total = context.contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length.coerceAtLeast(0) } ?: 0
                    mutableTask.value = mutableTask.value.copy(totalBytes = total)
                    context.contentResolver.openInputStream(uri).use { input ->
                        requireNotNull(input) { "Cannot open selected video" }
                        target.outputStream().use { output ->
                            val buffer = ByteArray(512 * 1024)
                            var copied = 0L
                            while (true) {
                                ensureActive()
                                val count = input.read(buffer)
                                if (count < 0) break
                                output.write(buffer, 0, count)
                                copied += count
                                mutableTask.value = mutableTask.value.copy(transferredBytes = copied, progress = if (total > 0) (copied.toFloat() / total).coerceIn(0f, 1f) else 0f)
                            }
                        }
                    }
                    metadata(Uri.fromFile(target))
                }
                require(meta.durationSeconds > 0 && meta.width > 0 && meta.height > 0) { "The selected file has no playable video track" }
                dao.upsertVideo(VideoProjectEntity(
                    id = id, sessionId = sessionId, sourceKind = "GALLERY", localUri = Uri.fromFile(target).toString(),
                    sourceDisplayName = withContext(Dispatchers.IO) { displayName(uri) }, durationSeconds = meta.durationSeconds,
                    fileSizeBytes = target.length(), pixelWidth = meta.width, pixelHeight = meta.height,
                    framesPerSecond = meta.fps, hasAudio = meta.hasAudio,
                    exportDurationSeconds = minOf(meta.durationSeconds, driveDurationSeconds), overlayTemplateId = OverlayStyle.RACE.name
                ))
                mutableTask.value = mutableTask.value.copy(progress = 1f, completed = true)
            } catch (cancelled: CancellationException) {
                target.delete()
                mutableTask.value = VideoTaskState()
                throw cancelled
            } catch (error: Exception) {
                target.delete()
                mutableTask.value = mutableTask.value.copy(error = error.message ?: "Import failed")
            }
        }
    }

    fun update(project: VideoProjectEntity) { scope.launch { dao.upsertVideo(project) } }

    fun registerCameraRecording(sessionId: String, file: File, cameraName: String, hasAudio: Boolean, startedAtMillis: Long = System.currentTimeMillis()) {
        scope.launch(Dispatchers.IO) {
            runCatching {
                val meta = metadata(Uri.fromFile(file))
                val id = UUID.randomUUID().toString()
                val session = dao.sessionOnce(sessionId)
                val offset = ((startedAtMillis - (session?.startedAt ?: startedAtMillis)) / 1000.0).coerceAtLeast(0.0)
                dao.upsertVideo(
                    VideoProjectEntity(
                        id = id, sessionId = sessionId, sourceKind = "CAMERA", localUri = Uri.fromFile(file).toString(),
                        sourceDisplayName = cameraName, durationSeconds = meta.durationSeconds, fileSizeBytes = file.length(),
                        pixelWidth = meta.width, pixelHeight = meta.height, framesPerSecond = meta.fps,
                        hasAudio = hasAudio, telemetryTrimStartSeconds = offset, exportDurationSeconds = meta.durationSeconds,
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

    fun export(
        project: VideoProjectEntity,
        samples: List<TelemetrySampleEntity>,
        definition: VideoOverlayTemplateDefinition,
        addsOverlay: Boolean = true,
        quality: DriveVideoExportQuality = DriveVideoExportQuality.FAST_FULL_HD,
        telemetryOriginMillis: Long = samples.firstOrNull()?.recordedAt ?: 0L
    ) {
        if (isBusy) return
        mutableTask.value = VideoTaskState("Rendering telemetry HUD", projectId = project.id)
        videoJob = scope.launch(Dispatchers.Main) {
            val output = File(File(context.cacheDir, "exports").apply { mkdirs() }, "touge-${UUID.randomUUID()}.mp4")
            exportOutput = output
            try {
                ContextCompat.startForegroundService(context, Intent(context, VideoExportService::class.java))
                require(project.exportDurationSeconds > 0) { "Choose a non-empty video and telemetry range" }
                val clip = MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs((project.videoTrimStartSeconds * 1000).toLong())
                    .setEndPositionMs(((project.videoTrimStartSeconds + project.exportDurationSeconds) * 1000).toLong())
                    .build()
                val dimensions = quality.dimensions(project.pixelWidth, project.pixelHeight)
                val effects = mutableListOf<androidx.media3.common.Effect>()
                if (quality == DriveVideoExportQuality.FAST_FULL_HD && dimensions != (project.pixelWidth to project.pixelHeight)) {
                    effects += Presentation.createForWidthAndHeight(dimensions.first, dimensions.second, Presentation.LAYOUT_SCALE_TO_FIT)
                }
                val elements = definition.resolvedElements()
                if (addsOverlay && elements.isNotEmpty()) {
                    val routeMap = if (elements.any { it.kind.isRouteMap }) createRouteMapSnapshot(context, samples, includesDetailedLayer = elements.any { it.kind.isRouteMap && it.mapZoom > 1.85f }) else null
                    val locale = context.videoLocale()
                    val polish = locale.language == "pl"
                    effects += OverlayEffect(listOf(TelemetryBitmapOverlay(samples, project.telemetryTrimStartSeconds, definition, dimensions.first, dimensions.second, routeMap,
                        telemetryOriginMillis = telemetryOriginMillis, maximumFramesPerSecond = if (quality == DriveVideoExportQuality.FAST_FULL_HD) 15 else 30,
                        timestampLabel = if (polish) "CZAS TELEMETRII" else "TELEMETRY TIME", locale = locale, maximumBitmapLongEdge = if (quality == DriveVideoExportQuality.FAST_FULL_HD) 1600 else 3840)))
                }
                val edited = EditedMediaItem.Builder(MediaItem.Builder().setUri(project.localUri).setClippingConfiguration(clip).build())
                    .setEffects(Effects(emptyList(), effects)).build()
                val plan = VideoExportQuality.plan(dimensions.first, dimensions.second, project.framesPerSecond)
                val encoderFactory = DefaultEncoderFactory.Builder(context).setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder()
                    .setBitrate(plan.bitrate).setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR).setiFrameIntervalSeconds(1f).build())
                    .setEnableFallback(true).build()
                val progressJob = launch {
                    val holder = ProgressHolder()
                    while (true) {
                        if (transformer?.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) mutableTask.value = mutableTask.value.copy(progress = holder.progress / 100f)
                        delay(250)
                    }
                }
                val result = try {
                    suspendCancellableCoroutine<ExportResult> { continuation ->
                        val active = Transformer.Builder(context)
                            .apply { if (addsOverlay || quality == DriveVideoExportQuality.FAST_FULL_HD) setVideoMimeType(plan.mimeType) }
                            .setAudioMimeType(MimeTypes.AUDIO_AAC).setEncoderFactory(encoderFactory)
                            .addListener(object : Transformer.Listener {
                                override fun onCompleted(composition: androidx.media3.transformer.Composition, exportResult: ExportResult) {
                                    if (continuation.isActive) continuation.resume(exportResult)
                                }
                                override fun onError(composition: androidx.media3.transformer.Composition, exportResult: ExportResult, exportException: ExportException) {
                                    if (continuation.isActive) continuation.resumeWithException(exportException)
                                }
                            }).build()
                        transformer = active
                        continuation.invokeOnCancellation { android.os.Handler(android.os.Looper.getMainLooper()).post { active.cancel() } }
                        active.start(edited, output.absolutePath)
                    }
                } finally {
                    progressJob.cancel()
                    if (!kotlinx.coroutines.currentCoroutineContext().isActive) transformer?.cancel()
                    transformer = null
                }
                mutableTask.value = mutableTask.value.copy(operation = "Saving video to gallery", progress = 1f)
                val savedUri = withContext(Dispatchers.IO) { saveToGallery(output) }
                mutableTask.value = mutableTask.value.copy(completed = true, transferredBytes = output.length(), totalBytes = output.length(),
                    outputVideoMimeType = result.videoMimeType, outputVideoBitrate = result.averageVideoBitrate,
                    outputWidth = result.width, outputHeight = result.height, outputHasAudio = result.audioMimeType != null, outputUri = savedUri.toString())
            } catch (cancelled: CancellationException) {
                mutableTask.value = VideoTaskState()
                throw cancelled
            } catch (error: Exception) {
                mutableTask.value = mutableTask.value.copy(error = error.message ?: "Video export failed")
            } finally {
                transformer?.cancel()
                transformer = null
                output.delete()
                exportOutput = null
                context.stopService(Intent(context, VideoExportService::class.java))
            }
        }
    }

    fun cancelExport() {
        val cancelling = videoJob
        cancelling?.cancel()
        scope.launch(Dispatchers.Main) {
            cancelling?.join()
            if (videoJob === cancelling) { videoJob = null; mutableTask.value = VideoTaskState() }
        }
    }

    private suspend fun saveToGallery(file: File): Uri {
        val name = "TougeDash-${SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())}.mp4"
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= 29) put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Touge Dash")
            put(MediaStore.Video.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
            put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis())
            if (Build.VERSION.SDK_INT >= 29) put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val uri = requireNotNull(context.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values))
        var published = false
        try {
            context.contentResolver.openOutputStream(uri).use { output ->
                requireNotNull(output)
                file.inputStream().use { input ->
                    val buffer = ByteArray(512 * 1024)
                    while (true) { kotlinx.coroutines.currentCoroutineContext().ensureActive(); val count = input.read(buffer); if (count < 0) break; output.write(buffer, 0, count) }
                }
            }
            if (Build.VERSION.SDK_INT >= 29) context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null)
            published = true
            return uri
        } finally { if (!published) context.contentResolver.delete(uri, null, null) }
    }

    private fun displayName(uri: Uri): String? = context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
    }

    private fun decodeTemplate(entity: OverlayTemplateEntity): VideoOverlayTemplate? = runCatching {
        val definition = json.decodeFromString<VideoOverlayTemplateDefinition>(normalizeVideoOverlayJson(entity.definitionJson))
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
        template("STREET_SHIFT", "Street Shift", VideoOverlayTemplateDefinition.streetShift()),
        template("ROUTE_RADAR", "Route Radar", VideoOverlayTemplateDefinition.routeRadar()),
        template("ROUTE_ORBIT", "Route Orbit", VideoOverlayTemplateDefinition.routeOrbit()),
        template("PURSUIT_MAP", "Pursuit Map", VideoOverlayTemplateDefinition.pursuitMap()),
        template("ROUTE_CHASE", "Route Chase", VideoOverlayTemplateDefinition.routeChase()),
        template("STREET_ATLAS", "Street Atlas", VideoOverlayTemplateDefinition.streetAtlas()),
        template("ICE_ORBIT", "Ice Orbit", VideoOverlayTemplateDefinition.iceOrbit()),
        template("AMBER_RUN", "Amber Run", VideoOverlayTemplateDefinition.amberRun())
    )

    private fun template(id: String, name: String, definition: VideoOverlayTemplateDefinition): VideoOverlayTemplate {
        val entity = OverlayTemplateEntity(id, name, json.encodeToString(definition), selected = id == "RACE")
        return VideoOverlayTemplate(entity, definition)
    }

    private data class Metadata(val durationSeconds: Double, val width: Int, val height: Int, val fps: Double, val hasAudio: Boolean)
    private fun metadata(uri: Uri): Metadata = MediaMetadataRetriever().run {
        try {
            setDataSource(context, uri)
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
