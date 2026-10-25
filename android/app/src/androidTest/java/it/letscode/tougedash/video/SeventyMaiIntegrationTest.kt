package it.letscode.tougedash.video

import android.media.MediaMetadataRetriever
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import it.letscode.tougedash.MainActivity
import it.letscode.tougedash.TougeDashApplication
import it.letscode.tougedash.data.local.DriveSessionEntity
import it.letscode.tougedash.ui.CompatibilityOnboardingPreference
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.*
import okio.Buffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@RunWith(AndroidJUnit4::class)
class SeventyMaiIntegrationTest {
    @Test fun cancellingAStalledCameraDownloadClosesTheSocketAndRemovesItsPartialFile() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<TougeDashApplication>()
        val server = MockWebServer().apply {
            enqueue(MockResponse().setBody(Buffer().write(ByteArray(1_000_000))).throttleBody(1024, 1, java.util.concurrent.TimeUnit.SECONDS))
            start()
        }
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            chain.proceed(chain.request().newBuilder().url(chain.request().url.newBuilder().host(server.hostName).port(server.port).build()).build())
        }.build()
        val target = java.io.File(app.cacheDir, "cancelled-70mai.mp4")
        target.delete()
        val received = CompletableDeferred<Unit>()
        try {
            val download = launch { SeventyMaiClient(app, http).download(SeventyMaiClip("/DCIM", "slow.mp4", 1_000_000, 0, 60_000), target) { count, _ -> if (count > 0) received.complete(Unit) } }
            withTimeout(10_000) { received.await() }
            val began = android.os.SystemClock.elapsedRealtime()
            withTimeout(3_000) { download.cancelAndJoin() }
            assertTrue(android.os.SystemClock.elapsedRealtime() - began < 3_000)
            assertFalse(target.exists())
            assertFalse(java.io.File(target.path + ".part").exists())
        } finally { server.shutdown() }
    }

    @Test fun cameraProtocolDownloadAndJoiningPreserveClockAndRealGap() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<TougeDashApplication>()
        CompatibilityOnboardingPreference.accept(app)
        val video = InstrumentationRegistry.getInstrumentation().context.assets.open("parity-drive.mp4").use { it.readBytes() }
        val start = (System.currentTimeMillis() / 1000 - 3600) * 1000
        val dateFormat = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
        val session = DriveSessionEntity("70mai-test-drive", "70mai-test", startedAt = start, endedAt = start + 20000, modifiedAt = start)
        app.container.dao.upsertSession(session)
        val server = MockWebServer()
        fun result(value: String) = MockResponse().setHeader("Content-Type", "application/json").setBody("{\"ResultCode\":0,\"Result\":$value}")
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when (request.requestUrl!!.encodedPath) {
                "/cgi-bin/BindByBanya.cgi" -> result("{\"Token\":\"TOKEN\",\"timestamp\":\"1700000000\"}")
                "/cgi-bin/UserconfirmByBanya.cgi" -> result("null")
                "/cgi-bin/getsystime.cgi" -> result("\"${dateFormat.format(Date(System.currentTimeMillis() + 300000))}\"")
                "/cgi-bin/setaccessalbum.cgi" -> result("null")
                "/cgi-bin/getfilelist.cgi" -> result("""[
                    {"name":"a.mp4","path":"/DCIM","time":"${dateFormat.format(Date(start - 3000 + 300000))}","duration":"1200","size":${video.size}},
                    {"name":"b.mp4","path":"/DCIM","time":"${dateFormat.format(Date(start + 11000 + 300000))}","duration":"1200","size":${video.size}}
                ]""")
                "/DCIM/a.mp4", "/DCIM/b.mp4" -> MockResponse().setHeader("Content-Type", "video/mp4").setBody(Buffer().write(video))
                else -> MockResponse().setResponseCode(404)
            }
        }
        server.start()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            chain.proceed(chain.request().newBuilder().url(chain.request().url.newBuilder().host(server.hostName).port(server.port).build()).build())
        }.build()
        val importer = SeventyMaiImporter(app, scope, app.container.dao) { SeventyMaiClient(it, http) }
        try {
            ActivityScenario.launch(MainActivity::class.java).use {
                importer.scan(session, SeventyMaiCameraModel.M300, false)
                val scanned = withTimeout(20_000) { importer.state.first { it.scan != null || it.error != null } }
                assertNull(scanned.error)
                assertEquals(2, scanned.scan!!.clips.size)
                assertEquals(300000.0, scanned.scan.clockOffsetMillis!!.toDouble(), 1500.0)
                importer.download(session)
                val finished = withTimeout(150_000) { importer.state.first { it.projectId != null || it.error != null } }
                assertNull("70mai pipeline failed: ${finished.error}", finished.error)
                val project = app.container.dao.videosOnce(session.id).first { it.id == finished.projectId }
                assertEquals(20.0, project.durationSeconds, .3)
                assertEquals(0.0, project.telemetryTrimStartSeconds, .01)
                val metadata = MediaMetadataRetriever()
                try {
                    metadata.setDataSource(app, android.net.Uri.parse(project.localUri))
                    assertEquals("yes", metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))
                    val gap = requireNotNull(metadata.getFrameAtTime(10_000_000, MediaMetadataRetriever.OPTION_CLOSEST))
                    val center = gap.getPixel(gap.width / 2, gap.height / 2)
                    assertTrue("The real gap must be black, not a shifted subsequent clip", android.graphics.Color.red(center) < 20 && android.graphics.Color.green(center) < 20 && android.graphics.Color.blue(center) < 20)
                } finally { metadata.release() }
            }
        } finally { scope.cancel(); server.shutdown() }
    }
}
