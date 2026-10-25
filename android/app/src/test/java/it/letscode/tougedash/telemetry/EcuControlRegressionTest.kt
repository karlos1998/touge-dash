package it.letscode.tougedash.telemetry

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

@OptIn(ExperimentalCoroutinesApi::class)
class EcuControlRegressionTest {
    private val initial = EcuControlSnapshot(
        switches = listOf(false, true, false, true, false, true, false, true),
        rotaryValues = listOf(1, 2, 3, 4, 10, 11, 12, 13)
    )

    private fun EcuControlCoordinator.connect(writer: (ByteArray) -> Boolean = { true }) {
        connectionChanged(true)
        transportChanged(true, writer)
        ingestStatusFrame(initial.encodeStatusFrame())
    }

    @Test fun everySwitchUsesTheIosBitOrderAndPreservesAllOtherControls() = runTest {
        for (channel in 1..8) {
            val control = EcuControlCoordinator(backgroundScope)
            var sent: ByteArray? = null
            control.connect { sent = it; true }
            assertTrue(control.toggleSwitch(channel))
            val expected = initial.settingSwitch(channel, !initial.switchValue(channel)!!)!!
            assertEquals(expected, EcuControlSnapshot.decodeStatusFrame(sent!!))
            assertEquals(initial, control.state.value.observed)
            assertEquals(expected.switchValue(channel), control.state.value.switchValue(channel))
            assertNotNull(control.state.value.pending)
            // Other loopback groups and the old switch value cannot confirm it.
            control.ingest(EmuFrame(253, 0x1234))
            control.ingest(EmuFrame(254, 0x55))
            assertNotNull(control.state.value.pending)
            control.ingest(EmuFrame(254, (0x55 xor (1 shl (8 - channel)))))
            assertNull(control.state.value.pending)
            assertEquals(expected, control.state.value.observed)
        }
    }

