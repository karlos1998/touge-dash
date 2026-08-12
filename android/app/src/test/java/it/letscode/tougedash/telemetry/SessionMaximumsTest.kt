package it.letscode.tougedash.telemetry

import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.model.TelemetrySnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class SessionMaximumsTest {
    @Test
    fun `maximums only move upward and support negative readings`() {
        val first = accumulateSessionMaximums(
            emptyMap(),
            TelemetrySnapshot(boostBar = -0.4, rpm = 3_200.0)
        )
        val lower = accumulateSessionMaximums(
            first,
            TelemetrySnapshot(boostBar = -0.7, rpm = 2_800.0)
        )
        val higher = accumulateSessionMaximums(
            lower,
            TelemetrySnapshot(boostBar = 1.2, rpm = 6_400.0)
        )

        assertEquals(-0.4, lower[TelemetryMetric.BOOST]!!, 0.001)
        assertEquals(3_200.0, lower[TelemetryMetric.RPM]!!, 0.001)
        assertEquals(1.2, higher[TelemetryMetric.BOOST]!!, 0.001)
        assertEquals(6_400.0, higher[TelemetryMetric.RPM]!!, 0.001)
    }
}
