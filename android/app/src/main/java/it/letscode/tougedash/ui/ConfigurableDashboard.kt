package it.letscode.tougedash.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.DriveFileRenameOutline
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.DashboardCustomize
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.model.DashboardAccent
import it.letscode.tougedash.model.DashboardDefinition
import it.letscode.tougedash.model.DashboardTemplate
import it.letscode.tougedash.model.DashboardWidget
import it.letscode.tougedash.model.DashboardWidgetKind
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.model.TelemetrySnapshot
import it.letscode.tougedash.model.VehicleAlertRules
import it.letscode.tougedash.telemetry.TimedTelemetry
import it.letscode.tougedash.performance.AccelerationRuntimeState
import it.letscode.tougedash.performance.AccelerationType
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeRed
import it.letscode.tougedash.ui.theme.TougeMuted
import kotlinx.coroutines.launch
import kotlin.math.abs

@Composable
fun ConfigurableDashboardScreen(
    container: AppContainer,
    snapshot: TelemetrySnapshot,
    hardwareId: String?
) {
    val template by container.dashboardRepository.selected.collectAsState(initial = DashboardTemplate.factory())
    val templates by container.dashboardRepository.templates.collectAsState(initial = listOf(DashboardTemplate.factory()))
    val chartPoints by container.runtime.chartPoints.collectAsState()
    val performance by container.accelerationEngine.state.collectAsState()
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf(false) }
    var editorWidget by remember { mutableStateOf<DashboardWidget?>(null) }
    var templateMenu by remember { mutableStateOf(false) }
    var renameTemplate by remember { mutableStateOf<DashboardTemplate?>(null) }
    var deleteTemplate by remember { mutableStateOf<DashboardTemplate?>(null) }
    var restoreFactory by remember { mutableStateOf(false) }
    val authSession by container.authRepository.session.collectAsState()
    val alertRules by container.alertRepository.rules(hardwareId ?: "local-default").collectAsState(initial = VehicleAlertRules())
    val landscape = LocalConfiguration.current.screenWidthDp > LocalConfiguration.current.screenHeightDp
    val gridState = rememberLazyGridState()
    LaunchedEffect(landscape) { gridState.scrollToItem(0) }
    val widgets = template.definition.widgets.filter { (if (landscape) it.landscapeSpan else it.portraitSpan) > 0 }
        .sortedBy { if (landscape) it.landscapeOrder else it.portraitOrder }

    Column(Modifier.fillMaxSize()) {
        if (!editing) {
            Row(Modifier.fillMaxWidth().padding(horizontal = if (landscape) 14.dp else 16.dp, vertical = if (landscape) 1.dp else 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                Box(
                    Modifier.weight(1f).background(Color.White.copy(alpha = .05f), CutCornerShape(8.dp)).border(1.dp, Color.White.copy(alpha = .08f), CutCornerShape(8.dp)).clickable { templateMenu = true }.padding(horizontal = 12.dp, vertical = if (landscape) 3.dp else 10.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.DashboardCustomize, null, tint = TougeCyan, modifier = Modifier.size(18.dp))
                        Column(Modifier.padding(start = 9.dp).weight(1f)) {
                            Text(template.localizedName(), fontSize = if (landscape) 10.sp else 12.sp, fontWeight = FontWeight.Black, maxLines = 1)
                            if (!landscape) Text(if (authSession == null) appText("SAVED ON DEVICE", "ZAPISANY NA URZĄDZENIU") else appText("CLOUD SYNC ACTIVE", "SYNCHRONIZACJA ONLINE"), color = if (authSession == null) TougeMuted else TougeMint, fontSize = 7.sp, fontWeight = FontWeight.Black, letterSpacing = .65.sp)
                        }
                        Text("⌄", color = TougeMuted, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    }
                }
                DropdownMenu(expanded = templateMenu, onDismissRequest = { templateMenu = false }) {
                    templates.forEach { item -> DropdownMenuItem(text = { Text(item.localizedName()) }, onClick = { templateMenu = false; scope.launch { container.dashboardRepository.select(item.id) } }) }
                    DropdownMenuItem(text = { Text(appText("New dashboard", "Nowy dashboard")) }, leadingIcon = { Icon(Icons.Default.Add, null) }, onClick = { templateMenu = false; scope.launch { container.dashboardRepository.create() } })
                    DropdownMenuItem(text = { Text(appText("Duplicate", "Duplikuj")) }, leadingIcon = { Icon(Icons.Default.ContentCopy, null) }, onClick = { templateMenu = false; scope.launch { container.dashboardRepository.duplicate(template) } })
                    DropdownMenuItem(text = { Text(appText("Rename", "Zmień nazwę")) }, leadingIcon = { Icon(Icons.Default.DriveFileRenameOutline, null) }, onClick = { templateMenu = false; renameTemplate = template })
                    if (template.id != DashboardTemplate.FACTORY_ID) DropdownMenuItem(
                        text = { Text(appText("Delete dashboard", "Usuń dashboard"), color = TougeRed) },
                        leadingIcon = { Icon(Icons.Default.Delete, null, tint = TougeRed) },
                        onClick = { templateMenu = false; deleteTemplate = template }
                    )
                    DropdownMenuItem(text = { Text(appText("Restore factory dashboard", "Przywróć fabryczny dashboard")) }, leadingIcon = { Icon(Icons.Default.Restore, null) }, onClick = { templateMenu = false; restoreFactory = true })
                }
                Row(
                    Modifier.background(TougeCyan, CutCornerShape(8.dp)).clickable { editing = true }.padding(horizontal = if (landscape) 11.dp else 13.dp, vertical = if (landscape) 5.dp else 13.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Edit, null, tint = Color.Black, modifier = Modifier.size(17.dp))
                    if (!landscape) Text(appText(" Edit dashboard", " Edytuj dashboard"), color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.Black)
                }
            }
        } else {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = if (landscape) 14.dp else 16.dp, vertical = if (landscape) 3.dp else 8.dp).background(TougeCyan.copy(alpha = .065f), CutCornerShape(10.dp)).border(1.dp, TougeCyan.copy(alpha = .32f), CutCornerShape(10.dp)).padding(horizontal = 11.dp, vertical = if (landscape) 6.dp else 9.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.DashboardCustomize, null, tint = TougeCyan, modifier = Modifier.size(20.dp))
                Column(Modifier.padding(start = 9.dp).weight(1f)) {
                    Text(appText("EDITING DASHBOARD", "EDYTUJESZ DASHBOARD"), color = TougeCyan, fontSize = 9.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                    if (!landscape) Text(appText("Hold and drag a card to move it", "Przytrzymaj i przeciągnij kartę, aby ją przenieść"), color = TougeMuted, fontSize = 9.sp)
                }
                Row(Modifier.background(TougeCyan, CutCornerShape(7.dp)).clickable { editing = false }.padding(horizontal = 13.dp, vertical = 9.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Done, null, tint = Color.Black, modifier = Modifier.size(16.dp))
                    Text(appText(" Done", " Gotowe"), color = Color.Black, fontSize = 10.sp, fontWeight = FontWeight.Black)
                }
            }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(12),
            state = gridState,
            horizontalArrangement = Arrangement.spacedBy(if (landscape) 8.dp else 10.dp), verticalArrangement = Arrangement.spacedBy(if (landscape) 6.dp else 12.dp),
            modifier = Modifier.fillMaxSize().padding(horizontal = if (landscape) 14.dp else 16.dp, vertical = if (landscape) 3.dp else 7.dp)
        ) {
            items(widgets, key = { it.id }, span = { GridItemSpan(if (landscape) it.landscapeSpan else it.portraitSpan) }) { widget ->
                EditableDashboardCard(
                    widget, snapshot, chartPoints, performance, alertRules, landscape, editing,
                    edit = { editorWidget = widget },
                    remove = { scope.launch { saveWidgets(container, template, template.definition.widgets.filterNot { it.id == widget.id }) } },
                    move = { direction -> scope.launch { saveWidgets(container, template, moveWidget(template.definition.widgets, widget.id, direction, landscape)) } }
                )
            }
            if (editing) item(span = { GridItemSpan(12) }) {
                Button(onClick = { editorWidget = DashboardWidget(kind = DashboardWidgetKind.VALUE, metrics = listOf(TelemetryMetric.RPM), portraitSpan = 6, landscapeSpan = 4, portraitOrder = template.definition.widgets.size) }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.Add, null); Text(appText(" Add card", " Dodaj kartę"))
                }
            }
        }
    }
    editorWidget?.let { widget ->
        WidgetEditor(widget, dismiss = { editorWidget = null }) { saved ->
            val values = template.definition.widgets.toMutableList()
            val index = values.indexOfFirst { it.id == saved.id }
            if (index >= 0) values[index] = saved else values += saved
            scope.launch { saveWidgets(container, template, values) }
            editorWidget = null
        }
    }
    renameTemplate?.let { current ->
        RenameDashboardDialog(current, dismiss = { renameTemplate = null }) { name ->
            scope.launch { container.dashboardRepository.rename(current, name) }
            renameTemplate = null
        }
    }
    deleteTemplate?.let { current ->
        AlertDialog(
            onDismissRequest = { deleteTemplate = null },
            title = { Text(appText("Delete this dashboard?", "Usunąć ten dashboard?")) },
            text = { Text(appText("The dashboard layout will be removed from this device and from cloud synchronization.", "Układ dashboardu zostanie usunięty z tego urządzenia i synchronizacji online."), color = TougeMuted) },
            confirmButton = { Button(onClick = { scope.launch { container.dashboardRepository.delete(current) }; deleteTemplate = null }) { Text(appText("Delete", "Usuń")) } },
            dismissButton = { TextButton(onClick = { deleteTemplate = null }) { Text(appText("Cancel", "Anuluj")) } }
        )
    }
    if (restoreFactory) AlertDialog(
        onDismissRequest = { restoreFactory = false },
        title = { Text(appText("Restore factory layout?", "Przywrócić układ fabryczny?")) },
        text = { Text(appText("The built-in dashboard will return to the same layout as on iPhone. Your other dashboards will stay untouched.", "Wbudowany dashboard wróci do takiego samego układu jak na iPhonie. Pozostałe dashboardy pozostaną bez zmian."), color = TougeMuted) },
        confirmButton = { Button(onClick = { scope.launch { container.dashboardRepository.restoreFactory() }; restoreFactory = false }) { Text(appText("Restore", "Przywróć")) } },
        dismissButton = { TextButton(onClick = { restoreFactory = false }) { Text(appText("Cancel", "Anuluj")) } }
    )
}

