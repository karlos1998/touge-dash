package it.letscode.tougedash.alerts

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.provider.Settings
import androidx.core.app.NotificationCompat
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.R
import it.letscode.tougedash.model.ActiveAlert
import it.letscode.tougedash.model.IncidentKind
import it.letscode.tougedash.model.IncidentSeverity

class EngineAlertNotifier(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    init {
        val sound = Settings.System.DEFAULT_ALARM_ALERT_URI
        val audio = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.alert_channel_name), NotificationManager.IMPORTANCE_HIGH).apply {
                description = local(
                    "Safety alerts calculated from read-only ECU telemetry",
                    "Alerty bezpieczeństwa obliczane z telemetrii ECU tylko do odczytu"
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 180, 500, 180, 900)
                setSound(sound, audio)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
        )
    }

    fun show(alert: ActiveAlert) {
        val critical = alert.severity == IncidentSeverity.CRITICAL
        val intent = PendingIntent.getActivity(
            context, alert.kind.ordinal,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val message = "${alert.value.format()} ${alert.unit} • ${local("limit", "próg")} ${alert.threshold.format()} ${alert.unit}"
        val criticalMessage = local("STOP THE VEHICLE", "ZATRZYMAJ POJAZD")
        val explanation = local(
            "Stop safely and verify engine parameters.",
            "Zatrzymaj się bezpiecznie i sprawdź parametry silnika."
        )
        manager.notify(
            1_000 + alert.kind.ordinal,
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setColor(if (critical) 0xffff352f.toInt() else 0xffff9d3d.toInt())
                .setContentTitle(alert.kind.title())
                .setContentText(if (critical) "$criticalMessage • $message" else message)
                .setStyle(NotificationCompat.BigTextStyle().bigText(if (critical) "$explanation $message" else message))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(false)
                .setOngoing(critical)
                .setContentIntent(intent)
                .build()
        )
    }

    private fun IncidentKind.title() = when (this) {
        IncidentKind.LOW_OIL_PRESSURE -> local("Low oil pressure", "Niskie ciśnienie oleju")
        IncidentKind.LEAN_UNDER_BOOST -> local("Lean mixture under boost", "Uboga mieszanka pod doładowaniem")
        IncidentKind.OVERBOOST -> local("Overboost", "Przekroczone doładowanie")
        IncidentKind.HIGH_COOLANT_TEMPERATURE -> local("High coolant temperature", "Wysoka temperatura płynu")
        IncidentKind.HIGH_OIL_TEMPERATURE -> local("High oil temperature", "Wysoka temperatura oleju")
        IncidentKind.LOW_FUEL_PRESSURE -> local("Low fuel pressure", "Niskie ciśnienie paliwa")
        IncidentKind.LOW_BATTERY_VOLTAGE -> local("Low battery voltage", "Niskie napięcie akumulatora")
        IncidentKind.CHECK_ENGINE -> local("Check engine", "Błąd silnika")
    }

    private fun local(english: String, polish: String): String =
        if (context.resources.configuration.locales[0].language == "pl") polish else english
    private fun Double.format() = if (kotlin.math.abs(this - toInt()) < .01) toInt().toString() else "%.1f".format(this)

    companion object { private const val CHANNEL_ID = "engine_alerts_v2" }
}
