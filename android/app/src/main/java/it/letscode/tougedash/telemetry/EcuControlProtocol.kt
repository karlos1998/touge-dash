package it.letscode.tougedash.telemetry

data class EcuControlSnapshot(
    val switches: List<Boolean> = List(8) { false },
    val rotaryValues: List<Int> = List(8) { 0 }
) {
    init {
        require(switches.size == 8)
        require(rotaryValues.size == 8 && rotaryValues.all { it in ROTARY_RANGE })
    }

    fun switchValue(channel: Int): Boolean? = switches.getOrNull(channel - 1)
    fun rotaryValue(channel: Int): Int? = rotaryValues.getOrNull(channel - 1)

    fun settingSwitch(channel: Int, value: Boolean): EcuControlSnapshot? {
        if (channel !in CHANNEL_RANGE) return null
        return copy(switches = switches.toMutableList().also { it[channel - 1] = value })
    }

    fun settingRotary(channel: Int, value: Int): EcuControlSnapshot? {
        if (channel !in CHANNEL_RANGE || value !in ROTARY_RANGE) return null
        return copy(rotaryValues = rotaryValues.toMutableList().also { it[channel - 1] = value })
    }

    fun encodeStatusFrame(): ByteArray {
        val bytes = mutableListOf(0x08, 0x55, switchBitmap())
        rotaryValues.chunked(2).forEach { pair -> bytes += (pair[0] shl 4) or pair[1] }
        bytes += bytes.sum() and 0xff
        return bytes.map(Int::toByte).toByteArray()
    }

    private fun switchBitmap(): Int = switches.withIndex().fold(0) { result, item ->
        if (item.value) result or (1 shl (7 - item.index)) else result
    }

    companion object {
        val CHANNEL_RANGE = 1..8
        val ROTARY_RANGE = 0..15

        fun isValidStatusFrame(data: ByteArray): Boolean = data.size == 8 &&
            data[0].toUByte().toInt() == 0x08 &&
            data[1].toUByte().toInt() == 0x55 &&
            (data.take(7).sumOf { it.toUByte().toInt() } and 0xff) == data[7].toUByte().toInt()
    }
}

internal class EcuControlLoopbackAccumulator {
    private var switchByte: Int? = null
    private var rotary1234: Int? = null
    private var rotary5678: Int? = null
    private var revision = 0L
    private var switchRevision = 0L
    private var rotary1234Revision = 0L
    private var rotary5678Revision = 0L

    val currentRevision: Long get() = revision
    val missingChannels: List<Int> get() = buildList {
        if (rotary5678 == null) add(252)
        if (rotary1234 == null) add(253)
        if (switchByte == null) add(254)
    }

    fun reset() {
        switchByte = null
        rotary1234 = null
        rotary5678 = null
        revision = 0
        switchRevision = 0
        rotary1234Revision = 0
        rotary5678Revision = 0
    }

    fun apply(frame: EmuFrame, @Suppress("UNUSED_PARAMETER") receivedAt: Long): Boolean {
        if (frame.channel != 254 && frame.channel != 253 && frame.channel != 252) return false
        revision++
        return when (frame.channel) {
            254 -> { switchByte = frame.rawValue and 0xff; switchRevision = revision; true }
            253 -> { rotary1234 = frame.rawValue and 0xffff; rotary1234Revision = revision; true }
            252 -> { rotary5678 = frame.rawValue and 0xffff; rotary5678Revision = revision; true }
            else -> false
        }
    }

    fun synchronizedSnapshot(): EcuControlSnapshot? {
        val switchesRaw = switchByte ?: return null
        val firstRotary = rotary1234 ?: return null
        val secondRotary = rotary5678 ?: return null
        return EcuControlSnapshot(
            switches = List(8) { index -> switchesRaw and (1 shl (7 - index)) != 0 },
            rotaryValues = unpack(firstRotary) + unpack(secondRotary)
        )
    }

    fun snapshotConfirming(kind: EcuControlKind, channel: Int, afterRevision: Long): EcuControlSnapshot? {
        if (channel !in EcuControlSnapshot.CHANNEL_RANGE) return null
        val snapshot = synchronizedSnapshot() ?: return null
        val relevantRevision = when (kind) {
            EcuControlKind.SWITCH -> switchRevision
            EcuControlKind.ROTARY -> if (channel <= 4) rotary1234Revision else rotary5678Revision
        }
        return snapshot.takeIf { relevantRevision > afterRevision }
    }

    private fun unpack(value: Int) = listOf(12, 8, 4, 0).map { shift -> (value shr shift) and 0x0f }
}
