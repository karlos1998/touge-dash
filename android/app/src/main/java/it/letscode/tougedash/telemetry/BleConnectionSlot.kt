package it.letscode.tougedash.telemetry

/**
 * Serializes BLE connection attempts. Android can deliver several already queued
 * scan results after stopScan(), so stopping the scanner alone is not a lock.
 */
internal class BleConnectionSlot<T : Any> {
    private var reserved = false
    private var active: T? = null

    @Synchronized
    fun tryReserve(): Boolean {
        if (reserved || active != null) return false
        reserved = true
        return true
    }

    @Synchronized
    fun bind(value: T): Boolean {
        if (!reserved || active != null) return false
        reserved = false
        active = value
        return true
    }

    @Synchronized
    fun cancelReservation() {
        reserved = false
    }

    @Synchronized
    fun isActive(value: T): Boolean = active === value

    @Synchronized
    fun activeValue(): T? = active

    @Synchronized
    fun release(value: T): Boolean {
        if (active !== value) return false
        active = null
        reserved = false
        return true
    }

    @Synchronized
    fun clear(): T? {
        val previous = active
        active = null
        reserved = false
        return previous
    }
}
