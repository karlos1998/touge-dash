package it.letscode.tougedash.video

import it.letscode.tougedash.data.local.VideoProjectEntity

/** All positions are seconds from the session/video origin, never sample indices. */
data class VideoTimeline(val videoStart: Double, val telemetryStart: Double, val duration: Double) {
    fun normalized(videoDuration: Double, telemetryDuration: Double): VideoTimeline {
        val video = videoDuration.takeIf { it.isFinite() && it > 0 } ?: 0.0
        val telemetry = telemetryDuration.takeIf { it.isFinite() && it > 0 } ?: 0.0
        val start = videoStart.takeIf(Double::isFinite)?.coerceIn(0.0, video) ?: 0.0
        val dataStart = telemetryStart.takeIf(Double::isFinite)?.coerceIn(0.0, telemetry) ?: 0.0
        val maximum = minOf(video - start, telemetry - dataStart).coerceAtLeast(0.0)
        return VideoTimeline(start, dataStart, duration.takeIf(Double::isFinite)?.coerceIn(0.0, maximum) ?: maximum)
    }

    fun telemetryAt(videoSeconds: Double) = telemetryStart + videoSeconds - videoStart
    fun videoAt(telemetrySeconds: Double) = videoStart + telemetrySeconds - telemetryStart

    fun trimStart(requested: Double): VideoTimeline {
        val end = videoStart + duration
        val minimum = maxOf(0.0, videoStart - telemetryStart)
        val start = requested.coerceIn(minimum, maxOf(minimum, end - minOf(.1, duration)))
        return copy(videoStart = start, telemetryStart = telemetryAt(start), duration = end - start)
    }

    fun trimEnd(requested: Double, videoDuration: Double, telemetryDuration: Double): VideoTimeline {
        val maximum = minOf(videoDuration, videoStart + telemetryDuration - telemetryStart)
        val end = requested.coerceIn(minOf(videoStart + .1, maximum), maximum)
        return copy(duration = (end - videoStart).coerceAtLeast(0.0))
    }

    fun applyTo(project: VideoProjectEntity) = project.copy(
        videoTrimStartSeconds = videoStart,
        telemetryTrimStartSeconds = telemetryStart,
        exportDurationSeconds = duration
    )

    companion object {
        fun from(project: VideoProjectEntity) = VideoTimeline(project.videoTrimStartSeconds, project.telemetryTrimStartSeconds, project.exportDurationSeconds)
    }
}
