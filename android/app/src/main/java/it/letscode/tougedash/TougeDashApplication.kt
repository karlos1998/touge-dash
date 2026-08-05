package it.letscode.tougedash

import android.app.Application
import it.letscode.tougedash.di.AppContainer

class TougeDashApplication : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
    override fun onCreate() {
        super.onCreate()
        container.initialize()
    }
}