@Composable
private fun RenameDashboardDialog(template: DashboardTemplate, dismiss: () -> Unit, save: (String) -> Unit) {
    val initialName = template.localizedName()
    var name by remember(template.id) { mutableStateOf(initialName) }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(appText("Dashboard name", "Nazwa dashboardu")) },
        text = { OutlinedTextField(name, { name = it.take(80) }, singleLine = true, modifier = Modifier.fillMaxWidth()) },
        confirmButton = { Button(enabled = name.isNotBlank(), onClick = { save(name) }) { Text(appText("Save", "Zapisz")) } },
        dismissButton = { TextButton(onClick = dismiss) { Text(appText("Cancel", "Anuluj")) } }
    )
}

@Composable
private fun EditableDashboardCard(
    widget: DashboardWidget,
    snapshot: TelemetrySnapshot,
    chartPoints: List<TimedTelemetry>,
    performance: AccelerationRuntimeState,
    alertRules: VehicleAlertRules,
    landscape: Boolean,
    editing: Boolean,
    edit: () -> Unit,
    remove: () -> Unit,
    move: (Int) -> Unit
) {
    val transition = rememberInfiniteTransition(label = "edit wiggle")
    val rotation by transition.animateFloat(-.45f, .45f, infiniteRepeatable(tween(120), RepeatMode.Reverse), label = "wiggle")
    var drag by remember { mutableFloatStateOf(0f) }
    Box(
        Modifier.rotate(if (editing) rotation else 0f).pointerInput(editing, widget.id) {
            if (editing) detectDragGesturesAfterLongPress(
                onDragEnd = { if (abs(drag) > 35) move(if (drag > 0) 1 else -1); drag = 0f },
                onDragCancel = { drag = 0f },
                onDrag = { change, amount -> change.consume(); drag += amount.y + amount.x }
            )
        }
    ) {
        val effectiveKind = if (landscape) widget.wideKind ?: widget.kind else widget.kind
        if (effectiveKind == DashboardWidgetKind.CHART) ChartCard(widget, snapshot, chartPoints, landscape)
        else if (effectiveKind == DashboardWidgetKind.PERFORMANCE) PerformanceCard(widget, performance, landscape)
        else DashboardCard(widget, snapshot, landscape, alertRules)
        if (editing) {
            Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().padding(7.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(30.dp).background(TougeRed.copy(alpha = .88f), CircleShape).border(1.dp, Color.White.copy(alpha = .18f), CircleShape).clickable(onClick = remove), contentAlignment = Alignment.Center) { Icon(Icons.Default.Close, null, tint = Color.White, modifier = Modifier.size(15.dp)) }
                Box(Modifier.weight(1f))
                Row(Modifier.background(Color.Black.copy(alpha = .72f), RoundedCornerShape(18.dp)).border(1.dp, Color.White.copy(alpha = .14f), RoundedCornerShape(18.dp)).padding(horizontal = 9.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.DragHandle, null, tint = Color.White.copy(alpha = .8f), modifier = Modifier.size(15.dp))
                    if (!landscape && widget.portraitSpan == 12) Text(appText(" DRAG", " PRZECIĄGNIJ"), color = Color.White.copy(alpha = .8f), fontSize = 7.sp, fontWeight = FontWeight.Black, letterSpacing = .6.sp)
                }
                Box(Modifier.weight(1f))
                Box(Modifier.size(30.dp).background(TougeCyan.copy(alpha = .9f), CircleShape).border(1.dp, Color.White.copy(alpha = .18f), CircleShape).clickable(onClick = edit), contentAlignment = Alignment.Center) { Icon(Icons.Default.Edit, null, tint = Color.Black, modifier = Modifier.size(15.dp)) }
            }
        }
    }
}

