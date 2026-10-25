package it.letscode.tougedash.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

object DatabaseMigrations {
    val VIDEO_PROJECT_LAYOUT = object : Migration(5, 6) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE video_projects ADD COLUMN overlayDefinitionJson TEXT")
        }
    }
}
