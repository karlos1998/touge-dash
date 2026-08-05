package it.letscode.tougedash.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [
        VehicleEntity::class, DriveSessionEntity::class, TelemetrySampleEntity::class,
        IncidentEntity::class, AnnotationEntity::class, DashboardTemplateEntity::class,
        AlertConfigurationEntity::class, VideoProjectEntity::class, OverlayTemplateEntity::class
    ],
    version = 1,
    exportSchema = true
)
abstract class TougeDashDatabase : RoomDatabase() {
    abstract fun dao(): TougeDashDao
}
