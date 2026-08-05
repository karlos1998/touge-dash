package it.letscode.tougedash.ui

import android.Manifest
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.BuildConfig
import it.letscode.tougedash.R
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.data.local.VehicleEntity
import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.DashboardAccent
import it.letscode.tougedash.model.DashboardTemplate
import it.letscode.tougedash.model.DashboardWidget
import it.letscode.tougedash.model.DashboardWidgetKind
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.model.TelemetrySnapshot
import it.letscode.tougedash.ui.theme.TougeBlue
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougeOrange
import it.letscode.tougedash.ui.theme.TougePanel
import it.letscode.tougedash.ui.theme.TougePanelLight
import it.letscode.tougedash.ui.theme.TougeRed
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts

@Composable
fun TougeDashApp(
    container: AppContainer,
    snapshot: TelemetrySnapshot,
    connection: TelemetryConnection,
    requestPermissions: () -> Unit,
    rescan: () -> Unit
) {
    var tab by remember { mutableIntStateOf(0) }
    var showConnection by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf(false) }
    var selectedSessionId by remember { mutableStateOf<String?>(null) }
    var showCamera by remember { mutableStateOf(false) }
    var vehicleToName by remember { mutableStateOf<VehicleEntity?>(null) }
    val vehicles by container.dao.vehicles().collectAsState(initial = emptyList())
    val context = LocalContext.current
    val namePrompts = remember { context.getSharedPreferences("vehicle-name-prompts", android.content.Context.MODE_PRIVATE) }
    LaunchedEffect(connection.hardwareId, vehicles) {
        val hardwareId = connection.hardwareId ?: return@LaunchedEffect
        val vehicle = vehicles.firstOrNull { it.localHardwareId == hardwareId } ?: return@LaunchedEffect
        if (!namePrompts.getBoolean(hardwareId, false)) vehicleToName = vehicle
    }
    val visibleSnapshot = if (preview && BuildConfig.DEBUG) TelemetrySnapshot.Preview else snapshot
    val landscape = LocalConfiguration.current.screenWidthDp > LocalConfiguration.current.screenHeightDp
    Scaffold(
        bottomBar = {
            NavigationBar(containerColor = TougePanel) {
                listOf(
                    Triple(R.string.dashboard, Icons.Default.DirectionsCar, 0),
                    Triple(R.string.history, Icons.Default.History, 1),
                    Triple(R.string.alerts, Icons.Default.Notifications, 2),
                    Triple(R.string.more, Icons.Default.MoreHoriz, 3)
                ).forEach { item ->
                    NavigationBarItem(selected = tab == item.third, onClick = { tab = item.third }, icon = { Icon(item.second, null) }, label = { Text(stringResource(item.first)) })
                }
            }
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).background(MaterialTheme.colorScheme.background)) {
            if (landscape) CompactAppHeader(connection, { showConnection = true }, { showCamera = true })
            else AppHeader(connection, { showConnection = true }, { showCamera = true })
            when (tab) {
                0 -> ConfigurableDashboardScreen(container, visibleSnapshot, connection, preview, { preview = it })
                1 -> HistoryScreen(container, selectedSessionId, { selectedSessionId = it }, { selectedSessionId = null })
                2 -> AlertsScreen(container, connection.hardwareId ?: "local-default")
                else -> MoreScreen(container)
            }
        }
    }
    if (showConnection) ConnectionDialog(connection, { showConnection = false }, requestPermissions, rescan)
    if (showCamera) DriveCameraScreen(container, { showCamera = false })
    vehicleToName?.let { vehicle ->
        VehicleNameDialog(container, vehicle) {
            namePrompts.edit().putBoolean(vehicle.localHardwareId, true).apply()
            vehicleToName = null
        }
    }
}

