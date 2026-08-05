package it.letscode.tougedash.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import it.letscode.tougedash.BuildConfig
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.model.ConnectionState
import it.letscode.tougedash.model.DashboardAccent
import it.letscode.tougedash.model.DashboardDefinition
import it.letscode.tougedash.model.DashboardTemplate
import it.letscode.tougedash.model.DashboardWidget
import it.letscode.tougedash.model.DashboardWidgetKind
import it.letscode.tougedash.model.TelemetryConnection
import it.letscode.tougedash.model.TelemetryMetric
import it.letscode.tougedash.model.TelemetrySnapshot
import it.letscode.tougedash.telemetry.TimedTelemetry
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougePanel
import it.letscode.tougedash.ui.theme.TougeRed
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.math.abs

@Composable
fun ConfigurableDashboardScreen(
    container: AppContainer,
    snapshot: TelemetrySnapshot,
    connection: TelemetryConnection,
    preview: Boolean,
    setPreview: (Boolean) -> Unit
) {
    val template by container.dashboardRepository.selected.collectAsState(initial = DashboardTemplate.factory())
    val templates by container.dashboardRepository.templates.collectAsState(initial = listOf(DashboardTemplate.factory()))
    val chartPoints by container.runtime.chartPoints.collectAsState()
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf(false) }
    var editorWidget by remember { mutableStateOf<DashboardWidget?>(null) }
    var templateMenu by remember { mutableStateOf(false) }
    val landscape = LocalConfiguration.current.screenWidthDp > LocalConfiguration.current.screenHeightDp
    val gridState = rememberLazyGridState()
    LaunchedEffect(landscape) { gridState.scrollToItem(0) }
    val widgets = template.definition.widgets.filter { (if (landscape) it.landscapeSpan else it.portraitSpan) > 0 }
        .sortedBy { if (landscape) it.landscapeOrder else it.portraitOrder }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().background(if (editing) TougeCyan.copy(alpha = .12f) else Color.Transparent).padding(horizontal = 12.dp, vertical = if (landscape) 0.dp else 5.dp), verticalAlignment = Alignment.CenterVertically) {
            Box {
                TextButton(onClick = { templateMenu = true }) { Text(template.name, fontWeight = FontWeight.Bold) }
                DropdownMenu(expanded = templateMenu, onDismissRequest = { templateMenu = false }) {
                    templates.forEach { item -> DropdownMenuItem(text = { Text(item.name) }, onClick = { templateMenu = false; scope.launch { container.dashboardRepository.select(item.id) } }) }
                    DropdownMenuItem(text = { Text(appText("New dashboard", "Nowy dashboard")) }, leadingIcon = { Icon(Icons.Default.Add, null) }, onClick = { templateMenu = false; scope.launch { container.dashboardRepository.create() } })
                    DropdownMenuItem(text = { Text(appText("Duplicate", "Duplikuj")) }, leadingIcon = { Icon(Icons.Default.ContentCopy, null) }, onClick = { templateMenu = false; scope.launch { container.dashboardRepository.duplicate(template) } })
                }
            }
            Box(Modifier.weight(1f))
            if (BuildConfig.DEBUG && connection.state != ConnectionState.Connected) TextButton(onClick = { setPreview(!preview) }) { Text(if (preview) "LIVE" else "DEMO") }
            IconButton(onClick = { editing = !editing }) { Icon(if (editing) Icons.Default.Done else Icons.Default.Edit, null, tint = if (editing) TougeMint else TougeCyan) }
        }
        if (editing) Text(appText("EDIT MODE  •  hold and drag a card to move it", "TRYB EDYCJI  •  przytrzymaj i przeciągnij kartę"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        LazyVerticalGrid(
            columns = GridCells.Fixed(12),
            state = gridState,
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = if (landscape) 5.dp else 12.dp)
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
        if (widget.kind == DashboardWidgetKind.CHART) ChartCard(widget, snapshot, chartPoints)
        else DashboardCard(widget, snapshot, landscape)
        if (editing) {
            Row(Modifier.align(Alignment.TopEnd).padding(4.dp)) {
                IconButton(onClick = edit, modifier = Modifier.size(34.dp).background(TougeCyan, CircleShape)) { Icon(Icons.Default.Settings, null, tint = Color.Black, modifier = Modifier.size(18.dp)) }
                IconButton(onClick = remove, modifier = Modifier.size(34.dp).background(TougeRed, CircleShape)) { Icon(Icons.Default.Close, null, tint = Color.White, modifier = Modifier.size(18.dp)) }
            }
        }
    }
}

@Composable
private fun ChartCard(widget: DashboardWidget, snapshot: TelemetrySnapshot, points: List<TimedTelemetry>) {
    val metric = widget.metrics.first()
    val accent = widget.accent.color()
    val duration = widget.chartDurationSeconds ?: 30
    val now = snapshot.updatedAt
    val values = points.filter { now - it.recordedAt <= duration * 1_000L }.map { metric.value(it.snapshot).toFloat() }
    Column(Modifier.fillMaxWidth().background(TougePanel, RoundedCornerShape(3.dp)).padding(14.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(metric.shortName, color = accent, fontWeight = FontWeight.Bold)
            Text("${metric.format(metric.value(snapshot))} ${metric.unit}  •  ${duration}s", fontWeight = FontWeight.Black)
        }
        Canvas(Modifier.fillMaxWidth().size(110.dp)) {
            if (values.size > 1) {
                val min = (widget.gaugeMinimum ?: metric.defaultMin).toFloat()
                val max = (widget.gaugeMaximum ?: metric.defaultMax).toFloat()
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

@Composable
private fun WidgetEditor(initial: DashboardWidget, dismiss: () -> Unit, save: (DashboardWidget) -> Unit) {
    var value by remember(initial.id) { mutableStateOf(initial) }
    var title by remember(initial.id) { mutableStateOf(initial.title.orEmpty()) }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(appText("Dashboard card", "Karta dashboardu")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(appText("TYPE", "TYP"), color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(DashboardWidgetKind.VALUE, DashboardWidgetKind.GAUGE, DashboardWidgetKind.CHART, DashboardWidgetKind.COMPACT).forEach { kind ->
                        FilterChip(selected = value.kind == kind, onClick = { value = value.copy(kind = kind) }, label = { Text(kind.name.lowercase()) })
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
        confirmButton = { Button(onClick = { save(value.copy(title = title.ifBlank { null })) }) { Text(appText("Save", "Zapisz")) } },
        dismissButton = { TextButton(onClick = dismiss) { Text(appText("Cancel", "Anuluj")) } }
    )
}

@Composable
private fun MetricDropdown(selected: TelemetryMetric, changed: (TelemetryMetric) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Button(onClick = { open = true }) { Text("${selected.shortName} — ${selected.unit}") }
        DropdownMenu(open, { open = false }) {
            TelemetryMetric.entries.forEach { metric -> DropdownMenuItem(text = { Text("${metric.shortName}  ${metric.unit}") }, onClick = { open = false; changed(metric) }) }
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
