package it.letscode.tougedash.video

import android.content.ContentValues
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.TougeDashApplication
import it.letscode.tougedash.data.local.*
import it.letscode.tougedash.ui.*
import it.letscode.tougedash.ui.theme.*
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class AndroidParityUiTest {
    @get:Rule(order = 0) val environment = object : org.junit.rules.ExternalResource() {
        override fun before() {
            val app = ApplicationProvider.getApplicationContext<TougeDashApplication>()
            CompatibilityOnboardingPreference.accept(app)
            AppLanguagePreference.write(app, AppLanguage.POLISH)
            AppThemePreference.write(app, AppTheme.DARK)
            val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
            listOf(android.Manifest.permission.BLUETOOTH_SCAN, android.Manifest.permission.BLUETOOTH_CONNECT, android.Manifest.permission.POST_NOTIFICATIONS).forEach { automation.grantRuntimePermission(app.packageName, it) }
        }
    }
    @get:Rule(order = 1) val compose = createAndroidComposeRule<MainActivity>()
    private val app = ApplicationProvider.getApplicationContext<TougeDashApplication>()
    private val container get() = app.container

    @Before fun fixture() = runBlocking {
        CompatibilityOnboardingPreference.accept(app)
        AppLanguagePreference.write(app, AppLanguage.POLISH)
        AppThemePreference.write(app, AppTheme.DARK)
        container.videoRecordingSettings.update(DriveVideoSettings())
        val origin = 1_800_000_000_000L
        val file = File(File(app.filesDir, "drive-videos").apply { mkdirs() }, "ui-parity-drive.mp4")
        InstrumentationRegistry.getInstrumentation().context.assets.open("parity-drive.mp4").use { input -> file.outputStream().use { input.copyTo(it) } }
        container.dao.upsertSession(DriveSessionEntity(SESSION, "ui-parity", startedAt = origin, endedAt = origin + 12000, modifiedAt = origin,
            sampleCount = 121, customName = "Porównanie iOS / Android", maxRpm = 7000.0, maxSpeedKph = 92.0, maxBoostBar = 1.2, maxCoolantCelsius = 82.0, maxOilTemperatureCelsius = 76.0))
        container.dao.insertSamples((0..120).map { index -> TelemetrySampleEntity(id = "ui-$index", sessionId = SESSION, recordedAt = origin + index * 100L,
            rpm = 2200.0 + index * 40, boostBar = -.05 + index / 100.0, mapKpa = 95.0 + index, throttlePercent = 42.0,
            coolantCelsius = 82.0, intakeCelsius = 34.0, egt1Celsius = 914.0, egt2Celsius = 887.0, oilTemperatureCelsius = 76.0,
            oilPressureBar = 2.4, fuelPressureBar = 3.4, afr = 14.5, lambda = .84, batteryVoltage = 13.8, ignitionDegrees = 15.0,
            injectorDutyPercent = 48.0, speedKph = 62.0 + index / 4.0, checkEngineMask = 0) })
        container.dao.upsertVideo(VideoProjectEntity(PROJECT, SESSION, "GALLERY", Uri.fromFile(file).toString(), "ui-parity-drive.mp4", 12.0, file.length(), 1280, 720, 30.0, true, exportDurationSeconds = 12.0, overlayTemplateId = "RACE"))
        container.videoRepository.ensureOverlayTemplates()
        compose.waitForIdle()
    }

    @Test fun primaryScreensAndVideoEditorWorkInPolishPortraitAndLandscape() {
        screenshot("android-dashboard")
        compose.onNodeWithText("Ustawienia").performClick()
        compose.onNodeWithText("Automatyczne dzielenie przejazdu").performScrollTo().assertIsDisplayed()
        screenshot("android-settings")
        compose.onNodeWithText("Historia").performClick()
        compose.onNodeWithText("Incydenty (0)").assertExists()
        screenshot("android-history")
        compose.onNodeWithText("Porównanie iOS / Android").performClick()
        compose.onNodeWithText("NAGRANIA Z APLIKACJI").assertExists()
        compose.waitUntil(10_000) { compose.onAllNodesWithText("ui-parity-drive.mp4").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("ui-parity-drive.mp4").performScrollTo().performClick()
        compose.onNodeWithTag("hud-preview").assertIsDisplayed()
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("video-ready").fetchSemanticsNodes().isNotEmpty() }
        screenshot("android-editor-portrait")
        compose.onNodeWithContentDescription("Dodaj widget").performClick()
        compose.onNodeWithText("Data i czas telemetrii").performClick()
        compose.onNodeWithText("JAKOŚĆ EKSPORTU").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Szybki · 1080p").assertExists()
        compose.onNodeWithText("Oryginalna rozdzielczość").assertExists()
        compose.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        compose.waitUntil(10_000) { compose.activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE }
        compose.waitUntil(15_000) { compose.onAllNodes(isRoot()).fetchSemanticsNodes().last().boundsInRoot.width > compose.onAllNodes(isRoot()).fetchSemanticsNodes().last().boundsInRoot.height }
        // Compose has the new bounds before Android's window rotation
        // animation finishes. Touch injection must wait for that window too.
        InstrumentationRegistry.getInstrumentation().uiAutomation.waitForIdle(500, 5_000)
        compose.waitForIdle()
        screenshot("android-editor-landscape")
        compose.onNodeWithText("Zapisz projekt").performClick()
        compose.waitUntil(10_000) {
            runBlocking { container.dao.videosOnce(SESSION).first { it.id == PROJECT }.overlayDefinitionJson?.contains("TELEMETRY_TIMESTAMP") == true }
        }
        compose.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        compose.waitUntil(10_000) { compose.activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT }
        InstrumentationRegistry.getInstrumentation().uiAutomation.waitForIdle(500, 5_000)
        compose.waitUntil(10_000) { compose.onAllNodesWithText("ui-parity-drive.mp4").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("ui-parity-drive.mp4").performScrollTo().performClick()
        compose.onNodeWithTag("hud-preview").assertIsDisplayed()
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("video-ready").fetchSemanticsNodes().isNotEmpty() }
        screenshot("android-editor-reopened")
    }

    @Test fun draggingAndPinchingAWidgetPersistItsPositionAndSize() {
        // Isolate the widget under test; the factory's overlapping gauges are
        // intentionally above the RPM bar in z-order and receive touches there.
        val originalDefinition = runBlocking {
            val project = container.dao.videosOnce(SESSION).first { it.id == PROJECT }
            val factory = VideoOverlayTemplateDefinition.tougePro()
            val isolated = factory.copy(elements = factory.elements.filter { it.kind == OverlayElementKind.BAR }.map { it.copy(landscapePosition = OverlayPosition(.5f, .25f)) })
            container.json.encodeToString(isolated).also { container.dao.upsertVideo(project.copy(overlayDefinitionJson = it)) }
        }
        compose.onNodeWithText("Historia").performClick()
        compose.onNodeWithText("Porównanie iOS / Android").performClick()
        compose.waitUntil(10_000) { compose.onAllNodesWithText("ui-parity-drive.mp4").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("ui-parity-drive.mp4").performScrollTo().performClick()
        compose.onNodeWithTag("hud-preview").assertIsDisplayed()
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("video-ready").fetchSemanticsNodes().isNotEmpty() }
        compose.waitUntil(10_000) { compose.onNodeWithTag("hud-widget-BAR-RPM").isDisplayed() }
        // Start on the exposed left side, away from the digital widgets above the bar.
        compose.onNodeWithTag("hud-widget-BAR-RPM").performTouchInput {
            down(Offset(width * .2f, height * .25f))
            advanceEventTime(16)
            moveBy(Offset(0f, height * .75f))
            advanceEventTime(16)
            up()
        }
        compose.onNodeWithTag("hud-widget-BAR-RPM").performTouchInput {
            pinch(Offset(width * .2f, height * .5f), Offset(width * .8f, height * .5f), Offset(width * .1f, height * .5f), Offset(width * .9f, height * .5f))
        }
        compose.onNodeWithText("Zapisz projekt").performClick()
        compose.waitUntil(10_000) { runBlocking {
            container.dao.videosOnce(SESSION).first { it.id == PROJECT }.overlayDefinitionJson.let { it != null && it != originalDefinition }
        } }
        val definition = runBlocking { container.dao.videosOnce(SESSION).first { it.id == PROJECT }.overlayDefinitionJson!! }
        val restored = container.json.decodeFromString<VideoOverlayTemplateDefinition>(definition)
        val rpm = restored.elements.first { it.kind == OverlayElementKind.BAR }
        assertTrue("Widget movement was not saved: ${rpm.landscapePosition}", rpm.landscapePosition.y > .3f)
        assertTrue("Pinch resizing was not saved: ${rpm.sizeMultiplier}", rpm.sizeMultiplier > 1.1f)
    }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        val uri = app.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/TougeDashQA")
        })!!
        app.contentResolver.openOutputStream(uri)!!.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    companion object { const val SESSION = "ui-parity-drive"; const val PROJECT = "ui-parity-video" }
}
