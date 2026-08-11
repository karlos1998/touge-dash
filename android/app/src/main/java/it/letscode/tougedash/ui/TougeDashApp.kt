package it.letscode.tougedash.ui

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarDefaults
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.BuildConfig
import it.letscode.tougedash.R
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.data.local.VehicleEntity
import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.DashboardAccent
import it.letscode.tougedash.model.DashboardWidget
import it.letscode.tougedash.model.DashboardWidgetKind
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.model.TelemetrySnapshot
import it.letscode.tougedash.model.VehicleAlertRules
import it.letscode.tougedash.telemetry.TelemetryRuntime
import it.letscode.tougedash.telemetry.TelemetryOverlayPreferences
import it.letscode.tougedash.telemetry.TelemetryService
import it.letscode.tougedash.ui.theme.TougeBlue
import it.letscode.tougedash.ui.theme.AppTheme
import it.letscode.tougedash.video.DriveVideoQuality
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.delay

@Composable
fun TougeDashApp(
    container: AppContainer,
    snapshot: TelemetrySnapshot,
    connection: TelemetryConnection,
    appTheme: AppTheme,
    onAppThemeChanged: (AppTheme) -> Unit,
    requestPermissions: () -> Unit,
    rescan: () -> Unit
) {
    var tab by remember { mutableIntStateOf(0) }
    var showConnection by remember { mutableStateOf(false) }
    var selectedSessionId by remember { mutableStateOf<String?>(null) }
    var dashboardNavigationVisible by remember { mutableStateOf(false) }
    var dashboardEditing by remember { mutableStateOf(false) }
    var vehicleToName by remember { mutableStateOf<VehicleEntity?>(null) }
    val vehicles by container.dao.vehicles().collectAsState(initial = emptyList())
    val context = LocalContext.current
    val rootView = LocalView.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val videoSettings by container.videoRecordingSettings.settings.collectAsState()
    val namePrompts = remember { context.getSharedPreferences("vehicle-name-prompts", android.content.Context.MODE_PRIVATE) }
    androidx.compose.runtime.DisposableEffect(lifecycleOwner, container) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> container.ecuControls.applicationActive(true)
                Lifecycle.Event.ON_PAUSE, Lifecycle.Event.ON_STOP -> container.ecuControls.applicationActive(false)
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        container.ecuControls.applicationActive(lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    androidx.compose.runtime.DisposableEffect(rootView, connection.state, videoSettings.automaticRecording) {
        rootView.keepScreenOn = connection.state == ConnectionState.Connected || videoSettings.automaticRecording
        onDispose { rootView.keepScreenOn = false }
    }
    LaunchedEffect(connection.hardwareId, vehicles) {
        val hardwareId = connection.hardwareId ?: return@LaunchedEffect
        val vehicle = vehicles.firstOrNull { it.localHardwareId == hardwareId } ?: return@LaunchedEffect
        if (!namePrompts.getBoolean(hardwareId, false)) vehicleToName = vehicle
    }
    LaunchedEffect(videoSettings.automaticRecording, connection.state, lifecycleOwner) {
        if (!videoSettings.automaticRecording) {
            container.cameraRecordingController.stopWhenSessionEnds(null)
            return@LaunchedEffect
        }
        while (videoSettings.automaticRecording) {
            val sessionId = container.historyRepository.activeSessionId()
            val activeVideoSessionId = sessionId.takeIf { connection.state == ConnectionState.Connected }
            container.cameraRecordingController.stopWhenSessionEnds(activeVideoSessionId)
            if (activeVideoSessionId != null) {
                container.cameraRecordingController.ensureAutomaticRecording(lifecycleOwner, activeVideoSessionId)
            }
            delay(500)
        }
    }
    LaunchedEffect(dashboardNavigationVisible, tab, dashboardEditing) {
        if (dashboardNavigationVisible && tab == 0 && !dashboardEditing) {
            delay(5000)
            dashboardNavigationVisible = false
        }
    }
    val landscape = LocalConfiguration.current.screenWidthDp > LocalConfiguration.current.screenHeightDp
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentColor = MaterialTheme.colorScheme.onBackground,
        bottomBar = {
            if (tab != 0) AppNavigationBar(tab, landscape) { tab = it }
        }
    ) { padding ->
        DashboardBackdrop(Modifier.padding(padding)) {
            Column(Modifier.fillMaxSize()) {
                if (tab == 0) DriverDashboardHeader(
                    connection = connection,
                    landscape = landscape,
                    onConnection = { showConnection = true },
                    dashboardEditing = dashboardEditing,
                    toggleDashboardEditor = {
                        dashboardNavigationVisible = false
                        dashboardEditing = !dashboardEditing
                    },
                    showNavigation = { dashboardNavigationVisible = true }
                ) else if (landscape) CompactAppHeader(connection) { showConnection = true }
                else AppHeader(connection) { showConnection = true }
                when (tab) {
                    0 -> ConfigurableDashboardScreen(container, snapshot, connection.hardwareId, dashboardEditing)
                    1 -> HistoryScreen(container, selectedSessionId, { selectedSessionId = it }, { selectedSessionId = null })
                    2 -> AlertsScreen(container, connection.hardwareId)
                    else -> MoreScreen(container, appTheme, onAppThemeChanged)
                }
            }
            if (tab == 0 && !dashboardEditing) DashboardNavigationOverlay(
                expanded = dashboardNavigationVisible,
                landscape = landscape,
                reveal = { dashboardNavigationVisible = true },
                hide = { dashboardNavigationVisible = false },
                navigate = {
                    dashboardNavigationVisible = false
                    tab = it
                }
            )
        }
    }
    if (showConnection) ConnectionDialog(connection, { showConnection = false }, requestPermissions, rescan)
    vehicleToName?.let { vehicle ->
        VehicleNameDialog(container, vehicle) {
            namePrompts.edit().putBoolean(vehicle.localHardwareId, true).apply()
            vehicleToName = null
        }
    }
}

