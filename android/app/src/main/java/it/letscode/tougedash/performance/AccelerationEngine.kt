package it.letscode.tougedash.performance

import it.letscode.tougedash.data.local.AccelerationAttemptEntity
import it.letscode.tougedash.model.TelemetrySnapshot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.ArrayDeque
import java.util.UUID
import kotlin.math.max

/**
 * Read-only acceleration timer. It only consumes decoded telemetry and never writes
 * anything to EMU/EMULOGGER. A fresh lower-threshold crossing is required for every run,
 * preventing ordinary motorway driving from becoming an hour-long 100–200 measurement.
 */
class AccelerationEngine {
    private data class Point(val at: Long, val speed: Double, val rpm: Double, val throttle: Double)
    private data class Running(
        val type: AccelerationType,
        val startedAt: Double,
        var peakSpeed: Double,
        var lastProgressAt: Long,
        var previousRpm: Double,
        var previousThrottle: Double,
        var shiftDropActive: Boolean = false,
        var shiftCount: Int = 0,
        var samples: Int = 1
    )

    private val history = ArrayDeque<Point>()
    private var previous: Point? = null
    private var running: Running? = null
    private var stationarySince: Long? = null
    private var zeroArmed = false
    private val mutableState = MutableStateFlow(AccelerationRuntimeState())
    val state: StateFlow<AccelerationRuntimeState> = mutableState.asStateFlow()

    fun reset() {
        history.clear()
        previous = null
        running = null
        stationarySince = null
        zeroArmed = false
        mutableState.value = AccelerationRuntimeState()
    }

    fun sample(snapshot: TelemetrySnapshot, at: Long, sessionId: String?): AccelerationAttemptEntity? {
        val point = Point(at, snapshot.speedKph.coerceAtLeast(0.0), snapshot.rpm, snapshot.throttlePercent)
        val candidate = previous
        val prior = candidate?.takeIf { at - it.at <= MAX_INPUT_GAP_MS }
        if (candidate != null && prior == null) {
            abort()
            history.clear()
            stationarySince = null
            zeroArmed = false
        }
        previous = point
        history.addLast(point)
        while (history.isNotEmpty() && at - history.first.at > APPROACH_WINDOW_MS) history.removeFirst()

        updateStationary(point)
        val completed = updateRunning(point, prior, sessionId)
        if (running == null && prior != null) tryStart(point, prior)
        publish(point)
        return completed
    }

    private fun updateStationary(point: Point) {
        if (point.speed <= STATIONARY_KPH) {
            if (stationarySince == null) stationarySince = point.at
            if (point.at - (stationarySince ?: point.at) >= STATIONARY_ARM_MS) zeroArmed = true
        } else if (point.speed > 5.0) {
            stationarySince = null
        }
    }

    private fun tryStart(point: Point, prior: Point) {
        if (zeroArmed && prior.speed <= MOTION_KPH && point.speed > MOTION_KPH) {
            val started = interpolateTime(prior, point, MOTION_KPH)
            running = Running(AccelerationType.ZERO_TO_100, started, point.speed, point.at, point.rpm, point.throttle)
            zeroArmed = false
            stationarySince = null
            return
        }
        listOf(AccelerationType.HUNDRED_TO_200, AccelerationType.TWO_HUNDRED_TO_250).forEach { type ->
            if (prior.speed < type.startKph && point.speed >= type.startKph && hasFreshApproach(type, point)) {
                val started = interpolateTime(prior, point, type.startKph)
                running = Running(type, started, point.speed, point.at, point.rpm, point.throttle)
                return
            }
        }
    }

    private fun hasFreshApproach(type: AccelerationType, point: Point): Boolean {
        val points = history.toList()
        val minimum = points.minOfOrNull(Point::speed) ?: point.speed
        val earliest = points.firstOrNull { it.speed <= type.startKph - REQUIRED_APPROACH_KPH } ?: return false
        val elapsed = (point.at - earliest.at).coerceAtLeast(1)
        val averageGainPerSecond = (point.speed - earliest.speed) * 1_000.0 / elapsed
        return minimum <= type.startKph - REQUIRED_APPROACH_KPH && averageGainPerSecond >= MIN_APPROACH_GAIN_KPH_S
    }

