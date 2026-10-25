package it.letscode.tougedash.video

import android.content.Context
import it.letscode.tougedash.ui.AppLanguage
import it.letscode.tougedash.ui.AppLanguagePreference
import java.util.Locale

internal fun Context.videoLocale(): Locale = when (AppLanguagePreference.read(this)) {
    AppLanguage.POLISH -> Locale.forLanguageTag("pl")
    AppLanguage.ENGLISH -> Locale.ENGLISH
    AppLanguage.SYSTEM -> resources.configuration.locales[0]
}
internal fun Context.videoText(english: String, polish: String) = if (videoLocale().language == "pl") polish else english
