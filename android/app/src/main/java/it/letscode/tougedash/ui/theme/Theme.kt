package it.letscode.tougedash.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

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

@Composable
fun TougeDashTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = TougeColors, content = content)
}
