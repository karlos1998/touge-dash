package it.letscode.tougedash.ui

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.LocaleList
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import java.util.Locale

enum class AppLanguage(val storedValue: String) {
    SYSTEM("system"),
    POLISH("pl"),
    ENGLISH("en");

    companion object {
        fun fromStoredValue(value: String?): AppLanguage =
            entries.firstOrNull { it.storedValue == value } ?: SYSTEM
    }
}

object AppLanguagePreference {
    private const val PREFERENCES = "language"
    private const val KEY_LANGUAGE = "language"

    fun read(context: Context): AppLanguage = AppLanguage.fromStoredValue(
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(KEY_LANGUAGE, null)
    )

    fun write(context: Context, language: AppLanguage) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LANGUAGE, language.storedValue)
            .apply()
    }
}

@Composable
fun AppLanguageEnvironment(language: AppLanguage, content: @Composable () -> Unit) {
    val baseContext = LocalContext.current
    val systemConfiguration = LocalConfiguration.current
    val configuration = remember(language, systemConfiguration) {
        Configuration(systemConfiguration).apply {
            val locales = when (language) {
                AppLanguage.SYSTEM -> Resources.getSystem().configuration.locales
                AppLanguage.POLISH -> LocaleList(Locale.forLanguageTag("pl"))
                AppLanguage.ENGLISH -> LocaleList(Locale.forLanguageTag("en"))
            }
            setLocales(locales)
        }
    }
    val localizedContext = remember(baseContext, configuration) {
        baseContext.createConfigurationContext(configuration)
    }

    CompositionLocalProvider(
        LocalContext provides localizedContext,
        LocalConfiguration provides configuration,
        content = content
    )
}
