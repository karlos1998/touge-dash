package it.letscode.tougedash.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.intl.Locale

@Composable
internal fun appText(english: String, polish: String): String =
    if (Locale.current.language == "pl") polish else english