    private fun updateRunning(point: Point, prior: Point?, sessionId: String?): AccelerationAttemptEntity? {
        val current = running ?: return null
        current.samples += 1
        if (point.speed > current.peakSpeed + PROGRESS_STEP_KPH) {
            current.peakSpeed = point.speed
            current.lastProgressAt = point.at
        } else {
            current.peakSpeed = max(current.peakSpeed, point.speed)
        }

        if (!current.shiftDropActive && current.previousThrottle >= 35 && point.throttle <= 15 && current.previousRpm - point.rpm >= 250) {
            current.shiftDropActive = true
            current.shiftCount += 1
        }
        if (point.throttle >= 25) current.shiftDropActive = false
        current.previousRpm = point.rpm
        current.previousThrottle = point.throttle

        if (prior != null && prior.speed < current.type.endKph && point.speed >= current.type.endKph) {
            val endedAt = interpolateTime(prior, point, current.type.endKph)
            val duration = (endedAt - current.startedAt).toLong().coerceAtLeast(1)
            val sampleRate = current.samples * 1_000.0 / duration
            val attempt = sessionId?.let {
                AccelerationAttemptEntity(
                    id = UUID.randomUUID().toString(),
                    sessionId = it,
                    type = current.type.name,
                    startedAt = current.startedAt.toLong(),
                    endedAt = endedAt.toLong(),
                    durationMillis = duration,
                    startSpeedKph = current.type.startKph,
                    endSpeedKph = current.type.endKph,
                    source = "ECU",
                    quality = when {
                        sampleRate >= 20 && duration >= 1_000 -> "HIGH"
                        sampleRate >= 8 -> "MEDIUM"
                        else -> "ESTIMATED"
                    },
                    sampleRateHz = sampleRate,
                    shiftCount = current.shiftCount
                )
            }
            running = null
            if (attempt != null) {
                mutableState.value = mutableState.value.copy(
                    recentResults = (listOf(attempt) + mutableState.value.recentResults)
                        .distinctBy { it.id }
                        .take(12)
                )
            }
            return attempt
        }

        val invalid = point.speed < current.type.startKph - MAX_SPEED_DROP_KPH ||
            current.peakSpeed - point.speed > MAX_SPEED_DROP_KPH ||
            point.at - current.lastProgressAt > MAX_PLATEAU_MS
        if (invalid) abort()
        return null
    }

    private fun abort() {
        running = null
        mutableState.value = mutableState.value.copy(active = null)
    }

    private fun publish(point: Point) {
        val current = running
        mutableState.value = mutableState.value.copy(active = current?.let {
            ActiveAcceleration(
                type = it.type,
                startedAt = it.startedAt.toLong(),
                elapsedMillis = (point.at - it.startedAt).toLong().coerceAtLeast(0),
                currentSpeedKph = point.speed,
                progress = ((point.speed - it.type.startKph) / (it.type.endKph - it.type.startKph)).coerceIn(0.0, 1.0)
            )
        })
    }

    private fun interpolateTime(before: Point, after: Point, threshold: Double): Double {
        val delta = after.speed - before.speed
        if (delta <= 0.0001) return after.at.toDouble()
        val fraction = ((threshold - before.speed) / delta).coerceIn(0.0, 1.0)
        return before.at + (after.at - before.at) * fraction
    }

    private companion object {
        const val STATIONARY_KPH = 2.0
        const val MOTION_KPH = 1.0
        const val STATIONARY_ARM_MS = 800L
        const val APPROACH_WINDOW_MS = 2_500L
        const val REQUIRED_APPROACH_KPH = 6.0
        const val MIN_APPROACH_GAIN_KPH_S = 3.0
        const val MAX_INPUT_GAP_MS = 750L
        const val MAX_PLATEAU_MS = 3_200L
        const val MAX_SPEED_DROP_KPH = 8.0
        const val PROGRESS_STEP_KPH = 0.25
    }
}