@Composable
private fun AppNavigationBar(selectedTab: Int, landscape: Boolean, overlay: Boolean = false, navigate: (Int) -> Unit) {
    val navigationItems: @Composable RowScope.() -> Unit = {
        listOf(
            Triple(R.string.dashboard, Icons.Default.DirectionsCar, 0),
            Triple(R.string.history, Icons.Default.History, 1),
            Triple(R.string.alerts, Icons.Default.Notifications, 2),
            Triple(R.string.more, Icons.Default.MoreHoriz, 3)
        ).forEach { item ->
            NavigationBarItem(
                selected = selectedTab == item.third,
                onClick = { navigate(item.third) },
                icon = { Icon(item.second, null, modifier = Modifier.size(if (landscape) 19.dp else 24.dp)) },
                label = { Text(stringResource(item.first), fontSize = if (landscape) 9.sp else 12.sp, fontWeight = if (selectedTab == item.third) FontWeight.Black else FontWeight.SemiBold) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = MaterialTheme.colorScheme.primary,
                    selectedTextColor = MaterialTheme.colorScheme.onSurface,
                    indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = .12f),
                    unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                )
            )
        }
    }
    if (overlay) {
        NavigationBar(
            containerColor = Color.Transparent,
            tonalElevation = 0.dp,
            windowInsets = WindowInsets(0, 0, 0, 0),
            modifier = Modifier.fillMaxWidth().height(if (landscape) 58.dp else 72.dp),
            content = navigationItems
        )
    } else {
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
            color = MaterialTheme.colorScheme.surface.copy(alpha = .98f),
            tonalElevation = 2.dp,
            shadowElevation = 7.dp
        ) {
            NavigationBar(
                containerColor = Color.Transparent,
                tonalElevation = 0.dp,
                windowInsets = NavigationBarDefaults.windowInsets,
                content = navigationItems
            )
        }
    }
}

@Composable
private fun DashboardNavigationOverlay(
    expanded: Boolean,
    landscape: Boolean,
    reveal: () -> Unit,
    hide: () -> Unit,
    navigate: (Int) -> Unit
) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        androidx.compose.animation.AnimatedVisibility(
            visible = !expanded,
            modifier = Modifier.fillMaxWidth().height(if (landscape) 28.dp else 38.dp),
            enter = fadeIn(tween(220)),
            exit = fadeOut(tween(100))
        ) {
            Box(
                Modifier.fillMaxSize().pointerInput(Unit) {
                    var drag = 0f
                    detectVerticalDragGestures(
                        onDragStart = { drag = 0f },
                        onVerticalDrag = { _, amount ->
                            drag += amount
                            if (drag < -24f) reveal()
                        }
                    )
                },
                contentAlignment = Alignment.BottomCenter
            ) {
                Box(
                    Modifier.padding(bottom = 4.dp)
                        .width(if (landscape) 92.dp else 112.dp)
                        .height(if (landscape) 24.dp else 30.dp)
                        .background(MaterialTheme.colorScheme.surface.copy(alpha = .92f), RoundedCornerShape(18.dp))
                        .border(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = .26f), RoundedCornerShape(18.dp))
                        .clickable(onClick = reveal),
                    contentAlignment = Alignment.Center
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            appText("NAVIGATION", "NAWIGACJA"),
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = .82f),
                            fontSize = if (landscape) 7.sp else 8.sp,
                            fontWeight = FontWeight.Black,
                            letterSpacing = .8.sp
                        )
                        Text("  ↑", color = MaterialTheme.colorScheme.primary, fontSize = if (landscape) 11.sp else 13.sp, fontWeight = FontWeight.Black)
                    }
                }
            }
        }
        androidx.compose.animation.AnimatedVisibility(
            visible = expanded,
            modifier = Modifier.fillMaxWidth(),
            enter = slideInVertically(tween(240)) { it } + fadeIn(tween(160)),
            exit = slideOutVertically(tween(220)) { it } + fadeOut(tween(180))
        ) {
            Column(
                Modifier.fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = .98f), RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                    .pointerInput(Unit) {
                        var drag = 0f
                        detectVerticalDragGestures(
                            onDragStart = { drag = 0f },
                            onVerticalDrag = { _, amount ->
                                drag += amount
                                if (drag > 28f) hide()
                            }
                        )
                    }
            ) {
                Box(
                    Modifier.fillMaxWidth().height(if (landscape) 18.dp else 24.dp).clickable(onClick = hide),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.KeyboardArrowDown, null, tint = MaterialTheme.colorScheme.primary.copy(alpha = .72f), modifier = Modifier.size(if (landscape) 16.dp else 19.dp))
                }
                AppNavigationBar(0, landscape, overlay = true, navigate = navigate)
            }
        }
    }
}

