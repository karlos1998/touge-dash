package it.letscode.tougedash.video

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.TougeDashApplication
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/** Keeps an explicitly started export alive when the screen locks or the user leaves the editor. */
class VideoExportService : Service() {
    private var wakeLock: android.os.PowerManager.WakeLock? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    override fun onBind(intent: Intent?): IBinder? = null
    // dataSync is declared in both merged manifests, as with TelemetryService.
    // AGP 8.7's lint does not resolve this service declaration in this project.
    @android.annotation.SuppressLint("ForegroundServiceType")
    override fun onCreate() {
        super.onCreate()
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel(CHANNEL, "Video export", NotificationManager.IMPORTANCE_LOW))
        androidx.core.app.ServiceCompat.startForeground(this, ID, notification(0), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        wakeLock = getSystemService(android.os.PowerManager::class.java).newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "TougeDash:VideoExport").apply { acquire(6 * 60 * 60 * 1000L) }
        scope.launch {
            val container = (application as TougeDashApplication).container
            combine(container.videoRepository.task, container.seventyMaiImporter.state) { export, camera ->
                val busy = (export.operation != null && !export.completed && export.error == null) || camera.busy
                busy to if (camera.busy) (camera.progress * 100).toInt() else (export.progress * 100).toInt()
            }.collectLatest { (busy, progress) ->
                if (!busy) stopSelf() else notifications.notify(ID, notification(progress))
            }
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == CANCEL) {
            val container = (application as TougeDashApplication).container
            container.videoRepository.cancelExport()
            container.seventyMaiImporter.cancel()
        }
        return START_NOT_STICKY
    }
    private fun notification(progress: Int): android.app.Notification {
        val polish = videoLocale().language == "pl"
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val cancel = PendingIntent.getService(this, 1, Intent(this, VideoExportService::class.java).setAction(CANCEL), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(if (polish) "Eksport filmu Touge Dash" else "Touge Dash video export")
            .setContentText("$progress%").setProgress(100, progress, progress == 0).setContentIntent(open).setOngoing(true)
            .addAction(0, if (polish) "Anuluj" else "Cancel", cancel).build()
    }
    override fun onDestroy() { scope.cancel(); wakeLock?.takeIf { it.isHeld }?.release(); super.onDestroy() }
    companion object { private const val CHANNEL = "video-export"; private const val ID = 420; private const val CANCEL = "cancel-video-export" }
}
