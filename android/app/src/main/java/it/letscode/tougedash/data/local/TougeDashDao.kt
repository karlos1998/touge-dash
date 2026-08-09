package it.letscode.tougedash.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Transaction
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface TougeDashDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertVehicle(value: VehicleEntity)
    @Query("SELECT * FROM vehicles ORDER BY createdAt") fun vehicles(): Flow<List<VehicleEntity>>
    @Query("SELECT * FROM vehicles WHERE localHardwareId = :hardwareId") suspend fun vehicle(hardwareId: String): VehicleEntity?
    @Query("SELECT * FROM vehicles ORDER BY createdAt") suspend fun vehiclesOnce(): List<VehicleEntity>

    // INSERT OR REPLACE deletes the existing parent row before inserting it again.
    // Because telemetry_samples references drive_sessions with ON DELETE CASCADE,
    // that used to erase every recorded sample whenever a session was flushed.
    @Upsert suspend fun upsertSession(value: DriveSessionEntity)
    @Update suspend fun updateSession(value: DriveSessionEntity)
    @Query("SELECT * FROM drive_sessions ORDER BY startedAt DESC") fun sessions(): Flow<List<DriveSessionEntity>>
    @Query("SELECT * FROM drive_sessions WHERE id = :id") fun session(id: String): Flow<DriveSessionEntity?>
    @Query("SELECT * FROM drive_sessions WHERE id = :id") suspend fun sessionOnce(id: String): DriveSessionEntity?
    @Query("SELECT * FROM drive_sessions WHERE syncState IN ('LOCAL','PENDING_UPLOAD','CHANGED_AFTER_SYNC','FAILED') ORDER BY startedAt LIMIT :limit") suspend fun pendingSessions(limit: Int = 5): List<DriveSessionEntity>
    @Query("DELETE FROM incidents WHERE sessionId = :sessionId") suspend fun deleteIncidentsForSession(sessionId: String)
    @Query("DELETE FROM annotations WHERE sessionId = :sessionId") suspend fun deleteAnnotationsForSession(sessionId: String)
    @Query("DELETE FROM video_projects WHERE sessionId = :sessionId") suspend fun deleteVideosForSession(sessionId: String)
    @Query("DELETE FROM acceleration_attempts WHERE sessionId = :sessionId") suspend fun deleteAccelerationAttemptsForSession(sessionId: String)
    @Query("DELETE FROM drive_sessions WHERE id = :sessionId") suspend fun deleteSession(sessionId: String)
    @Transaction suspend fun deleteSessionCascade(sessionId: String) {
        deleteIncidentsForSession(sessionId)
        deleteAnnotationsForSession(sessionId)
        deleteVideosForSession(sessionId)
        deleteAccelerationAttemptsForSession(sessionId)
        deleteSession(sessionId)
    }

    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insertSamples(values: List<TelemetrySampleEntity>)
    @Query("SELECT * FROM telemetry_samples WHERE sessionId = :sessionId ORDER BY recordedAt") fun samples(sessionId: String): Flow<List<TelemetrySampleEntity>>
    @Query("SELECT * FROM telemetry_samples WHERE sessionId = :sessionId ORDER BY recordedAt") suspend fun samplesOnce(sessionId: String): List<TelemetrySampleEntity>
    @Query("SELECT * FROM telemetry_samples WHERE sessionId = :sessionId AND chartEligible = 1 ORDER BY recordedAt") fun chartSamples(sessionId: String): Flow<List<TelemetrySampleEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertAccelerationAttempt(value: AccelerationAttemptEntity)
    @Query("SELECT * FROM acceleration_attempts WHERE sessionId = :sessionId ORDER BY startedAt") fun accelerationAttempts(sessionId: String): Flow<List<AccelerationAttemptEntity>>
    @Query("SELECT * FROM acceleration_attempts WHERE sessionId = :sessionId ORDER BY startedAt") suspend fun accelerationAttemptsOnce(sessionId: String): List<AccelerationAttemptEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertIncident(value: IncidentEntity)
    @Query("SELECT * FROM incidents ORDER BY triggeredAt DESC") fun incidents(): Flow<List<IncidentEntity>>
    @Query("SELECT * FROM incidents WHERE sessionId = :sessionId ORDER BY triggeredAt") fun incidentsForSession(sessionId: String): Flow<List<IncidentEntity>>
    @Query("SELECT * FROM incidents WHERE id = :id") suspend fun incidentOnce(id: String): IncidentEntity?
    @Query("SELECT * FROM incidents WHERE syncState IN ('LOCAL','PENDING_UPLOAD','FAILED') ORDER BY triggeredAt LIMIT :limit") suspend fun pendingIncidents(limit: Int = 5): List<IncidentEntity>
    @Update suspend fun updateIncident(value: IncidentEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertAnnotation(value: AnnotationEntity)
    @Query("SELECT * FROM annotations WHERE sessionId = :sessionId ORDER BY recordedAt") fun annotations(sessionId: String): Flow<List<AnnotationEntity>>
    @Query("SELECT * FROM annotations WHERE syncState IN ('LOCAL','PENDING_UPLOAD','FAILED') ORDER BY recordedAt LIMIT :limit") suspend fun pendingAnnotations(limit: Int = 50): List<AnnotationEntity>
    @Query("SELECT COUNT(*) FROM annotations WHERE syncState IN ('LOCAL','PENDING_UPLOAD','FAILED')") fun pendingAnnotationCount(): Flow<Int>
    @Query("SELECT COUNT(*) FROM telemetry_samples WHERE sessionId IN (SELECT id FROM drive_sessions WHERE syncState IN ('LOCAL','PENDING_UPLOAD','CHANGED_AFTER_SYNC','FAILED','UPLOADING'))") fun pendingSampleCount(): Flow<Int>
    @Update suspend fun updateAnnotation(value: AnnotationEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertTemplate(value: DashboardTemplateEntity)
    @Query("SELECT * FROM dashboard_templates WHERE deletedAt IS NULL ORDER BY modifiedAt DESC") fun templates(): Flow<List<DashboardTemplateEntity>>
    @Query("SELECT * FROM dashboard_templates WHERE selected = 1 AND deletedAt IS NULL LIMIT 1") fun selectedTemplate(): Flow<DashboardTemplateEntity?>
    @Query("SELECT * FROM dashboard_templates") suspend fun templatesOnce(): List<DashboardTemplateEntity>
    @Query("UPDATE dashboard_templates SET dirty = 0 WHERE id = :id") suspend fun markTemplateSynced(id: String)
    @Query("UPDATE dashboard_templates SET selected = CASE WHEN id = :id THEN 1 ELSE 0 END") suspend fun selectTemplate(id: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertAlertConfiguration(value: AlertConfigurationEntity)
    @Query("SELECT * FROM alert_configurations WHERE vehicleHardwareId = :hardwareId") fun alertConfiguration(hardwareId: String): Flow<AlertConfigurationEntity?>
    @Query("SELECT * FROM alert_configurations WHERE vehicleHardwareId = :hardwareId") suspend fun alertConfigurationOnce(hardwareId: String): AlertConfigurationEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertVideo(value: VideoProjectEntity)
    @Query("SELECT * FROM video_projects WHERE sessionId = :sessionId ORDER BY createdAt DESC") fun videos(sessionId: String): Flow<List<VideoProjectEntity>>
    @Query("SELECT * FROM video_projects WHERE sessionId = :sessionId ORDER BY createdAt DESC") suspend fun videosOnce(sessionId: String): List<VideoProjectEntity>
    @Query("SELECT COALESCE(SUM(fileSizeBytes), 0) FROM video_projects") fun videoStorageBytes(): Flow<Long>
    @Query("DELETE FROM video_projects WHERE id = :id") suspend fun deleteVideo(id: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun upsertOverlayTemplate(value: OverlayTemplateEntity)
    @Query("SELECT * FROM overlay_templates ORDER BY modifiedAt DESC") fun overlayTemplates(): Flow<List<OverlayTemplateEntity>>
    @Query("SELECT * FROM overlay_templates ORDER BY modifiedAt DESC") suspend fun overlayTemplatesOnce(): List<OverlayTemplateEntity>
    @Query("SELECT * FROM overlay_templates WHERE id = :id") suspend fun overlayTemplate(id: String): OverlayTemplateEntity?
    @Query("DELETE FROM overlay_templates WHERE id = :id") suspend fun deleteOverlayTemplate(id: String)
}