@Composable
private fun DriverDashboardHeader(
    connection: TelemetryConnection,
    landscape: Boolean,
    onConnection: () -> Unit,
    dashboardEditing: Boolean,
    toggleDashboardEditor: () -> Unit,
    showNavigation: () -> Unit
) {
    val controlSize = if (landscape) 30.dp else 34.dp
    val touchSize = if (landscape) 38.dp else 44.dp
    Row(
        Modifier.fillMaxWidth().height(if (landscape) 38.dp else 44.dp).padding(horizontal = if (landscape) 14.dp else 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier.clickable(onClick = onConnection)
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .72f), RoundedCornerShape(18.dp))
                .border(1.dp, if (connection.state == ConnectionState.Connected) MaterialTheme.colorScheme.secondary.copy(alpha = .3f) else MaterialTheme.colorScheme.outline.copy(alpha = .45f), RoundedCornerShape(18.dp))
                .padding(horizontal = 10.dp, vertical = if (landscape) 5.dp else 7.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(Modifier.size(7.dp).background(if (connection.state == ConnectionState.Connected) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.error, CircleShape))
            Text(
                connection.deviceName ?: connection.state.localizedLabel().uppercase(),
                Modifier.padding(start = 7.dp),
                fontSize = if (landscape) 9.sp else 10.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }
        Spacer(Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(if (landscape) 8.dp else 10.dp)) {
            Box(
                Modifier.size(touchSize).clickable(onClick = toggleDashboardEditor),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    Modifier.size(controlSize).background(if (dashboardEditing) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .72f), RoundedCornerShape(10.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        if (dashboardEditing) Icons.Default.Done else Icons.Default.Edit,
                        null,
                        tint = if (dashboardEditing) Color.Black else MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(if (landscape) 16.dp else 18.dp)
                    )
                }
            }
            Box(
                Modifier.size(touchSize).clickable(onClick = showNavigation),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    Modifier.size(controlSize).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .72f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.MoreHoriz, stringResource(R.string.more), tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(if (landscape) 18.dp else 20.dp))
                }
            }
        }
    }
}

@Composable
private fun AppHeader(
    connection: TelemetryConnection,
    onConnection: () -> Unit
) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(
            Modifier.size(44.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = .12f), CutCornerShape(9.dp)).border(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = .10f), CutCornerShape(9.dp)),
            contentAlignment = Alignment.Center
        ) {
            DashboardLogoMark(Modifier.size(27.dp))
        }
        Column(Modifier.padding(start = 12.dp).weight(1f)) {
            Text("TOUGE DASH", fontSize = 18.sp, fontWeight = FontWeight.Black, letterSpacing = 2.1.sp)
            Text("EMU BLACK  /  DRIVER DISPLAY", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 8.sp, fontWeight = FontWeight.Bold, letterSpacing = .9.sp, maxLines = 1)
        }
        Row(Modifier.padding(start = 8.dp).clickable(onClick = onConnection).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .72f), RoundedCornerShape(22.dp)).border(1.dp, if (connection.state == ConnectionState.Connected) MaterialTheme.colorScheme.secondary.copy(alpha = .32f) else MaterialTheme.colorScheme.outline.copy(alpha = .45f), RoundedCornerShape(22.dp)).padding(horizontal = 11.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).background(if (connection.state == ConnectionState.Connected) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.error, CircleShape))
            Text(connection.deviceName ?: connection.state.localizedLabel().uppercase(), Modifier.padding(start = 7.dp), fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
    }
}

