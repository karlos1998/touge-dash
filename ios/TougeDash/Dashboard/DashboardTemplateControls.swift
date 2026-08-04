import SwiftUI

struct DashboardTemplateBar: View {
    @ObservedObject var store: DashboardTemplateStore
    let compact: Bool
    let onTemplateChanged: () -> Void

    @State private var editorDraft: DashboardTemplateRecord?
    @State private var showingFactoryResetConfirmation = false

    var body: some View {
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
                editorDraft = store.activeTemplate
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
                    }
                    .onDelete { offsets in
                        draft.definition.widgets.remove(atOffsets: offsets)
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
                    Label(localized("Touge Dash wyłącznie odczytuje dane. Konfiguracja dashboardu nie wysyła żadnych wartości ani poleceń do ECU lub EMULOGGERA."), systemImage: "checkmark.shield.fill")
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
    }
}

private struct DashboardWidgetEditorRow: View {
    @Binding var widget: DashboardWidget

    private var maximumMetricCount: Int {
        switch widget.kind {
        case .hero: 4
        case .group: 3
        default: 1
        }
    }

    var body: some View {
        DisclosureGroup {
            TextField(localized("Własny tytuł (opcjonalnie)"), text: titleBinding)

            Picker(localized("Rodzaj karty"), selection: $widget.kind) {
                ForEach(DashboardWidgetKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            Picker(localized("Główny parametr"), selection: metricBinding(at: 0, fallback: .boost)) {
                ForEach(DashboardMetric.allCases) { metric in
                    Label(metric.title, systemImage: metric.icon).tag(metric)
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
                    Label(accent.title, systemImage: "circle.fill")
                        .foregroundStyle(accent.color)
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
                Image(systemName: widget.primaryMetric.icon)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(widget.accent.color)
                    .background(widget.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.title?.isEmpty == false ? widget.title! : widget.primaryMetric.title)
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

    private func normalizeMetrics(for kind: DashboardWidgetKind) {
        let count = kind == .hero ? 4 : (kind == .group ? 3 : 1)
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
