package it.letscode.tougedash.video

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import androidx.media3.common.MimeTypes
import kotlin.math.min
import kotlin.math.roundToInt

internal data class VideoEncodingPlan(
    val mimeType: String,
    val bitrate: Int
)

internal object VideoExportQuality {
    fun plan(width: Int, height: Int, framesPerSecond: Double): VideoEncodingPlan {
        val hevc = supportsHardwareEncoding(MimeTypes.VIDEO_H265, width, height, framesPerSecond)
        val mimeType = if (hevc) MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264
        return VideoEncodingPlan(
            mimeType = mimeType,
            bitrate = targetBitrate(width, height, framesPerSecond, hevc)
        )
    }

    internal fun targetBitrate(width: Int, height: Int, framesPerSecond: Double, hevc: Boolean): Int {
        val safeWidth = width.coerceAtLeast(640)
        val safeHeight = height.coerceAtLeast(360)
        val safeFps = framesPerSecond.takeIf { it.isFinite() && it > 0 }?.coerceIn(24.0, 60.0) ?: 30.0
        val bitsPerPixel = if (hevc) .16 else .25
        val calculated = (safeWidth.toDouble() * safeHeight * safeFps * bitsPerPixel).roundToInt()
        return calculated.coerceIn(
            if (hevc) 6_000_000 else 8_000_000,
            if (hevc) 45_000_000 else 60_000_000
        )
    }

    private fun supportsHardwareEncoding(mimeType: String, width: Int, height: Int, fps: Double): Boolean =
        runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
                codec.isEncoder && codec.supportedTypes.any { it.equals(mimeType, ignoreCase = true) } &&
                    isHardware(codec) && supportsFormat(codec, mimeType, width, height, fps)
            }
        }.getOrDefault(false)

    private fun isHardware(codec: MediaCodecInfo): Boolean = if (Build.VERSION.SDK_INT >= 29) {
        codec.isHardwareAccelerated
    } else {
        val name = codec.name.lowercase()
        !name.startsWith("omx.google.") && !name.startsWith("c2.android.")
    }

    private fun supportsFormat(codec: MediaCodecInfo, mimeType: String, width: Int, height: Int, fps: Double): Boolean {
        if (width <= 0 || height <= 0) return true
        val capabilities = codec.getCapabilitiesForType(mimeType).videoCapabilities ?: return true
        val safeFps = fps.takeIf { it.isFinite() && it > 0 } ?: 30.0
        return runCatching {
            capabilities.areSizeAndRateSupported(width, height, safeFps) ||
                capabilities.areSizeAndRateSupported(height, width, safeFps)
        }.getOrDefault(false)
    }
}

internal fun overlayBitmapSize(width: Int, height: Int): Pair<Int, Int> {
    val sourceWidth = width.takeIf { it > 0 } ?: 1920
    val sourceHeight = height.takeIf { it > 0 } ?: 1080
    val scale = min(1.0, 3840.0 / maxOf(sourceWidth, sourceHeight))
    return maxOf(2, (sourceWidth * scale).roundToInt()) to
        maxOf(2, (sourceHeight * scale).roundToInt())
}
