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
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
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
    private val bluetoothManager by lazy { getSystemService(BluetoothManager::class.java) }
    private val adapter: BluetoothAdapter? get() = bluetoothManager?.adapter
    private val container get() = (application as TougeDashApplication).container
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var samplingJob: Job? = null
    private var bluetoothGatt: BluetoothGatt? = null
    private var scanning = false
    private var manuallyStopped = false
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
        stopSampling()
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
        if (!force && bluetoothGatt != null) return
        stopScan()
        lastAddress?.let { address ->
            runCatching { currentAdapter.getRemoteDevice(address) }.getOrNull()?.let {
                updateConnection(ConnectionState.Connecting, it.name, address)
                bluetoothGatt = it.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
                return
            }
        }
        scanning = true
        updateConnection(ConnectionState.Scanning, message = local("Looking only for ECUMaster interfaces", "Szukanie wyłącznie interfejsów ECUMaster"))
        currentAdapter.bluetoothLeScanner?.startScan(scanCallback)
    }

    fun stopTelemetry() {
        manuallyStopped = true
        stopScan()
        bluetoothGatt?.disconnect()
        bluetoothGatt?.close()
        bluetoothGatt = null
        stopSampling()
        updateConnection(ConnectionState.Idle, message = local("Stopped", "Zatrzymano"))
        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
    }

    private fun stopScan() {
        if (scanning && hasBluetoothPermission()) adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        scanning = false
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (!hasBluetoothPermission()) return
            val advertised = result.scanRecord?.deviceName
            val name = advertised ?: result.device.name ?: "BLE device"
            val serviceMatch = result.scanRecord?.serviceUuids?.any { it.uuid == EMU_SERVICE_UUID } == true
            if (!serviceMatch && !likelyEmuName(name)) return
            TelemetryRuntime.diagnostic("Accepted $name, RSSI ${result.rssi}")
            stopScan()
            updateConnection(ConnectionState.Connecting, name, result.device.address)
            bluetoothGatt = result.device.connectGatt(this@TelemetryService, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            updateConnection(ConnectionState.Failed, message = local("Bluetooth scan failed", "Skanowanie Bluetooth nie powiodło się") + " ($errorCode)")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                if (!hasBluetoothPermission()) return
                lastAddress = gatt.device.address
                updateConnection(ConnectionState.Connected, gatt.device.name ?: "EMULOGGER", gatt.device.address)
                TelemetryRuntime.diagnostic("Connected; discovering FFE0")
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                gatt.close()
                if (bluetoothGatt === gatt) bluetoothGatt = null
                stopSampling()
                updateConnection(ConnectionState.Reconnecting, message = local("Connection lost", "Utracono połączenie"))
                if (!manuallyStopped) Handler(Looper.getMainLooper()).post { startScanning(force = true) }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (!hasBluetoothPermission()) return
            val service: BluetoothGattService? = gatt.getService(EMU_SERVICE_UUID)
            val characteristic = service?.getCharacteristic(EMU_CHARACTERISTIC_UUID)
            if (characteristic == null) {
                TelemetryRuntime.diagnostic("FFE1 not found")
                gatt.disconnect()
                return
            }
            gatt.setCharacteristicNotification(characteristic, true)
            characteristic.getDescriptor(CCCD_UUID)?.let { descriptor ->
                // CCCD is Bluetooth subscription metadata; no value is ever written to EMU data characteristic FFE1.
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                gatt.writeDescriptor(descriptor)
            }
            TelemetryRuntime.diagnostic("Subscribed read-only to FFE1 notifications")
            startSampling(gatt.device.address, gatt.device.name ?: "EMULOGGER")
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (characteristic.uuid != EMU_CHARACTERISTIC_UUID) return
            parser.feed(characteristic.value ?: return).forEach { TelemetryRuntime.updateSnapshot(accumulator.apply(it)) }
            updateConnection(
                ConnectionState.Connected,
                gatt.device.name ?: "EMULOGGER",
                gatt.device.address,
                valid = parser.stats.validFrames,
                bad = parser.stats.badChecksums,
                dropped = parser.stats.droppedBytes
            )
        }
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
            TelemetryRuntime.updateConnection(TelemetryConnection(state, name, hardwareId, message, valid, bad, dropped))
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

    private fun likelyEmuName(name: String): Boolean {
        val normalized = name.lowercase()
        return listOf("emu", "ecumaster", "canbt", "btcan", "edl", "logger").any(normalized::contains)
    }

    private fun local(english: String, polish: String): String =
        if (resources.configuration.locales[0].language == "pl") polish else english

    companion object {
        const val ACTION_RESCAN = "it.letscode.tougedash.RESCAN"
        const val ACTION_STOP = "it.letscode.tougedash.STOP"
        private const val PREFS = "telemetry"
        private const val LAST_DEVICE = "last_device"
        private const val CHANNEL_ID = "live_telemetry"
        private const val NOTIFICATION_ID = 42
        val EMU_SERVICE_UUID: UUID = UUID.fromString("0000ffe0-0000-1000-8000-00805f9b34fb")
        val EMU_CHARACTERISTIC_UUID: UUID = UUID.fromString("0000ffe1-0000-1000-8000-00805f9b34fb")
        val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
