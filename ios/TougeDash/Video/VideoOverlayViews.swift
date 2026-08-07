import SwiftUI

struct VideoTelemetryOverlayView: View {
    let template: VideoOverlayTemplate
    let sample: TelemetryHistorySample?

    var body: some View {
        GeometryReader { proxy in
            let orientation = VideoOverlayCanvasOrientation(size: proxy.size)
            ForEach(template.elements) { element in
                let position = element.position(for: orientation)
                VideoOverlayElementView(
                    element: element,
                    style: template.style,
                    configuration: template.gaugeConfiguration,
                    sample: sample,
                    canvasSize: proxy.size
                )
                .position(
                    x: proxy.size.width * position.x,
                    y: proxy.size.height * position.y
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct EditableVideoTelemetryOverlayView: View {
    @Binding var template: VideoOverlayTemplate
    @Binding var selectedElementID: UUID?
    let sample: TelemetryHistorySample?
    @State private var magnificationBases: [UUID: Double] = [:]

    var body: some View {
        GeometryReader { proxy in
            let orientation = VideoOverlayCanvasOrientation(size: proxy.size)
            ForEach($template.elements) { $element in
                let position = element.position(for: orientation)
                VideoOverlayElementView(
                    element: element,
                    style: template.style,
                    configuration: template.gaugeConfiguration,
                    sample: sample,
                    canvasSize: proxy.size
                )
                .overlay {
                    if selectedElementID == element.id {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .padding(-5)
                    }
                }
                .contentShape(Rectangle())
                .position(
                    x: proxy.size.width * position.x,
                    y: proxy.size.height * position.y
                )
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("video-overlay-canvas"))
                        .onChanged { value in
                            selectedElementID = element.id
                            element.setPosition(
                                VideoOverlayPosition(
                                    x: value.location.x / max(1, proxy.size.width),
                                    y: value.location.y / max(1, proxy.size.height)
                                ),
                                for: orientation
                            )
                        }
                        .simultaneously(with:
                            MagnificationGesture()
                                .onChanged { value in
                                    selectedElementID = element.id
                                    let base = magnificationBases[element.id] ?? element.sizeMultiplier
                                    if magnificationBases[element.id] == nil {
                                        magnificationBases[element.id] = base
                                    }
                                    element.setSizeMultiplier(base * value)
                                }
                                .onEnded { _ in
                                    magnificationBases[element.id] = nil
                                }
                        )
                )
            }
        }
        .coordinateSpace(name: "video-overlay-canvas")
    }
}

private struct VideoOverlayElementView: View {
    let element: VideoOverlayElement
    let style: VideoOverlayStyle
    let configuration: VideoOverlayGaugeConfiguration
    let sample: TelemetryHistorySample?
    let canvasSize: CGSize

    private var value: Double { sample.map { element.metric.value(in: $0) } ?? 0 }
    private var scale: CGFloat {
        max(0.48, min(canvasSize.width / 390, canvasSize.height / 220)) * CGFloat(element.effectiveScale)
    }
    private var progress: Double {
        let range = configuration.range(for: element.metric)
        return min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var body: some View {
        Group {
            switch element.kind {
            case .digital: digitalValue
            case .gauge: gaugeValue
            case .bar: barValue
            case .speedCluster: speedCluster
            case .oilCluster: oilCluster
            }
        }
        .shadow(color: shadowColor, radius: 5 * scale)
    }

    private var digitalValue: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            HStack(alignment: .lastTextBaseline, spacing: 4 * scale) {
                Text(value.formatted(.number.precision(.fractionLength(element.metric.precision))))
                    .font(.system(size: 19 * scale, weight: .black, design: .rounded))
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
        .frame(width: 94 * scale, alignment: .leading)
        .background(background)
        .overlay(alignment: .topLeading) {
            if style == .racing {
                Rectangle().fill(element.accent.color).frame(width: 28 * scale, height: 2 * scale)
                    .padding(.leading, 8 * scale)
            }
        }
    }

    private var gaugeValue: some View {
        ZStack {
            dialFace(metric: element.metric, value: value, accent: element.accent.color)

            VStack(spacing: 0) {
                Text(element.metric.shortTitle)
                    .font(.system(size: 6.5 * scale, weight: .black))
                    .tracking(0.8 * scale)
                    .foregroundStyle(element.accent.color)
                HStack(alignment: .lastTextBaseline, spacing: 3 * scale) {
                    Text(value.formatted(.number.precision(.fractionLength(element.metric.precision))))
                        .font(.system(size: 22 * scale, weight: .black, design: .rounded))
                        .fontWidth(.expanded)
                        .monospacedDigit()
                    Text(element.metric.unit)
                        .font(.system(size: 6 * scale, weight: .black))
                        .foregroundStyle(.secondary)
                }
            }
            .offset(y: 5 * scale)
        }
        .foregroundStyle(.white)
        .frame(width: 102 * scale, height: 102 * scale)
        .padding(5 * scale)
        .background(Color.black.opacity(style == .minimal ? 0.28 : 0.5), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: max(0.5, scale * 0.6)))
    }

    private var speedCluster: some View {
        ZStack {
            dialFace(metric: .speed, value: metricValue(.speed), accent: element.accent.color)
            VStack(spacing: 0) {
                Text("RPM \(Int(metricValue(.rpm)))")
                    .font(.system(size: 6 * scale, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                Text(Int(metricValue(.speed)).formatted())
                    .font(.system(size: 24 * scale, weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .monospacedDigit()
                Text("km/h")
                    .font(.system(size: 6 * scale, weight: .black))
                    .foregroundStyle(element.accent.color)
                boostStrip
            }
            .offset(y: 7 * scale)
        }
        .frame(width: 126 * scale, height: 126 * scale)
        .background(Color.black.opacity(0.78), in: Circle())
        .overlay(Circle().stroke(element.accent.color.opacity(0.55), lineWidth: 1.2 * scale))
    }

    private var oilCluster: some View {
        ZStack {
            dialFace(metric: .oilTemperature, value: metricValue(.oilTemperature), accent: element.accent.color)
            VStack(spacing: 0) {
                Text("OIL TEMP")
                    .font(.system(size: 6 * scale, weight: .black))
                    .foregroundStyle(element.accent.color)
                Text("\(Int(metricValue(.oilTemperature)))°")
                    .font(.system(size: 22 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text("OIL P  \(metricValue(.oilPressure).formatted(.number.precision(.fractionLength(1)))) bar")
                    .font(.system(size: 6 * scale, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .offset(y: 6 * scale)
        }
        .frame(width: 116 * scale, height: 116 * scale)
        .background(Color(red: 0.07, green: 0.025, blue: 0.015).opacity(0.88), in: Circle())
        .overlay(Circle().stroke(element.accent.color.opacity(0.7), lineWidth: 1.2 * scale))
    }

    private func dialFace(metric: DashboardMetric, value: Double, accent: Color) -> some View {
        let dialProgress = progress(for: metric, value: value)
        return ZStack {
            ForEach(0..<25, id: \.self) { index in
                Capsule()
                    .fill(index % 4 == 0 ? Color.white.opacity(0.9) : Color.white.opacity(0.32))
                    .frame(width: max(0.7, scale), height: (index % 4 == 0 ? 7 : 4) * scale)
                    .offset(y: -42 * scale)
                    .rotationEffect(.degrees(-120 + Double(index) * 10))
            }
            ForEach(0..<7, id: \.self) { index in
                let range = configuration.range(for: metric)
                let labelValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(index) / 6
                let angle = (-120 + Double(index) * 40) * Double.pi / 180
                Text(scaleLabel(labelValue, metric: metric))
                    .font(.system(size: 4.8 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.72))
                    .offset(
                        x: sin(angle) * 31 * scale,
                        y: -cos(angle) * 31 * scale
                    )
            }
            Circle()
                .trim(from: 0.165, to: 0.835)
                .stroke(accent.opacity(0.28), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                .rotationEffect(.degrees(60))
            Capsule()
                .fill(accent)
                .frame(width: 2.2 * scale, height: 34 * scale)
                .offset(y: -17 * scale)
                .rotationEffect(.degrees(-120 + 240 * dialProgress))
                .shadow(color: accent.opacity(0.9), radius: 3 * scale)
            Circle().fill(.white).frame(width: 6 * scale, height: 6 * scale)
        }
    }

    private var boostStrip: some View {
        let boostProgress = progress(for: .boost, value: metricValue(.boost))
        return VStack(spacing: 1 * scale) {
            Text("BOOST  \(metricValue(.boost).formatted(.number.precision(.fractionLength(1))))")
                .font(.system(size: 5 * scale, weight: .black, design: .monospaced))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(Color.tougeMint).frame(width: max(2, geometry.size.width * boostProgress))
                }
            }
            .frame(width: 48 * scale, height: 3 * scale)
        }
    }

    private func metricValue(_ metric: DashboardMetric) -> Double {
        sample.map { metric.value(in: $0) } ?? 0
    }

    private func progress(for metric: DashboardMetric, value: Double) -> Double {
        let range = configuration.range(for: metric)
        return min(1, max(0, (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)))
    }

    private func scaleLabel(_ value: Double, metric: DashboardMetric) -> String {
        if metric == .rpm { return "\(Int(value / 1_000))k" }
        if metric == .boost { return value.formatted(.number.precision(.fractionLength(1))) }
        return Int(value).formatted()
    }

    private var barValue: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(alignment: .lastTextBaseline) {
                Text(element.metric.shortTitle)
                    .font(.system(size: 7 * scale, weight: .black))
                    .tracking(0.8 * scale)
                    .foregroundStyle(element.accent.color)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(element.metric.precision))))
                    .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(element.metric.unit)
                    .font(.system(size: 6 * scale, weight: .black))
                    .foregroundStyle(.secondary)
            }

            if style == .arcade, element.metric == .rpm {
                HStack(spacing: 2 * scale) {
                    ForEach(0..<12, id: \.self) { index in
                        let threshold = Double(index + 1) / 12
                        Capsule()
                            .fill(threshold <= progress ? shiftLightColor(index) : Color.white.opacity(0.12))
                    }
                }
                .frame(height: 6 * scale)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(element.accent.color)
                            .frame(width: max(3, geometry.size.width * progress))
                    }
                }
                .frame(height: 5 * scale)
            }
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 7 * scale)
        .frame(width: 190 * scale)
        .background(background)
    }

    private func shiftLightColor(_ index: Int) -> Color {
        switch index {
        case 0..<7: element.accent.color
        case 7..<10: .tougeOrange
        default: .tougeRed
        }
    }

    private var shadowColor: Color {
        style == .arcade ? element.accent.color.opacity(0.42) : .black.opacity(0.45)
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
            .confirmationDialog(localized("Przywrócić gotowe nakładki?"), isPresented: $showingReset) {
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

                Section(localized("Skale zegarów")) {
                    Stepper(
                        "\(localized("Prędkość maks.")): \(Int(draft.gaugeConfiguration.maximumSpeedKPH)) km/h",
                        value: $draft.gaugeConfiguration.maximumSpeedKPH,
                        in: 100...450,
                        step: 10
                    )
                    Stepper(
                        "\(localized("Temperatura oleju maks.")): \(Int(draft.gaugeConfiguration.maximumOilTemperatureCelsius))°C",
                        value: $draft.gaugeConfiguration.maximumOilTemperatureCelsius,
                        in: 80...180,
                        step: 5
                    )
                    Stepper(
                        "RPM maks.: \(Int(draft.gaugeConfiguration.maximumRPM))",
                        value: $draft.gaugeConfiguration.maximumRPM,
                        in: 4_000...12_000,
                        step: 500
                    )
                    Stepper(
                        "Boost maks.: \(draft.gaugeConfiguration.maximumBoostBar.formatted(.number.precision(.fractionLength(1)))) bar",
                        value: $draft.gaugeConfiguration.maximumBoostBar,
                        in: 0.5...4,
                        step: 0.1
                    )
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
                    Text(localized("Przeciągnij element jednym palcem, a dwoma palcami zmień jego rozmiar bezpośrednio na podglądzie filmu."))
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
            Picker(localized("Wygląd"), selection: $element.kind) {
                ForEach(VideoOverlayElementKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.icon).tag(kind)
                }
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
                    Text("\(element.kind.title) · \(element.scale.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
