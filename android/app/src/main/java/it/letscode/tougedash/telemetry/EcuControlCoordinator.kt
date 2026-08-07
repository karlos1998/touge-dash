package it.letscode.tougedash.telemetry

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class EcuControlKind { SWITCH, ROTARY }
enum class EcuControlError { WRITE_REJECTED, CONFIRMATION_TIMEOUT, BACKGROUND, TRANSPORT_LOST }

data class PendingEcuControl(
    val kind: EcuControlKind,
    val channel: Int,
    val target: EcuControlSnapshot,
    val startedAt: Long,
    val loopbackRevisionAtStart: Long
)

data class EcuControlState(
    val observed: EcuControlSnapshot? = null,
    val displayed: EcuControlSnapshot? = null,
    val pending: PendingEcuControl? = null,
    val connected: Boolean = false,
    val transportAvailable: Boolean = false,
    val synchronizedLoopback: Boolean = false,
    val missingLoopbackChannels: List<Int> = listOf(252, 253, 254),
    val applicationActive: Boolean = true,
    val error: EcuControlError? = null
) {
    val ready: Boolean get() = connected && transportAvailable && synchronizedLoopback && applicationActive && pending == null
}

class EcuControlCoordinator(private val scope: CoroutineScope) {
    private val loopback = EcuControlLoopbackAccumulator()
    private val mutableState = MutableStateFlow(EcuControlState())
    val state = mutableState.asStateFlow()
    private var writer: ((ByteArray) -> Boolean)? = null
    private var confirmationJob: Job? = null

    @Synchronized
    fun connectionChanged(connected: Boolean) {
        writer = null
        confirmationJob?.cancel()
        confirmationJob = null
        loopback.reset()
        mutableState.value = EcuControlState(connected = connected, applicationActive = mutableState.value.applicationActive)
    }

    @Synchronized
    fun transportChanged(available: Boolean, writer: ((ByteArray) -> Boolean)? = null) {
        this.writer = writer.takeIf { available }
        val current = mutableState.value
        mutableState.value = current.copy(
            transportAvailable = current.connected && available,
            pending = if (available) current.pending else null,
            displayed = if (available) current.displayed else current.observed,
            error = if (!available && current.pending != null) EcuControlError.TRANSPORT_LOST else current.error
        )
    }

    @Synchronized
    fun applicationActive(active: Boolean) {
        val current = mutableState.value
        if (!active && current.pending != null) confirmationJob?.cancel()
        mutableState.value = current.copy(
            applicationActive = active,
            pending = if (active) current.pending else null,
            displayed = if (active) current.displayed else current.observed,
            error = if (!active && current.pending != null) EcuControlError.BACKGROUND else current.error
        )
        if (active) refresh()
    }

    @Synchronized
    fun ingest(frame: EmuFrame, receivedAt: Long = System.currentTimeMillis()) {
        if (!mutableState.value.connected || !loopback.apply(frame, receivedAt)) return
        refresh()
    }

    @Synchronized
    fun toggleSwitch(channel: Int): Boolean {
        val current = mutableState.value
        val observed = current.observed ?: return false
        if (!current.ready) return false
        val value = observed.switchValue(channel) ?: return false
        val target = observed.settingSwitch(channel, !value) ?: return false
        return send(EcuControlKind.SWITCH, channel, target)
    }

    @Synchronized
    fun setRotary(channel: Int, value: Int): Boolean {
        val current = mutableState.value
        val observed = current.observed ?: return false
        if (!current.ready || observed.rotaryValue(channel) == value) return false
        val target = observed.settingRotary(channel, value) ?: return false
        return send(EcuControlKind.ROTARY, channel, target)
    }

    @Synchronized
    fun transportWriteFailed() {
        val current = mutableState.value
        if (current.pending == null) return
        confirmationJob?.cancel()
        confirmationJob = null
        mutableState.value = current.copy(pending = null, displayed = current.observed, error = EcuControlError.WRITE_REJECTED)
    }

    private fun send(kind: EcuControlKind, channel: Int, target: EcuControlSnapshot): Boolean {
        val currentWriter = writer ?: return false
        val request = PendingEcuControl(kind, channel, target, System.currentTimeMillis(), loopback.currentRevision)
        mutableState.value = mutableState.value.copy(pending = request, displayed = target, error = null)
        if (!currentWriter(target.encodeStatusFrame())) {
            mutableState.value = mutableState.value.copy(pending = null, displayed = mutableState.value.observed, error = EcuControlError.WRITE_REJECTED)
            return false
        }
        confirmationJob?.cancel()
        confirmationJob = scope.launch {
            delay(2_000)
            synchronized(this@EcuControlCoordinator) {
                val current = mutableState.value
                if (current.pending == request) {
                    mutableState.value = current.copy(pending = null, displayed = current.observed, error = EcuControlError.CONFIRMATION_TIMEOUT)
                }
            }
        }
        return true
    }

    private fun refresh() {
        val snapshot = loopback.synchronizedSnapshot()
        val current = mutableState.value
        if (snapshot == null) {
            mutableState.value = current.copy(
                synchronizedLoopback = false,
                missingLoopbackChannels = loopback.missingChannels
            )
            return
        }
        val confirmed = current.pending?.takeIf {
            val confirmation = loopback.snapshotConfirming(it.kind, it.channel, it.loopbackRevisionAtStart)
            when (it.kind) {
                EcuControlKind.SWITCH -> confirmation?.switchValue(it.channel) == it.target.switchValue(it.channel)
                EcuControlKind.ROTARY -> confirmation?.rotaryValue(it.channel) == it.target.rotaryValue(it.channel)
            }
        }
        if (confirmed != null) {
            confirmationJob?.cancel()
            confirmationJob = null
        }
        mutableState.value = current.copy(
            observed = snapshot,
            displayed = if (confirmed != null || current.pending == null) snapshot else current.displayed,
            pending = if (confirmed != null) null else current.pending,
            synchronizedLoopback = true,
            missingLoopbackChannels = emptyList(),
            error = if (confirmed != null) null else current.error
        )
    }
}
