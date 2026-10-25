@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
package it.letscode.tougedash.video

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.TougeDashApplication
import it.letscode.tougedash.data.local.*
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.ui.*
import it.letscode.tougedash.ui.theme.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.encodeToString
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class VideoParityInstrumentedTest {
    private val app = ApplicationProvider.getApplicationContext<TougeDashApplication>()
    private val container get() = app.container
    private lateinit var activity: ActivityScenario<MainActivity>
    private lateinit var project: VideoProjectEntity
    private lateinit var samples: List<TelemetrySampleEntity>
    private val origin = 1_800_000_000_000L

    @Before fun prepare() = runBlocking {
        CompatibilityOnboardingPreference.accept(app)
        AppLanguagePreference.write(app, AppLanguage.POLISH)
        AppThemePreference.write(app, AppTheme.DARK)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        listOf(android.Manifest.permission.BLUETOOTH_SCAN, android.Manifest.permission.BLUETOOTH_CONNECT, android.Manifest.permission.POST_NOTIFICATIONS).forEach {
            runCatching { instrumentation.uiAutomation.grantRuntimePermission(app.packageName, it) }
        }
        val file = File(File(app.filesDir, "drive-videos").apply { mkdirs() }, "parity-drive.mp4")
        instrumentation.context.assets.open("parity-drive.mp4").use { input -> file.outputStream().use { input.copyTo(it) } }
        samples = (0..120).map { index ->
            TelemetrySampleEntity(id = "parity-$index", sessionId = SESSION, recordedAt = origin + index * 100L,
                rpm = 1000.0 + index * 50, boostBar = index / 100.0, mapKpa = 100.0 + index,
                throttlePercent = 42.0, coolantCelsius = 82.0, intakeCelsius = 34.0, egt1Celsius = 914.0, egt2Celsius = 887.0,
                oilTemperatureCelsius = 76.0, oilPressureBar = 2.4, fuelPressureBar = 3.4, afr = 14.5, lambda = .84,
                batteryVoltage = 13.8, ignitionDegrees = 15.0, injectorDutyPercent = 48.0, speedKph = 62.0 + index / 4.0, checkEngineMask = 0)
        }
        container.dao.upsertSession(DriveSessionEntity(SESSION, "parity-logger", startedAt = origin, endedAt = origin + 12000,
            modifiedAt = origin, sampleCount = samples.size, customName = "Porównanie iOS / Android", maxRpm = 7000.0, maxSpeedKph = 92.0, maxBoostBar = 1.2, maxCoolantCelsius = 82.0, maxOilTemperatureCelsius = 76.0))
        container.dao.insertSamples(samples)
        project = VideoProjectEntity(PROJECT, SESSION, "GALLERY", Uri.fromFile(file).toString(), "parity-drive.mp4", 12.0, file.length(), 1280, 720, 30.0, true, exportDurationSeconds = 12.0, overlayTemplateId = "RACE")
        container.dao.upsertVideo(project)
        activity = ActivityScenario.launch(MainActivity::class.java)
    }
    @After fun close() { if (::activity.isInitialized) activity.close() }

    @Test fun immediateCancellationLeavesNoStuckTaskAndAllowsAnotherExport() = runBlocking {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            container.videoRepository.export(project, samples, VideoOverlayTemplateDefinition.tougePro(), telemetryOriginMillis = origin)
            container.videoRepository.cancelExport()
        }
        withTimeout(10_000) { container.videoRepository.task.first { it.operation == null } }
        assertFalse(container.videoRepository.isBusy)
    }

    @Test fun automaticCameraKeepsRecordingAfterActivityMovesToBackground() = runBlocking {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.uiAutomation.grantRuntimePermission(app.packageName, android.Manifest.permission.CAMERA)
        container.videoRecordingSettings.acceptWarning()
        container.videoRecordingSettings.update(DriveVideoSettings(automaticRecording = true, recordAudio = false, quality = DriveVideoQuality.STORAGE_SAVER))
        val snapshot = it.letscode.tougedash.model.TelemetrySnapshot(rpm = 2500.0, mapKpa = 150.0, updatedAt = System.currentTimeMillis())
        val id = container.historyRepository.record("parity-camera", "Camera QA", snapshot)!!
        try {
            instrumentation.runOnMainSync { androidx.core.content.ContextCompat.startForegroundService(app, android.content.Intent(app, DriveRecordingService::class.java)) }
            withTimeout(20_000) { container.cameraRecordingController.isRecording.first { it } }
            activity.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
            repeat(35) {
                container.historyRepository.record("parity-camera", "Camera QA", snapshot.copy(updatedAt = System.currentTimeMillis()))
                delay(100)
            }
            assertTrue("Camera stopped when the Activity was backgrounded", container.cameraRecordingController.isRecording.value)
        } finally {
            container.videoRecordingSettings.update(DriveVideoSettings())
            instrumentation.runOnMainSync { container.cameraRecordingController.stop() }
            container.historyRepository.finish()
            activity.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        }
        val recordings = withTimeout(20_000) { container.dao.videos(id).first { it.isNotEmpty() } }
        assertTrue(recordings.first().durationSeconds >= 2.0)
        assertTrue(recordings.first().telemetryTrimStartSeconds >= 0.0)
    }

    @Test fun galleryImportCreatesAnIndependentLocalProject() = runBlocking {
        val before = container.dao.videosOnce(SESSION).map { it.id }.toSet()
        container.videoRepository.clearTask()
        container.videoRepository.importFromGallery(SESSION, 8.0, Uri.parse(project.localUri))
        val result = withTimeout(20_000) { container.videoRepository.task.first { it.completed || it.error != null } }
        assertNull(result.error)
        val imported = container.dao.videosOnce(SESSION).first { it.id !in before }
        assertEquals("GALLERY", imported.sourceKind)
        assertEquals(8.0, imported.exportDurationSeconds, .001)
        assertEquals(project.fileSizeBytes, imported.fileSizeBytes)
        assertNotEquals(project.localUri, imported.localUri)
        assertTrue(File(Uri.parse(imported.localUri).path!!).exists())
    }

    @Test fun exportContinuesWhenActivityLeavesForeground() = runBlocking {
        export(project.copy(exportDurationSeconds = 4.0), VideoOverlayTemplateDefinition.tougePro(), true, "qa-export-background.mp4", background = true)
    }

    @Test fun originalRawExportKeepsSourceResolutionAndAudio() = runBlocking {
        export(project.copy(exportDurationSeconds = 2.0), VideoOverlayTemplateDefinition.tougePro(), false, "qa-export-original.mp4", quality = DriveVideoExportQuality.ORIGINAL)
    }

    @Test fun fastExportDownscalesFourKToFullHdAndKeepsAudio() = runBlocking {
        val file = File(app.filesDir, "parity-4k.mp4")
        InstrumentationRegistry.getInstrumentation().context.assets.open("parity-4k.mp4").use { input -> file.outputStream().use { input.copyTo(it) } }
        val source = project.copy(localUri = Uri.fromFile(file).toString(), pixelWidth = 3840, pixelHeight = 2160, durationSeconds = 2.0, exportDurationSeconds = 2.0)
        export(source, VideoOverlayTemplateDefinition.tougePro(), true, "qa-export-4k-fullhd.mp4", 1920, 1080)
    }

    @Test fun factoryHudExportsTheSameInitialTelemetryAsIosReference() = runBlocking {
        val reference = samples.map { it.copy(rpm = 2200.0, speedKph = 62.0, boostBar = -.05) }
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            container.videoRepository.export(project.copy(exportDurationSeconds = 2.0), reference, VideoOverlayTemplateDefinition.tougePro(), telemetryOriginMillis = origin)
        }
        val result = withTimeout(90_000) { container.videoRepository.task.first { it.completed || it.error != null } }
        assertNull(result.error)
        assertTrue(result.completed)
        app.contentResolver.openInputStream(Uri.parse(result.outputUri!!))!!.use { input -> File(app.filesDir, "qa-export-reference.mp4").outputStream().use { input.copyTo(it) } }
        assertTrue(File(app.filesDir, "qa-export-reference.mp4").length() > 0)
    }

    @Test fun trimmedExportRendersHudPreservesAudioAndDuration() = runBlocking {
        val definition = VideoOverlayTemplateDefinition.tougePro().copy(elements = VideoOverlayTemplateDefinition.tougePro().elements + VideoOverlayElement(
            metric = TelemetryMetric.SPEED, kind = OverlayElementKind.TELEMETRY_TIMESTAMP, landscapePosition = OverlayPosition(.5f, .5f)))
        export(project.copy(videoTrimStartSeconds = 3.0, telemetryTrimStartSeconds = 5.0, exportDurationSeconds = 4.0), definition, true, "qa-export-hud.mp4")
    }
    @Test fun rawExportPreservesAudioAndDuration() = runBlocking {
        export(project.copy(videoTrimStartSeconds = 2.0, exportDurationSeconds = 3.0), VideoOverlayTemplateDefinition.tougePro(), false, "qa-export-raw.mp4")
    }
    @Test fun projectRetainsItsOwnLayoutIncludingTheLastRemovedWidget() = runBlocking {
        val empty = VideoOverlayTemplateDefinition.tougePro().copy(elements = emptyList(), allowsEmptyLayout = true)
        container.dao.upsertVideo(project.copy(overlayDefinitionJson = container.json.encodeToString(empty)))
        val restored = container.dao.videosOnce(SESSION).first { it.id == PROJECT }
        assertEquals(empty, container.json.decodeFromString<VideoOverlayTemplateDefinition>(restored.overlayDefinitionJson!!))
    }
    @Test fun timestampAndTelemetryAdvanceAndNoWidgetIsClipped() {
        val element = VideoOverlayElement(metric = TelemetryMetric.SPEED, kind = OverlayElementKind.TELEMETRY_TIMESTAMP, landscapePosition = OverlayPosition(.95f, .95f))
        val overlay = TelemetryBitmapOverlay(samples, 0.0, VideoOverlayTemplateDefinition.tougePro().copy(elements = listOf(element)), 640, 360, telemetryOriginMillis = origin)
        val first = overlay.getBitmap(0).copy(android.graphics.Bitmap.Config.ARGB_8888, false)
        val next = overlay.getBitmap(1_000_000)
        assertFalse(first.sameAs(next))
        val bounds = element.bounds(640, 360)
        assertTrue(bounds.left + bounds.width <= 640)
        File(app.filesDir, "qa-timestamp.png").outputStream().use { next.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    }
    @Test fun importRejectsUnreadableFilesWithoutLeavingWorkingCopies() = runBlocking {
        val bad = File(app.cacheDir, "invalid-video.mp4").apply { writeText("not a movie") }
        val before = File(app.filesDir, "drive-videos").listFiles()?.map { it.name }?.toSet().orEmpty()
        container.videoRepository.clearTask()
        container.videoRepository.importFromGallery(SESSION, 12.0, Uri.fromFile(bad))
        val state = withTimeout(20_000) { container.videoRepository.task.first { it.error != null } }
        assertNotNull(state.error)
        assertEquals(before, File(app.filesDir, "drive-videos").listFiles()?.map { it.name }?.toSet().orEmpty())
    }
    private suspend fun export(value: VideoProjectEntity, definition: VideoOverlayTemplateDefinition, hud: Boolean, outputName: String, expectedWidth: Int = 1280, expectedHeight: Int = 720, background: Boolean = false, quality: DriveVideoExportQuality = DriveVideoExportQuality.FAST_FULL_HD) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            container.videoRepository.export(value, samples, definition, hud, quality, origin)
        }
        if (background) activity.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        val result = withTimeout(120_000) { container.videoRepository.task.first { it.completed || it.error != null } }
        assertNull("Export failed: ${result.error}", result.error)
        assertTrue(result.completed)
        assertTrue(result.outputHasAudio)
        assertEquals(expectedWidth, result.outputWidth)
        assertEquals(expectedHeight, result.outputHeight)
        val uri = Uri.parse(result.outputUri!!)
        val output = File(app.filesDir, outputName)
        app.contentResolver.openInputStream(uri)!!.use { input -> output.outputStream().use { input.copyTo(it) } }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(output.path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong() / 1000.0
            assertEquals(value.exportDurationSeconds, duration, .2)
            assertEquals("yes", retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))
            assertNotNull(retriever.getFrameAtTime(500_000))
        } finally { retriever.release() }
    }
    companion object { const val SESSION = "parity-drive"; const val PROJECT = "parity-video" }
}
