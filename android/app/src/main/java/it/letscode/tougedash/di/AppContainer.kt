@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package it.letscode.tougedash.di

import android.app.Application
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import it.letscode.tougedash.data.local.DashboardTemplateEntity
import it.letscode.tougedash.data.local.TougeDashDatabase
import it.letscode.tougedash.alerts.EngineAlertNotifier
import it.letscode.tougedash.alerts.AlertRepository
import it.letscode.tougedash.history.HistoryRepository
import it.letscode.tougedash.history.IncidentCaptureEngine
import it.letscode.tougedash.dashboard.DashboardRepository
import it.letscode.tougedash.location.LocationTracker
import it.letscode.tougedash.video.VideoRepository
import it.letscode.tougedash.video.CameraRecordingController
import it.letscode.tougedash.video.VideoRecordingSettings
import it.letscode.tougedash.cloud.CloudAuthRepository
import it.letscode.tougedash.cloud.CloudSyncRepository
import it.letscode.tougedash.model.DashboardTemplate
import it.letscode.tougedash.telemetry.TelemetryRuntime
import it.letscode.tougedash.telemetry.EcuControlCoordinator
import it.letscode.tougedash.performance.AccelerationEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class AppContainer(val application: Application) {
    val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    val database = Room.databaseBuilder(application, TougeDashDatabase::class.java, "touge-dash.db")
        .addMigrations(object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS acceleration_attempts (
                        id TEXT NOT NULL PRIMARY KEY,
                        sessionId TEXT NOT NULL,
                        type TEXT NOT NULL,
                        startedAt INTEGER NOT NULL,
                        endedAt INTEGER NOT NULL,
                        durationMillis INTEGER NOT NULL,
                        startSpeedKph REAL NOT NULL,
                        endSpeedKph REAL NOT NULL,
                        source TEXT NOT NULL,
                        quality TEXT NOT NULL,
                        sampleRateHz REAL NOT NULL,
                        shiftCount INTEGER NOT NULL,
                        revision INTEGER NOT NULL,
                        FOREIGN KEY(sessionId) REFERENCES drive_sessions(id) ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                """.trimIndent())
                db.execSQL("CREATE INDEX IF NOT EXISTS index_acceleration_attempts_sessionId ON acceleration_attempts(sessionId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_acceleration_attempts_sessionId_type_durationMillis ON acceleration_attempts(sessionId, type, durationMillis)")
            }
        })
        .build()
    val dao = database.dao()
    val runtime = TelemetryRuntime
    val ecuControls = EcuControlCoordinator(applicationScope)
    val historyRepository = HistoryRepository(dao)
    val accelerationEngine = AccelerationEngine()
    val alertNotifier = EngineAlertNotifier(application)
    val alertRepository = AlertRepository(dao, json)
    val incidentEngine = IncidentCaptureEngine(dao, json, alertNotifier::show)
    val dashboardRepository = DashboardRepository(dao, json)
    val locationTracker = LocationTracker(application)
    val videoRepository = VideoRepository(application, dao, applicationScope)
    val videoRecordingSettings = VideoRecordingSettings(application)
    val cameraRecordingController = CameraRecordingController(application, videoRepository, videoRecordingSettings)
    val authRepository = CloudAuthRepository(application, json)
    val cloudSyncRepository = CloudSyncRepository(application, dao, authRepository, json, alertRepository)

    fun initialize() {
        cloudSyncRepository.schedulePeriodic()
        videoRepository.ensureOverlayTemplates()
        applicationScope.launch { authRepository.session.filterNotNull().collect { cloudSyncRepository.schedule() } }
        applicationScope.launch(Dispatchers.IO) {
            if (dao.templates().first().isEmpty()) {
                val factory = DashboardTemplate.factory()
                dao.upsertTemplate(
                    DashboardTemplateEntity(
                        id = factory.id,
                        name = factory.name,
                        definitionJson = json.encodeToString(factory.definition),
                        modifiedAt = factory.modifiedAt,
                        selected = true,
                        dirty = false
                    )
                )
            }
        }
    }
}
