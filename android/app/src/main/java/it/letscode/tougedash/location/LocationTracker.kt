package it.letscode.tougedash.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import androidx.core.content.ContextCompat
import it.letscode.tougedash.model.RecordedLocation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class LocationTracker(private val context: Context) : LocationListener {
    private val manager = context.getSystemService(LocationManager::class.java)
    private val mutableLocation = MutableStateFlow<RecordedLocation?>(null)
    val location = mutableLocation.asStateFlow()
    private val preferences = context.getSharedPreferences("location", Context.MODE_PRIVATE)
    val isEnabled: Boolean get() = preferences.getBoolean("record-route", false)

    @SuppressLint("MissingPermission")
    fun start() {
        if (!isEnabled) return
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return
        val provider = when {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> return
        }
        manager.requestLocationUpdates(provider, 500L, 1f, this)
    }

    fun stop() = manager.removeUpdates(this)

    fun setEnabled(value: Boolean) {
        preferences.edit().putBoolean("record-route", value).apply()
        if (value) start() else {
            stop()
            mutableLocation.value = null
        }
    }

    override fun onLocationChanged(location: Location) {
        mutableLocation.value = RecordedLocation(location.latitude, location.longitude, location.accuracy.toDouble(), location.altitude, location.time)
    }
}