@Composable
private fun CompactAppHeader(
    connection: TelemetryConnection,
    onConnection: () -> Unit
) {
    Row(Modifier.fillMaxWidth().height(40.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(28.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = .12f), CutCornerShape(7.dp)), contentAlignment = Alignment.Center) { DashboardLogoMark(Modifier.size(18.dp)) }
        Text("TOUGE DASH", Modifier.padding(start = 10.dp), fontWeight = FontWeight.Black, letterSpacing = 2.sp)
        Text("  /  EMU BLACK", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 8.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        Row(Modifier.clickable(onClick = onConnection).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .72f), RoundedCornerShape(18.dp)).border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = .45f), RoundedCornerShape(18.dp)).padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).background(if (connection.state == ConnectionState.Connected) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.error, CircleShape))
            Text(connection.deviceName ?: connection.state.localizedLabel().uppercase(), Modifier.padding(start = 6.dp), fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun DashboardLogoMark(modifier: Modifier = Modifier) {
    val logoColor = MaterialTheme.colorScheme.primary
    Canvas(modifier) {
        val points = listOf(
            Offset(0f, size.height * .55f), Offset(size.width * .22f, size.height * .55f),
            Offset(size.width * .32f, size.height * .18f), Offset(size.width * .46f, size.height * .86f),
            Offset(size.width * .60f, size.height * .35f), Offset(size.width * .72f, size.height * .55f),
            Offset(size.width, size.height * .55f)
        )
        points.zipWithNext().forEach { (start, end) -> drawLine(logoColor, start, end, strokeWidth = 3.dp.toPx(), cap = StrokeCap.Round) }
    }
}

@Composable
internal fun DashboardCard(widget: DashboardWidget, snapshot: TelemetrySnapshot, landscape: Boolean, rules: VehicleAlertRules = VehicleAlertRules()) {
    val accent = widget.accent.color()
    val kind = dashboardDisplayKind(widget, landscape)
    val screenHeightDp = LocalConfiguration.current.screenHeightDp
    val fontScale = LocalDensity.current.fontScale
    val compactLandscape = landscape && screenHeightDp < 600
    val fittedPortrait = !landscape && screenHeightDp < 850
    val height = if (landscape) {
        when (kind) {
            DashboardWidgetKind.HERO -> if (compactLandscape) 154.dp else 210.dp
            DashboardWidgetKind.GROUP -> if (compactLandscape) 112.dp else 178.dp
            DashboardWidgetKind.COMPACT -> if (compactLandscape) 68.dp else 76.dp
            DashboardWidgetKind.GAUGE -> if (compactLandscape) 110.dp else 180.dp
            DashboardWidgetKind.PERFORMANCE -> if (compactLandscape) 118.dp else 188.dp
            else -> if (compactLandscape) 116.dp else 145.dp
        }
    } else {
        when (kind) {
            DashboardWidgetKind.HERO -> if (fittedPortrait) 190.dp else 250.dp
            DashboardWidgetKind.GROUP -> if (fittedPortrait) 125.dp else 190.dp
            DashboardWidgetKind.COMPACT -> if (fittedPortrait) maxOf(64f, 54f * fontScale).dp else 70.dp
            DashboardWidgetKind.GAUGE -> if (fittedPortrait) 174.dp else 210.dp
            DashboardWidgetKind.CHART -> if (fittedPortrait) 184.dp else 220.dp
            DashboardWidgetKind.PERFORMANCE -> if (fittedPortrait) 164.dp else 188.dp
            else -> if (fittedPortrait) 110.dp else 145.dp
        }
    }
    val warning = widget.metrics.any { it.isWarning(snapshot, rules) }
    TougePanelSurface(accent = accent, warning = warning, modifier = Modifier.fillMaxWidth().height(height)) {
        val horizontalPadding = if (kind == DashboardWidgetKind.COMPACT) 10.dp else if (compactLandscape || fittedPortrait) 13.dp else 17.dp
        val verticalPadding = if (kind == DashboardWidgetKind.COMPACT && fittedPortrait) 6.dp else if (kind == DashboardWidgetKind.COMPACT) 9.dp else if (compactLandscape || fittedPortrait) 13.dp else 17.dp
        Box(Modifier.fillMaxSize().padding(horizontal = horizontalPadding, vertical = verticalPadding)) {
            when (kind) {
                DashboardWidgetKind.HERO -> HeroWidget(widget, snapshot, if (warning) MaterialTheme.colorScheme.error else accent, compactLandscape, fittedPortrait)
                DashboardWidgetKind.GROUP -> GroupWidget(widget, snapshot, if (warning) MaterialTheme.colorScheme.error else accent, compactLandscape, fittedPortrait, warning)
                DashboardWidgetKind.GAUGE -> GaugeWidget(widget, snapshot, if (warning) MaterialTheme.colorScheme.error else accent, compactLandscape, fittedPortrait)
                DashboardWidgetKind.PERFORMANCE -> ValueWidget(TelemetryMetric.SPEED, snapshot, accent, false, compactLandscape, fittedPortrait)
                else -> ValueWidget(widget.metrics.first(), snapshot, if (warning) MaterialTheme.colorScheme.error else accent, kind == DashboardWidgetKind.COMPACT, compactLandscape, fittedPortrait)
            }
        }
    }
}

@Composable
private fun HeroWidget(widget: DashboardWidget, snapshot: TelemetrySnapshot, accent: Color, compact: Boolean, fittedPortrait: Boolean) {
    val metric = widget.metrics.first()
    val value = metric.value(snapshot)
    val dense = compact || fittedPortrait
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.SpaceBetween) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TelemetryGlyph(metric, MaterialTheme.colorScheme.onSurfaceVariant, Modifier.size(if (dense) 14.dp else 16.dp))
                Text(widget.title?.takeIf(String::isNotBlank)?.uppercase() ?: metric.localizedName(), Modifier.padding(start = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = if (dense) 9.sp else 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.25.sp)
            }
            StatusTag(stringResource(R.string.live_data).uppercase(), accent, dense)
        }
        Column {
            Row(verticalAlignment = Alignment.Bottom) {
                val valueSize = if (dense) 48.sp else 68.sp
                Text(metric.format(value), fontSize = valueSize, lineHeight = valueSize, fontWeight = FontWeight.Black, maxLines = 1)
                Text(metric.unit.uppercase(), Modifier.padding(start = 7.dp, bottom = if (dense) 6.dp else 10.dp), color = accent, fontSize = if (dense) 9.sp else 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp)
            }
            val min = widget.gaugeMinimum ?: metric.defaultMin
            val max = widget.gaugeMaximum ?: metric.defaultMax
            val progress = ((value - min) / (max - min)).coerceIn(0.0, 1.0).toFloat()
            Box(Modifier.fillMaxWidth().height(if (dense) 7.dp else 9.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .075f), RoundedCornerShape(5.dp))) {
                Box(Modifier.fillMaxWidth(progress.coerceAtLeast(.018f)).fillMaxHeight().background(Brush.horizontalGradient(listOf(TougeBlue.copy(alpha = .75f), accent)), RoundedCornerShape(5.dp)))
            }
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                ScaleText(metric.format(min))
                ScaleText(metric.format((min + max) / 2))
                ScaleText("${metric.format(max)} ${metric.unit.uppercase()}")
            }
            Row(Modifier.fillMaxWidth().padding(top = if (dense) 5.dp else 9.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                widget.metrics.drop(1).take(3).forEach { InlineMetric(it, snapshot, accent, dense) }
            }
        }
    }
}

