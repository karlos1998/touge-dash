package it.letscode.tougedash.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

enum class SyncState { LOCAL, PENDING_UPLOAD, UPLOADING, SYNCED, CHANGED_AFTER_SYNC, FAILED }

@Entity(tableName = "vehicles")
data class VehicleEntity(
    @PrimaryKey val localHardwareId: String,
    val remoteId: String? = null,
    val displayName: String,
    val role: String = "OWNER",
    val accountId: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)

@Entity(tableName = "drive_sessions", indices = [Index("vehicleHardwareId"), Index("startedAt")])
data class DriveSessionEntity(
    @PrimaryKey val id: String,
    val vehicleHardwareId: String,
    val remoteId: String? = null,
    val startedAt: Long,
    val endedAt: Long,
    val modifiedAt: Long,
    val sampleCount: Int = 0,
    val distanceMeters: Double = 0.0,
    val maxRpm: Double = 0.0,
    val maxSpeedKph: Double = 0.0,
    val maxBoostBar: Double = 0.0,
    val maxCoolantCelsius: Double = 0.0,
    val maxOilTemperatureCelsius: Double = 0.0,
    val minimumOilPressureBar: Double? = null,
    val containsLocation: Boolean = false,
    val syncState: SyncState = SyncState.LOCAL,
    val syncProgress: Float = 0f,
    val syncBytesSent: Long = 0,
    val syncBytesTotal: Long = 0,
    val syncError: String? = null,
    val revision: Int = 1
)

@Entity(
    tableName = "telemetry_samples",
    foreignKeys = [ForeignKey(entity = DriveSessionEntity::class, parentColumns = ["id"], childColumns = ["sessionId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("sessionId"), Index(value = ["sessionId", "recordedAt"])]
)
data class TelemetrySampleEntity(
    @PrimaryKey val id: String,
    val sessionId: String,
    val recordedAt: Long,
    val rpm: Double,
    val boostBar: Double,
    val mapKpa: Double,
    val throttlePercent: Double,
    val coolantCelsius: Double,
    val intakeCelsius: Double,
    val oilTemperatureCelsius: Double,
    val oilPressureBar: Double,
    val fuelPressureBar: Double,
    val afr: Double,
    val lambda: Double,
    val batteryVoltage: Double,
    val ignitionDegrees: Double,
    val injectorDutyPercent: Double,
    val speedKph: Double,
    val checkEngineMask: Int,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val horizontalAccuracy: Double? = null,
    val altitude: Double? = null,
    val chartEligible: Boolean = true
)

@Entity(tableName = "incidents", indices = [Index("sessionId"), Index("vehicleHardwareId"), Index("triggeredAt")])
data class IncidentEntity(
    @PrimaryKey val id: String,
    val vehicleHardwareId: String,
    val sessionId: String,
    val kind: String,
    val severity: String,
    val triggeredAt: Long,
    val captureStartedAt: Long,
    val captureEndedAt: Long,
    val sampleCount: Int,
    val sampleRateHz: Double,
    val triggerValue: Double,
    val thresholdValue: Double,
    val triggerUnit: String,
    val triggerRpm: Double,
    val triggerBoostBar: Double,
    val triggerAfr: Double,
    val triggerSpeedKph: Double,
    val latitude: Double?,
    val longitude: Double?,
    val encodedSamples: String,
    val syncState: SyncState = SyncState.LOCAL,
    val syncProgress: Float = 0f,
    val syncError: String? = null,
    val revision: Int = 1,
    val remoteId: String? = null
)

@Entity(tableName = "annotations", indices = [Index("sessionId"), Index("incidentId")])
data class AnnotationEntity(
    @PrimaryKey val id: String,
    val vehicleHardwareId: String,
    val sessionId: String,
    val incidentId: String? = null,
    val recordedAt: Long,
    val body: String,
    val createdAt: Long = System.currentTimeMillis(),
    val modifiedAt: Long = System.currentTimeMillis(),
    val syncState: SyncState = SyncState.LOCAL
)

@Entity(tableName = "dashboard_templates")
data class DashboardTemplateEntity(
    @PrimaryKey val id: String,
    val name: String,
    val definitionJson: String,
    val schemaVersion: Int = 1,
    val modifiedAt: Long,
    val deletedAt: Long? = null,
    val selected: Boolean = false,
    val dirty: Boolean = true
)

@Entity(tableName = "alert_configurations")
data class AlertConfigurationEntity(
    @PrimaryKey val vehicleHardwareId: String,
    val rulesJson: String,
    val revision: Int = 1,
    val dirty: Boolean = true,
    val updatedAt: Long = System.currentTimeMillis(),
    val updatedByDisplayName: String? = null
)

@Entity(tableName = "video_projects", indices = [Index("sessionId")])
data class VideoProjectEntity(
    @PrimaryKey val id: String,
    val sessionId: String,
    val sourceKind: String,
    val localUri: String,
    val sourceDisplayName: String? = null,
    val durationSeconds: Double,
    val fileSizeBytes: Long,
    val pixelWidth: Int,
    val pixelHeight: Int,
    val framesPerSecond: Double,
    val hasAudio: Boolean,
    val videoTrimStartSeconds: Double = 0.0,
    val telemetryTrimStartSeconds: Double = 0.0,
    val exportDurationSeconds: Double,
    val overlayTemplateId: String? = null,
    val createdAt: Long = System.currentTimeMillis()
)

@Entity(tableName = "overlay_templates")
data class OverlayTemplateEntity(
    @PrimaryKey val id: String,
    val name: String,
    val definitionJson: String,
    val modifiedAt: Long = System.currentTimeMillis(),
    val selected: Boolean = false
)
