package it.letscode.tougedash.telemetry

import it.letscode.tougedash.model.TelemetrySnapshot

data class EmuFrame(val channel: Int, val rawValue: Int)
data class EmuParserStats(val validFrames: Long = 0, val badChecksums: Long = 0, val droppedBytes: Long = 0)

class EmuFrameParser {
    private val buffer = ArrayDeque<Byte>()
    var stats = EmuParserStats()
        private set

    fun feed(data: ByteArray): List<EmuFrame> {
        data.forEach(buffer::addLast)
        val result = mutableListOf<EmuFrame>()
        while (buffer.size >= FRAME_SIZE) {
            val bytes = buffer.take(FRAME_SIZE).map(Byte::toUByte)
            if (bytes[1].toInt() != MARKER) {
                buffer.removeFirst()
                stats = stats.copy(droppedBytes = stats.droppedBytes + 1)
                continue
            }
            val expected = bytes.take(4).sumOf { it.toInt() } and 0xff
            if (expected != bytes[4].toInt()) {
                buffer.removeFirst()
                stats = stats.copy(badChecksums = stats.badChecksums + 1, droppedBytes = stats.droppedBytes + 1)
                continue
            }
            result += EmuFrame(bytes[0].toInt(), (bytes[2].toInt() shl 8) or bytes[3].toInt())
            repeat(FRAME_SIZE) { buffer.removeFirst() }
            stats = stats.copy(validFrames = stats.validFrames + 1)
        }
        return result
    }

    companion object {
        private const val FRAME_SIZE = 5
        private const val MARKER = 0xA3

        /** Test/simulator helper. Production Bluetooth code never sends this data to an ECU. */
        fun encode(channel: Int, rawValue: Int): ByteArray {
            val payload = byteArrayOf(channel.toByte(), MARKER.toByte(), (rawValue shr 8).toByte(), rawValue.toByte())
            return payload + byteArrayOf((payload.sumOf { it.toUByte().toInt() } and 0xff).toByte())
        }
    }
}

class EmuTelemetryAccumulator {
    var snapshot = TelemetrySnapshot()
        private set
    private var barometricKpa = 101.325

    fun apply(frame: EmuFrame): TelemetrySnapshot {
        val raw = frame.rawValue
        val now = System.currentTimeMillis()
        snapshot = when (frame.channel) {
            1 -> snapshot.copy(rpm = raw.toDouble(), updatedAt = now)
            2 -> snapshot.copy(mapKpa = raw.toDouble(), boostBar = (raw - barometricKpa) / 100.0, updatedAt = now)
            3 -> snapshot.copy(throttlePercent = unsigned8(raw) / 2.0, updatedAt = now)
            4 -> snapshot.copy(intakeCelsius = signed8(raw), updatedAt = now)
            5 -> snapshot.copy(batteryVoltage = raw / 37.0, updatedAt = now)
            6 -> snapshot.copy(ignitionDegrees = signed8(raw) / 2.0, updatedAt = now)
            8 -> snapshot.copy(egt1Celsius = raw.toDouble(), updatedAt = now)
            9 -> snapshot.copy(egt2Celsius = raw.toDouble(), updatedAt = now)
            12 -> snapshot.copy(afr = unsigned8(raw) / 10.0, updatedAt = now)
            14 -> {
                barometricKpa = unsigned8(raw)
                snapshot.copy(boostBar = if (snapshot.mapKpa > 0) (snapshot.mapKpa - barometricKpa) / 100.0 else snapshot.boostBar, updatedAt = now)
            }
            19 -> snapshot.copy(injectorDutyPercent = unsigned8(raw) / 2.0, updatedAt = now)
            21 -> snapshot.copy(oilPressureBar = unsigned8(raw) / 16.0, updatedAt = now)
            22 -> snapshot.copy(oilTemperatureCelsius = unsigned8(raw), updatedAt = now)
            23 -> snapshot.copy(fuelPressureBar = unsigned8(raw) / 16.0, updatedAt = now)
            24 -> snapshot.copy(coolantCelsius = signed16(raw), updatedAt = now)
            27 -> snapshot.copy(lambda = unsigned8(raw) / 128.0, updatedAt = now)
            28 -> snapshot.copy(speedKph = raw / 4.0, updatedAt = now)
            255 -> snapshot.copy(checkEngineMask = raw, updatedAt = now)
            else -> snapshot
        }
        return snapshot
    }

    private fun unsigned8(raw: Int) = (raw and 0xff).toDouble()
    private fun signed8(raw: Int) = (raw and 0xff).toByte().toDouble()
    private fun signed16(raw: Int) = raw.toShort().toDouble()
}