@Composable
private fun PerformanceCard(widget: DashboardWidget, state: AccelerationRuntimeState, landscape: Boolean) {
    val accent = widget.accent.color()
    val selected = widget.accelerationTypes.ifEmpty { AccelerationType.entries }
    TougePanelSurface(accent, Modifier.fillMaxWidth().height(if (landscape) 112.dp else 188.dp)) {
        Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(widget.title ?: appText("ACCELERATION", "PRZYSPIESZENIE"), color = TougeMuted, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                Text(if (state.active == null) appText("READY", "GOTOWY") else appText("MEASURING", "POMIAR"), color = if (state.active == null) TougeMint else accent, fontSize = 9.sp, fontWeight = FontWeight.Black)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                selected.forEach { type ->
                    val active = state.active?.takeIf { it.type == type }
                    val best = state.recentResults.filter { it.type == type.name }.minByOrNull { it.durationMillis }
                    Column(Modifier.weight(1f).background(Color.Black.copy(alpha = .18f), CutCornerShape(7.dp)).padding(horizontal = 10.dp, vertical = 11.dp)) {
                        Text(type.label, color = if (active != null) accent else TougeMuted, fontSize = 9.sp, fontWeight = FontWeight.Black)
                        Text(
                            when {
                                active != null -> "%.2f s".format(active.elapsedMillis / 1_000.0)
                                best != null -> "%.2f s".format(best.durationMillis / 1_000.0)
                                else -> "—"
                            },
                            fontSize = if (landscape) 18.sp else 23.sp,
                            fontWeight = FontWeight.Black
                        )
                        Text(
                            if (active != null) "${active.currentSpeedKph.toInt()} km/h" else if (best != null) appText("BEST THIS DRIVE", "NAJLEPSZY W TEJ JEŹDZIE") else appText("NO ATTEMPT", "BRAK PRÓBY"),
                            color = if (active != null) accent else TougeMuted,
                            fontSize = 7.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ChartCard(widget: DashboardWidget, snapshot: TelemetrySnapshot, points: List<TimedTelemetry>, landscape: Boolean) {
    val metric = widget.metrics.first()
    val accent = widget.accent.color()
    val duration = widget.chartDurationSeconds ?: 30
    val now = snapshot.updatedAt
    val values = points.filter { now - it.recordedAt <= duration * 1_000L }.map { metric.value(it.snapshot).toFloat() }
    TougePanelSurface(accent, Modifier.fillMaxWidth().height(if (landscape) 112.dp else 220.dp)) {
        Column(Modifier.fillMaxSize().padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TelemetryGlyph(metric, accent, Modifier.size(18.dp))
                    Text(metric.localizedName(), Modifier.padding(start = 8.dp), color = TougeMuted, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
                }
                Text("${metric.format(metric.value(snapshot))} ${metric.unit}  •  ${duration}s", fontWeight = FontWeight.Black)
            }
            Canvas(Modifier.fillMaxWidth().weight(1f).padding(top = 13.dp)) {
                if (values.size > 1) {
                    val min = (widget.gaugeMinimum ?: metric.defaultMin).toFloat()
                    val max = (widget.gaugeMaximum ?: metric.defaultMax).toFloat()
                    repeat(3) { line -> drawLine(Color.White.copy(alpha = .045f), androidx.compose.ui.geometry.Offset(0f, size.height * line / 2f), androidx.compose.ui.geometry.Offset(size.width, size.height * line / 2f), strokeWidth = 1f) }
                    values.zipWithNext().forEachIndexed { index, pair ->
                        val x1 = index.toFloat() / (values.size - 1) * size.width
                        val x2 = (index + 1).toFloat() / (values.size - 1) * size.width
                        val y1 = size.height * (1 - ((pair.first - min) / (max - min)).coerceIn(0f, 1f))
                        val y2 = size.height * (1 - ((pair.second - min) / (max - min)).coerceIn(0f, 1f))
                        drawLine(accent, androidx.compose.ui.geometry.Offset(x1, y1), androidx.compose.ui.geometry.Offset(x2, y2), strokeWidth = 3.dp.toPx())
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WidgetEditor(initial: DashboardWidget, dismiss: () -> Unit, save: (DashboardWidget) -> Unit) {
    var value by remember(initial.id) { mutableStateOf(initial) }
    var title by remember(initial.id) { mutableStateOf(initial.title.orEmpty()) }
    val landscape = LocalConfiguration.current.screenWidthDp > LocalConfiguration.current.screenHeightDp
    AlertDialog(
        onDismissRequest = dismiss,
        shape = CutCornerShape(18.dp),
        containerColor = Color(0xFF10191F),
        titleContentColor = Color.White,
        textContentColor = Color.White,
        title = {
            Column {
                Text(appText("Dashboard card", "Karta dashboardu"), fontWeight = FontWeight.Black)
                Text(appText("Choose how this parameter is presented", "Wybierz sposób prezentacji parametru"), color = TougeMuted, fontSize = 11.sp, fontWeight = FontWeight.Medium)
            }
        },
        text = {
            Column(
                Modifier.heightIn(max = if (landscape) 205.dp else 540.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(appText("TYPE", "TYP"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(2.dp), maxItemsInEachRow = 2) {
                    DashboardWidgetKind.entries.forEach { kind ->
                        FilterChip(
                            selected = value.kind == kind,
                            onClick = { value = value.copy(kind = kind, metrics = normalizeMetrics(value.metrics, kind)) },
                            modifier = Modifier.widthIn(min = 104.dp),
                            label = { Text(kind.localizedName(), maxLines = 1) }
                        )
                    }
                }
                OutlinedTextField(title, { title = it }, label = { Text(appText("Custom title", "Własny tytuł")) }, singleLine = true)
                if (value.kind == DashboardWidgetKind.PERFORMANCE) {
                    Text(appText("MEASUREMENTS", "POMIARY"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    AccelerationType.entries.forEach { type ->
                        FilterChip(
                            selected = type in value.accelerationTypes,
                            onClick = {
                                val updated = if (type in value.accelerationTypes) value.accelerationTypes - type else value.accelerationTypes + type
                                if (updated.isNotEmpty()) value = value.copy(accelerationTypes = updated)
                            },
                            label = { Text("${type.label} km/h") }
                        )
                    }
                } else {
                    Text(if (maximumMetricCount(value.kind) > 1) appText("PARAMETERS", "PARAMETRY") else appText("PARAMETER", "PARAMETR"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                }
                repeat(maximumMetricCount(value.kind)) { index ->
                    val fallback = TelemetryMetric.entries.getOrElse(index) { TelemetryMetric.RPM }
                    val selected = value.metrics.getOrNull(index) ?: fallback
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        Text("${index + 1}.", color = TougeMuted, fontWeight = FontWeight.Black)
                        MetricDropdown(selected) { metric ->
                            val metrics = value.metrics.toMutableList()
                            while (metrics.size <= index) metrics += fallback
                            metrics[index] = metric
                            value = value.copy(metrics = metrics)
                        }
                    }
                }
                Text(appText("COLOR", "KOLOR"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    DashboardAccent.entries.forEach { accent ->
                        Box(
                            Modifier.size(if (value.accent == accent) 30.dp else 24.dp)
                                .background(accent.color(), CircleShape)
                                .border(if (value.accent == accent) 2.dp else 0.dp, Color.White, CircleShape)
                                .clickable { value = value.copy(accent = accent) }
                        )
                    }
                }
                Text(appText("PORTRAIT WIDTH", "SZEROKOŚĆ W PIONIE"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                SpanSelector(value.portraitSpan) { value = value.copy(portraitSpan = it) }
                Text(appText("LANDSCAPE WIDTH", "SZEROKOŚĆ W POZIOMIE"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                SpanSelector(value.landscapeSpan) { value = value.copy(landscapeSpan = it) }
                Text(appText("LANDSCAPE PRESENTATION", "WIDOK W POZIOMIE"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    FilterChip(selected = value.wideKind == null, onClick = { value = value.copy(wideKind = null) }, label = { Text(appText("Same", "Taki sam")) })
                    DashboardWidgetKind.entries.forEach { kind ->
                        FilterChip(selected = value.wideKind == kind, onClick = { value = value.copy(wideKind = kind) }, label = { Text(kind.localizedName()) })
                    }
                }
                if (value.kind == DashboardWidgetKind.HERO || value.kind == DashboardWidgetKind.GAUGE || value.kind == DashboardWidgetKind.CHART) {
                    val metric = value.metrics.firstOrNull() ?: TelemetryMetric.RPM
                    val lowerBound = metric.defaultMin.toFloat()
                    val upperBound = metric.defaultMax.toFloat().coerceAtLeast(lowerBound + 1f)
                    val minimum = (value.gaugeMinimum ?: metric.defaultMin).toFloat().coerceIn(lowerBound, upperBound - .01f)
                    val maximum = (value.gaugeMaximum ?: metric.defaultMax).toFloat().coerceIn(minimum + .01f, upperBound)
                    Text("${appText("Scale minimum", "Minimum skali")}: ${metric.format(minimum.toDouble())} ${metric.unit}")
                    Slider(minimum, { value = value.copy(gaugeMinimum = it.coerceAtMost(maximum - .01f).toDouble()) }, valueRange = lowerBound..upperBound)
                    Text("${appText("Scale maximum", "Maksimum skali")}: ${metric.format(maximum.toDouble())} ${metric.unit}")
                    Slider(maximum, { value = value.copy(gaugeMaximum = it.coerceAtLeast(minimum + .01f).toDouble()) }, valueRange = lowerBound..upperBound)
                }
                if (value.kind == DashboardWidgetKind.CHART) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(30, 180, 600).forEach { seconds -> FilterChip(selected = (value.chartDurationSeconds ?: 30) == seconds, onClick = { value = value.copy(chartDurationSeconds = seconds) }, label = { Text(if (seconds < 60) "30 s" else "${seconds / 60} min") }) }
                }
            }
        },
        confirmButton = { Button(onClick = { save(value.copy(title = title.ifBlank { null })) }, shape = CutCornerShape(8.dp)) { Text(appText("Save", "Zapisz"), fontWeight = FontWeight.Black) } },
        dismissButton = { TextButton(onClick = dismiss) { Text(appText("Cancel", "Anuluj")) } }
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SpanSelector(selected: Int, changed: (Int) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        listOf(0, 2, 3, 4, 6, 12).forEach { span ->
            FilterChip(
                selected = selected == span,
                onClick = { changed(span) },
                label = { Text(if (span == 0) appText("Hidden", "Ukryty") else if (span == 12) appText("Full", "Pełna") else "$span/12") }
            )
        }
    }
}

private fun maximumMetricCount(kind: DashboardWidgetKind): Int = when (kind) {
    DashboardWidgetKind.HERO -> 4
    DashboardWidgetKind.GROUP -> 3
    DashboardWidgetKind.PERFORMANCE -> 0
    else -> 1
}

private fun normalizeMetrics(metrics: List<TelemetryMetric>, kind: DashboardWidgetKind): List<TelemetryMetric> {
    val defaults = listOf(TelemetryMetric.BOOST, TelemetryMetric.MAP, TelemetryMetric.THROTTLE, TelemetryMetric.RPM)
    return List(maximumMetricCount(kind)) { index -> metrics.getOrNull(index) ?: defaults[index] }
}

@Composable
private fun MetricDropdown(selected: TelemetryMetric, changed: (TelemetryMetric) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Button(onClick = { open = true }) { Text("${selected.localizedName()} — ${selected.unit}") }
        DropdownMenu(open, { open = false }) {
            TelemetryMetric.entries.forEach { metric -> DropdownMenuItem(text = { Text("${metric.localizedName()}  ${metric.unit}") }, onClick = { open = false; changed(metric) }) }
        }
    }
}

private suspend fun saveWidgets(container: AppContainer, template: DashboardTemplate, widgets: List<DashboardWidget>) {
    container.dashboardRepository.save(template.copy(definition = DashboardDefinition(widgets), modifiedAt = System.currentTimeMillis()), select = true)
}

private fun moveWidget(values: List<DashboardWidget>, id: String, direction: Int, landscape: Boolean): List<DashboardWidget> {
    val ordered = values.sortedBy { if (landscape) it.landscapeOrder else it.portraitOrder }.toMutableList()
    val index = ordered.indexOfFirst { it.id == id }
    val other = (index + direction).coerceIn(0, ordered.lastIndex)
    if (index < 0 || other == index) return values
    val moved = ordered.removeAt(index); ordered.add(other, moved)
    return ordered.mapIndexed { order, item -> if (landscape) item.copy(landscapeOrder = order) else item.copy(portraitOrder = order) }
}
