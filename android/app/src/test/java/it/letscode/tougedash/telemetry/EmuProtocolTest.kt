package it.letscode.tougedash.telemetry

import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.TelemetryConnection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EmuProtocolTest {
    @Test fun fragmentedAndConcatenatedFramesAreDecoded() {
        val rpm = EmuFrameParser.encode(1, 6420)
        val map = EmuFrameParser.encode(2, 219)
        val parser = EmuFrameParser()
        assertTrue(parser.feed(rpm.copyOfRange(0, 2)).isEmpty())
        val decoded = parser.feed(rpm.copyOfRange(2, rpm.size) + map)
        assertEquals(listOf(EmuFrame(1, 6420), EmuFrame(2, 219)), decoded)
        assertEquals(2, parser.stats.validFrames)
    }

    @Test fun checksumDamageDoesNotPoisonFollowingFrame() {
        val damaged = EmuFrameParser.encode(1, 5000).also { it[4]++ }
        val valid = EmuFrameParser.encode(12, 124)
        val parser = EmuFrameParser()
        assertEquals(listOf(EmuFrame(12, 124)), parser.feed(damaged + valid))
        assertEquals(1, parser.stats.badChecksums)
    }

    @Test fun channelsMatchIosProtocol() {
        val accumulator = EmuTelemetryAccumulator()
        listOf(
            EmuFrame(1, 6420), EmuFrame(14, 101), EmuFrame(2, 219), EmuFrame(12, 124),
            EmuFrame(21, 67), EmuFrame(22, 104), EmuFrame(24, 91), EmuFrame(28, 512)
        ).forEach(accumulator::apply)
        with(accumulator.snapshot) {
            assertEquals(6420.0, rpm, 0.001)
            assertEquals(1.18, boostBar, 0.001)
            assertEquals(12.4, afr, 0.001)
            assertEquals(4.1875, oilPressureBar, 0.001)
            assertEquals(104.0, oilTemperatureCelsius, 0.001)
            assertEquals(91.0, coolantCelsius, 0.001)
            assertEquals(128.0, speedKph, 0.001)
        }
    }

    @Test fun manualDriveSplitCanOnlyBeRequestedWhileConnectedAndIsConsumedOnce() {
        TelemetryRuntime.updateConnection(TelemetryConnection(state = ConnectionState.Connected))

        assertTrue(TelemetryRuntime.requestDriveSplit())
        assertTrue(TelemetryRuntime.consumeDriveSplitRequest())
        assertFalse(TelemetryRuntime.consumeDriveSplitRequest())

        TelemetryRuntime.updateConnection(TelemetryConnection(state = ConnectionState.Idle))
        assertFalse(TelemetryRuntime.requestDriveSplit())
    }
}
