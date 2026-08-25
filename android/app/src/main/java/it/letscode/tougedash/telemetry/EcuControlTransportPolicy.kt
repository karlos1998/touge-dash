package it.letscode.tougedash.telemetry

import java.util.UUID

/** Restricts ECU writes to the exact transport profiles used by eDash. */
internal object EcuControlTransportPolicy {
    val nordicUartService: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    val nordicUartRx: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    val emuService: UUID = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb")
    val emuTelemetryCharacteristic: UUID = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb")
    val emuControlCharacteristic: UUID = UUID.fromString("0000ffe2-0000-1000-8000-00805f9b34fb")

    fun priority(service: UUID, characteristic: UUID): Int? = when {
        service == nordicUartService && characteristic == nordicUartRx -> 3
        service == emuService && characteristic == emuControlCharacteristic -> 2
        // Older adapters and the desktop simulator can combine notify and write
        // on FFE1. Physical BT 4.0 EMULOGGER hardware exposes FFE2 separately.
        service == emuService && characteristic == emuTelemetryCharacteristic -> 1
        else -> null
    }
}
