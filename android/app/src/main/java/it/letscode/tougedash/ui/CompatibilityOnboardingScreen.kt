package it.letscode.tougedash.ui

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object CompatibilityOnboardingPreference {
    private const val PREFERENCES = "compatibility-onboarding"
    private const val KEY_ACCEPTED = "accepted-v1"

    fun read(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(KEY_ACCEPTED, false)

    fun accept(context: Context) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ACCEPTED, true)
            .apply()
    }
}

@Composable
fun CompatibilityOnboardingScreen(onContinue: () -> Unit) {
    var confirmed by remember { mutableStateOf(false) }

    DashboardBackdrop {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.Center
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(22.dp)
            ) {
                Box(
                    Modifier
                        .size(64.dp)
                        .background(
                            MaterialTheme.colorScheme.primary.copy(alpha = .12f),
                            RoundedCornerShape(16.dp)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Default.SettingsInputAntenna,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(32.dp)
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        appText("BEFORE YOU START", "ZANIM ZACZNIESZ"),
                        color = MaterialTheme.colorScheme.primary,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = 1.5.sp
                    )
                    Text(
                        appText("Touge Dash is not an OBD2 app", "Touge Dash nie jest aplikacją OBD2"),
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Black
                    )
                    Text(
                        appText(
                            "This app is for ECUMaster users and connects to a Data Logger EDL-1 that supports Bluetooth Low Energy (BLE).",
                            "Aplikacja jest przeznaczona dla użytkowników ECUMaster i łączy się z Data Loggerem EDL-1 obsługującym Bluetooth Low Energy (BLE)."
                        ),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .56f),
                    shape = RoundedCornerShape(18.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(15.dp)
                    ) {
                        RequirementRow(
                            Icons.Default.SettingsInputAntenna,
                            appText(
                                "Required: ECUMaster Data Logger EDL-1 with BLE",
                                "Wymagany: ECUMaster Data Logger EDL-1 z BLE"
                            )
                        )
                        RequirementRow(
                            Icons.Default.DirectionsCar,
                            appText(
                                "This is not a universal interface for every vehicle",
                                "To nie jest uniwersalny interfejs do każdego auta"
                            )
                        )
                        RequirementRow(
                            Icons.Default.CheckCircle,
                            appText(
                                "The app does not read data from the OBD2 port",
                                "Aplikacja nie odczytuje danych z gniazda OBD2"
                            )
                        )
                    }
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { confirmed = !confirmed },
                    verticalAlignment = Alignment.Top
                ) {
                    Checkbox(checked = confirmed, onCheckedChange = { confirmed = it })
                    Text(
                        appText(
                            "I understand the requirements and have a compatible Data Logger EDL-1 with BLE.",
                            "Rozumiem wymagania i mam zgodny Data Logger EDL-1 z BLE."
                        ),
                        modifier = Modifier.padding(top = 12.dp),
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Button(
                    onClick = onContinue,
                    enabled = confirmed,
                    modifier = Modifier.fillMaxWidth().height(54.dp)
                ) {
                    Text(
                        appText("Continue to the app", "Przejdź do aplikacji"),
                        fontWeight = FontWeight.Black
                    )
                }
            }
        }
    }
}

@Composable
private fun RequirementRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(20.dp)
        )
        Spacer(Modifier.size(12.dp))
        Text(text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}
