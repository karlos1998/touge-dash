package it.letscode.tougedash.telemetry

import android.content.ContentValues
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.provider.MediaStore
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.TougeDashApplication
import it.letscode.tougedash.model.*
import it.letscode.tougedash.ui.*
import it.letscode.tougedash.ui.theme.*
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.util.Collections

/** The real dashboard/editor, with only the physical ECU replaced by a writer. */
@RunWith(AndroidJUnit4::class)
class EcuSwitchDashboardTest {
    private val app get() = ApplicationProvider.getApplicationContext<TougeDashApplication>()
    private val container get() = app.container
    private val writes = Collections.synchronizedList(mutableListOf<ByteArray>())
    private var previousTemplateId: String? = null

    @get:Rule(order = 0) val environment = object : org.junit.rules.ExternalResource() {
        override fun before() {
            CompatibilityOnboardingPreference.accept(app)
            AppLanguagePreference.write(app, AppLanguage.POLISH)
            AppThemePreference.write(app, AppTheme.DARK)
            val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
            listOf(android.Manifest.permission.BLUETOOTH_SCAN, android.Manifest.permission.BLUETOOTH_CONNECT,
                android.Manifest.permission.POST_NOTIFICATIONS).forEach { automation.grantRuntimePermission(app.packageName, it) }
            runBlocking {
                // Let Application initialize its first factory page before
                // installing this persisted selection on a clean emulator.
                container.dashboardRepository.templates.first { it.isNotEmpty() }
                previousTemplateId = container.dashboardRepository.selected.first().id
                container.dashboardRepository.save(DashboardTemplate(
                    id = TEMPLATE, name = "Switche EMU", definition = DashboardDefinition(listOf(
                        DashboardWidget(id = "ecu-ui-switch-1", kind = DashboardWidgetKind.ECU_SWITCH,
                            metrics = emptyList(), controlChannel = 1, portraitSpan = 6, landscapeSpan = 3, portraitOrder = 0)
                    ), pageOrder = 100)), select = true)
            }
        }
        override fun after() {
            container.ecuControls.connectionChanged(false)
            runBlocking {
                container.dashboardRepository.templates.first().firstOrNull { it.id == TEMPLATE }?.let {
                    container.dashboardRepository.delete(it)
                }
                previousTemplateId?.let { container.dashboardRepository.select(it) }
            }
        }
    }
    @get:Rule(order = 1) val compose = createAndroidComposeRule<MainActivity>()

