package it.letscode.tougedash.video

import android.graphics.Bitmap
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TelemetryBitmapOverlayTest {
    @Test
    fun factoryHudRendersAtTheRequestedAspectRatio() {
        val overlay = TelemetryBitmapOverlay(
            samples = listOf(sample()),
            telemetryStartSeconds = 0.0,
            definition = VideoOverlayTemplateDefinition.tougePro(),
            width = 640,
            height = 360
        )

        val bitmap = overlay.getBitmap(0)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)

        assertEquals(640, bitmap.width)
        assertEquals(360, bitmap.height)
        assertTrue(pixels.count { it ushr 24 != 0 } > 8_000)

        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.cacheDir.resolve("overlay-proof.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }

    private fun sample() = TelemetrySampleEntity(
        id = "sample-1",
        sessionId = "session-1",
        recordedAt = 1_000,
        rpm = 6_250.0,
        boostBar = 1.35,
        mapKpa = 235.0,
        throttlePercent = 82.0,
        coolantCelsius = 91.0,
        intakeCelsius = 36.0,
        oilTemperatureCelsius = 104.0,
        oilPressureBar = 4.7,
        fuelPressureBar = 3.8,
        afr = 12.4,
        lambda = .84,
        batteryVoltage = 13.9,
        ignitionDegrees = 17.0,
        injectorDutyPercent = 64.0,
        speedKph = 128.0,
        checkEngineMask = 0
    )
}
