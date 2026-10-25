package it.letscode.tougedash.video

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

suspend fun loadVideoTimelineThumbnails(context: Context, uri: Uri, duration: Double, count: Int = 10): List<Bitmap> = withContext(Dispatchers.IO) {
    val retriever = MediaMetadataRetriever()
    try {
        retriever.setDataSource(context, uri)
        (0 until count).mapNotNull { index ->
            ensureActive()
            val time = (duration * index / count * 1_000_000).toLong()
            runCatching {
                if (Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 160, 90)
                else retriever.getFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)?.let { original ->
                    Bitmap.createScaledBitmap(original, 160, 90, true).also { if (it !== original) original.recycle() }
                }
            }.getOrNull()
        }
    } finally { retriever.release() }
}
