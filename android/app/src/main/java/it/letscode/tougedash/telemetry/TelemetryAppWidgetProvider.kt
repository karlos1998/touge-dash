package it.letscode.tougedash.telemetry

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.R
import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetrySnapshot
import kotlin.math.roundToInt

class TelemetryAppWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        val snapshot = TelemetryRuntime.snapshot.value
        val connection = TelemetryRuntime.connection.value
        appWidgetIds.forEach { update(context, manager, it, snapshot, connection) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        update(context, manager, appWidgetId, TelemetryRuntime.snapshot.value, TelemetryRuntime.connection.value)
    }

    companion object {
        fun updateAll(context: Context, snapshot: TelemetrySnapshot, connection: TelemetryConnection) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TelemetryAppWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach {
                update(context, manager, it, snapshot, connection)
            }
        }

        private fun update(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            snapshot: TelemetrySnapshot,
            connection: TelemetryConnection
        ) {
            val minimumWidth = manager.getAppWidgetOptions(appWidgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            manager.updateAppWidget(
                appWidgetId,
                views(context, snapshot, connection, compact = minimumWidth < 220)
            )
        }

        private fun views(
            context: Context,
            snapshot: TelemetrySnapshot,
            connection: TelemetryConnection,
            compact: Boolean
        ) = RemoteViews(
            context.packageName,
            if (compact) R.layout.touge_telemetry_widget_compact else R.layout.touge_telemetry_widget
        ).apply {
            setTextViewText(R.id.widget_rpm, snapshot.rpm.roundToInt().toString())
            setTextViewText(R.id.widget_boost, "%.2f bar".format(snapshot.boostBar))
            if (compact) {
                setTextViewText(R.id.widget_oil_temperature, "%.0f°C".format(snapshot.oilTemperatureCelsius))
            } else {
                setTextViewText(R.id.widget_oil_pressure, "%.1f bar".format(snapshot.oilPressureBar))
                setTextViewText(R.id.widget_oil_temperature, "%.0f°C".format(snapshot.oilTemperatureCelsius))
                setTextViewText(R.id.widget_coolant, "%.0f°C".format(snapshot.coolantCelsius))
                setTextViewText(R.id.widget_afr, "%.1f".format(snapshot.afr))
            }
            setTextViewText(
                R.id.widget_connection,
                when {
                    connection.state == ConnectionState.Connected && snapshot.isFresh ->
                        context.getString(R.string.widget_live)
                    connection.state == ConnectionState.Connected -> context.getString(R.string.widget_stale)
                    else -> context.getString(R.string.widget_disconnected)
                }
            )
            val openApp = PendingIntent.getActivity(
                context,
                301,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            setOnClickPendingIntent(R.id.widget_root, openApp)
        }
    }
}
