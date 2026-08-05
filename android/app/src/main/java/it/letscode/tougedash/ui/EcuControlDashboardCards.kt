package it.letscode.tougedash.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.model.DashboardWidget
import it.letscode.tougedash.telemetry.EcuControlError
import it.letscode.tougedash.telemetry.EcuControlKind
import it.letscode.tougedash.telemetry.EcuControlSnapshot
import it.letscode.tougedash.telemetry.EcuControlState
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougeRed

@Composable
internal fun EcuSwitchCard(
    widget: DashboardWidget,
    state: EcuControlState,
    landscape: Boolean,
    interactionEnabled: Boolean,
    toggle: (Int) -> Boolean
) {
    val channel = (widget.controlChannel ?: 1).coerceIn(EcuControlSnapshot.CHANNEL_RANGE)
    val value = state.displayed?.switchValue(channel)
    val pending = state.pending?.kind == EcuControlKind.SWITCH && state.pending.channel == channel
    val accent = widget.accent.color()
    TougePanelSurface(accent, Modifier.fillMaxWidth().height(if (landscape) 126.dp else 145.dp)) {
        Row(
            Modifier.fillMaxSize()
                .clickable(enabled = interactionEnabled && state.ready) { toggle(channel) }
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text((widget.title?.takeIf { it.isNotBlank() } ?: "BT SWITCH $channel").uppercase(), color = TougeMuted, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, maxLines = 1)
                Text(
                    when (value) { true -> appText("ON", "WŁĄCZONY"); false -> appText("OFF", "WYŁĄCZONY"); null -> "—" },
                    color = if (value == true) accent else Color.White,
                    fontSize = if (landscape) 25.sp else 34.sp,
                    fontWeight = FontWeight.Black
                )
                Text(ecuControlStatus(state, pending), color = ecuControlStatusColor(state, pending), fontSize = 8.sp, fontWeight = FontWeight.Black, letterSpacing = .55.sp, maxLines = 1)
            }
            Box(
                Modifier.size(width = 64.dp, height = 36.dp)
                    .background(if (value == true) accent.copy(alpha = .3f) else Color.White.copy(alpha = .08f), RoundedCornerShape(20.dp)),
                contentAlignment = if (value == true) Alignment.CenterEnd else Alignment.CenterStart
            ) {
                Box(Modifier.padding(4.dp).size(28.dp).background(if (value == true) accent else TougeMuted, CircleShape))
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
    val value = state.displayed?.rotaryValue(channel)
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
                    Text((widget.title?.takeIf { it.isNotBlank() } ?: "BT ROTARY $channel").uppercase(), color = TougeMuted, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, maxLines = 1)
                    Text(value?.toString() ?: "—", color = accent, fontSize = if (landscape) 28.sp else 39.sp, fontWeight = FontWeight.Black)
                    Text(ecuControlStatus(state, pending), color = ecuControlStatusColor(state, pending), fontSize = 8.sp, fontWeight = FontWeight.Black, letterSpacing = .55.sp, maxLines = 1)
                }
                Text("↕", color = if (state.ready) accent else TougeMuted, fontSize = 28.sp, fontWeight = FontWeight.Black)
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
    pending -> appText("WAITING FOR EMU", "OCZEKIWANIE NA EMU")
    !state.connected -> appText("DISCONNECTED", "BRAK POŁĄCZENIA")
    !state.transportAvailable -> appText("READ ONLY", "TYLKO ODCZYT")
    !state.applicationActive -> appText("APP IN BACKGROUND", "APLIKACJA W TLE")
    !state.freshLoopback -> appText("SYNCING ECU", "SYNCHRONIZACJA ECU")
    state.error != null -> when (state.error) {
        EcuControlError.WRITE_REJECTED -> appText("WRITE FAILED", "BŁĄD WYSYŁANIA")
        EcuControlError.CONFIRMATION_TIMEOUT -> appText("NO ECU CONFIRMATION", "BRAK POTWIERDZENIA ECU")
        EcuControlError.BACKGROUND -> appText("CANCELLED IN BACKGROUND", "PRZERWANO W TLE")
        EcuControlError.TRANSPORT_LOST -> appText("CONTROL CHANNEL LOST", "UTRACONO KANAŁ STEROWANIA")
    }
    else -> appText("CONFIRMED BY EMU", "POTWIERDZONE PRZEZ EMU")
}

private fun ecuControlStatusColor(state: EcuControlState, pending: Boolean): Color = when {
    state.error != null -> TougeRed
    pending -> Color(0xFFFF9D3D)
    state.ready -> TougeMint
    else -> TougeMuted
}
