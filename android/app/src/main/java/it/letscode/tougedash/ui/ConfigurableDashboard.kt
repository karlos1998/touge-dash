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
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.DashboardCustomize
import androidx.compose.material.icons.filled.DragHandle
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
import it.letscode.tougedash.telemetry.TimedTelemetry
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeRed
import it.letscode.tougedash.ui.theme.TougeMuted
import kotlinx.coroutines.launch
import kotlin.math.abs

@Composable
fun ConfigurableDashboardScreen(
    container: AppContainer,
    snapshot: TelemetrySnapshot
) {
    val template by container.dashboardRepository.selected.collectAsState(initial = DashboardTemplate.factory())
    val templates by container.dashboardRepository.templates.collectAsState(initial = listOf(DashboardTemplate.factory()))
    val chartPoints by container.runtime.chartPoints.collectAsState()
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf(false) }
    var editorWidget by remember { mutableStateOf<DashboardWidget?>(null) }
    var templateMenu by remember { mutableStateOf(false) }
    val authSession by container.authRepository.session.collectAsState()
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
                    widget, snapshot, chartPoints, landscape, editing,
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
}

@Composable
private fun EditableDashboardCard(
    widget: DashboardWidget,
    snapshot: TelemetrySnapshot,
    chartPoints: List<TimedTelemetry>,
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
        if (widget.kind == DashboardWidgetKind.CHART) ChartCard(widget, snapshot, chartPoints, landscape)
        else DashboardCard(widget, snapshot, landscape)
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
                    listOf(DashboardWidgetKind.VALUE, DashboardWidgetKind.GAUGE, DashboardWidgetKind.CHART, DashboardWidgetKind.COMPACT).forEach { kind ->
                        FilterChip(
                            selected = value.kind == kind,
                            onClick = { value = value.copy(kind = kind, wideKind = null) },
                            modifier = Modifier.widthIn(min = 104.dp),
                            label = { Text(kind.localizedName(), maxLines = 1) }
                        )
                    }
                }
                OutlinedTextField(title, { title = it }, label = { Text(appText("Custom title", "Własny tytuł")) }, singleLine = true)
                Text(appText("PARAMETER", "PARAMETR"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                MetricDropdown(value.metrics.firstOrNull() ?: TelemetryMetric.RPM) { value = value.copy(metrics = listOf(it)) }
                Text(appText("COLOR", "KOLOR"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    DashboardAccent.entries.forEach { accent ->
                        Box(Modifier.size(if (value.accent == accent) 30.dp else 24.dp).background(accent.color(), CircleShape).clickable { value = value.copy(accent = accent) })
                    }
                }
                Text("${appText("Width", "Szerokość")}: ${value.portraitSpan}/12")
                Slider(value.portraitSpan.toFloat(), { value = value.copy(portraitSpan = it.toInt().coerceIn(3, 12)) }, valueRange = 3f..12f, steps = 8)
                if (value.kind == DashboardWidgetKind.GAUGE || value.kind == DashboardWidgetKind.CHART) {
                    Text("${appText("Scale max", "Maksimum skali")}: ${value.gaugeMaximum ?: value.metrics.first().defaultMax}")
                    Slider((value.gaugeMaximum ?: value.metrics.first().defaultMax).toFloat(), { value = value.copy(gaugeMaximum = it.toDouble()) }, valueRange = 1f..value.metrics.first().defaultMax.toFloat().coerceAtLeast(2f))
                }
                if (value.kind == DashboardWidgetKind.CHART) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(30, 180, 600).forEach { seconds -> FilterChip(selected = value.chartDurationSeconds == seconds, onClick = { value = value.copy(chartDurationSeconds = seconds) }, label = { Text(if (seconds < 60) "30 s" else "${seconds / 60} min") }) }
                }
            }
        },
        confirmButton = { Button(onClick = { save(value.copy(title = title.ifBlank { null })) }, shape = CutCornerShape(8.dp)) { Text(appText("Save", "Zapisz"), fontWeight = FontWeight.Black) } },
        dismissButton = { TextButton(onClick = dismiss) { Text(appText("Cancel", "Anuluj")) } }
    )
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
