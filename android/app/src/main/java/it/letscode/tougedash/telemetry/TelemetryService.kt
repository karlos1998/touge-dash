@file:Suppress("DEPRECATION")

package it.letscode.tougedash.telemetry

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.R
import it.letscode.tougedash.TougeDashApplication
import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.data.local.TelemetrySampleEntity
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

// Every Bluetooth entry point is guarded by hasBluetoothPermission(). Android lint
// cannot carry that fact through asynchronous GATT callbacks, hence the scoped suppression.
// ForegroundServiceType is declared on TelemetryService in the merged manifest.
// Car App Library 1.7's lint model cannot associate the source-set manifest
// declaration with this ServiceCompat call, so suppress that false positive.
@SuppressLint("MissingPermission", "ForegroundServiceType")
class TelemetryService : Service() {
    inner class LocalBinder : Binder() { val service get() = this@TelemetryService }
    private val binder = LocalBinder()
    private val parser = EmuFrameParser()
    private val accumulator = EmuTelemetryAccumulator()
    private val connectionSlot = BleConnectionSlot<BluetoothGatt>()
    private val bluetoothManager by lazy { getSystemService(BluetoothManager::class.java) }
    private val adapter: BluetoothAdapter? get() = bluetoothManager?.adapter
    private val container get() = (application as TougeDashApplication).container
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var samplingJob: Job? = null
    private var controlCharacteristic: BluetoothGattCharacteristic? = null
    private var sppSocket: BluetoothSocket? = null
    private var sppConnectionJob: Job? = null
    private var scanning = false
    private var manuallyStopped = false
    private var reconnectJob: Job? = null
    private var connectionTimeoutJob: Job? = null
    @Volatile private var connectionReady = false
    private var reconnectAttempt = 0
    private var receivedPacketCount = 0L
    private var receivedByteCount = 0L
    private var lastPacketHex: String? = null
    private var lastConnectionPublishAt = 0L
    private var lastForegroundNotificationAt = 0L
    private var lastAddress: String?
        get() = getSharedPreferences(PREFS, MODE_PRIVATE).getString(LAST_DEVICE, null)
        set(value) { getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(LAST_DEVICE, value).apply() }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        container.locationTracker.start()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification(local("Searching for EMULOGGER", "Szukanie EMULOGGERA")),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        )
    }

    override fun onBind(intent: Intent?): IBinder = binder
    override fun onDestroy() {
        manuallyStopped = true
        reconnectJob?.cancel()
        reconnectJob = null
        connectionTimeoutJob?.cancel()
        connectionTimeoutJob = null
        sppConnectionJob?.cancel()
        sppConnectionJob = null
        runCatching { sppSocket?.close() }
        sppSocket = null
        stopScan()
        connectionSlot.clear()?.let {
            it.disconnect()
            it.close()
        }
        stopSampling()
        container.ecuControls.connectionChanged(false)
        container.locationTracker.stop()
        serviceScope.cancel()
        super.onDestroy()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopTelemetry()
            ACTION_RESCAN -> startScanning(force = true)
            else -> startScanning()
        }
        return START_STICKY
    }

    fun startScanning(force: Boolean = false) {
        manuallyStopped = false
        if (!hasBluetoothPermission()) {
            updateConnection(ConnectionState.PermissionRequired, message = local("Bluetooth permission required", "Wymagane uprawnienie Bluetooth"))
            return
        }
        val currentAdapter = adapter
        if (currentAdapter == null || !currentAdapter.isEnabled) {
            updateConnection(ConnectionState.BluetoothOff, message = local("Bluetooth is disabled", "Bluetooth jest wyłączony"))
            return
        }
        if (!force && (connectionSlot.activeValue() != null || sppSocket != null || sppConnectionJob?.isActive == true || scanning)) return
        reconnectJob?.cancel()
        reconnectJob = null
        stopScan()
        if (force) {
            reconnectAttempt = 0
            connectionTimeoutJob?.cancel()
            connectionTimeoutJob = null
            connectionReady = false
            sppConnectionJob?.cancel()
            sppConnectionJob = null
            runCatching { sppSocket?.close() }
            sppSocket = null
            connectionSlot.clear()?.let {
                it.disconnect()
                it.close()
            }
            controlCharacteristic = null
            container.ecuControls.transportChanged(false)
        }
        if (reconnectAttempt >= 2 && reconnectAttempt % 2 == 0 && beginSppConnection(currentAdapter)) return
        if (reconnectAttempt < 2) lastAddress?.let { address ->
            runCatching { currentAdapter.getRemoteDevice(address) }.getOrNull()?.let {
                if (beginConnection(it, it.name ?: "EMULOGGER")) return
            }
        }
        val scanner = currentAdapter.bluetoothLeScanner
        if (scanner == null) {
            updateConnection(ConnectionState.Failed, message = local("Bluetooth scanner is unavailable", "Skaner Bluetooth jest niedostępny"))
            scheduleReconnect("BluetoothLeScanner unavailable")
            return
        }
        scanning = true
        updateConnection(ConnectionState.Scanning, message = local("Looking only for ECUMaster interfaces", "Szukanie wyłącznie interfejsów ECUMaster"))
        runCatching { scanner.startScan(scanCallback) }
            .onSuccess { TelemetryRuntime.diagnostic("BLE scan started") }
            .onFailure {
                scanning = false
                updateConnection(ConnectionState.Failed, message = local("Bluetooth scan could not start", "Nie udało się uruchomić skanowania Bluetooth"))
                scheduleReconnect("startScan failed: ${it.message ?: it.javaClass.simpleName}")
            }
    }

    fun stopTelemetry() {
        manuallyStopped = true
        reconnectJob?.cancel()
        reconnectJob = null
        connectionTimeoutJob?.cancel()
        connectionTimeoutJob = null
        connectionReady = false
        sppConnectionJob?.cancel()
        sppConnectionJob = null
        runCatching { sppSocket?.close() }
        sppSocket = null
        stopScan()
        connectionSlot.clear()?.let {
            it.disconnect()
            it.close()
        }
        controlCharacteristic = null
        container.ecuControls.connectionChanged(false)
        stopSampling()
        updateConnection(ConnectionState.Idle, message = local("Stopped", "Zatrzymano"))
        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    private fun stopScan() {
        if (scanning && hasBluetoothPermission()) runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        scanning = false
    }

    private fun beginConnection(device: BluetoothDevice, name: String): Boolean {
        if (manuallyStopped || !connectionSlot.tryReserve()) return false
        connectionReady = false
        stopScan()
        updateConnection(ConnectionState.Connecting, name, device.address)
        TelemetryRuntime.diagnostic("Connecting once to $name [${device.address}]")
        val gatt = runCatching {
            device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        }.getOrNull()
        if (gatt == null || !connectionSlot.bind(gatt)) {
            connectionSlot.cancelReservation()
            gatt?.close()
            scheduleReconnect("connectGatt rejected")
            return false
        }
        scheduleConnectionTimeout(gatt)
        return true
    }

    private fun scheduleConnectionTimeout(gatt: BluetoothGatt) {
        connectionTimeoutJob?.cancel()
        connectionTimeoutJob = serviceScope.launch {
            delay(CONNECTION_TIMEOUT_MILLIS)
            withContext(Dispatchers.Main) {
                if (connectionSlot.isActive(gatt) && !connectionReady) {
                    failActiveConnection(gatt, "Connection setup timed out")
                }
            }
        }
    }

    private fun beginSppConnection(currentAdapter: BluetoothAdapter): Boolean {
        val device = currentAdapter.bondedDevices
            .filter { likelyEmuName(it.name ?: "") }
            .sortedByDescending { bonded -> bonded.uuids?.any { it.uuid == SPP_UUID } == true }
            .firstOrNull() ?: return false
        if (sppConnectionJob?.isActive == true || sppSocket != null || connectionSlot.activeValue() != null) return false
        stopScan()
        updateConnection(ConnectionState.Connecting, device.name ?: "EMULOGGER", device.address,
            message = local("Connecting through paired serial Bluetooth", "Łączenie przez sparowany port szeregowy Bluetooth"))
        TelemetryRuntime.diagnostic("Trying paired SPP ${device.name} [${device.address}]")
        sppConnectionJob = serviceScope.launch(Dispatchers.IO) {
            try {
                val socket = connectPairedSerial(device)
                reconnectAttempt = 0
                withContext(Dispatchers.Main) {
                    if (sppSocket !== socket || manuallyStopped) return@withContext
                    lastAddress = null
                    updateConnection(ConnectionState.Connected, device.name ?: "EMULOGGER", device.address,
                        message = local("Serial Bluetooth", "Bluetooth szeregowy"))
                    container.ecuControls.connectionChanged(true)
                    container.ecuControls.transportChanged(true) { data -> writeSppControl(socket, data) }
                    startSampling(device.address, device.name ?: "EMULOGGER")
                    TelemetryRuntime.diagnostic("Connected through paired SPP")
                }
                val buffer = ByteArray(1_024)
                while (isActive && sppSocket === socket) {
                    val count = socket.inputStream.read(buffer)
                    if (count < 0) break
                    if (count > 0) processEmuBytes(buffer.copyOf(count), device.name ?: "EMULOGGER", device.address)
                }
                throw IllegalStateException("SPP stream closed")
            } catch (error: Exception) {
                val failedSocket = sppSocket
                runCatching { failedSocket?.close() }
                withContext(Dispatchers.Main) {
                    if (sppSocket === failedSocket) {
                        sppSocket = null
                        finishSppConnection(device, "SPP ${error.message ?: "connection failed"}")
                    }
                }
            }
        }
        return true
    }

    private fun connectPairedSerial(device: BluetoothDevice): BluetoothSocket {
        if (hasBluetoothPermission()) runCatching { adapter?.cancelDiscovery() }
        val factories = listOf<Pair<String, () -> BluetoothSocket>>(
            "secure RFCOMM" to { device.createRfcommSocketToServiceRecord(SPP_UUID) },
            "insecure RFCOMM" to { device.createInsecureRfcommSocketToServiceRecord(SPP_UUID) }
        )
        var lastFailure: Throwable? = null
        for ((label, factory) in factories) {
            if (manuallyStopped) throw IllegalStateException("Telemetry stopped")
            val socket = try {
                factory()
            } catch (error: Throwable) {
                lastFailure = error
                TelemetryRuntime.diagnostic("$label socket creation failed: ${error.message}")
                continue
            }
            sppSocket = socket
            try {
                socket.connect()
                TelemetryRuntime.diagnostic("Connected through $label")
                return socket
            } catch (error: Throwable) {
                lastFailure = error
                TelemetryRuntime.diagnostic("$label connect failed: ${error.message}")
                runCatching { socket.close() }
                if (sppSocket === socket) sppSocket = null
            }
        }
        throw IllegalStateException(lastFailure?.message ?: "RFCOMM connection failed", lastFailure)
    }

    private fun finishSppConnection(device: BluetoothDevice, reason: String) {
        sppConnectionJob = null
        container.ecuControls.connectionChanged(false)
        stopSampling()
        updateConnection(ConnectionState.Reconnecting, device.name, device.address,
            message = local("Serial Bluetooth connection lost", "Utracono szeregowe połączenie Bluetooth") + " ($reason)")
        TelemetryRuntime.diagnostic(reason)
        scheduleReconnect(reason)
    }

    private fun writeSppControl(socket: BluetoothSocket, data: ByteArray): Boolean {
        if (sppSocket !== socket || !socket.isConnected || !EcuControlSnapshot.isValidStatusFrame(data)) return false
        return runCatching {
            socket.outputStream.write(data)
            socket.outputStream.flush()
            TelemetryRuntime.diagnostic("ECU TX [SPP] ${data.joinToString(" ") { "%02X".format(it.toUByte().toInt()) }}")
        }.isSuccess
    }

    private fun scheduleReconnect(reason: String) {
        if (manuallyStopped || reconnectJob?.isActive == true) return
        reconnectAttempt++
        val delayMillis = (1_500L shl minOf(reconnectAttempt - 1, 3)).coerceAtMost(10_000L)
        TelemetryRuntime.diagnostic("Bluetooth reconnect in ${delayMillis}ms: $reason")
        reconnectJob = serviceScope.launch {
            delay(delayMillis)
            withContext(Dispatchers.Main) {
                reconnectJob = null
                if (!manuallyStopped && connectionSlot.activeValue() == null) startScanning()
            }
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (!hasBluetoothPermission()) return
            val advertised = result.scanRecord?.deviceName
            val name = advertised ?: result.device.name ?: "BLE device"
            val scanRecord = result.scanRecord
            val serviceMatch = scanRecord?.serviceUuids?.any { it.uuid == EMU_SERVICE_UUID } == true
            val payloads = buildList {
                scanRecord?.bytes?.let(::add)
                scanRecord?.serviceData?.values?.let(::addAll)
                scanRecord?.manufacturerSpecificData?.let { values ->
                    repeat(values.size()) { index -> add(values.valueAt(index)) }
                }
            }
            if (!BleAdvertisementMatcher.matches(name, serviceMatch, payloads)) return
            TelemetryRuntime.diagnostic("Accepted $name, RSSI ${result.rssi}")
            beginConnection(result.device, name)
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            updateConnection(ConnectionState.Failed, message = local("Bluetooth scan failed", "Skanowanie Bluetooth nie powiodło się") + " ($errorCode)")
            scheduleReconnect("Scan failed ($errorCode)")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (!connectionSlot.isActive(gatt)) {
                TelemetryRuntime.diagnostic("Ignoring stale GATT callback status=$status state=$newState")
                gatt.close()
                return
            }
            if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                if (!hasBluetoothPermission()) {
                    abandonForMissingPermission(gatt)
                    return
                }
                lastAddress = gatt.device.address
                updateConnection(ConnectionState.Connected, gatt.device.name ?: "EMULOGGER", gatt.device.address)
                container.ecuControls.connectionChanged(true)
                TelemetryRuntime.diagnostic("Connected; discovering FFE0")
                if (!gatt.discoverServices()) failActiveConnection(gatt, "Service discovery was rejected")
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                failActiveConnection(gatt, "Disconnected, GATT status $status")
            } else if (status != BluetoothGatt.GATT_SUCCESS) {
                failActiveConnection(gatt, "GATT error $status, state $newState")
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (!connectionSlot.isActive(gatt)) return
            if (!hasBluetoothPermission()) {
                abandonForMissingPermission(gatt)
                return
            }
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failActiveConnection(gatt, "Service discovery failed ($status)")
                return
            }
            val service: BluetoothGattService? = gatt.getService(EMU_SERVICE_UUID)
            val characteristic = service?.getCharacteristic(EMU_CHARACTERISTIC_UUID)
            if (characteristic == null) {
                TelemetryRuntime.diagnostic("FFE1 not found")
                failActiveConnection(gatt, "FFE1 not found")
                return
            }
            val supportsNotify = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0
            val supportsIndicate = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
            if (!supportsNotify && !supportsIndicate) {
                failActiveConnection(gatt, "FFE1 does not support notifications")
                return
            }
            if (!gatt.setCharacteristicNotification(characteristic, true)) {
                failActiveConnection(gatt, "FFE1 notification setup rejected")
                return
            }
            val descriptor = characteristic.getDescriptor(CCCD_UUID)
            if (descriptor == null || !writeNotificationDescriptor(gatt, descriptor)) {
                failActiveConnection(gatt, "FFE1 notification descriptor rejected")
                return
            }
            val nusControl = gatt.getService(NUS_SERVICE_UUID)?.getCharacteristic(NUS_RX_UUID)
                ?.takeIf(::supportsWrite)
            val emuControl = characteristic.takeIf(::supportsWrite)
            controlCharacteristic = nusControl ?: emuControl
            val approvedControl = controlCharacteristic
            container.ecuControls.transportChanged(approvedControl != null) { data ->
                approvedControl != null && writeControlFrame(gatt, approvedControl, data)
            }
            TelemetryRuntime.diagnostic(
                if (approvedControl == null) "Discovered FFE1; ECU control is read-only"
                else "Discovered FFE1; approved ECU control ${approvedControl.uuid}"
            )
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (!connectionSlot.isActive(gatt) || descriptor.uuid != CCCD_UUID) return
            if (!hasBluetoothPermission()) {
                abandonForMissingPermission(gatt)
                return
            }
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failActiveConnection(gatt, "FFE1 subscription failed ($status)")
                return
            }
            reconnectAttempt = 0
            connectionReady = true
            connectionTimeoutJob?.cancel()
            connectionTimeoutJob = null
            TelemetryRuntime.diagnostic("Subscribed to FFE1")
            val characteristic = descriptor.characteristic
            if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0) {
                runCatching { gatt.readCharacteristic(characteristic) }.onFailure {
                    TelemetryRuntime.diagnostic("Initial FFE1 read rejected: ${it.message ?: it.javaClass.simpleName}")
                }
            }
            startSampling(gatt.device.address, gatt.device.name ?: "EMULOGGER")
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            processIncomingValue(gatt, characteristic, characteristic.value ?: return)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            processIncomingValue(gatt, characteristic, value)
        }

        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                processIncomingValue(gatt, characteristic, characteristic.value ?: return)
            }
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS) processIncomingValue(gatt, characteristic, value)
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (characteristic.uuid != controlCharacteristic?.uuid) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                TelemetryRuntime.diagnostic("ECU control write failed ($status)")
                container.ecuControls.transportWriteFailed()
            }
        }
    }

    private fun writeNotificationDescriptor(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor): Boolean {
        // CCCD is Bluetooth subscription metadata, not an ECU control value.
        val characteristic = descriptor.characteristic
        val subscriptionValue = if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
            BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        } else {
            BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
        }
        return if (Build.VERSION.SDK_INT >= 33) {
            gatt.writeDescriptor(descriptor, subscriptionValue) == BluetoothStatusCodes.SUCCESS
        } else {
            descriptor.value = subscriptionValue
            gatt.writeDescriptor(descriptor)
        }
    }

    private fun processIncomingValue(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray
    ) {
        if (!connectionSlot.isActive(gatt) || characteristic.uuid != EMU_CHARACTERISTIC_UUID || value.isEmpty()) return
        if (!hasBluetoothPermission()) {
            abandonForMissingPermission(gatt)
            return
        }
        processEmuBytes(value, gatt.device.name ?: "EMULOGGER", gatt.device.address)
    }

    private fun abandonForMissingPermission(gatt: BluetoothGatt) {
        if (!connectionSlot.release(gatt)) return
        connectionTimeoutJob?.cancel()
        connectionTimeoutJob = null
        connectionReady = false
        controlCharacteristic = null
        container.ecuControls.connectionChanged(false)
        stopSampling()
        runCatching { gatt.close() }
        updateConnection(
            ConnectionState.PermissionRequired,
            message = local("Bluetooth permission required", "Wymagane uprawnienie Bluetooth")
        )
    }

    private fun processEmuBytes(value: ByteArray, deviceName: String, hardwareId: String) {
        receivedPacketCount++
        receivedByteCount += value.size
        lastPacketHex = value.take(40).joinToString(" ") { "%02X".format(it.toUByte().toInt()) }
        if (receivedPacketCount <= 10 || receivedPacketCount % 100L == 0L) {
            TelemetryRuntime.diagnostic("RX #$receivedPacketCount [$deviceName] $lastPacketHex")
        }
        if (EcuControlSnapshot.isValidStatusFrame(value)) {
            container.ecuControls.ingestStatusFrame(value)
        } else {
            parser.feed(value).forEach {
                container.ecuControls.ingest(it)
                TelemetryRuntime.updateSnapshot(accumulator.apply(it))
            }
        }
        updateConnection(
            ConnectionState.Connected,
            deviceName,
            hardwareId,
            valid = parser.stats.validFrames,
            bad = parser.stats.badChecksums,
            dropped = parser.stats.droppedBytes
        )
    }

    private fun failActiveConnection(gatt: BluetoothGatt, reason: String) {
        if (!connectionSlot.release(gatt)) {
            gatt.close()
            return
        }
        connectionTimeoutJob?.cancel()
        connectionTimeoutJob = null
        connectionReady = false
        TelemetryRuntime.diagnostic(reason)
        controlCharacteristic = null
        container.ecuControls.connectionChanged(false)
        stopSampling()
        runCatching { gatt.disconnect() }
        runCatching { gatt.close() }
        updateConnection(
            ConnectionState.Reconnecting,
            message = local("Connection lost", "Utracono połączenie") + " ($reason)"
        )
        scheduleReconnect(reason)
    }

    private fun supportsWrite(characteristic: BluetoothGattCharacteristic): Boolean {
        val properties = characteristic.properties
        return properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0 ||
            properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
    }

    private fun writeControlFrame(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        data: ByteArray
    ): Boolean {
        if (!connectionSlot.isActive(gatt) || !EcuControlSnapshot.isValidStatusFrame(data) || !supportsWrite(characteristic)) return false
        val writeType = if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        val accepted = if (Build.VERSION.SDK_INT >= 33) {
            gatt.writeCharacteristic(characteristic, data, writeType) == BluetoothStatusCodes.SUCCESS
        } else {
            characteristic.writeType = writeType
            characteristic.value = data
            gatt.writeCharacteristic(characteristic)
        }
        if (accepted) {
            TelemetryRuntime.diagnostic("ECU TX [${characteristic.uuid}] ${data.joinToString(" ") { "%02X".format(it.toUByte().toInt()) }}")
        }
        return accepted
    }

    private fun startSampling(hardwareId: String, deviceName: String) {
        val previous = samplingJob
        previous?.cancel()
        samplingJob = serviceScope.launch {
            previous?.join()
            container.incidentEngine.rules = container.alertRepository.rules(hardwareId).first()
            var lastHistoryAt = 0L
            var lastLiveAt = 0L
            var lastPerformanceSourceAt = 0L
            try {
                while (isActive) {
                    val now = System.currentTimeMillis()
                    val snapshot = TelemetryRuntime.snapshot.value
                    val location = container.locationTracker.location.value
                    if (TelemetryRuntime.consumeDriveSplitRequest()) {
                        val closingSessionId = container.historyRepository.activeSessionId()
                        if (closingSessionId != null) {
                            container.incidentEngine.finish(hardwareId, closingSessionId)
                            container.historyRepository.finish()
                            container.accelerationEngine.reset()
                            container.cameraRecordingController.stopWhenSessionEnds(null)
                            container.cloudSyncRepository.schedule()
                            lastHistoryAt = 0L
                            lastPerformanceSourceAt = snapshot.updatedAt
                        }
                    }
                    if (now - lastHistoryAt >= 100) {
                        container.historyRepository.record(hardwareId, deviceName, snapshot, location)
                        lastHistoryAt = now
                    }
                    val sessionId = container.historyRepository.activeSessionId()
                    if (snapshot.updatedAt > lastPerformanceSourceAt) {
                        container.accelerationEngine.sample(snapshot, snapshot.updatedAt, sessionId)?.let {
                            container.historyRepository.recordAcceleration(it)
                        }
                        lastPerformanceSourceAt = snapshot.updatedAt
                    }
                    container.incidentEngine.record(hardwareId, sessionId, snapshot, location, now)
                    if (sessionId != null && now - lastLiveAt >= 1_000) {
                        container.cloudSyncRepository.publishLive(
                            hardwareId,
                            snapshot.asUploadSample(sessionId, location, now),
                            container.accelerationEngine.state.value
                        )
                        lastLiveAt = now
                    }
                    if (now - lastForegroundNotificationAt >= 1_000) {
                        updateForegroundNotification(snapshot)
                        lastForegroundNotificationAt = now
                    }
                    delay(40)
                }
            } finally {
                withContext(NonCancellable) {
                    val sessionId = container.historyRepository.activeSessionId()
                    container.incidentEngine.finish(hardwareId, sessionId)
                    container.historyRepository.finish()
                    container.accelerationEngine.reset()
                    container.cloudSyncRepository.schedule()
                }
            }
        }
    }

    private fun stopSampling() {
        samplingJob?.cancel()
    }

    private fun it.letscode.tougedash.model.TelemetrySnapshot.asUploadSample(sessionId: String, location: it.letscode.tougedash.model.RecordedLocation?, now: Long) =
        TelemetrySampleEntity(
            id = UUID.randomUUID().toString(), sessionId = sessionId, recordedAt = now,
            rpm = rpm, boostBar = boostBar, mapKpa = mapKpa, throttlePercent = throttlePercent,
            coolantCelsius = coolantCelsius, intakeCelsius = intakeCelsius,
            oilTemperatureCelsius = oilTemperatureCelsius, oilPressureBar = oilPressureBar,
            fuelPressureBar = fuelPressureBar, afr = afr, lambda = lambda, batteryVoltage = batteryVoltage,
            ignitionDegrees = ignitionDegrees, injectorDutyPercent = injectorDutyPercent, speedKph = speedKph,
            checkEngineMask = checkEngineMask, latitude = location?.latitude, longitude = location?.longitude,
            horizontalAccuracy = location?.horizontalAccuracy, altitude = location?.altitude
        )

    private fun updateConnection(
        state: ConnectionState,
        name: String? = null,
        hardwareId: String? = null,
        message: String? = null,
        valid: Long = parser.stats.validFrames,
        bad: Long = parser.stats.badChecksums,
        dropped: Long = parser.stats.droppedBytes
    ) {
        val now = System.currentTimeMillis()
        val previous = TelemetryRuntime.connection.value
        val statusChanged = previous.state != state || previous.deviceName != name ||
            previous.hardwareId != hardwareId || previous.message != message
        // EMULOGGER can emit hundreds of frames per second. Parser counters are useful in
        // diagnostics, but publishing them for every frame would constantly recompose UI.
        if (statusChanged || now - lastConnectionPublishAt >= 250) {
            TelemetryRuntime.updateConnection(
                TelemetryConnection(
                    state = state,
                    deviceName = name,
                    hardwareId = hardwareId,
                    message = message,
                    validFrames = valid,
                    badChecksums = bad,
                    droppedBytes = dropped,
                    receivedPackets = receivedPacketCount,
                    receivedBytes = receivedByteCount,
                    lastPacketHex = lastPacketHex
                )
            )
            lastConnectionPublishAt = now
        }
        if (statusChanged) {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification(name ?: message ?: state.name))
        }
    }

    private fun updateForegroundNotification(snapshot: it.letscode.tougedash.model.TelemetrySnapshot) {
        val text = "OIL %.1f bar / %.0f°C  •  WATER %.0f°C  •  BOOST %.2f bar".format(
            snapshot.oilPressureBar,
            snapshot.oilTemperatureCelsius,
            snapshot.coolantCelsius,
            snapshot.boostBar
        )
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(text))
    }

    private fun notification(text: String) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_notification)
        .setContentTitle("Touge Dash")
        .setContentText(text)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        .addAction(0, getString(R.string.stop), PendingIntent.getService(this, 1, Intent(this, TelemetryService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        .build()

    private fun createChannel() {
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, getString(R.string.telemetry_channel_name), NotificationManager.IMPORTANCE_LOW)
        )
    }

    private fun hasBluetoothPermission(): Boolean = Build.VERSION.SDK_INT < 31 ||
        ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
        ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun likelyEmuName(name: String): Boolean = BleAdvertisementMatcher.containsMarker(name)

    private fun local(english: String, polish: String): String =
        if (resources.configuration.locales[0].language == "pl") polish else english

    companion object {
        const val ACTION_RESCAN = "it.letscode.tougedash.RESCAN"
        const val ACTION_STOP = "it.letscode.tougedash.STOP"
        private const val PREFS = "telemetry"
        private const val LAST_DEVICE = "last_device"
        private const val CHANNEL_ID = "live_telemetry"
        private const val NOTIFICATION_ID = 42
        private const val CONNECTION_TIMEOUT_MILLIS = 45_000L
        val EMU_SERVICE_UUID: UUID = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb")
        val EMU_CHARACTERISTIC_UUID: UUID = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb")
        val NUS_SERVICE_UUID: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        val NUS_RX_UUID: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805f9b34fb")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
