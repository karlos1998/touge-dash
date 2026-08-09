package it.letscode.tougedash.telemetry

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BleAdvertisementMatcherTest {
    @Test
    fun acceptsKnownNameOrService() {
        assertTrue(BleAdvertisementMatcher.matches("EMULOGGER", false, emptyList()))
        assertTrue(BleAdvertisementMatcher.matches(null, true, emptyList()))
        assertTrue(BleAdvertisementMatcher.matches("ECUMaster EDL-1", false, emptyList()))
    }

    @Test
    fun acceptsNameHiddenInsideManufacturerPayload() {
        val payload = byteArrayOf(0x02, 0x01, 0x06) + "\u0000EMULOGGER\u0000".toByteArray()

        assertTrue(BleAdvertisementMatcher.matches(null, false, listOf(payload)))
    }

    @Test
    fun rejectsUnrelatedBluetoothDevice() {
        assertFalse(BleAdvertisementMatcher.matches("Pixel Buds", false, listOf(byteArrayOf(1, 2, 3, 4))))
    }
}
