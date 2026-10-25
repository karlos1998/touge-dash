package it.letscode.tougedash.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.model.DashboardWidget
import it.letscode.tougedash.telemetry.EcuControlError
import it.letscode.tougedash.telemetry.EcuControlKind
import it.letscode.tougedash.telemetry.EcuControlSnapshot
import it.letscode.tougedash.telemetry.EcuControlState

@Composable
internal fun EcuSwitchCard(
    widget: DashboardWidget,
    state: EcuControlState,
    landscape: Boolean,
    interactionEnabled: Boolean,
    toggle: (Int) -> Boolean
) {
    val channel = (widget.controlChannel ?: 1).coerceIn(EcuControlSnapshot.CHANNEL_RANGE)
    val value = state.switchValue(channel)
    val pending = state.pending?.kind == EcuControlKind.SWITCH && state.pending.channel == channel
    val accent = widget.accent.color()
    val title = widget.title?.takeIf { it.isNotBlank() } ?: "BT SWITCH $channel"
    val stateTitle = when (value) {
        true -> appText("ON", "WŁĄCZONY")
        false -> appText("OFF", "WYŁĄCZONY")
        null -> "—"
    }
    val status = ecuControlStatus(state, pending)
    val statusColor = ecuControlStatusColor(state, pending)
    @Composable fun header() {
        Text(title.uppercase(), color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, maxLines = 1)
    }
    @Composable fun statusLabel() {
        Text(status, color = statusColor, fontSize = 8.sp, fontWeight = FontWeight.Black,
            letterSpacing = .55.sp, maxLines = 2)
    }
    @Composable fun control() {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(stateTitle, color = if (value == true) accent else MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Switch(
                checked = value == true,
                onCheckedChange = { requested ->
                    if (value != null && requested != value) toggle(channel)
                },
                enabled = interactionEnabled && state.ready && value != null,
                modifier = Modifier.testTag("ecu-switch-$channel").semantics {
                    contentDescription = "$title, BT Switch $channel"
                },
                colors = SwitchDefaults.colors(
                    checkedThumbColor = MaterialTheme.colorScheme.surface,
                    checkedTrackColor = accent,
                    uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    uncheckedTrackColor = MaterialTheme.colorScheme.surfaceVariant
                )
            )
        }
    }
    TougePanelSurface(accent, Modifier.fillMaxWidth().height(if (landscape) 126.dp else 145.dp)) {
        BoxWithConstraints(Modifier.fillMaxSize().padding(if (landscape) 11.dp else 15.dp)) {
            if (maxWidth < 220.dp) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.SpaceBetween) {
                    header()
                    control()
                    statusLabel()
                }
            } else {
                Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        header()
                        statusLabel()
                    }
                    control()
                }
            }
        }
    }
}

@Composable
internal fun EcuRotaryCard(
    widget: DashboardWidget,
    state: EcuControlState,
    landscape: Boolean,
    interactionEnabled: Boolean,
    select: (Int, Int) -> Boolean
) {
    val channel = (widget.controlChannel ?: 1).coerceIn(EcuControlSnapshot.CHANNEL_RANGE)
    val value = state.rotaryValue(channel)
    val pending = state.pending?.kind == EcuControlKind.ROTARY && state.pending.channel == channel
    val accent = widget.accent.color()
    var menu by remember(widget.id) { mutableStateOf(false) }
    TougePanelSurface(accent, Modifier.fillMaxWidth().height(if (landscape) 126.dp else 145.dp)) {
        Box {
            Row(
                Modifier.fillMaxSize()
                    .clickable(enabled = interactionEnabled && state.ready) { menu = true }
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text((widget.title?.takeIf { it.isNotBlank() } ?: "BT ROTARY $channel").uppercase(), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, maxLines = 1)
                    Text(value?.toString() ?: "—", color = accent, fontSize = if (landscape) 28.sp else 39.sp, fontWeight = FontWeight.Black)
                    Text(ecuControlStatus(state, pending), color = ecuControlStatusColor(state, pending), fontSize = 8.sp, fontWeight = FontWeight.Black, letterSpacing = .55.sp, maxLines = 1)
                }
                Text("↕", color = if (state.ready) accent else MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 28.sp, fontWeight = FontWeight.Black)
            }
            DropdownMenu(menu, { menu = false }, modifier = Modifier.align(Alignment.TopEnd)) {
                EcuControlSnapshot.ROTARY_RANGE.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(if (option == value) "✓  $option" else option.toString()) },
                        onClick = { menu = false; select(channel, option) }
                    )
                }
            }
        }
    }
}

@Composable
private fun ecuControlStatus(state: EcuControlState, pending: Boolean): String = when {
    pending -> appText("SENDING WHOLE STATE", "WYSYŁANIE PEŁNEGO STANU")
    state.pending != null -> appText("WAITING FOR EMU", "OCZEKIWANIE NA EMU")
    !state.connected -> appText("DISCONNECTED", "BRAK POŁĄCZENIA")
    !state.transportAvailable -> appText("READ ONLY", "TYLKO ODCZYT")
    !state.applicationActive -> appText("APP IN BACKGROUND", "APLIKACJA W TLE")
    !state.synchronizedLoopback -> appText("WAITING FOR CHANNELS", "CZEKAM NA KANAŁY") +
        " " + state.missingLoopbackChannels.joinToString(", ")
    state.error != null -> when (state.error) {
        EcuControlError.WRITE_REJECTED -> appText("WRITE FAILED", "BŁĄD WYSYŁANIA")
        EcuControlError.CONFIRMATION_TIMEOUT -> appText("NO ECU CONFIRMATION", "BRAK POTWIERDZENIA ECU")
        EcuControlError.BACKGROUND -> appText("CANCELLED IN BACKGROUND", "PRZERWANO W TLE")
        EcuControlError.TRANSPORT_LOST -> appText("CONTROL CHANNEL LOST", "UTRACONO KANAŁ STEROWANIA")
    }
    else -> appText("CONFIRMED BY EMU", "POTWIERDZONE PRZEZ EMU")
}

@Composable
private fun ecuControlStatusColor(state: EcuControlState, pending: Boolean): Color = when {
    state.error != null -> MaterialTheme.colorScheme.error
    pending || state.pending != null -> MaterialTheme.colorScheme.tertiary
    state.ready -> MaterialTheme.colorScheme.secondary
    else -> MaterialTheme.colorScheme.onSurfaceVariant
}
