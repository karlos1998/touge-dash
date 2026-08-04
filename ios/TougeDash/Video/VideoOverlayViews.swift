import SwiftUI

struct VideoTelemetryOverlayView: View {
    let template: VideoOverlayTemplate
    let sample: TelemetryHistorySample?

    var body: some View {
        GeometryReader { proxy in
            ForEach(VideoOverlaySlot.allCases) { slot in
                let elements = template.elements.filter { $0.slot == slot }
                if !elements.isEmpty {
                    VStack(alignment: horizontalAlignment(for: slot), spacing: max(4, proxy.size.width * 0.008)) {
                        ForEach(elements) { element in
                            VideoOverlayElementView(
                                element: element,
                                style: template.style,
                                sample: sample,
                                canvasWidth: proxy.size.width
                            )
                        }
                    }
                    .frame(maxWidth: proxy.size.width * 0.42, alignment: frameAlignment(for: slot))
                    .position(position(for: slot, in: proxy.size))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func position(for slot: VideoOverlaySlot, in size: CGSize) -> CGPoint {
        let x: CGFloat
        switch slot {
        case .topLeading, .bottomLeading: x = size.width * 0.23
        case .topCenter, .bottomCenter: x = size.width * 0.5
        case .topTrailing, .bottomTrailing: x = size.width * 0.77
        }
        let y: CGFloat
        switch slot {
        case .topLeading, .topCenter, .topTrailing: y = size.height * 0.16
        case .bottomLeading, .bottomCenter, .bottomTrailing: y = size.height * 0.84
        }
        return CGPoint(x: x, y: y)
    }

    private func horizontalAlignment(for slot: VideoOverlaySlot) -> HorizontalAlignment {
        switch slot {
        case .topLeading, .bottomLeading: .leading
        case .topCenter, .bottomCenter: .center
        case .topTrailing, .bottomTrailing: .trailing
        }
    }

    private func frameAlignment(for slot: VideoOverlaySlot) -> Alignment {
        switch slot {
        case .topLeading, .bottomLeading: .leading
        case .topCenter, .bottomCenter: .center
        case .topTrailing, .bottomTrailing: .trailing
        }
    }
}

private struct VideoOverlayElementView: View {
    let element: VideoOverlayElement
    let style: VideoOverlayStyle
    let sample: TelemetryHistorySample?
    let canvasWidth: CGFloat

    private var value: Double { sample.map { element.metric.value(in: $0) } ?? 0 }
    private var scale: CGFloat { max(0.62, canvasWidth / 390) * CGFloat(element.scale.multiplier) }
    private var progress: Double {
        let range = element.metric.defaultRange
        return min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            HStack(alignment: .lastTextBaseline, spacing: 4 * scale) {
                Text(value.formatted(.number.precision(.fractionLength(element.metric.precision))))
                    .font(.system(size: baseValueSize * scale, weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(element.metric.unit)
                    .font(.system(size: 7 * scale, weight: .black))
                    .foregroundStyle(element.accent.color)
            }
            Text(element.metric.shortTitle)
                .font(.system(size: 7 * scale, weight: .black))
                .tracking(0.8 * scale)
                .foregroundStyle(element.accent.color)

            if style != .minimal {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(element.accent.color).frame(width: max(3, geometry.size.width * progress))
                    }
                }
                .frame(height: max(2, 3 * scale))
            }
        }
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 6 * scale)
        .frame(minWidth: 74 * scale, alignment: .leading)
        .background(background)
        .overlay(alignment: .topLeading) {
            if style == .racing {
                Rectangle().fill(element.accent.color).frame(width: 28 * scale, height: 2 * scale)
                    .padding(.leading, 8 * scale)
            }
        }
        .shadow(color: style == .arcade ? element.accent.color.opacity(0.5) : .black.opacity(0.45), radius: 5 * scale)
    }

    private var baseValueSize: CGFloat {
        switch element.scale {
        case .small: 15
        case .medium: 18
        case .large: 23
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .racing:
            CutCornerPanel(cut: 7 * scale)
                .fill(Color.black.opacity(0.72))
                .overlay(CutCornerPanel(cut: 7 * scale).stroke(Color.white.opacity(0.14), lineWidth: 0.7))
        case .arcade:
            RoundedRectangle(cornerRadius: 7 * scale)
                .fill(Color.black.opacity(0.62))
                .overlay(RoundedRectangle(cornerRadius: 7 * scale).stroke(element.accent.color.opacity(0.72), lineWidth: 1.2 * scale))
        case .minimal:
            RoundedRectangle(cornerRadius: 6 * scale)
                .fill(Color.black.opacity(0.42))
        }
    }
}

struct VideoOverlayTemplateManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VideoOverlayTemplateStore
    @State private var editorDraft: VideoOverlayTemplate?
    @State private var showingReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.templates) { template in
                        Button {
                            store.select(template.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.id == store.selectedTemplateID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(template.id == store.selectedTemplateID ? Color.tougeCyan : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).foregroundStyle(.primary)
                                    Text("\(template.style.title) · \(template.elements.count) \(localized("parametrów"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    editorDraft = template
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                } header: {
                    Text(localized("Szablony nakładek"))
                }

                Section {
                    Button {
                        editorDraft = store.createCopy()
                    } label: {
                        Label(localized("Nowa nakładka z kopii"), systemImage: "plus.square.on.square")
                    }
                    Button {
                        showingReset = true
                    } label: {
                        Label(localized("Przywróć gotowe nakładki"), systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle(localized("Nakładki filmu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Gotowe")) { dismiss() }
                }
            }
            .sheet(item: $editorDraft) { template in
                VideoOverlayTemplateEditor(
                    initial: template,
                    canDelete: store.templates.count > 1 && store.templates.contains(where: { $0.id == template.id }),
                    onSave: {
                        store.save($0)
                        editorDraft = nil
                    },
                    onDelete: {
                        store.delete(template.id)
                        editorDraft = nil
                    }
                )
            }
            .confirmationDialog(localized("Przywrócić trzy gotowe nakładki?"), isPresented: $showingReset) {
                Button(localized("Przywróć"), role: .destructive) { store.restoreFactoryTemplates() }
                Button(localized("Anuluj"), role: .cancel) { }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct VideoOverlayTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: VideoOverlayTemplate
    @State private var showingDelete = false
    let canDelete: Bool
    let onSave: (VideoOverlayTemplate) -> Void
    let onDelete: () -> Void

    init(
        initial: VideoOverlayTemplate,
        canDelete: Bool,
        onSave: @escaping (VideoOverlayTemplate) -> Void,
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
                    TextField(localized("Nazwa nakładki"), text: $draft.name)
                    Picker(localized("Styl"), selection: $draft.style) {
                        ForEach(VideoOverlayStyle.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    ForEach($draft.elements) { $element in
                        VideoOverlayElementEditor(element: $element)
                    }
                    .onMove { draft.elements.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.elements.remove(atOffsets: $0) }

                    Button {
                        let used = Set(draft.elements.map(\.metric))
                        let metric = DashboardMetric.allCases.first(where: { !used.contains($0) }) ?? .speed
                        draft.elements.append(VideoOverlayElement(metric: metric, slot: .bottomLeading))
                    } label: {
                        Label(localized("Dodaj parametr"), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(localized("Parametry HUD"))
                } footer: {
                    Text(localized("Kilka parametrów może zajmować tę samą pozycję — zostaną ułożone jeden pod drugim."))
                }

                if canDelete {
                    Section {
                        Button(localized("Usuń nakładkę"), role: .destructive) { showingDelete = true }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(localized("Edytuj nakładkę"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(localized("Anuluj")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Zapisz")) { onSave(draft) }.disabled(draft.elements.isEmpty)
                }
            }
            .confirmationDialog(localized("Usunąć nakładkę?"), isPresented: $showingDelete) {
                Button(localized("Usuń nakładkę"), role: .destructive, action: onDelete)
                Button(localized("Anuluj"), role: .cancel) { }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct VideoOverlayElementEditor: View {
    @Binding var element: VideoOverlayElement

    var body: some View {
        DisclosureGroup {
            Picker(localized("Parametr"), selection: $element.metric) {
                ForEach(DashboardMetric.allCases) { metric in Text(metric.title).tag(metric) }
            }
            Picker(localized("Pozycja"), selection: $element.slot) {
                ForEach(VideoOverlaySlot.allCases) { slot in Text(slot.title).tag(slot) }
            }
            Picker(localized("Rozmiar"), selection: $element.scale) {
                ForEach(VideoOverlayScale.allCases) { scale in Text(scale.title).tag(scale) }
            }
            Picker(localized("Kolor"), selection: $element.accent) {
                ForEach(DashboardAccent.allCases) { accent in
                    HStack(spacing: 8) {
                        Circle().fill(accent.color).frame(width: 12, height: 12)
                        Text(accent.title)
                    }
                    .tag(accent)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: element.metric.icon)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(element.accent.color)
                    .background(element.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.metric.title).font(.headline)
                    Text("\(element.slot.title) · \(element.scale.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
