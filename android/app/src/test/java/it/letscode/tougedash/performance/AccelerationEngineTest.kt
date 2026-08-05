package it.letscode.tougedash.performance

import it.letscode.tougedash.model.TelemetrySnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AccelerationEngineTest {
    @Test
    fun `records a fresh zero to one hundred attempt`() {
        val engine = AccelerationEngine()
        var now = 1_000L
        repeat(26) { engine.sample(sample(0.0), now, SESSION); now += 40 }

        var result: it.letscode.tougedash.data.local.AccelerationAttemptEntity? = null
        repeat(151) { index ->
            val speed = index * (110.0 / 150.0)
            result = result ?: engine.sample(sample(speed), now, SESSION)
            now += 40
        }

        requireNotNull(result)
        assertEquals(AccelerationType.ZERO_TO_100.name, result!!.type)
        assertTrue(result!!.durationMillis in 5_300L..5_600L)
        assertTrue(result!!.sampleRateHz >= 20)
    }

    @Test
    fun `does not create an hour long rolling attempt`() {
        val engine = AccelerationEngine()
        var now = 1_000L
        repeat(250) { engine.sample(sample(120.0), now, SESSION); now += 40 }
        var result: it.letscode.tougedash.data.local.AccelerationAttemptEntity? = null
        repeat(120) { index ->
            result = result ?: engine.sample(sample(120 + index.toDouble()), now, SESSION)
            now += 40
        }
        assertNull(result)
    }

    @Test
    fun `manual shift plateau does not abort a rolling attempt`() {
        val engine = AccelerationEngine()
        var now = 1_000L
        var result: it.letscode.tougedash.data.local.AccelerationAttemptEntity? = null
        for (speed in 88..140) {
            result = result ?: engine.sample(sample(speed.toDouble(), rpm = 5_500.0, throttle = 80.0), now, SESSION)
            now += 40
        }
        repeat(35) {
            engine.sample(sample(140.0, rpm = 4_600.0, throttle = 5.0), now, SESSION)
            now += 40
        }
        for (speed in 141..205) {
            result = result ?: engine.sample(sample(speed.toDouble(), rpm = 5_200.0, throttle = 85.0), now, SESSION)
            now += 40
        }
        requireNotNull(result)
        assertEquals(AccelerationType.HUNDRED_TO_200.name, result!!.type)
        assertTrue(result!!.shiftCount >= 1)
    }

    @Test
    fun `input gap cannot create a threshold crossing`() {
        val engine = AccelerationEngine()
        var now = 1_000L
        for (speed in 85..99) {
            engine.sample(sample(speed.toDouble()), now, SESSION)
            now += 40
        }

        now += 2_000
        var result = engine.sample(sample(101.0), now, SESSION)
        repeat(120) { index ->
            now += 40
            result = result ?: engine.sample(sample(101.0 + index), now, SESSION)
        }

        assertNull(result)
    }

    @Test
    fun `one continuous pull records all supported ranges`() {
        val engine = AccelerationEngine()
        var now = 1_000L
        val results = mutableListOf<it.letscode.tougedash.data.local.AccelerationAttemptEntity>()
        repeat(26) { engine.sample(sample(0.0), now, SESSION); now += 40 }

        for (speed in 0..260) {
            engine.sample(sample(speed.toDouble()), now, SESSION)?.let(results::add)
            now += 40
        }

        assertEquals(
            listOf(
                AccelerationType.ZERO_TO_100.name,
                AccelerationType.HUNDRED_TO_200.name,
                AccelerationType.TWO_HUNDRED_TO_250.name
            ),
            results.map { it.type }
        )
    }

    private fun sample(speed: Double, rpm: Double = 4_000.0, throttle: Double = 75.0) =
        TelemetrySnapshot(speedKph = speed, rpm = rpm, throttlePercent = throttle)

    private companion object { const val SESSION = "session" }
}
