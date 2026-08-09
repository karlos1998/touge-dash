package it.letscode.tougedash.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SessionUpsertTest {
    private lateinit var database: TougeDashDatabase
    private lateinit var dao: TougeDashDao

    @Before
    fun createDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, TougeDashDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = database.dao()
    }

    @After
    fun closeDatabase() {
        database.close()
    }

    @Test
    fun updatingSessionDoesNotCascadeDeleteSamples() = runBlocking {
        val session = DriveSessionEntity(
            id = "session-1",
            vehicleHardwareId = "logger-1",
            startedAt = 1_000,
            endedAt = 1_000,
            modifiedAt = 1_000
        )
        dao.upsertSession(session)
        dao.insertSamples(listOf(sample(session.id)))

        dao.upsertSession(session.copy(endedAt = 2_000, modifiedAt = 2_000, sampleCount = 1))

        assertEquals(1, dao.samples(session.id).first().size)
        assertEquals(1, dao.session(session.id).first()?.sampleCount)
    }

    private fun sample(sessionId: String) = TelemetrySampleEntity(
        id = "sample-1",
        sessionId = sessionId,
        recordedAt = 1_500,
        rpm = 3_000.0,
        boostBar = 0.8,
        mapKpa = 180.0,
        throttlePercent = 50.0,
        coolantCelsius = 90.0,
        intakeCelsius = 30.0,
        oilTemperatureCelsius = 95.0,
        oilPressureBar = 4.0,
        fuelPressureBar = 3.5,
        afr = 14.7,
        lambda = 1.0,
        batteryVoltage = 13.8,
        ignitionDegrees = 15.0,
        injectorDutyPercent = 40.0,
        speedKph = 80.0,
        checkEngineMask = 0
    )
}
