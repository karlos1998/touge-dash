@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.video

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlaySettings
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import kotlin.math.abs

enum class OverlayStyle { MINIMAL, RACE, UNDERGROUND }

class TelemetryBitmapOverlay(
    private val samples: List<TelemetrySampleEntity>,
    private val telemetryStartSeconds: Double,
    private val style: OverlayStyle,
    private val x: Float,
    private val y: Float
) : BitmapOverlay() {
    private val bitmap = Bitmap.createBitmap(1600, 340, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create("sans-serif-condensed", Typeface.BOLD) }
    private val firstTime = samples.firstOrNull()?.recordedAt ?: 0L

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        bitmap.eraseColor(Color.TRANSPARENT)
        val target = firstTime + ((telemetryStartSeconds + presentationTimeUs / 1_000_000.0) * 1000).toLong()
        val sample = samples.minByOrNull { abs(it.recordedAt - target) } ?: return bitmap
        when (style) {
            OverlayStyle.MINIMAL -> drawMinimal(sample)
            OverlayStyle.RACE -> drawRace(sample)
            OverlayStyle.UNDERGROUND -> drawUnderground(sample)
        }
        return bitmap
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = OverlaySettings.Builder()
        .setBackgroundFrameAnchor(x.coerceIn(-1f, 1f), y.coerceIn(-1f, 1f))
        .setOverlayFrameAnchor(0f, 0f)
        .setScale(.92f, .92f)
        .build()

    private fun drawMinimal(s: TelemetrySampleEntity) {
        pill(30f, 60f, 520f, 250f, 0xbb071014.toInt())
        text("${s.speedKph.toInt()}", 70f, 205f, 138f, Color.WHITE)
        text("KM/H", 335f, 195f, 34f, 0xff27d7e5.toInt())
        text("BOOST  %.2f bar   OIL  %.1f bar / %.0f°C".format(s.boostBar, s.oilPressureBar, s.oilTemperatureCelsius), 590f, 180f, 48f, Color.WHITE)
    }

    private fun drawRace(s: TelemetrySampleEntity) {
        pill(25f, 35f, 1550f, 275f, 0xd6071014.toInt())
        text("${s.speedKph.toInt()}", 65f, 225f, 150f, Color.WHITE)
        text("KM/H", 340f, 215f, 34f, 0xff27d7e5.toInt())
        gauge(500f, 70f, 970f, 60f, (s.rpm / 10_000).toFloat(), 0xff27d7e5.toInt())
        text("RPM ${s.rpm.toInt()}", 500f, 180f, 48f, Color.WHITE)
        text("BOOST", 1035f, 95f, 26f, 0xff8398a4.toInt()); text("%.2f bar".format(s.boostBar), 1035f, 155f, 49f, 0xff43e8a8.toInt())
        text("OIL", 1280f, 95f, 26f, 0xff8398a4.toInt()); text("%.1f / %.0f°".format(s.oilPressureBar, s.oilTemperatureCelsius), 1280f, 155f, 44f, 0xffff9d3d.toInt())
        text("COOLANT %.0f°C   AFR %.1f".format(s.coolantCelsius, s.afr), 1035f, 235f, 31f, Color.WHITE)
    }

    private fun drawUnderground(s: TelemetrySampleEntity) {
        paint.style = Paint.Style.STROKE; paint.strokeWidth = 8f; paint.color = 0xff39ff14.toInt(); canvas.drawRoundRect(20f, 25f, 1570f, 315f, 20f, 20f, paint); paint.style = Paint.Style.FILL
        text("TOUGE // LIVE", 55f, 85f, 35f, 0xff39ff14.toInt())
        text("${s.speedKph.toInt()}", 55f, 270f, 160f, Color.WHITE)
        text("KM/H", 335f, 260f, 34f, 0xff39ff14.toInt())
        text("RPM ${s.rpm.toInt()}  •  BOOST %.2f  •  AFR %.1f".format(s.boostBar, s.afr), 525f, 150f, 53f, Color.WHITE)
        text("OIL %.1f bar / %.0f°C   WATER %.0f°C".format(s.oilPressureBar, s.oilTemperatureCelsius, s.coolantCelsius), 525f, 235f, 44f, 0xffff9d3d.toInt())
    }

    private fun text(value: String, x: Float, y: Float, size: Float, color: Int) { paint.textSize = size; paint.color = color; paint.style = Paint.Style.FILL; canvas.drawText(value, x, y, paint) }
    private fun pill(left: Float, top: Float, right: Float, bottom: Float, color: Int) { paint.color = color; paint.style = Paint.Style.FILL; canvas.drawRoundRect(left, top, right, bottom, 35f, 35f, paint) }
    private fun gauge(x: Float, y: Float, width: Float, height: Float, progress: Float, color: Int) { pill(x, y, x + width, y + height, 0xff1c292f.toInt()); pill(x, y, x + width * progress.coerceIn(0f, 1f), y + height, color) }
}
