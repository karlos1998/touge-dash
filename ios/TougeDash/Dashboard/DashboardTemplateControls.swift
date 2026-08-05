import SwiftUI

struct DashboardTemplateBar: View {
    @ObservedObject var store: DashboardTemplateStore
    @Binding var isEditingDashboard: Bool
    let compact: Bool
    let onTemplateChanged: () -> Void

    @State private var editorDraft: DashboardTemplateRecord?
    @State private var showingFactoryResetConfirmation = false

    var body: some View {
        Group {
            if isEditingDashboard {
                editingBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                regularBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.24), value: isEditingDashboard)
        .sheet(item: $editorDraft) { draft in
            DashboardTemplateEditor(
                initial: draft,
                canDelete: store.templates.count > 1 && store.templates.contains(where: { $0.id == draft.id }),
                onSave: {
                    store.save($0)
                    editorDraft = nil
                    onTemplateChanged()
                },
                onDelete: {
                    store.delete(draft.id)
                    editorDraft = nil
                    isEditingDashboard = false
                    onTemplateChanged()
                }
            )
        }
        .confirmationDialog(
            localized("Przywrócić fabryczny dashboard?"),
            isPresented: $showingFactoryResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("Przywróć"), role: .destructive) {
                store.restoreFactoryTemplate()
                onTemplateChanged()
            }
            Button(localized("Anuluj"), role: .cancel) { }
        } message: {
            Text(localized("Fabryczny układ wróci do ustawień początkowych. Pozostałe dashboardy nie zostaną zmienione."))
        }
    }

    private var regularBar: some View {
        HStack(spacing: compact ? 7 : 10) {
            Menu {
                Section(localized("Zapisane dashboardy")) {
                    ForEach(store.templates) { template in
                        Button {
                            store.select(template.id)
                        } label: {
                            Label(template.name, systemImage: template.id == store.activeTemplateID ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }

                Section {
                    Button {
                        editorDraft = DashboardTemplateRecord(
                            name: localized("Nowy dashboard"),
                            definition: store.activeTemplate.definition
                        )
                    } label: {
                        Label(localized("Nowy dashboard"), systemImage: "plus")
                    }

                    Button {
                        let source = store.activeTemplate
                        editorDraft = DashboardTemplateRecord(
                            name: String(format: localized("Kopia %@"), source.name),
                            definition: source.definition
                        )
                    } label: {
                        Label(localized("Duplikuj bieżący"), systemImage: "square.on.square")
                    }

                    Button {
                        showingFactoryResetConfirmation = true
                    } label: {
                        Label(localized("Przywróć fabryczny"), systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                HStack(spacing: compact ? 6 : 8) {
                    Image(systemName: "rectangle.3.group.fill")
                        .foregroundStyle(Color.tougeCyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.activeTemplate.name)
                            .font(.system(size: compact ? 10 : 12, weight: .bold))
                            .lineLimit(1)
                        Text(syncLabel)
                            .font(.system(size: compact ? 6 : 8, weight: .black))
                            .tracking(0.7)
                            .foregroundStyle(syncColor)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: compact ? 8 : 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, compact ? 10 : 12)
                .padding(.vertical, compact ? 7 : 9)
                .background(Color.white.opacity(0.055), in: CutCornerPanel(cut: 8))
                .overlay(CutCornerPanel(cut: 8).stroke(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Button {
                isEditingDashboard = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    if !compact {
                        Text(localized("Edytuj dashboard"))
                    }
                }
                    .font(.system(size: compact ? 10 : 12, weight: .bold))
                    .frame(minWidth: compact ? 34 : 124)
                    .padding(.horizontal, compact ? 4 : 10)
                    .padding(.vertical, compact ? 9 : 11)
                    .foregroundStyle(Color.black)
                    .background(Color.tougeCyan, in: CutCornerPanel(cut: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var editingBar: some View {
        ViewThatFits(in: .horizontal) {
            editingBarContent(narrow: false)
                .fixedSize(horizontal: true, vertical: false)
            editingBarContent(narrow: true)
        }
        .padding(.horizontal, compact ? 9 : 12)
        .padding(.vertical, compact ? 7 : 9)
        .background(Color.tougeCyan.opacity(0.065), in: CutCornerPanel(cut: 10))
        .overlay(CutCornerPanel(cut: 10).stroke(Color.tougeCyan.opacity(0.32), lineWidth: 1))
    }

    private func editingBarContent(narrow: Bool) -> some View {
        HStack(spacing: compact || narrow ? 7 : 10) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: compact || narrow ? 13 : 16, weight: .bold))
                .foregroundStyle(Color.tougeCyan)
                .frame(width: compact || narrow ? 30 : 38, height: compact || narrow ? 30 : 38)
                .background(Color.tougeCyan.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(localized("EDYTUJESZ DASHBOARD"))
                    .font(.system(size: compact || narrow ? 8 : 10, weight: .black))
                    .tracking(narrow ? 0.65 : 1.05)
                    .foregroundStyle(Color.tougeCyan)
                    .lineLimit(narrow ? 2 : 1)
                if !compact && !narrow {
                    Text(localized("Przeciągnij kartę na inną, aby zamienić je miejscami."))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer(minLength: 2)

            Button {
                editorDraft = store.activeTemplate
            } label: {
                Group {
                    if narrow {
                        VStack(spacing: 2) {
                            Image(systemName: "slider.horizontal.3")
                            Text(localized("Zaawansowane"))
                                .font(.system(size: 7, weight: .black))
                                .lineLimit(1)
                        }
                    } else {
                        Label(localized("Zaawansowane"), systemImage: "slider.horizontal.3")
                    }
                }
                    .font(.system(size: compact || narrow ? 11 : 12, weight: .bold))
                    .frame(width: narrow ? 78 : nil)
                    .padding(.horizontal, compact ? 9 : (narrow ? 0 : 12))
                    .padding(.vertical, compact || narrow ? 7 : 10)
                    .background(Color.white.opacity(0.075), in: CutCornerPanel(cut: 7))
                    .overlay(CutCornerPanel(cut: 7).stroke(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Edycja zaawansowana dashboardu"))

            Button {
                isEditingDashboard = false
            } label: {
                Group {
                    if narrow {
                        VStack(spacing: 2) {
                            Image(systemName: "checkmark")
                            Text(localized("Gotowe"))
                                .font(.system(size: 7, weight: .black))
                                .lineLimit(1)
                        }
                    } else {
                        Label(localized("Gotowe"), systemImage: "checkmark")
                    }
                }
                    .font(.system(size: compact || narrow ? 11 : 12, weight: .black))
                    .frame(width: narrow ? 54 : nil)
                    .padding(.horizontal, compact ? 10 : (narrow ? 0 : 14))
                    .padding(.vertical, compact || narrow ? 7 : 10)
                    .foregroundStyle(Color.black)
                    .background(Color.tougeCyan, in: CutCornerPanel(cut: 7))
            }
            .buttonStyle(.plain)
        }
    }

    private var syncLabel: String {
        switch store.syncState {
        case .localOnly: localized("TYLKO NA URZĄDZENIU")
        case .pending: localized("CZEKA NA SYNCHRONIZACJĘ")
        case .syncing: localized("SYNCHRONIZACJA")
        case .synchronized: localized("ZAPISANO ONLINE")
        case .failed: localized("BŁĄD SYNCHRONIZACJI")
        }
    }

    private var syncColor: Color {
        switch store.syncState {
        case .failed: .tougeRed
        case .pending: .tougeOrange
        case .syncing: .tougeCyan
        case .synchronized: .tougeMint
        case .localOnly: .secondary
        }
    }
}

struct DashboardTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DashboardTemplateRecord
    @State private var showingDeleteConfirmation = false

    let canDelete: Bool
    let onSave: (DashboardTemplateRecord) -> Void
    let onDelete: () -> Void

    init(
        initial: DashboardTemplateRecord,
        canDelete: Bool,
        onSave: @escaping (DashboardTemplateRecord) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: initial)
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(localized("Nazwa dashboardu"), text: $draft.name)
                } header: {
                    Text(localized("Dashboard"))
                } footer: {
                    Text(localized("Szablon jest zawsze dostępny offline. Po zalogowaniu synchronizuje się z kontem Touge Dash."))
                }

                Section {
                    ForEach($draft.definition.widgets) { $widget in
                        DashboardWidgetEditorRow(widget: $widget)
                    }
                    .onMove { source, destination in
                        draft.definition.widgets.move(fromOffsets: source, toOffset: destination)
                        resetWidgetOrders()
                    }
                    .onDelete { offsets in
                        draft.definition.widgets.remove(atOffsets: offsets)
                        resetWidgetOrders()
                    }

                    Button {
                        addWidget()
                    } label: {
                        Label(localized("Dodaj kartę"), systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.tougeCyan)
                    }
                } header: {
                    Text(localized("Karty i kolejność"))
                } footer: {
                    Text(localized("Przeciągnij karty w trybie edycji. Szerokość telefonu i widoku poziomego ustawisz osobno."))
                }

                Section {
                    Label(localized("Karty parametrów pozostają tylko do odczytu. Karta sterowania wysyła wyłącznie stan BT Switch lub BT Rotary po potwierdzonej synchronizacji z EMU."), systemImage: "checkmark.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.tougeMint)
                }

                if canDelete {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label(localized("Usuń dashboard"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(localized("Układ dashboardu"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Anuluj")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Zapisz")) { onSave(draft) }
                        .disabled(draft.definition.widgets.isEmpty)
                }
            }
            .confirmationDialog(
                localized("Usunąć ten dashboard?"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(localized("Usuń dashboard"), role: .destructive, action: onDelete)
                Button(localized("Anuluj"), role: .cancel) { }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func addWidget() {
        let order = draft.definition.widgets.count
        draft.definition.widgets.append(
            DashboardWidget(
                kind: .value,
                metrics: [.boost],
                portraitSpan: .half,
                landscapeSpan: .third,
                portraitOrder: order,
                accent: .cyan
            )
        )
        resetWidgetOrders()
    }

    private func resetWidgetOrders() {
        for index in draft.definition.widgets.indices {
            draft.definition.widgets[index].portraitOrder = index
            draft.definition.widgets[index].landscapeOrder = index
        }
    }
}

struct DashboardWidgetQuickEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DashboardWidget

    let onSave: (DashboardWidget) -> Void

    init(initial: DashboardWidget, onSave: @escaping (DashboardWidget) -> Void) {
        _draft = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                DashboardWidgetEditorRow(widget: $draft, initiallyExpanded: true)

                Section {
                    Label(
                        localized("Konfiguracja wyglądu nie jest wysyłana do ECU. Dopiero użycie gotowej karty sterowania może zmienić przypisany BT Switch lub BT Rotary."),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.tougeMint)
                }
            }
            .navigationTitle(localized("Edytuj kartę"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Anuluj")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Zapisz")) { onSave(draft) }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct DashboardWidgetEditorRow: View {
    @Binding var widget: DashboardWidget
    @State private var isExpanded: Bool

    init(widget: Binding<DashboardWidget>, initiallyExpanded: Bool = false) {
        _widget = widget
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    private var maximumMetricCount: Int {
        switch widget.kind {
        case .hero: 4
        case .group: 3
        case .performance, .ecuSwitch, .ecuRotary: 0
        default: 1
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            TextField(localized("Własny tytuł (opcjonalnie)"), text: titleBinding)

            Picker(localized("Rodzaj karty"), selection: $widget.kind) {
                ForEach(DashboardWidgetKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            if widget.kind == .performance {
                Section(localized("Widoczne pomiary")) {
                    ForEach(AccelerationType.allCases) { type in
                        Toggle("\(type.label) km/h", isOn: accelerationTypeBinding(type))
                    }
                }
            } else if widget.kind == .ecuSwitch || widget.kind == .ecuRotary {
                Picker(localized("Kanał ECU"), selection: controlChannelBinding) {
                    ForEach(ECUControlSnapshot.channelRange, id: \.self) { channel in
                        Text(widget.kind == .ecuSwitch ? "BT Switch \(channel)" : "BT Rotary \(channel)")
                            .tag(channel)
                    }
                }
                Label(
                    localized("Stan zostanie odczytany z EMU po połączeniu. Karta nie używa zapamiętanej wartości z telefonu."),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Picker(localized("Główny parametr"), selection: metricBinding(at: 0, fallback: .boost)) {
                    ForEach(DashboardMetric.allCases) { metric in
                        Label(metric.title, systemImage: metric.icon).tag(metric)
                    }
                }
            }

            if maximumMetricCount > 1 {
                ForEach(1..<maximumMetricCount, id: \.self) { index in
                    Picker(String(format: localized("Parametr %d"), index + 1), selection: metricBinding(at: index, fallback: fallbackMetric(at: index))) {
                        ForEach(DashboardMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                }
            }

            Picker(localized("Szerokość pionowo"), selection: $widget.portraitSpan) {
                ForEach(DashboardWidgetSpan.allCases) { span in Text(span.title).tag(span) }
            }

            Picker(localized("Szerokość poziomo"), selection: $widget.landscapeSpan) {
                ForEach(DashboardWidgetSpan.allCases) { span in Text(span.title).tag(span) }
            }

            Picker(localized("Kolor"), selection: $widget.accent) {
                ForEach(DashboardAccent.allCases) { accent in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 12, height: 12)
                        Text(accent.title)
                    }
                        .tag(accent)
                }
            }

            if widget.kind == .gauge || widget.kind == .hero {
                HStack {
                    TextField(localized("Minimum"), value: minimumBinding, format: .number)
                        .keyboardType(.numbersAndPunctuation)
                    TextField(localized("Maksimum"), value: maximumBinding, format: .number)
                        .keyboardType(.numbersAndPunctuation)
                }
            }

            if widget.kind == .chart {
                Picker(localized("Zakres czasu"), selection: chartDurationBinding) {
                    ForEach(DashboardChartDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: widget.displayIcon)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(widget.accent.color)
                    .background(widget.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.displayTitle)
                        .font(.headline)
                    Text(widget.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: widget.kind) { _, kind in
            normalizeMetrics(for: kind)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { widget.title ?? "" },
            set: { widget.title = $0.isEmpty ? nil : $0 }
        )
    }

    private func metricBinding(at index: Int, fallback: DashboardMetric) -> Binding<DashboardMetric> {
        Binding(
            get: { widget.metrics.indices.contains(index) ? widget.metrics[index] : fallback },
            set: { value in
                while widget.metrics.count <= index { widget.metrics.append(fallback) }
                widget.metrics[index] = value
            }
        )
    }

    private func accelerationTypeBinding(_ type: AccelerationType) -> Binding<Bool> {
        Binding(
            get: { (widget.accelerationTypes ?? AccelerationType.allCases).contains(type) },
            set: { enabled in
                var values = widget.accelerationTypes ?? AccelerationType.allCases
                if enabled, !values.contains(type) { values.append(type) }
                if !enabled, values.count > 1 { values.removeAll { $0 == type } }
                widget.accelerationTypes = values
            }
        )
    }

    private func fallbackMetric(at index: Int) -> DashboardMetric {
        let defaults: [DashboardMetric] = [.boost, .rpm, .throttle, .speed]
        return defaults[min(index, defaults.count - 1)]
    }

    private var minimumBinding: Binding<Double> {
        Binding(
            get: { widget.gaugeMinimum ?? widget.primaryMetric.defaultRange.lowerBound },
            set: { widget.gaugeMinimum = $0 }
        )
    }

    private var maximumBinding: Binding<Double> {
        Binding(
            get: { widget.gaugeMaximum ?? widget.primaryMetric.defaultRange.upperBound },
            set: { widget.gaugeMaximum = $0 }
        )
    }

    private var chartDurationBinding: Binding<DashboardChartDuration> {
        Binding(
            get: { widget.chartDuration ?? .thirtySeconds },
            set: { widget.chartDuration = $0 }
        )
    }

    private var controlChannelBinding: Binding<Int> {
        Binding(
            get: { min(8, max(1, widget.controlChannel ?? 1)) },
            set: { widget.controlChannel = min(8, max(1, $0)) }
        )
    }

    private func normalizeMetrics(for kind: DashboardWidgetKind) {
        let isControl = kind == .ecuSwitch || kind == .ecuRotary
        let count = kind == .hero ? 4 : (kind == .group ? 3 : ((kind == .performance || isControl) ? 0 : 1))
        if count == 0 {
            widget.metrics = []
            widget.wideKind = nil
            widget.controlChannel = isControl ? min(8, max(1, widget.controlChannel ?? 1)) : nil
            return
        }
        widget.controlChannel = nil
        while widget.metrics.count < count {
            widget.metrics.append(fallbackMetric(at: widget.metrics.count))
        }
        widget.metrics = Array(widget.metrics.prefix(count))
        widget.wideKind = nil
        if kind == .chart, widget.chartDuration == nil { widget.chartDuration = .thirtySeconds }
        if kind == .gauge || kind == .hero {
            widget.gaugeMinimum = widget.gaugeMinimum ?? widget.primaryMetric.defaultRange.lowerBound
            widget.gaugeMaximum = widget.gaugeMaximum ?? widget.primaryMetric.defaultRange.upperBound
        }
    }
}
