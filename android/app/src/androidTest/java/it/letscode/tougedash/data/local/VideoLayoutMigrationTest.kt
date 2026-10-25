package it.letscode.tougedash.data.local

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VideoLayoutMigrationTest {
    @get:Rule val helper = MigrationTestHelper(InstrumentationRegistry.getInstrumentation(), TougeDashDatabase::class.java)
    @Test fun existingVideosSurviveUpgradeAndReceiveAnOptionalProjectLayout() {
        helper.createDatabase("video-migration-test", 5).apply {
            execSQL("""INSERT INTO video_projects(id,sessionId,sourceKind,localUri,sourceDisplayName,durationSeconds,fileSizeBytes,pixelWidth,pixelHeight,framesPerSecond,hasAudio,videoTrimStartSeconds,telemetryTrimStartSeconds,exportDurationSeconds,overlayTemplateId,createdAt)
                VALUES ('old-video','drive','GALLERY','file:///original.mp4','Original',12,1024,1280,720,30,1,2,4,6,'RACE',1000)""")
            close()
        }
        helper.runMigrationsAndValidate("video-migration-test", 6, true, DatabaseMigrations.VIDEO_PROJECT_LAYOUT).use { database ->
            database.query("SELECT localUri,videoTrimStartSeconds,telemetryTrimStartSeconds,exportDurationSeconds,overlayDefinitionJson FROM video_projects WHERE id='old-video'").use { row ->
                assertTrue(row.moveToFirst())
                assertEquals("file:///original.mp4", row.getString(0))
                assertEquals(2.0, row.getDouble(1), .001)
                assertEquals(4.0, row.getDouble(2), .001)
                assertEquals(6.0, row.getDouble(3), .001)
                assertTrue(row.isNull(4))
            }
        }
    }
}
