package it.letscode.tougedash.telemetry

import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class BleConnectionSlotTest {
    @Test
    fun queuedScanResultsCanStartOnlyOneConnection() {
        val slot = BleConnectionSlot<Any>()

        assertTrue(slot.tryReserve())
        repeat(20) { assertFalse(slot.tryReserve()) }

        val active = Any()
        assertTrue(slot.bind(active))
        assertSame(active, slot.activeValue())
        repeat(20) { assertFalse(slot.tryReserve()) }
    }

    @Test
    fun staleDisconnectCannotReleaseCurrentConnection() {
        val slot = BleConnectionSlot<Any>()
        val current = Any()
        val stale = Any()

        assertTrue(slot.tryReserve())
        assertTrue(slot.bind(current))
        assertFalse(slot.release(stale))
        assertSame(current, slot.activeValue())
        assertTrue(slot.release(current))
        assertTrue(slot.tryReserve())
    }
}
