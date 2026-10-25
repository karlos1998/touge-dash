package it.letscode.tougedash.telemetry

import java.util.UUID

/** GATT completion and ECU loopback are independent acknowledgements. */
internal class EcuControlWriteTracker<Connection : Any> {
    private data class Write<Connection>(
        val connection: Connection,
        val endpoint: Pair<UUID, Int>,
        val request: PendingEcuControl
    )

    private var pending: Write<Connection>? = null

    @Synchronized
    fun begin(connection: Connection, endpoint: Pair<UUID, Int>, request: PendingEcuControl): Boolean {
        // Android permits only one outstanding characteristic write. In
        // particular, early ECU feedback does not finish the GATT operation.
        if (pending != null) return false
        pending = Write(connection, endpoint, request)
        return true
    }

    @Synchronized
    fun complete(connection: Connection, endpoint: Pair<UUID, Int>): PendingEcuControl? {
        val write = pending ?: return null
        if (write.connection !== connection || write.endpoint != endpoint) return null
        pending = null
        return write.request
    }

    @Synchronized
    fun reset() { pending = null }
}
