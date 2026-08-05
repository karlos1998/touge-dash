package it.letscode.tougedash

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import it.letscode.tougedash.telemetry.TelemetryService
import it.letscode.tougedash.ui.TougeDashApp
import it.letscode.tougedash.ui.theme.TougeDashTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as TougeDashApplication).container
        container.authRepository.handleUri(intent?.data)
        setContent {
            TougeDashTheme {
                val snapshot by container.runtime.snapshot.collectAsStateWithLifecycle()
                val connection by container.runtime.connection.collectAsStateWithLifecycle()
                val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
                    startTelemetry()
                }
                LaunchedEffect(Unit) {
                    if (hasBluetoothPermissions()) startTelemetry()
                    else permissionLauncher.launch(requestedPermissions())
                }
                TougeDashApp(
                    container = container,
                    snapshot = snapshot,
                    connection = connection,
                    requestPermissions = { permissionLauncher.launch(requestedPermissions()) },
                    rescan = { startTelemetry(TelemetryService.ACTION_RESCAN) }
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        (application as TougeDashApplication).container.authRepository.handleUri(intent.data)
    }

    private fun startTelemetry(action: String? = null) {
        if (!hasBluetoothPermissions()) return
        ContextCompat.startForegroundService(this, Intent(this, TelemetryService::class.java).apply { this.action = action })
    }

    private fun hasBluetoothPermissions() = requiredPermissions().all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requiredPermissions(): Array<String> = buildList {
        if (Build.VERSION.SDK_INT >= 31) {
            add(Manifest.permission.BLUETOOTH_SCAN)
            add(Manifest.permission.BLUETOOTH_CONNECT)
        } else add(Manifest.permission.ACCESS_FINE_LOCATION)
    }.toTypedArray()

    private fun requestedPermissions(): Array<String> = buildList {
        addAll(requiredPermissions())
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }.distinct().toTypedArray()
}
