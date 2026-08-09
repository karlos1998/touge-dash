package it.letscode.tougedash.history

import org.junit.Assert.assertEquals
import org.junit.Test

class DriveShareRangeTest {
    @Test fun clampsReversedAndOutsideOffsetsToANonEmptyDriveRange() {
        assertEquals(DriveShareRange(9_999, 10_000), DriveShareRange.normalize(10_000, 20_000, -5))
    }

    @Test fun preservesAValidSelection() {
        val range = DriveShareRange.normalize(60_000, 12_000, 44_000)
        assertEquals(12_000, range.startOffsetMillis)
        assertEquals(44_000, range.endOffsetMillis)
        assertEquals(32_000, range.durationMillis)
    }
}
