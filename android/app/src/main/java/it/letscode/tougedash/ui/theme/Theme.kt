package it.letscode.tougedash.ui.theme

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

val TougeCyan = Color(0xFF26D7E5)
val TougeMint = Color(0xFF43E8A8)
val TougeOrange = Color(0xFFFF9D3D)
val TougeRed = Color(0xFFFF4B3E)
val TougeBlue = Color(0xFF4B9EFF)
val TougeBackground = Color(0xFF050A0D)
val TougePanel = Color(0xFF0B1217)
val TougePanelLight = Color(0xFF111C23)
val TougeMuted = Color(0xFF8498A4)

private val TougeColors = darkColorScheme(
    primary = TougeCyan,
    secondary = TougeMint,
    tertiary = TougeOrange,
    error = TougeRed,
    background = TougeBackground,
    surface = TougePanel,
    surfaceVariant = TougePanelLight,
    onPrimary = Color.Black,
    onBackground = Color(0xFFF2FAFC),
    onSurface = Color(0xFFF2FAFC),
    onSurfaceVariant = TougeMuted
)

private val TougeLightColors = lightColorScheme(
    primary = Color(0xFF008F9D),
    secondary = Color(0xFF00985B),
    tertiary = Color(0xFFE05216),
    error = Color(0xFFD91F2B),
    background = Color(0xFFF0F6F8),
    surface = Color(0xFFFFFFFF),
    surfaceVariant = Color(0xFFE4EDF0),
    onPrimary = Color.Black,
    onBackground = Color(0xFF102027),
    onSurface = Color(0xFF102027),
    onSurfaceVariant = Color(0xFF526771),
    outline = Color(0xFFB4C3C9)
)

enum class AppTheme(val storedValue: String) {
    SYSTEM("system"),
    LIGHT("light"),
    DARK("dark");

    companion object {
        fun fromStoredValue(value: String?): AppTheme = entries.firstOrNull { it.storedValue == value } ?: SYSTEM
    }
}

object AppThemePreference {
    private const val PREFERENCES = "appearance"
    private const val KEY_THEME = "theme"

    fun read(context: Context): AppTheme = AppTheme.fromStoredValue(
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(KEY_THEME, null)
    )

    fun write(context: Context, theme: AppTheme) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_THEME, theme.storedValue)
            .apply()
    }
}

@Composable
fun TougeDashTheme(appTheme: AppTheme = AppTheme.SYSTEM, content: @Composable () -> Unit) {
    val darkTheme = when (appTheme) {
        AppTheme.SYSTEM -> isSystemInDarkTheme()
        AppTheme.LIGHT -> false
        AppTheme.DARK -> true
    }
    val colorScheme = if (darkTheme) TougeColors else TougeLightColors
    val view = LocalView.current
    val activity = LocalContext.current.findActivity()

    if (!view.isInEditMode && activity != null) {
        SideEffect {
            activity.window.statusBarColor = colorScheme.background.toArgb()
            activity.window.navigationBarColor = colorScheme.background.toArgb()
            WindowCompat.getInsetsController(activity.window, view).apply {
                isAppearanceLightStatusBars = !darkTheme
                isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    MaterialTheme(colorScheme = colorScheme, content = content)
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
