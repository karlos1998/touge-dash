@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.video

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.PendingRecording
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.util.UUID

class CameraRecordingController(
    private val context: Context,
    private val repository: VideoRepository,
    private val settingsStore: VideoRecordingSettings
) {
    private var provider: ProcessCameraProvider? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var activeFile: File? = null
    private var activeSessionId: String? = null
    private var activeCameraName = "Rear camera"
    private var activeHasAudio = false
    private var preparingAutomaticRecording = false
    private val mutableRecording = MutableStateFlow(false)
    val isRecording = mutableRecording.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val error = mutableError.asStateFlow()

    fun bind(owner: LifecycleOwner, previewView: PreviewView, front: Boolean, result: (Boolean) -> Unit = {}) {
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            runCatching {
                val cameraProvider = future.get()
                provider = cameraProvider
                val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
                val recorder = createRecorder()
                videoCapture = VideoCapture.withOutput(recorder)
                val selector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                activeCameraName = if (front) "Front camera" else "Rear camera"
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(owner, selector, preview, videoCapture)
                result(true)
            }.onFailure { mutableError.value = it.message; result(false) }
        }, ContextCompat.getMainExecutor(context))
    }

    fun ensureAutomaticRecording(owner: LifecycleOwner, sessionId: String) {
        if (recording != null || preparingAutomaticRecording) return
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return
        preparingAutomaticRecording = true
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            runCatching {
                val settings = settingsStore.settings.value
                val cameraProvider = future.get()
                provider = cameraProvider
                videoCapture = VideoCapture.withOutput(createRecorder())
                val selector = if (settings.frontCamera) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                activeCameraName = if (settings.frontCamera) "Front camera" else "Rear camera"
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(owner, selector, videoCapture)
                start(sessionId)
            }.onFailure { mutableError.value = it.message }
            preparingAutomaticRecording = false
        }, ContextCompat.getMainExecutor(context))
    }

    fun stopWhenSessionEnds(currentSessionId: String?) {
        if (recording != null && activeSessionId != currentSessionId) stop()
    }

    fun start(sessionId: String) {
        if (recording != null) return
        val capture = videoCapture ?: return
        val directory = File(context.filesDir, "drive-videos").apply { mkdirs() }
        val file = File(directory, "camera-${UUID.randomUUID()}.mp4")
        val audio = settingsStore.settings.value.recordAudio && ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        var pending: PendingRecording = capture.output.prepareRecording(context, FileOutputOptions.Builder(file).build())
        if (audio) pending = pending.withAudioEnabled()
        activeFile = file; activeSessionId = sessionId; activeHasAudio = audio; mutableError.value = null
        recording = pending.start(ContextCompat.getMainExecutor(context)) { event ->
            when (event) {
                is VideoRecordEvent.Start -> mutableRecording.value = true
                is VideoRecordEvent.Finalize -> {
                    mutableRecording.value = false
                    val completed = activeFile; val session = activeSessionId
                    recording = null; activeFile = null; activeSessionId = null
                    if (event.hasError()) { completed?.delete(); mutableError.value = event.cause?.message ?: "Camera recording failed (${event.error})" }
                    else if (completed != null && session != null) repository.registerCameraRecording(session, completed, activeCameraName, activeHasAudio)
                }
            }
        }
    }

    fun stop() { recording?.stop() }
    fun clearError() { mutableError.value = null }

    private fun createRecorder(): Recorder {
        val quality = when (settingsStore.settings.value.quality) {
            DriveVideoQuality.STORAGE_SAVER -> Quality.HD
            DriveVideoQuality.FULL_HD -> Quality.FHD
            DriveVideoQuality.ULTRA_HD -> Quality.UHD
        }
        return Recorder.Builder().setQualitySelector(
            QualitySelector.from(quality, FallbackStrategy.lowerQualityOrHigherThan(Quality.SD))
        ).build()
    }
}