@Composable
private fun InlineMetric(metric: TelemetryMetric, snapshot: TelemetrySnapshot, accent: Color, compact: Boolean) {
    Column(Modifier.fillMaxWidth(.3f)) {
        Text(metric.localizedName(), color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .8f), fontSize = if (compact) 6.sp else 7.sp, lineHeight = if (compact) 7.sp else 9.sp, fontWeight = FontWeight.Black, letterSpacing = .7.sp)
        Row(verticalAlignment = Alignment.Bottom) {
            Text(metric.format(metric.value(snapshot)), color = MaterialTheme.colorScheme.onSurface, fontSize = if (compact) 11.sp else 13.sp, lineHeight = if (compact) 12.sp else 15.sp, fontWeight = FontWeight.Bold)
            Text(metric.unit, Modifier.padding(start = 3.dp, bottom = 1.dp), color = accent, fontSize = if (compact) 7.sp else 8.sp, lineHeight = if (compact) 8.sp else 10.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun GroupWidget(widget: DashboardWidget, snapshot: TelemetrySnapshot, accent: Color, compact: Boolean, fittedPortrait: Boolean, warning: Boolean) {
    val dense = compact || fittedPortrait
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Build, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(if (dense) 14.dp else 16.dp))
                Text((widget.title?.takeUnless { it.equals("Engine health", ignoreCase = true) } ?: stringResource(R.string.engine_health)).uppercase(), Modifier.padding(start = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = if (dense) 9.sp else 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.35.sp)
            }
            StatusTag(if (warning) appText("CHECK", "SPRAWDŹ") else appText("NOMINAL", "NOMINALNIE"), if (warning) MaterialTheme.colorScheme.error else accent, dense)
        }
        Row(Modifier.fillMaxWidth().weight(1f).padding(top = if (dense) 2.dp else 18.dp), verticalAlignment = Alignment.Bottom) {
            widget.metrics.take(3).forEachIndexed { index, metric ->
                if (index > 0) Box(Modifier.fillMaxHeight(.78f).width(1.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = .08f)))
                Column(Modifier.weight(1f).padding(horizontal = if (dense) 8.dp else 12.dp), verticalArrangement = Arrangement.Bottom) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TelemetryGlyph(metric, metricAccent(metric, accent), Modifier.size(if (dense) 10.dp else 15.dp))
                        Text(metric.localizedName(), Modifier.padding(start = 5.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = if (dense) 6.sp else 8.sp, fontWeight = FontWeight.Black, letterSpacing = .55.sp, maxLines = 1)
                    }
                    Row(verticalAlignment = Alignment.Bottom) {
                        val valueSize = if (compact) 21.sp else if (fittedPortrait) 25.sp else 37.sp
                        val valueLineHeight = if (compact) 22.sp else if (fittedPortrait) 26.sp else 39.sp
                        Text(metric.format(metric.value(snapshot)), fontSize = valueSize, lineHeight = valueLineHeight, fontWeight = FontWeight.Black, maxLines = 1)
                        Text(metric.unit, Modifier.padding(start = 4.dp, bottom = if (dense) 2.dp else 5.dp), color = metricAccent(metric, accent), fontSize = if (dense) 7.sp else 10.sp, fontWeight = FontWeight.Black)
                    }
                }
            }
        }
    }
}