    @Test fun duplicateTapsAndOtherCardsCannotSendWhileAwaitingEmu() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        var writes = 0
        control.connect { writes++; true }
        assertTrue(control.toggleSwitch(1))
        assertFalse(control.toggleSwitch(1))
        assertFalse(control.toggleSwitch(8))
        assertFalse(control.setRotary(4, 15))
        assertEquals(1, writes)
    }

    @Test fun missingConfirmationRollsBackAfterTwoSecondsWithoutRetryingWrite() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        var writes = 0
        control.connect { writes++; true }
        control.toggleSwitch(1)
        runCurrent()
        advanceTimeBy(1_999)
        assertNotNull(control.state.value.pending)
        advanceTimeBy(1)
        runCurrent()
        assertNull(control.state.value.pending)
        assertEquals(EcuControlError.CONFIRMATION_TIMEOUT, control.state.value.error)
        assertEquals(false, control.state.value.switchValue(1))
        advanceTimeBy(10_000)
        assertEquals(1, writes)
    }

    @Test fun rejectedWriteNeverChangesObservedState() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        control.connect { false }
        assertFalse(control.toggleSwitch(1))
        assertNull(control.state.value.pending)
        assertEquals(initial, control.state.value.observed)
        assertEquals(EcuControlError.WRITE_REJECTED, control.state.value.error)
    }

    @Test fun readOnlyTransportAndDisconnectedFeedbackNeverEnableWrites() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        control.ingestStatusFrame(initial.encodeStatusFrame())
        assertNull(control.state.value.observed)
        control.connectionChanged(true)
        control.ingestStatusFrame(initial.encodeStatusFrame())
        assertEquals(initial, control.state.value.observed)
        assertFalse(control.state.value.ready)
        assertFalse(control.toggleSwitch(1))
        control.transportChanged(true) { true }
        assertTrue(control.state.value.ready)
    }

    @Test fun damagedOrWrongStatusCannotConfirmAPendingSwitch() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        control.connect()
        control.toggleSwitch(1)
        val target = control.state.value.pending!!.target.encodeStatusFrame()
        val damaged = target.copyOf().also { it[7]++ }
        control.ingestStatusFrame(damaged)
        assertNotNull(control.state.value.pending)
        control.ingestStatusFrame(initial.encodeStatusFrame())
        assertNotNull(control.state.value.pending)
        control.ingestStatusFrame(target)
        assertNull(control.state.value.pending)
        assertEquals(initial.settingSwitch(1, true), control.state.value.observed)
    }

    @Test fun lateWriteFailureCannotCancelANewerRequest() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        control.connect()
        control.toggleSwitch(1)
        val old = control.state.value.pending!!
        control.ingest(EmuFrame(254, 0xD5))
        assertNull(control.state.value.pending)
        control.toggleSwitch(2)
        val newer = control.state.value.pending!!
        control.transportWriteFailed(old)
        assertSame(newer, control.state.value.pending)
        assertNull(control.state.value.error)
        control.transportWriteFailed(newer)
        assertNull(control.state.value.pending)
        assertEquals(EcuControlError.WRITE_REJECTED, control.state.value.error)
        assertEquals(initial.settingSwitch(1, true), control.state.value.observed)
    }

    @Test fun reconnectDropsCachedStateAndNeverSendsItToTheNewConnection() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        var writes = 0
        control.connect { writes++; true }
        control.toggleSwitch(1)
        val old = control.state.value.pending!!
        control.connectionChanged(false)
        control.connectionChanged(true)
        control.transportChanged(true) { writes++; true }
        assertNull(control.state.value.switchValue(1))
        assertFalse(control.toggleSwitch(1))
        control.ingest(EmuFrame(254, 0x80))
        control.ingest(EmuFrame(253, 0xFEDC))
        assertFalse(control.state.value.ready)
        control.ingest(EmuFrame(252, 0xBA98))
        assertTrue(control.state.value.ready)
        assertEquals(1, writes)
        control.toggleSwitch(1)
        val next = control.state.value.pending!!
        control.transportWriteFailed(old)
        assertSame(next, control.state.value.pending)
        assertEquals(listOf(15, 14, 13, 12, 11, 10, 9, 8), next.target.rotaryValues)
        assertEquals(false, next.target.switchValue(1))
    }

    @Test fun backgroundCancelsPendingAndDoesNotReplayOnResume() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        var writes = 0
        control.connect { writes++; true }
        control.toggleSwitch(1)
        control.applicationActive(false)
        assertNull(control.state.value.pending)
        assertEquals(false, control.state.value.switchValue(1))
        assertEquals(EcuControlError.BACKGROUND, control.state.value.error)
        assertFalse(control.toggleSwitch(1))
        // ECU may have accepted the write before the phone entered background.
        control.ingest(EmuFrame(254, 0xD5))
        control.applicationActive(true)
        assertEquals(true, control.state.value.switchValue(1))
        assertEquals(1, writes)
    }

    @Test fun transportLossCancelsPendingAndOldTimeoutDoesNotCancelRetry() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        control.connect()
        control.toggleSwitch(1)
        runCurrent()
        advanceTimeBy(1_000)
        control.transportChanged(false)
        assertNull(control.state.value.pending)
        assertFalse(control.state.value.ready)
        assertEquals(EcuControlError.TRANSPORT_LOST, control.state.value.error)
        control.transportChanged(true) { true }
        control.toggleSwitch(1)
        val next = control.state.value.pending!!
        runCurrent()
        advanceTimeBy(1_001)
        runCurrent()
        assertSame(next, control.state.value.pending)
    }

    @Test fun invalidControlNumbersAndUnchangedRotaryNeverWrite() = runTest {
        val control = EcuControlCoordinator(backgroundScope)
        var writes = 0
        control.connect { writes++; true }
        listOf(0, 9, -1, Int.MAX_VALUE).forEach { channel ->
            assertFalse(control.toggleSwitch(channel))
            assertFalse(control.setRotary(channel, 1))
        }
        assertFalse(control.setRotary(1, -1))
        assertFalse(control.setRotary(1, 16))
        assertFalse(control.setRotary(1, 1))
        assertEquals(0, writes)
    }

    @Test fun allRotaryChannelsConfirmOnlyFromTheirOwnGroupAndPreserveSwitches() = runTest {
        for (channel in 1..8) {
            val control = EcuControlCoordinator(backgroundScope)
            var sent: ByteArray? = null
            control.connect { sent = it; true }
            assertTrue(control.setRotary(channel, 15))
            val expected = initial.settingRotary(channel, 15)!!
            assertEquals(expected, EcuControlSnapshot.decodeStatusFrame(sent!!))
            control.ingest(EmuFrame(if (channel <= 4) 252 else 253, 0xFFFF))
            assertNotNull(control.state.value.pending)
            val group = if (channel <= 4) expected.rotaryValues.take(4) else expected.rotaryValues.drop(4)
            control.ingest(EmuFrame(if (channel <= 4) 253 else 252, group.fold(0) { value, nibble -> (value shl 4) or nibble }))
            assertNull(control.state.value.pending)
            assertEquals(initial.switches, control.state.value.observed!!.switches)
        }
    }

    @Test fun gattCompletionTracksConnectionAndEndpointAndSerializesWrites() {
        val tracker = EcuControlWriteTracker<Any>()
        val connection = Any()
        val endpoint = EcuControlTransportPolicy.emuControlCharacteristic to 1
        val request = PendingEcuControl(EcuControlKind.SWITCH, 1, initial, 0, 0)
        assertTrue(tracker.begin(connection, endpoint, request))
        assertFalse(tracker.begin(connection, endpoint, request.copy(channel = 2)))
        assertNull(tracker.complete(Any(), endpoint))
        assertNull(tracker.complete(connection, UUID.randomUUID() to 1))
        assertNull(tracker.complete(connection, endpoint.first to 2))
        assertSame(request, tracker.complete(connection, endpoint))
        assertNull(tracker.complete(connection, endpoint))
        assertTrue(tracker.begin(connection, endpoint, request))
        tracker.reset()
        val next = Any()
        assertTrue(tracker.begin(next, endpoint, request))
        assertNull(tracker.complete(connection, endpoint))
        assertSame(request, tracker.complete(next, endpoint))
    }
}
