package it.letscode.tougedash.video

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.TougeDashApplication
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** CameraX stays bound to this foreground lifecycle while the activity is backgrounded. */
class DriveRecordingService : LifecycleService() {
    // Manifest declares camera|microphone; the type mask is selected at runtime
    // so camera-only recording does not require microphone permission.
    @android.annotation.SuppressLint("ForegroundServiceType")
    override fun onCreate() {
        super.onCreate()
        running = true
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, "Drive camera", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val polish = videoLocale().language == "pl"
        val container = (application as TougeDashApplication).container
        val microphone = container.videoRecordingSettings.settings.value.recordAudio && androidx.core.content.ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val serviceType = if (android.os.Build.VERSION.SDK_INT >= 30) android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or (if (microphone) android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0) else 0
        androidx.core.app.ServiceCompat.startForeground(this, 421, NotificationCompat.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle(if (polish) "Nagrywanie przejazdu" else "Recording drive")
            .setContentText(if (polish) "Kamera i telemetria Touge Dash" else "Touge Dash camera and telemetry").setOngoing(true).setContentIntent(open).build(), serviceType)
        lifecycleScope.launch {
            val container = (application as TougeDashApplication).container
            var inactiveSince = 0L
            while (isActive) {
                val session = container.historyRepository.activeSession.value
                val enabled = container.videoRecordingSettings.settings.value.automaticRecording
                if (session != null && enabled) {
                    inactiveSince = 0
                    container.cameraRecordingController.stopWhenSessionEnds(session.id)
                    container.cameraRecordingController.ensureAutomaticRecording(this@DriveRecordingService, session.id)
                } else {
                    container.cameraRecordingController.stopWhenSessionEnds(null)
                    if (inactiveSince == 0L) inactiveSince = android.os.SystemClock.elapsedRealtime()
                    if (android.os.SystemClock.elapsedRealtime() - inactiveSince > 3_000) { stopSelf(); break }
                }
                delay(100)
            }
        }
    }
    override fun onDestroy() {
        (application as TougeDashApplication).container.cameraRecordingController.stop()
        running = false
        super.onDestroy()
    }
    companion object { @Volatile var running = false; private const val CHANNEL = "drive-camera" }
}