@Composable
private fun ValueWidget(metric: TelemetryMetric, snapshot: TelemetrySnapshot, accent: Color, compact: Boolean, compactLandscape: Boolean, fittedPortrait: Boolean) {
    Column(
        Modifier.fillMaxSize(),
        verticalArrangement = if (compact) Arrangement.spacedBy(2.dp, Alignment.CenterVertically) else Arrangement.SpaceBetween
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(metric.localizedName(), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = if (compact && fittedPortrait) 8.sp else if (compact) 9.sp else 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp, maxLines = 1)
            TelemetryGlyph(metric, accent, Modifier.size(if (compact) 15.dp else if (fittedPortrait) 18.dp else 22.dp))
        }
        if (compact) {
            Text(
                "${metric.format(metric.value(snapshot))}${if (metric.unit == "%") "%" else " ${metric.unit}"}",
                color = accent,
                fontSize = if (fittedPortrait) 19.sp else if (compactLandscape) 21.sp else 23.sp,
                lineHeight = if (fittedPortrait) 20.sp else 23.sp,
                fontWeight = FontWeight.Black,
                maxLines = 1
            )
        } else {
            Column {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(metric.format(metric.value(snapshot)), fontSize = if (compactLandscape || fittedPortrait) 34.sp else 43.sp, lineHeight = if (compactLandscape || fittedPortrait) 35.sp else 44.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Clip)
                    if (metric != TelemetryMetric.AFR && metric != TelemetryMetric.BATTERY_VOLTAGE) {
                        Text(metric.unit, Modifier.padding(start = 5.dp, bottom = 5.dp), color = accent, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    }
                }
                Text(valueSubtitle(metric, snapshot), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = if (compactLandscape || fittedPortrait) 9.sp else 12.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun GaugeWidget(widget: DashboardWidget, snapshot: TelemetrySnapshot, accent: Color, compact: Boolean, fittedPortrait: Boolean) {
    val metric = widget.metrics.first()
    val min = widget.gaugeMinimum ?: metric.defaultMin
    val max = widget.gaugeMaximum ?: metric.defaultMax
    val progress = ((metric.value(snapshot) - min) / (max - min)).coerceIn(0.0, 1.0).toFloat()
    val gaugeTrack = MaterialTheme.colorScheme.onSurface.copy(alpha = .07f)
    Box(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(widget.title?.takeIf(String::isNotBlank)?.uppercase() ?: metric.localizedName(), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = if (compact) 8.sp else 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
            TelemetryGlyph(metric, accent, Modifier.size(if (compact) 15.dp else 20.dp))
        }
        Box(Modifier.fillMaxSize().padding(top = if (compact) 7.dp else 14.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxHeight(.88f).aspectRatio(1f)) {
                drawArc(gaugeTrack, 150f, 240f, false, style = Stroke(if (compact) 8.dp.toPx() else 12.dp.toPx(), cap = StrokeCap.Round))
                drawArc(Brush.sweepGradient(listOf(TougeBlue, accent)), 150f, 240f * progress, false, style = Stroke(if (compact) 8.dp.toPx() else 12.dp.toPx(), cap = StrokeCap.Round))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(metric.format(metric.value(snapshot)), fontSize = if (compact) 24.sp else if (fittedPortrait) 31.sp else 38.sp, lineHeight = if (compact) 25.sp else if (fittedPortrait) 32.sp else 39.sp, fontWeight = FontWeight.Black)
                Text(metric.unit, color = accent, fontSize = if (compact) 8.sp else if (fittedPortrait) 9.sp else 10.sp, fontWeight = FontWeight.Black)
            }
        }
    }
}

@Composable
private fun StatusTag(title: String, tint: Color, compact: Boolean) {
    Row(
        Modifier.background(tint.copy(alpha = .09f), RoundedCornerShape(18.dp)).border(1.dp, tint.copy(alpha = .35f), RoundedCornerShape(18.dp)).padding(horizontal = if (compact) 7.dp else 10.dp, vertical = if (compact) 3.dp else 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(if (compact) 5.dp else 6.dp).background(tint, CircleShape))
        Text(title, Modifier.padding(start = 6.dp), color = tint, fontSize = if (compact) 6.sp else 8.sp, fontWeight = FontWeight.Black, letterSpacing = .8.sp)
    }
}

@Composable
private fun ScaleText(value: String) {
    Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .58f), fontSize = 7.sp, fontWeight = FontWeight.Bold)
}

private fun TelemetryMetric.isWarning(snapshot: TelemetrySnapshot, rules: VehicleAlertRules): Boolean = when (this) {
    TelemetryMetric.BOOST -> rules.overboostEnabled && snapshot.boostBar > rules.maximumBoostBar
    TelemetryMetric.COOLANT -> rules.highCoolantTemperatureEnabled && snapshot.coolantCelsius >= rules.maximumCoolantCelsius
    TelemetryMetric.OIL_TEMPERATURE -> rules.highOilTemperatureEnabled && snapshot.oilTemperatureCelsius >= rules.maximumOilTemperatureCelsius
    TelemetryMetric.OIL_PRESSURE -> rules.lowOilPressureEnabled && snapshot.rpm >= rules.lowOilMinimumRpm && snapshot.oilPressureBar > 0 && snapshot.oilPressureBar < rules.minimumOilPressureBar
    TelemetryMetric.AFR -> rules.leanUnderBoostEnabled && snapshot.boostBar >= rules.leanMinimumBoostBar && snapshot.afr > rules.maximumAfr
    TelemetryMetric.FUEL_PRESSURE -> rules.lowFuelPressureEnabled && snapshot.rpm >= rules.lowFuelPressureMinimumRpm && snapshot.fuelPressureBar > 0 && snapshot.fuelPressureBar < rules.minimumFuelPressureBar
    TelemetryMetric.BATTERY_VOLTAGE -> rules.lowBatteryVoltageEnabled && snapshot.rpm >= rules.lowBatteryMinimumRpm && snapshot.batteryVoltage > 0 && snapshot.batteryVoltage < rules.minimumBatteryVoltage
    else -> false
}

@Composable
private fun metricAccent(metric: TelemetryMetric, fallback: Color): Color = when (metric) {
    TelemetryMetric.OIL_TEMPERATURE -> MaterialTheme.colorScheme.tertiary
    TelemetryMetric.COOLANT -> TougeBlue
    else -> fallback
}

@Composable
private fun valueSubtitle(metric: TelemetryMetric, snapshot: TelemetrySnapshot): String = when (metric) {
    TelemetryMetric.AFR -> "λ ${TelemetryMetric.LAMBDA.format(snapshot.lambda)}"
    TelemetryMetric.BATTERY_VOLTAGE -> metric.unit
    else -> metric.unit
}

@Composable
private fun PlaceholderScreen(title: String, body: String, icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(icon, null, Modifier.size(52.dp), tint = MaterialTheme.colorScheme.primary)
        Text(title, fontSize = 30.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(top = 16.dp))
        Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun MoreScreen(container: AppContainer, appTheme: AppTheme, onAppThemeChanged: (AppTheme) -> Unit) {
    val context = LocalContext.current
    val vehicles by container.dao.vehicles().collectAsState(initial = emptyList())
    var rename by remember { mutableStateOf<VehicleEntity?>(null) }
    var routeEnabled by remember { mutableStateOf(container.locationTracker.isEnabled) }
    val videoSettings by container.videoRecordingSettings.settings.collectAsState()
    var showVideoWarning by remember { mutableStateOf(false) }
    var warningCountdown by remember { mutableIntStateOf(5) }
    val lifecycleOwner = LocalLifecycleOwner.current
    var overlayEnabled by remember {
        mutableStateOf(
            Settings.canDrawOverlays(context) && TelemetryOverlayPreferences.isEnabled(context)
        )
    }
    val overlayPermission = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        val granted = Settings.canDrawOverlays(context)
        overlayEnabled = granted
        TelemetryOverlayPreferences.setEnabled(context, granted)
        if (granted) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, TelemetryService::class.java).setAction(TelemetryService.ACTION_SHOW_OVERLAY)
            )
        }
    }
    val locationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        routeEnabled = granted
        container.locationTracker.setEnabled(granted)
    }
    val videoPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        val cameraGranted = result[Manifest.permission.CAMERA] == true || ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (cameraGranted) container.videoRecordingSettings.update(videoSettings.copy(automaticRecording = true))
    }
    androidx.compose.runtime.DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                overlayEnabled = Settings.canDrawOverlays(context) &&
                    TelemetryOverlayPreferences.isEnabled(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(showVideoWarning) {
        if (showVideoWarning) {
            warningCountdown = 5
            while (warningCountdown > 0) { delay(1_000); warningCountdown-- }
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)) {
        Column(Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.more), fontSize = 30.sp, fontWeight = FontWeight.Black)
            TougePanelSurface(TougeBlue, Modifier.fillMaxWidth().padding(top = 14.dp)) {
                Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column {
                        Text(appText("Application theme", "Motyw aplikacji"), fontWeight = FontWeight.Bold)
                        Text(
                            appText("Uses the device setting by default", "Domyślnie zgodny z ustawieniem urządzenia"),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 11.sp
                        )
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        AppTheme.entries.forEach { option ->
                            FilterChip(
                                selected = appTheme == option,
                                onClick = { onAppThemeChanged(option) },
                                label = {
                                    Text(
                                        when (option) {
                                            AppTheme.SYSTEM -> appText("System", "Systemowy")
                                            AppTheme.LIGHT -> appText("Light", "Jasny")
                                            AppTheme.DARK -> appText("Dark", "Ciemny")
                                        },
                                        maxLines = 1
                                    )
                                },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                }
            }
            TougePanelSurface(MaterialTheme.colorScheme.primary, Modifier.fillMaxWidth().padding(top = 14.dp)) {
                Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(appText("Record route", "Zapisuj trasę"), fontWeight = FontWeight.Bold)
                        Text(appText("Optional GPS track stored with drive history", "Opcjonalny ślad GPS zapisany z historią przejazdu"), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 11.sp)
                    }
                    Switch(routeEnabled, { enabled ->
                        if (enabled) locationPermission.launch(Manifest.permission.ACCESS_FINE_LOCATION)
                        else { routeEnabled = false; container.locationTracker.setEnabled(false) }
                    })
                }
            }
            TougePanelSurface(MaterialTheme.colorScheme.primary, Modifier.fillMaxWidth().padding(top = 10.dp)) {
                Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.telemetry_hud), fontWeight = FontWeight.Bold)
                            Text(
                                stringResource(R.string.telemetry_hud_description),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 11.sp
                            )
                        }
                        Switch(overlayEnabled, { enabled ->
                            if (!enabled) {
                                overlayEnabled = false
                                TelemetryOverlayPreferences.setEnabled(context, false)
                                ContextCompat.startForegroundService(
                                    context,
                                    Intent(context, TelemetryService::class.java).setAction(TelemetryService.ACTION_HIDE_OVERLAY)
                                )
                            } else if (Settings.canDrawOverlays(context)) {
                                overlayEnabled = true
                                TelemetryOverlayPreferences.setEnabled(context, true)
                                ContextCompat.startForegroundService(
                                    context,
                                    Intent(context, TelemetryService::class.java).setAction(TelemetryService.ACTION_SHOW_OVERLAY)
                                )
                            } else {
                                overlayPermission.launch(
                                    Intent(
                                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                        Uri.parse("package:${context.packageName}")
                                    )
                                )
                            }
                        })
                    }
                    if (!Settings.canDrawOverlays(context)) {
                        Text(
                            stringResource(R.string.telemetry_hud_permission),
                            color = MaterialTheme.colorScheme.tertiary,
                            fontSize = 10.sp
                        )
                    }
                }
            }
            TougePanelSurface(MaterialTheme.colorScheme.tertiary, Modifier.fillMaxWidth().padding(top = 10.dp)) {
                Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(appText("Automatic drive recording", "Automatyczne nagrywanie przejazdu"), fontWeight = FontWeight.Bold)
                            Text(appText("Starts the phone camera together with telemetry", "Uruchamia kamerę telefonu razem z telemetrią"), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 11.sp)
                        }
                        Switch(videoSettings.automaticRecording, { enabled ->
                            if (!enabled) container.videoRecordingSettings.update(videoSettings.copy(automaticRecording = false))
                            else if (!container.videoRecordingSettings.warningAccepted) showVideoWarning = true
                            else videoPermission.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
                        })
                    }
                    if (videoSettings.automaticRecording) {
                        Text(appText("QUALITY", "JAKOŚĆ"), color = MaterialTheme.colorScheme.tertiary, fontSize = 9.sp, fontWeight = FontWeight.Black)
                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            DriveVideoQuality.entries.forEach { quality ->
                                FilterChip(
                                    selected = videoSettings.quality == quality,
                                    onClick = { container.videoRecordingSettings.update(videoSettings.copy(quality = quality)) },
                                    label = { Text(when (quality) { DriveVideoQuality.STORAGE_SAVER -> "720p"; DriveVideoQuality.FULL_HD -> "1080p"; DriveVideoQuality.ULTRA_HD -> "4K" }) }
                                )
                            }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(appText("Front camera", "Przednia kamera"), Modifier.weight(1f), fontSize = 12.sp)
                            Switch(videoSettings.frontCamera, { container.videoRecordingSettings.update(videoSettings.copy(frontCamera = it)) })
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(appText("Record audio", "Nagrywaj dźwięk"), Modifier.weight(1f), fontSize = 12.sp)
                            Switch(videoSettings.recordAudio, { container.videoRecordingSettings.update(videoSettings.copy(recordAudio = it)) })
                        }
                    }
                }
            }
            if (vehicles.isNotEmpty()) {
                Text(appText("GARAGE", "GARAŻ"), color = MaterialTheme.colorScheme.primary, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp))
                vehicles.forEach { vehicle ->
                    TougePanelSurface(
                        MaterialTheme.colorScheme.secondary,
                        Modifier.fillMaxWidth().padding(top = 7.dp).clickable { rename = vehicle }
                    ) {
                        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.DirectionsCar, null, tint = MaterialTheme.colorScheme.secondary)
                            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                                Text(vehicle.displayName, fontWeight = FontWeight.Black)
                                Text(vehicle.localHardwareId, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 10.sp, maxLines = 1)
                            }
                            Icon(Icons.Default.Edit, null, tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
            CloudAccountCard(container)
            if (BuildConfig.DEBUG) Text("DEV API • ${BuildConfig.API_BASE_URL}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 10.sp, modifier = Modifier.padding(top = 10.dp))
        }
        Column(
            Modifier.fillMaxWidth().clickable { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://letscode.it"))) }.padding(vertical = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.made_by), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("  ♥  ", color = MaterialTheme.colorScheme.error)
                Text(stringResource(R.string.by_lets_code_it), color = MaterialTheme.colorScheme.primary)
            }
            Text("v${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 9.sp)
        }
    }
    rename?.let { vehicle -> VehicleNameDialog(container, vehicle) { rename = null } }
    if (showVideoWarning) AlertDialog(
        onDismissRequest = { showVideoWarning = false },
        title = { Text(appText("Experimental drive recording", "Eksperymentalne nagrywanie przejazdu")) },
        text = { Text(appText(
            "Touge Dash will record the road with the selected phone camera while it saves engine telemetry. Later you can align the recording, preview it and export a copy with a configurable HUD. Video encoding can heat the phone, increase battery use and reduce responsiveness. Mount the phone securely and never operate it while driving.",
            "Touge Dash będzie nagrywać drogę wybraną kamerą telefonu równolegle z telemetrią silnika. Później dopasujesz nagranie, obejrzysz podgląd i wyeksportujesz kopię z konfigurowalnym HUD-em. Kodowanie wideo może nagrzewać telefon, zwiększać zużycie baterii i obniżać płynność. Zamocuj telefon stabilnie i nigdy nie obsługuj go podczas jazdy."
        )) },
        confirmButton = {
            Button(enabled = warningCountdown == 0, onClick = {
                container.videoRecordingSettings.acceptWarning()
                showVideoWarning = false
                videoPermission.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
            }) { Text(if (warningCountdown > 0) appText("I understand (${warningCountdown}s)", "Rozumiem (${warningCountdown}s)") else appText("I understand — enable", "Rozumiem — włącz")) }
        },
        dismissButton = { TextButton(onClick = { showVideoWarning = false }) { Text(appText("Not now", "Nie teraz")) } }
    )
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
                Text(appText("Touge Dash recognizes each car by its Bluetooth interface. You can change this name at any time.", "Touge Dash rozpoznaje każde auto po interfejsie Bluetooth. Nazwę możesz zmienić w dowolnym momencie."), color = MaterialTheme.colorScheme.onSurfaceVariant)
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
    val diagnostics by TelemetryRuntime.diagnostics.collectAsState()
    AlertDialog(
        onDismissRequest = close,
        title = { Text(stringResource(R.string.connection_details)) },
        text = {
            Column(
                Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(connection.deviceName ?: connection.state.localizedLabel(), fontWeight = FontWeight.Bold)
                connection.hardwareId?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp) }
                connection.message?.let { Text(it) }
                Text("${appText("Frames", "Ramki")} ${connection.validFrames} • ${appText("checksum", "błędne sumy")} ${connection.badChecksums} • ${appText("dropped", "pominięte bajty")} ${connection.droppedBytes}", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                Text(
                    "RX ${connection.receivedPackets} ${appText("packets", "pakietów")} • ${connection.receivedBytes} B",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 12.sp
                )
                connection.lastPacketHex?.let {
                    Text("LAST RX  $it", color = MaterialTheme.colorScheme.primary, fontSize = 9.sp, fontFamily = FontFamily.Monospace)
                }
                if (diagnostics.isNotEmpty()) {
                    Text(appText("DIAGNOSTICS", "DIAGNOSTYKA"), color = MaterialTheme.colorScheme.primary, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    Text(
                        diagnostics.take(10).reversed().joinToString("\n") { it.substringAfter(": ") },
                        modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.onSurface.copy(alpha = .055f), RoundedCornerShape(7.dp)).padding(9.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 9.sp,
                        lineHeight = 12.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }
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

@Composable
internal fun DashboardAccent.color(): Color = when (this) {
    DashboardAccent.CYAN -> MaterialTheme.colorScheme.primary
    DashboardAccent.MINT -> MaterialTheme.colorScheme.secondary
    DashboardAccent.BLUE, DashboardAccent.ICE -> TougeBlue
    DashboardAccent.ORANGE -> MaterialTheme.colorScheme.tertiary
    DashboardAccent.YELLOW -> Color(0xFFFFC83D)
    DashboardAccent.RED -> MaterialTheme.colorScheme.error
    DashboardAccent.WHITE -> MaterialTheme.colorScheme.onBackground
}

@Composable
internal fun TelemetryMetric.format(value: Double): String {
    val locale = if (androidx.compose.ui.text.intl.Locale.current.language == "pl") Locale.forLanguageTag("pl-PL") else Locale.US
    return when (precision) {
        0 -> value.roundToInt().toString()
        1 -> String.format(locale, "%.1f", value)
        else -> String.format(locale, "%.2f", value)
    }
}
