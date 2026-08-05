package it.letscode.tougedash.car

import android.Manifest
import android.content.Intent
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.SessionInfo
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.CarText
import androidx.car.app.model.ForegroundCarColorSpan
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.Header
import androidx.car.app.model.ItemList
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import it.letscode.tougedash.TougeDashApplication
import it.letscode.tougedash.R
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetrySnapshot
import it.letscode.tougedash.telemetry.TelemetryRuntime
import it.letscode.tougedash.telemetry.TelemetryService
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Developer-only Android Auto and Android Automotive OS preview.
 *
 * The production APK intentionally doesn't declare this service because Google
 * currently has no supported Android Auto category for an engine telemetry
 * display. The service never communicates with the ECU; it only observes the
 * same read-only in-process telemetry stream as the phone dashboard.
 */
class TougeDashCarAppService : CarAppService() {
    override fun onCreate() {
        super.onCreate()
        // Opening Touge Dash directly from the car must also start the phone's
        // read-only BLE collector. Permissions are still requested on the phone.
        if (!hasBluetoothPermissions()) {
            TelemetryRuntime.diagnostic("Car host is waiting for Bluetooth permissions on the phone")
            return
        }
        runCatching {
            ContextCompat.startForegroundService(
                this,
                Intent(this, TelemetryService::class.java)
            )
        }.onFailure { TelemetryRuntime.diagnostic("Car host could not start telemetry: ${it.message}") }
    }

    private fun hasBluetoothPermissions(): Boolean = Build.VERSION.SDK_INT < 31 ||
        checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
        checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(sessionInfo: SessionInfo): Session = TougeDashCarSession()
}

private class TougeDashCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen = TelemetryCarScreen(carContext)
}

internal class TelemetryCarScreen(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val container = (carContext.applicationContext as TougeDashApplication).container
    private var snapshot = TelemetryRuntime.snapshot.value
    private var connection = TelemetryRuntime.connection.value
    private var lastInvalidationAt = 0L
    private var pendingInvalidation: Job? = null

    init {
        lifecycle.addObserver(this)
        scope.launch {
            combine(TelemetryRuntime.snapshot, TelemetryRuntime.connection) { nextSnapshot, nextConnection ->
                nextSnapshot to nextConnection
            }.collect { (nextSnapshot, nextConnection) ->
                snapshot = nextSnapshot
                connection = nextConnection
                requestRefresh()
            }
        }
    }

    override fun onGetTemplate(): Template {
        val language = carContext.resources.configuration.locales[0]?.language ?: Locale.getDefault().language
        val dashboard = TelemetryCarDashboardFactory.create(
            snapshot = snapshot,
            connection = connection,
            rules = container.incidentEngine.rules,
            language = language
        )
        return TelemetryCarTemplateFactory.create(carContext, dashboard)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        pendingInvalidation?.cancel()
        scope.cancel()
    }

    private fun requestRefresh() {
        val elapsed = System.currentTimeMillis() - lastInvalidationAt
        if (elapsed >= REFRESH_INTERVAL_MS) {
            lastInvalidationAt = System.currentTimeMillis()
            mainHandler.post(::invalidate)
            return
        }
        if (pendingInvalidation?.isActive == true) return
        pendingInvalidation = scope.launch {
            delay(REFRESH_INTERVAL_MS - elapsed)
            lastInvalidationAt = System.currentTimeMillis()
            invalidate()
        }
    }

    companion object {
        private const val REFRESH_INTERVAL_MS = 1_000L
    }
}

internal object TelemetryCarTemplateFactory {
    fun create(context: Context, dashboard: TelemetryCarDashboard): GridTemplate {
        val list = ItemList.Builder()
        dashboard.cards.forEach { card ->
            list.addItem(
                GridItem.Builder()
                    .setTitle(card.label)
                    .setText(coloredValue(card.value, card.tone))
                    .setImage(metricIcon(context, card.id, card.tone), GridItem.IMAGE_TYPE_ICON)
                    .build()
            )
        }

        return GridTemplate.Builder()
            .setHeader(
                Header.Builder()
                    .setTitle(dashboard.title)
                    .setStartHeaderAction(Action.APP_ICON)
                    .build()
            )
            .setSingleList(list.build())
            .build()
    }

    private fun coloredValue(value: String, tone: CarMetricTone): CarText {
        val text = SpannableString(value)
        text.setSpan(ForegroundCarColorSpan.create(carColor(tone)), 0, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        return CarText.create(text)
    }

    private fun metricIcon(context: Context, metricId: String, tone: CarMetricTone): CarIcon =
        CarIcon.Builder(IconCompat.createWithResource(context, iconResource(metricId)))
            .setTint(carColor(tone))
            .build()

    private fun iconResource(metricId: String): Int = when (metricId) {
        "oil-pressure" -> R.drawable.ic_car_oil_pressure
        "oil-temperature" -> R.drawable.ic_car_temperature
        "coolant" -> R.drawable.ic_car_coolant
        "boost" -> R.drawable.ic_car_boost
        "fuel-pressure" -> R.drawable.ic_car_fuel_pressure
        else -> R.drawable.ic_car_afr
    }

    private fun carColor(tone: CarMetricTone): CarColor = when (tone) {
        CarMetricTone.NORMAL -> CarColor.GREEN
        CarMetricTone.WARNING -> CarColor.YELLOW
        CarMetricTone.CRITICAL -> CarColor.RED
    }
}