@Composable
private fun AppHeader(connection: TelemetryConnection, onConnection: () -> Unit, camera: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(38.dp).background(TougeCyan.copy(alpha = .12f), RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
            Text("⌁", color = TougeCyan, fontSize = 25.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.padding(start = 10.dp).weight(1f)) {
            Text("TOUGE DASH", fontWeight = FontWeight.Black, letterSpacing = 2.sp)
            Text("EMU BLACK / DRIVER DISPLAY", color = TougeMuted, fontSize = 9.sp, letterSpacing = 1.sp)
        }
        IconButton(onClick = camera, modifier = Modifier.size(38.dp)) { Icon(Icons.Default.Videocam, null, tint = TougeMuted) }
        Row(Modifier.clickable(onClick = onConnection).border(1.dp, if (connection.state == ConnectionState.Connected) TougeMint.copy(alpha = .5f) else TougeMuted.copy(alpha = .3f), RoundedCornerShape(18.dp)).padding(horizontal = 11.dp, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).background(if (connection.state == ConnectionState.Connected) TougeMint else TougeOrange, RoundedCornerShape(4.dp)))
            Text(connection.deviceName ?: connection.state.name.uppercase(), Modifier.padding(start = 7.dp), fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
    }
    HorizontalDivider(color = TougeMuted.copy(alpha = .12f))
}

@Composable
private fun CompactAppHeader(connection: TelemetryConnection, onConnection: () -> Unit, camera: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(58.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("TOUGE DASH", fontWeight = FontWeight.Black, letterSpacing = 2.sp)
        Text("  /  EMU BLACK", color = TougeMuted, fontSize = 9.sp)
        Spacer(Modifier.weight(1f))
        IconButton(onClick = camera) { Icon(Icons.Default.Videocam, null, tint = TougeMuted) }
        Row(Modifier.clickable(onClick = onConnection).border(1.dp, TougeMuted.copy(alpha = .3f), RoundedCornerShape(18.dp)).padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).background(if (connection.state == ConnectionState.Connected) TougeMint else TougeOrange, CircleShape))
            Text(connection.deviceName ?: connection.state.name.uppercase(), Modifier.padding(start = 6.dp), fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun DashboardScreen(snapshot: TelemetrySnapshot, connection: TelemetryConnection, preview: Boolean, setPreview: (Boolean) -> Unit) {
    val landscape = LocalConfiguration.current.screenWidthDp > LocalConfiguration.current.screenHeightDp
    val template = remember { DashboardTemplate.factory() }
    val widgets = template.definition.widgets.filter { (if (landscape) it.landscapeSpan else it.portraitSpan) > 0 }
        .sortedBy { if (landscape) it.landscapeOrder else it.portraitOrder }
    Column(Modifier.fillMaxSize()) {
        if (BuildConfig.DEBUG && connection.state != ConnectionState.Connected) {
            TextButton(onClick = { setPreview(!preview) }, modifier = Modifier.align(Alignment.End)) {
                Text(if (preview) "Hide preview" else stringResource(R.string.demo_data))
            }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(12),
            contentPadding = PaddingValues(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f)
        ) {
            items(widgets, key = { it.id }, span = { GridItemSpan(if (landscape) it.landscapeSpan else it.portraitSpan) }) {
                DashboardCard(it, snapshot, landscape)
            }
        }
    }
}

@Composable
internal fun DashboardCard(widget: DashboardWidget, snapshot: TelemetrySnapshot, landscape: Boolean) {
    val accent = widget.accent.color()
    val kind = if (landscape) widget.wideKind ?: widget.kind else widget.kind
    val height = if (landscape) {
        when (kind) {
            DashboardWidgetKind.GROUP -> 126.dp
            DashboardWidgetKind.COMPACT -> 88.dp
            else -> 105.dp
        }
    } else if (kind == DashboardWidgetKind.HERO) 265.dp else if (kind == DashboardWidgetKind.COMPACT) 92.dp else 164.dp
    Card(colors = CardDefaults.cardColors(containerColor = TougePanel), shape = RoundedCornerShape(3.dp), modifier = Modifier.fillMaxWidth().height(height)) {
        Box(Modifier.fillMaxSize().border(1.dp, accent.copy(alpha = .16f), RoundedCornerShape(3.dp)).padding(14.dp)) {
            when (kind) {
                DashboardWidgetKind.HERO -> HeroWidget(widget, snapshot, accent)
                DashboardWidgetKind.GROUP -> GroupWidget(widget, snapshot, accent)
                DashboardWidgetKind.GAUGE -> GaugeWidget(widget, snapshot, accent)
                else -> ValueWidget(widget.metrics.first(), snapshot, accent, widget.kind == DashboardWidgetKind.COMPACT)
            }
        }
    }
}

@Composable
private fun HeroWidget(widget: DashboardWidget, snapshot: TelemetrySnapshot, accent: Color) {
    val metric = widget.metrics.first()
    val value = metric.value(snapshot)
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.SpaceBetween) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(metric.shortName, color = TougeMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp)
            Text(stringResource(R.string.live_data).uppercase(), color = accent, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
        Column {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(metric.format(value), fontSize = 58.sp, lineHeight = 58.sp, fontWeight = FontWeight.Black)
                Text(metric.unit.uppercase(), Modifier.padding(start = 7.dp, bottom = 9.dp), color = accent, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
            val min = widget.gaugeMinimum ?: metric.defaultMin
            val max = widget.gaugeMaximum ?: metric.defaultMax
            val progress = ((value - min) / (max - min)).coerceIn(0.0, 1.0).toFloat()
            Box(Modifier.fillMaxWidth().height(7.dp).background(TougePanelLight, RoundedCornerShape(4.dp))) {
                Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(accent, RoundedCornerShape(4.dp)))
            }
            Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                widget.metrics.drop(1).take(3).forEach { InlineMetric(it, snapshot, accent) }
            }
        }
    }
}

@Composable
private fun InlineMetric(metric: TelemetryMetric, snapshot: TelemetrySnapshot, accent: Color) {
    Column {
        Text(metric.shortName, color = TougeMuted, fontSize = 8.sp, fontWeight = FontWeight.Bold)
        Text("${metric.format(metric.value(snapshot))} ${metric.unit}", color = accent, fontSize = 11.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun GroupWidget(widget: DashboardWidget, snapshot: TelemetrySnapshot, accent: Color) {
    Column(Modifier.fillMaxSize()) {
        Text((widget.title ?: stringResource(R.string.engine_health)).uppercase(), color = TougeMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp)
        Row(Modifier.fillMaxSize().padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            widget.metrics.forEach { metric ->
                Column(Modifier.weight(1f)) {
                    Text(metric.shortName, color = TougeMuted, fontSize = 8.sp, fontWeight = FontWeight.Bold)
                    Text(metric.format(metric.value(snapshot)), fontSize = 29.sp, fontWeight = FontWeight.Black, maxLines = 1)
                    Text(metric.unit, color = accent, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
private fun ValueWidget(metric: TelemetryMetric, snapshot: TelemetrySnapshot, accent: Color, compact: Boolean) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.SpaceBetween) {
        Text(metric.shortName, color = TougeMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(metric.format(metric.value(snapshot)), fontSize = if (compact) 24.sp else 35.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Clip)
            Text(metric.unit, Modifier.padding(start = 4.dp, bottom = 4.dp), color = accent, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun GaugeWidget(widget: DashboardWidget, snapshot: TelemetrySnapshot, accent: Color) {
    val metric = widget.metrics.first()
    val min = widget.gaugeMinimum ?: metric.defaultMin
    val max = widget.gaugeMaximum ?: metric.defaultMax
    val progress = ((metric.value(snapshot) - min) / (max - min)).coerceIn(0.0, 1.0).toFloat()
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxHeight(.75f).aspectRatio(1f)) {
            drawArc(TougePanelLight, 150f, 240f, false, style = Stroke(12.dp.toPx(), cap = StrokeCap.Round))
            drawArc(accent, 150f, 240f * progress, false, style = Stroke(12.dp.toPx(), cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(metric.shortName, color = TougeMuted, fontSize = 9.sp, fontWeight = FontWeight.Bold)
            Text(metric.format(metric.value(snapshot)), fontSize = 28.sp, fontWeight = FontWeight.Black)
            Text(metric.unit, color = accent, fontSize = 9.sp)
        }
    }
}

@Composable
private fun PlaceholderScreen(title: String, body: String, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(icon, null, Modifier.size(52.dp), tint = TougeCyan)
        Text(title, fontSize = 30.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(top = 16.dp))
        Text(body, color = TougeMuted, modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun MoreScreen(container: AppContainer) {
    val context = LocalContext.current
    val vehicles by container.dao.vehicles().collectAsState(initial = emptyList())
    var rename by remember { mutableStateOf<VehicleEntity?>(null) }
    var routeEnabled by remember { mutableStateOf(container.locationTracker.isEnabled) }
    val locationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        routeEnabled = granted
        container.locationTracker.setEnabled(granted)
    }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.more), fontSize = 30.sp, fontWeight = FontWeight.Black)
            Card(Modifier.fillMaxWidth().padding(top = 14.dp), colors = CardDefaults.cardColors(containerColor = TougePanel)) {
                Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(appText("Record route", "Zapisuj trasę"), fontWeight = FontWeight.Bold)
                        Text(appText("Optional GPS track stored with drive history", "Opcjonalny ślad GPS zapisany z historią przejazdu"), color = TougeMuted, fontSize = 11.sp)
                    }
                    Switch(routeEnabled, { enabled ->
                        if (enabled) locationPermission.launch(Manifest.permission.ACCESS_FINE_LOCATION)
                        else { routeEnabled = false; container.locationTracker.setEnabled(false) }
                    })
                }
            }
            if (vehicles.isNotEmpty()) {
                Text(appText("GARAGE", "GARAŻ"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp))
                vehicles.forEach { vehicle ->
                    Card(
                        Modifier.fillMaxWidth().padding(top = 7.dp).clickable { rename = vehicle },
                        colors = CardDefaults.cardColors(containerColor = TougePanel)
                    ) {
                        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.DirectionsCar, null, tint = TougeMint)
                            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                                Text(vehicle.displayName, fontWeight = FontWeight.Black)
                                Text(vehicle.localHardwareId, color = TougeMuted, fontSize = 10.sp, maxLines = 1)
                            }
                            Icon(Icons.Default.Edit, null, tint = TougeCyan)
                        }
                    }
                }
            }
            CloudAccountCard(container)
            if (BuildConfig.DEBUG) Text("DEV API • ${BuildConfig.API_BASE_URL}", color = TougeMuted, fontSize = 10.sp, modifier = Modifier.padding(top = 10.dp))
        }
        Row(Modifier.fillMaxWidth().clickable { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://letscode.it"))) }.padding(vertical = 18.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.made_by), color = TougeMuted)
            Text("  ♥  ", color = TougeRed)
            Text(stringResource(R.string.by_lets_code_it), color = TougeCyan)
        }
    }
    rename?.let { vehicle -> VehicleNameDialog(container, vehicle) { rename = null } }
}

@Composable
private fun VehicleNameDialog(container: AppContainer, vehicle: VehicleEntity, dismiss: () -> Unit) {
    var value by remember(vehicle.localHardwareId) { mutableStateOf(vehicle.displayName) }
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(appText("Name this car", "Nazwij to auto")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(appText("Touge Dash recognizes each car by its Bluetooth interface. You can change this name at any time.", "Touge Dash rozpoznaje każde auto po interfejsie Bluetooth. Nazwę możesz zmienić w dowolnym momencie."), color = TougeMuted)
                OutlinedTextField(value, { value = it.take(120) }, label = { Text(appText("Vehicle name", "Nazwa auta")) }, singleLine = true)
            }
        },
        confirmButton = {
            Button(enabled = value.isNotBlank(), onClick = { scope.launch { container.cloudSyncRepository.renameVehicle(vehicle, value); dismiss() } }) { Text(appText("Save", "Zapisz")) }
        },
        dismissButton = { TextButton(onClick = dismiss) { Text(appText("Later", "Później")) } }
    )
}

@Composable
private fun ConnectionDialog(connection: TelemetryConnection, close: () -> Unit, permissions: () -> Unit, rescan: () -> Unit) {
    AlertDialog(
        onDismissRequest = close,
        title = { Text(stringResource(R.string.connection_details)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(connection.deviceName ?: connection.state.name, fontWeight = FontWeight.Bold)
                connection.hardwareId?.let { Text(it, color = TougeMuted, fontSize = 12.sp) }
                connection.message?.let { Text(it) }
                Text("Frames ${connection.validFrames} • checksum ${connection.badChecksums} • dropped ${connection.droppedBytes}", color = TougeMuted, fontSize = 12.sp)
                if (connection.state == ConnectionState.PermissionRequired) Text(stringResource(R.string.permissions_explanation))
            }
        },
        confirmButton = {
            Button(onClick = if (connection.state == ConnectionState.PermissionRequired) permissions else rescan) {
                Text(if (connection.state == ConnectionState.PermissionRequired) stringResource(R.string.allow_permissions) else stringResource(R.string.rescan))
            }
        },
        dismissButton = { TextButton(onClick = close) { Text(stringResource(R.string.close)) } }
    )
}

internal fun DashboardAccent.color(): Color = when (this) {
    DashboardAccent.CYAN -> TougeCyan
    DashboardAccent.MINT -> TougeMint
    DashboardAccent.BLUE, DashboardAccent.ICE -> TougeBlue
    DashboardAccent.ORANGE -> TougeOrange
    DashboardAccent.YELLOW -> Color(0xFFFFC83D)
    DashboardAccent.RED -> TougeRed
    DashboardAccent.WHITE -> Color.White
}

internal fun TelemetryMetric.format(value: Double): String = when (precision) {
    0 -> value.roundToInt().toString()
    1 -> String.format(Locale.getDefault(), "%.1f", value)
    else -> String.format(Locale.getDefault(), "%.2f", value)
}
