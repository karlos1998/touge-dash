package it.letscode.tougedash.ui

import android.Manifest
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.LocalLifecycleOwner
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeRed
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun DriveCameraScreen(container: AppContainer, close: () -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val recording by container.cameraRecordingController.isRecording.collectAsState()
    val error by container.cameraRecordingController.error.collectAsState()
    var accepted by remember { mutableStateOf(context.getSharedPreferences("camera", 0).getBoolean("accepted", false)) }
    var countdown by remember { mutableIntStateOf(5) }
    var front by remember { mutableStateOf(false) }
    var permissionGranted by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<PreviewView?>(null) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result -> permissionGranted = result[Manifest.permission.CAMERA] == true }
    BackHandler { if (!recording) close() }
    LaunchedEffect(Unit) { permission.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)) }
    LaunchedEffect(accepted) { if (!accepted) { countdown = 5; while (countdown > 0) { delay(1000); countdown-- } } }
    LaunchedEffect(preview, front, permissionGranted) { if (permissionGranted) preview?.let { container.cameraRecordingController.bind(owner, it, front) } }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(factory = { PreviewView(it).also { view -> preview = view } }, modifier = Modifier.fillMaxSize())
        Row(Modifier.fillMaxWidth().padding(16.dp).align(Alignment.TopCenter), horizontalArrangement = Arrangement.SpaceBetween) {
            IconButton(onClick = { if (!recording) close() }, modifier = Modifier.background(Color.Black.copy(alpha = .5f), CircleShape)) { Icon(Icons.Default.Close, null, tint = Color.White) }
            Column(horizontalAlignment = Alignment.CenterHorizontally) { Text(appText("DRIVE CAMERA", "KAMERA PRZEJAZDU"), color = Color.White, fontWeight = FontWeight.Black); Text(if (recording) appText("RECORDING WITH TELEMETRY", "NAGRYWANIE Z TELEMETRIĄ") else appText("READY", "GOTOWE"), color = if (recording) TougeRed else TougeCyan, fontSize = 10.sp) }
            IconButton(onClick = { if (!recording) front = !front }, modifier = Modifier.background(Color.Black.copy(alpha = .5f), CircleShape)) { Icon(Icons.Default.Cameraswitch, null, tint = Color.White) }
        }
        Column(Modifier.fillMaxWidth().align(Alignment.BottomCenter).background(Color.Black.copy(alpha = .6f)).padding(18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            error?.let { Text(it, color = TougeRed) }
            IconButton(
                onClick = {
                    if (recording) container.cameraRecordingController.stop()
                    else scope.launch { container.historyRepository.activeSessionId()?.let(container.cameraRecordingController::start) }
                },
                enabled = accepted && permissionGranted,
                modifier = Modifier.size(78.dp).background(if (recording) Color.White else TougeRed, CircleShape)
            ) { Icon(if (recording) Icons.Default.Stop else Icons.Default.FiberManualRecord, null, tint = if (recording) TougeRed else Color.White, modifier = Modifier.size(42.dp)) }
            Text(if (recording) appText("Tap to stop. The recording will be attached to this drive.", "Dotknij, aby zatrzymać. Nagranie zostanie przypisane do przejazdu.") else appText("Connect to EMULOGGER and start a drive before recording.", "Połącz się z EMULOGGEREM i rozpocznij przejazd przed nagrywaniem."), color = Color.White, fontSize = 11.sp, modifier = Modifier.padding(top = 8.dp))
        }
    }
    if (!accepted) AlertDialog(
        onDismissRequest = close,
        title = { Text(appText("Experimental drive recording", "Eksperymentalne nagrywanie przejazdu")) },
        text = { Text(appText("This option records the road with your phone camera while Touge Dash saves engine telemetry. The synchronized recording can later be trimmed and exported with a configurable data HUD. Camera encoding puts significant load on a phone and may cause heat, higher battery use or reduced responsiveness. Use it only when the phone is securely mounted and never operate it while driving.", "Ta opcja nagrywa drogę kamerą telefonu, gdy Touge Dash zapisuje telemetrię silnika. Zsynchronizowany film można później przyciąć i wyeksportować z konfigurowalnym HUD-em. Kodowanie mocno obciąża telefon i może powodować nagrzewanie, większe zużycie baterii lub spadek płynności. Używaj tylko w stabilnym uchwycie i nigdy nie obsługuj telefonu podczas jazdy.")) },
        confirmButton = { Button(enabled = countdown == 0, onClick = { context.getSharedPreferences("camera", 0).edit().putBoolean("accepted", true).apply(); accepted = true }) { Text(if (countdown > 0) appText("I understand (${countdown}s)", "Rozumiem (${countdown}s)") else appText("I understand — enable", "Rozumiem — włącz")) } },
        dismissButton = { TextButton(onClick = close) { Text(appText("Not now", "Nie teraz")) } }
    )
}