    @Test fun addSwitchSelectChannelSendConfirmTimeoutAndReconnectOnRealDashboard() {
        try {
            compose.waitUntil(10_000) { compose.onAllNodesWithTag("ecu-switch-1").fetchSemanticsNodes().isNotEmpty() }
        } catch (error: Throwable) {
            screenshot("android-switch-fixture-failure")
            throw AssertionError(runBlocking { container.dao.templatesOnce().map { it.id to it.selected } }.toString() + "\n" +
                compose.onRoot(useUnmergedTree = true).printToString(), error)
        }
        val control = container.ecuControls
        control.connectionChanged(true)
        control.transportChanged(true) { frame -> writes += frame.copyOf(); true }
        control.ingest(EmuFrame(254, 0x01))
        compose.onNodeWithTag("ecu-switch-1").assertIsNotEnabled()
        compose.onNodeWithContentDescription("Edytuj dashboard").performClick()
        compose.onNodeWithText(" Dodaj kartę").performScrollTo().performClick()
        compose.onNodeWithText("przełącznik ECU").performScrollTo().performClick()
        compose.onNodeWithText("SW 8").performScrollTo().performClick()
        screenshot("android-switch-channel-editor")
        compose.onNodeWithText("Zapisz").performClick()
        compose.waitUntil(10_000) {
            runBlocking { container.dashboardRepository.templates.first().first { it.id == TEMPLATE }
                .definition.widgets.any { it.kind == DashboardWidgetKind.ECU_SWITCH && it.controlChannel == 8 } }
        }
        compose.onNodeWithTag("ecu-switch-8").assertIsNotEnabled()
        control.ingest(EmuFrame(253, 0x1234))
        control.ingest(EmuFrame(252, 0xABCD))
        // Editing a dashboard must never operate the ECU, even after sync.
        compose.onNodeWithTag("ecu-switch-8").assertIsNotEnabled().performTouchInput { click() }
        assertTrue(writes.isEmpty())
        compose.onNodeWithContentDescription("Edytuj dashboard").performClick()
        compose.onNodeWithTag("ecu-switch-8").assertIsEnabled().assertIsOn()
        compose.onNodeWithTag("ecu-switch-1").assertIsEnabled().assertIsOff()
        screenshot("android-switches-synchronized")
        compose.onNodeWithTag("ecu-switch-8").performClick()
        compose.onNodeWithTag("ecu-switch-8").assertIsOff().assertIsNotEnabled()
        compose.onNodeWithTag("ecu-switch-1").assertIsNotEnabled()
        assertEquals(1, writes.size)
        val sent = EcuControlSnapshot.decodeStatusFrame(writes.single())!!
        assertEquals(List(8) { false }, sent.switches)
        assertEquals(listOf(1, 2, 3, 4, 10, 11, 12, 13), sent.rotaryValues)
        compose.onNodeWithText("WYSYŁANIE PEŁNEGO STANU").assertExists()
        compose.onNodeWithText("OCZEKIWANIE NA EMU").assertExists()
        screenshot("android-switch-pending")
        // EMU sends only the changed switch group, as on physical EDL-1.
        control.ingest(EmuFrame(254, 0))
        compose.onNodeWithTag("ecu-switch-8").assertIsEnabled().assertIsOff()
        assertNull(control.state.value.pending)

        compose.onNodeWithTag("ecu-switch-1").performClick()
        compose.waitUntil(5_000) { control.state.value.error == EcuControlError.CONFIRMATION_TIMEOUT }
        compose.onNodeWithTag("ecu-switch-1").assertIsOff().assertIsEnabled()
        screenshot("android-switch-no-confirmation")
        control.connectionChanged(false)
        control.connectionChanged(true)
        control.transportChanged(true) { frame -> writes += frame.copyOf(); true }
        compose.onNodeWithTag("ecu-switch-1").assertIsNotEnabled()
        assertNull(control.state.value.switchValue(1))
        assertEquals(2, writes.size)
        control.ingestStatusFrame(EcuControlSnapshot(switches = List(8) { true }).encodeStatusFrame())
        compose.onNodeWithTag("ecu-switch-1").assertIsEnabled().assertIsOn()
        compose.onNodeWithTag("ecu-switch-8").assertIsEnabled().assertIsOn()

        compose.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        compose.waitUntil(10_000) { compose.activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE }
        compose.waitUntil(10_000) {
            compose.onAllNodes(isRoot()).fetchSemanticsNodes().first().boundsInRoot.let { it.width > it.height }
        }
        InstrumentationRegistry.getInstrumentation().uiAutomation.waitForIdle(500, 5_000)
        compose.onNodeWithTag("ecu-switch-1").assertIsDisplayed().assertIsOn()
        compose.onNodeWithTag("ecu-switch-8").assertIsDisplayed().assertIsOn()
        screenshot("android-switches-landscape")
        assertEquals(2, writes.size)
        val saved = runBlocking { container.dashboardRepository.templates.first().first { it.id == TEMPLATE } }
        assertEquals(listOf(1, 8), saved.definition.widgets.map { it.controlChannel })
        compose.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        compose.waitUntil(10_000) { compose.activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_PORTRAIT }
        compose.onNodeWithTag("ecu-switch-1").performClick()
        assertNotNull(control.state.value.pending)
        compose.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        assertNull(control.state.value.pending)
        assertEquals(EcuControlError.BACKGROUND, control.state.value.error)
        compose.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        compose.onNodeWithTag("ecu-switch-1").assertIsOn()
        compose.activityRule.scenario.recreate()
        compose.onNodeWithTag("ecu-switch-8").assertIsOn()
        assertEquals(3, writes.size)
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
        bitmap.recycle()
    }
    companion object { private const val TEMPLATE = "ecu-switch-ui-regression" }
}
