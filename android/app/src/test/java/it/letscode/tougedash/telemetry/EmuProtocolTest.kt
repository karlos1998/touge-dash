package it.letscode.tougedash.telemetry

import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.TelemetryConnection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.coroutines.test.runTest

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
            EmuFrame(3, 200), EmuFrame(8, 914), EmuFrame(9, 887),
            EmuFrame(21, 67), EmuFrame(22, 104), EmuFrame(24, 91), EmuFrame(28, 512)
        ).forEach(accumulator::apply)
        with(accumulator.snapshot) {
            assertEquals(6420.0, rpm, 0.001)
            assertEquals(1.18, boostBar, 0.001)
            assertEquals(12.4, afr, 0.001)
            assertEquals(100.0, throttlePercent, 0.001)
            assertEquals(914.0, egt1Celsius, 0.001)
            assertEquals(887.0, egt2Celsius, 0.001)
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

    @Test fun ecuControlFrameMatchesEDashWholeStateFormat() {
        val state = EcuControlSnapshot()
            .settingSwitch(1, true)!!
            .settingSwitch(3, true)!!
            .settingRotary(1, 2)!!
            .settingRotary(2, 7)!!
        val frame = state.encodeStatusFrame()

        assertEquals(listOf(0x08, 0x55, 0xA0, 0x27, 0, 0, 0, 0x24), frame.map { it.toUByte().toInt() })
        assertTrue(EcuControlSnapshot.isValidStatusFrame(frame))
    }

    @Test fun fullStatusFrameInitializesControlState() {
        val frame = byteArrayOf(0x08, 0x55, 0xA0.toByte(), 0x12, 0x34, 0xAB.toByte(), 0xCD.toByte(), 0xBB.toByte())
        val accumulator = EcuControlLoopbackAccumulator()

        assertTrue(accumulator.applyStatusFrame(frame))
        val state = requireNotNull(accumulator.synchronizedSnapshot())
        assertEquals(listOf(true, false, true, false, false, false, false, false), state.switches)
        assertEquals(listOf(1, 2, 3, 4, 10, 11, 12, 13), state.rotaryValues)
    }

    @Test fun ecuControlLoopbackDecodesAndRetainsSynchronizedState() {
        val accumulator = EcuControlLoopbackAccumulator()
        accumulator.apply(EmuFrame(254, 0xA0), 1_000)
        accumulator.apply(EmuFrame(253, 0x1234), 1_000)
        accumulator.apply(EmuFrame(252, 0xABCD), 1_000)

        val state = accumulator.synchronizedSnapshot()!!
        assertEquals(listOf(true, false, true, false, false, false, false, false), state.switches)
        assertEquals(listOf(1, 2, 3, 4, 10, 11, 12, 13), state.rotaryValues)
        assertEquals(state, accumulator.synchronizedSnapshot())
    }

    @Test fun coordinatorNeverWritesBeforeFreshLoopbackAndConfirmsFromEmu() = runTest {
        val coordinator = EcuControlCoordinator(backgroundScope)
        var sent: ByteArray? = null
        coordinator.connectionChanged(true)
        coordinator.transportChanged(true) { frame -> sent = frame; true }

        assertFalse(coordinator.toggleSwitch(1))
        val now = System.currentTimeMillis()
        coordinator.ingest(EmuFrame(254, 0), now)
        coordinator.ingest(EmuFrame(253, 0), now)
        coordinator.ingest(EmuFrame(252, 0), now)
        assertTrue(coordinator.state.value.ready)

        assertTrue(coordinator.toggleSwitch(1))
        assertTrue(EcuControlSnapshot.isValidStatusFrame(sent!!))
        assertTrue(coordinator.state.value.pending != null)

        val confirmationAt = System.currentTimeMillis() + 1
        coordinator.ingest(EmuFrame(254, 0x80), confirmationAt)
        assertEquals(true, coordinator.state.value.observed?.switchValue(1))
        assertEquals(null, coordinator.state.value.pending)
    }

    @Test fun coordinatorAcceptsLoopbackChannelsArrivingInSlowCycle() = runTest {
        val coordinator = EcuControlCoordinator(backgroundScope)
        coordinator.connectionChanged(true)
        coordinator.transportChanged(true) { true }

        coordinator.ingest(EmuFrame(254, 0), 1_000)
        coordinator.ingest(EmuFrame(253, 0), 4_000)
        assertFalse(coordinator.state.value.ready)
        coordinator.ingest(EmuFrame(252, 0), 7_000)

        assertTrue(coordinator.state.value.ready)
        assertTrue(coordinator.state.value.missingLoopbackChannels.isEmpty())
    }

    @Test fun rotaryConfirmationWaitsOnlyForItsLoopbackGroup() = runTest {
        val coordinator = EcuControlCoordinator(backgroundScope)
        coordinator.connectionChanged(true)
        coordinator.transportChanged(true) { true }
        coordinator.ingest(EmuFrame(254, 0))
        coordinator.ingest(EmuFrame(253, 0))
        coordinator.ingest(EmuFrame(252, 0))

        assertTrue(coordinator.setRotary(6, 7))
        coordinator.ingest(EmuFrame(253, 0))
        assertTrue(coordinator.state.value.pending != null)
        coordinator.ingest(EmuFrame(252, 0x0700))

        assertEquals(7, coordinator.state.value.observed?.rotaryValue(6))
        assertEquals(null, coordinator.state.value.pending)
    }
}
