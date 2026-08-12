import Charts
import SwiftUI

struct ConfigurableDashboardView: View {
    let template: DashboardTemplateRecord
    let snapshot: TelemetrySnapshot
    @ObservedObject var telemetryBuffer: DashboardTelemetryBuffer
    @ObservedObject var accelerationEngine: AccelerationEngine
    @ObservedObject var ecuControls: ECUControlCoordinator
    let isWide: Bool
    let compact: Bool
    let isEditing: Bool
    let canDeleteWidgets: Bool
    let onEditWidget: (DashboardWidget) -> Void
    let onDeleteWidget: (DashboardWidget) -> Void
    let onSwapWidgets: (UUID, UUID) -> Void

    private var widgets: [DashboardWidget] {
        template.definition.widgets
            .filter { (isWide ? $0.landscapeSpan : $0.portraitSpan) != .hidden }
            .sorted {
                let lhs = isWide ? $0.landscapeOrder : $0.portraitOrder
                let rhs = isWide ? $1.landscapeOrder : $1.portraitOrder
                return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
            }
    }

    private var rows: [[DashboardWidget]] {
        DashboardGridLayout.rows(for: widgets, isWide: isWide)
    }

    var body: some View {
        let spacing: CGFloat = compact ? 8 : 12
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                DashboardGridRow(
                    widgets: row,
                    snapshot: snapshot,
                    telemetryBuffer: telemetryBuffer,
                    accelerationEngine: accelerationEngine,
                    ecuControls: ecuControls,
                    isWide: isWide,
                    compact: compact,
                    spacing: spacing,
                    isEditing: isEditing,
                    canDeleteWidgets: canDeleteWidgets,
                    onEditWidget: onEditWidget,
                    onDeleteWidget: onDeleteWidget,
                    onSwapWidgets: onSwapWidgets
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DashboardGridRow: View {
    let widgets: [DashboardWidget]
    let snapshot: TelemetrySnapshot
    @ObservedObject var telemetryBuffer: DashboardTelemetryBuffer
    @ObservedObject var accelerationEngine: AccelerationEngine
    @ObservedObject var ecuControls: ECUControlCoordinator
    let isWide: Bool
    let compact: Bool
    let spacing: CGFloat
    let isEditing: Bool
    let canDeleteWidgets: Bool
    let onEditWidget: (DashboardWidget) -> Void
    let onDeleteWidget: (DashboardWidget) -> Void
    let onSwapWidgets: (UUID, UUID) -> Void

    private var occupiedColumns: Int {
        widgets.reduce(0) { $0 + span(for: $1) }
    }

    private var height: CGFloat {
        widgets.map { DashboardGridLayout.height(for: $0, isWide: isWide, compact: compact) }.max() ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = max(0, (proxy.size.width - (spacing * 11)) / 12)

            HStack(alignment: .top, spacing: spacing) {
                ForEach(widgets) { widget in
                    EditableDashboardWidget(
                        widget: widget,
                        snapshot: snapshot,
                        telemetryBuffer: telemetryBuffer,
                        accelerationEngine: accelerationEngine,
                        ecuControls: ecuControls,
                        isWide: isWide,
                        compact: compact,
                        isEditing: isEditing,
                        canDelete: canDeleteWidgets,
                        onEdit: { onEditWidget(widget) },
                        onDelete: { onDeleteWidget(widget) },
                        onSwap: { sourceID in onSwapWidgets(sourceID, widget.id) }
                    )
                    .frame(
                        width: width(for: span(for: widget), columnWidth: columnWidth),
                        height: DashboardGridLayout.height(for: widget, isWide: isWide, compact: compact)
                    )
                    .clipped()
                }

                if occupiedColumns < 12 {
                    Color.clear
                        .frame(
                            width: width(for: 12 - occupiedColumns, columnWidth: columnWidth),
                            height: 1
                        )
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: height)
    }

    private func span(for widget: DashboardWidget) -> Int {
        (isWide ? widget.landscapeSpan : widget.portraitSpan).rawValue
    }

    private func width(for columns: Int, columnWidth: CGFloat) -> CGFloat {
        (columnWidth * CGFloat(columns)) + (spacing * CGFloat(max(0, columns - 1)))
    }
}

private struct EditableDashboardWidget: View {
    let widget: DashboardWidget
    let snapshot: TelemetrySnapshot
    @ObservedObject var telemetryBuffer: DashboardTelemetryBuffer
    @ObservedObject var accelerationEngine: AccelerationEngine
    @ObservedObject var ecuControls: ECUControlCoordinator
    let isWide: Bool
    let compact: Bool
    let isEditing: Bool
    let canDelete: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSwap: (UUID) -> Void

    @State private var isWobbling = false
    @State private var isDropTarget = false

    var body: some View {
        Group {
            if isEditing {
                editableContent
                    .draggable(widget.id.uuidString) {
                        dragPreview
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let rawID = items.first,
                              let sourceID = UUID(uuidString: rawID),
                              sourceID != widget.id else {
                            return false
                        }
                        onSwap(sourceID)
                        return true
                    } isTargeted: { targeted in
                        withAnimation(.easeOut(duration: 0.14)) {
                            isDropTarget = targeted
                        }
                    }
                    .onAppear(perform: startWobble)
                    .onDisappear {
                        isWobbling = false
                        isDropTarget = false
                    }
            } else {
                dashboardContent
            }
        }
        .accessibilityElement(children: isEditing ? .contain : .combine)
    }

    private var editableContent: some View {
        dashboardContent
            .saturation(0.82)
            .scaleEffect(isDropTarget ? 0.965 : 0.985)
            .rotationEffect(.degrees(isWobbling ? 0.32 : -0.32))
            .overlay {
                if isDropTarget {
                    CutCornerPanel(cut: 12)
                        .stroke(Color.tougeCyan, lineWidth: 2)
                        .shadow(color: Color.tougeCyan.opacity(0.65), radius: 9)
                }
            }
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 5) {
                    editButton(
                        icon: "xmark",
                        tint: .tougeRed,
                        enabled: canDelete,
                        accessibilityLabel: localized("Usuń kartę"),
                        action: onDelete
                    )

                    Spacer(minLength: 0)

                    Group {
                        if showsDragTitle {
                            Label(localized("PRZECIĄGNIJ"), systemImage: "line.3.horizontal")
                        } else {
                            Image(systemName: "line.3.horizontal")
                        }
                    }
                        .font(.system(size: showsDragTitle ? 8 : 10, weight: .black))
                        .tracking(showsDragTitle ? 0.7 : 0)
                        .foregroundStyle(Color.primary.opacity(0.8))
                        .padding(.horizontal, showsDragTitle ? 9 : 8)
                        .frame(height: compact ? 26 : 30)
                        .background(.black.opacity(0.72), in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.15)))

                    Spacer(minLength: 0)

                    editButton(
                        icon: "pencil",
                        tint: .tougeCyan,
                        enabled: true,
                        accessibilityLabel: localized("Edytuj kartę"),
                        action: onEdit
                    )
                }
                .padding(compact ? 5 : 7)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.88), Color.black.opacity(0.62), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .contentShape(Rectangle())
    }

    private var showsDragTitle: Bool {
        !compact && (isWide ? widget.landscapeSpan : widget.portraitSpan) == .full
    }

    private var dashboardContent: some View {
        DashboardWidgetView(
            widget: widget,
            snapshot: snapshot,
            telemetryBuffer: telemetryBuffer,
            accelerationEngine: accelerationEngine,
            ecuControls: ecuControls,
            isWide: isWide,
            compact: compact,
            controlsAreInteractive: !isEditing
        )
    }

    private var dragPreview: some View {
        HStack(spacing: 9) {
            Image(systemName: widget.displayIcon)
                .foregroundStyle(widget.accent.color)
            Text(widget.displayTitle)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .foregroundStyle(Color.primary)
        .background(Color.black.opacity(0.88), in: Capsule())
        .overlay(Capsule().stroke(widget.accent.color.opacity(0.7)))
    }

    private func editButton(
        icon: String,
        tint: Color,
        enabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: compact ? 10 : 11, weight: .black))
                .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.35))
                .background(tint.opacity(enabled ? 0.88 : 0.3), in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(enabled ? 0.2 : 0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func startWobble() {
        isWobbling = false
        withAnimation(.easeInOut(duration: 0.17).repeatForever(autoreverses: true)) {
            isWobbling = true
        }
    }
}

enum DashboardGridLayout {
    static func rows(for widgets: [DashboardWidget], isWide: Bool) -> [[DashboardWidget]] {
        var result: [[DashboardWidget]] = []
        var current: [DashboardWidget] = []
        var occupied = 0

        for widget in widgets {
            let span = (isWide ? widget.landscapeSpan : widget.portraitSpan).rawValue
            guard span > 0 else { continue }
            if occupied + span > 12, !current.isEmpty {
                result.append(current)
                current = []
                occupied = 0
            }
            current.append(widget)
            occupied += span
            if occupied == 12 {
                result.append(current)
                current = []
                occupied = 0
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func height(for widget: DashboardWidget, isWide: Bool, compact: Bool) -> CGFloat {
        let kind = isWide ? (widget.wideKind ?? widget.kind) : widget.kind
        if compact {
            switch kind {
            case .hero: return 150
            case .group: return 112
            case .value, .gauge, .chart, .performance, .ecuSwitch, .ecuRotary: return 96
            case .compact: return 54
            }
        } else {
            switch kind {
            case .hero: return isWide ? 215 : 250
            case .group: return isWide ? 180 : 190
            case .value: return 145
            case .gauge: return 210
            case .chart: return 220
            case .compact: return 70
            case .performance: return 188
            case .ecuSwitch, .ecuRotary: return 145
            }
        }
    }
}

private struct DashboardWidgetView: View {
    let widget: DashboardWidget
    let snapshot: TelemetrySnapshot
    @ObservedObject var telemetryBuffer: DashboardTelemetryBuffer
    @ObservedObject var accelerationEngine: AccelerationEngine
    @ObservedObject var ecuControls: ECUControlCoordinator
    let isWide: Bool
    let compact: Bool
    let controlsAreInteractive: Bool

    var body: some View {
        let kind = isWide ? (widget.wideKind ?? widget.kind) : widget.kind
        switch kind {
        case .hero:
            DashboardHeroWidget(widget: widget, snapshot: snapshot, sessionMaximums: telemetryBuffer.sessionMaximums, compact: compact)
        case .group:
            DashboardGroupWidget(widget: widget, snapshot: snapshot, sessionMaximums: telemetryBuffer.sessionMaximums, compact: compact, prominent: isWide && !compact)
        case .value:
            DashboardValueWidget(widget: widget, snapshot: snapshot, sessionMaximums: telemetryBuffer.sessionMaximums, compact: compact, prominent: isWide && !compact)
        case .gauge:
            DashboardGaugeWidget(widget: widget, snapshot: snapshot, sessionMaximums: telemetryBuffer.sessionMaximums, compact: compact)
        case .chart:
            DashboardChartWidget(widget: widget, snapshot: snapshot, sessionMaximums: telemetryBuffer.sessionMaximums, telemetryBuffer: telemetryBuffer, compact: compact)
        case .compact:
            DashboardCompactWidget(widget: widget, snapshot: snapshot, sessionMaximums: telemetryBuffer.sessionMaximums, compact: compact)
        case .performance:
            DashboardPerformanceWidget(widget: widget, engine: accelerationEngine, compact: compact)
        case .ecuSwitch:
            DashboardECUSwitchWidget(
                widget: widget,
                controls: ecuControls,
                compact: compact,
                interactionEnabled: controlsAreInteractive
            )
        case .ecuRotary:
            DashboardECURotaryWidget(
                widget: widget,
                controls: ecuControls,
                compact: compact,
                interactionEnabled: controlsAreInteractive
            )
        }
    }
}

private struct DashboardPerformanceWidget: View {
    let widget: DashboardWidget
    @ObservedObject var engine: AccelerationEngine
    let compact: Bool

    private var selectedTypes: [AccelerationType] {
        let values = widget.accelerationTypes ?? AccelerationType.allCases
        return values.isEmpty ? AccelerationType.allCases : values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 11) {
            HStack {
                Label((widget.title?.isEmpty == false ? widget.title! : localized("Przyspieszenie")).uppercased(), systemImage: "stopwatch.fill")
                    .font(.system(size: compact ? 8 : 10, weight: .black))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                DashboardStatusTag(title: engine.active == nil ? localized("GOTOWY") : localized("POMIAR"), tint: engine.active == nil ? .tougeMint : widget.accent.color)
            }
            HStack(spacing: compact ? 5 : 8) {
                ForEach(selectedTypes) { type in
                    let active = engine.active.flatMap { $0.type == type ? $0 : nil }
                    let best = engine.recentResults.filter { $0.type == type }.min { $0.durationMillis < $1.durationMillis }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(type.label).font(.system(size: 8, weight: .black)).foregroundStyle(active == nil ? Color.secondary : widget.accent.color)
                        Text(active.map { $0.elapsed.formatted(.number.precision(.fractionLength(2))) } ?? best.map { (Double($0.durationMillis) / 1_000).formatted(.number.precision(.fractionLength(2))) } ?? "—")
                            .font(.system(size: compact ? 17 : 25, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(active.map { "\(Int($0.currentSpeedKPH)) km/h" } ?? (best == nil ? localized("BRAK PRÓBY") : localized("NAJLEPSZY")))
                            .font(.system(size: 6, weight: .black)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(compact ? 7 : 10)
                    .background(Color.primary.opacity(0.045), in: CutCornerPanel(cut: 7))
                }
            }
        }
        .padding(compact ? 10 : 14)
        .cardSurface(accent: widget.accent.color)
    }
}

private struct DashboardHeroWidget: View {
    let widget: DashboardWidget
    let snapshot: TelemetrySnapshot
    let sessionMaximums: [DashboardMetric: Double]
    let compact: Bool

    private var metric: DashboardMetric { widget.primaryMetric }
    private var value: Double { metric.value(in: snapshot) }
    private var warning: Bool { metric.isWarning(in: snapshot) }
    private var range: ClosedRange<Double> {
        let fallback = metric.defaultRange
        let minimum = widget.gaugeMinimum ?? fallback.lowerBound
        let maximum = max(minimum + 0.01, widget.gaugeMaximum ?? fallback.upperBound)
        return minimum...maximum
    }
    private var progress: Double {
        min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Label((widget.title?.isEmpty == false ? widget.title! : metric.title).uppercased(), systemImage: metric.icon)
                    .font(.system(size: compact ? 9 : 11, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                DashboardStatusTag(title: warning ? localized("WYSOKO") : localized("DANE NA ŻYWO"), tint: warning ? .tougeRed : widget.accent.color)
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(value.formatted(.number.precision(.fractionLength(metric.precision))))
                    .font(.system(size: compact ? 49 : 76, weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.52)
                    .lineLimit(1)
                    .foregroundStyle(warning ? Color.tougeRed : Color.primary)
                DashboardSessionMaximum(metric: metric, maximum: sessionMaximums[metric], compact: compact)
                    .alignmentGuide(.lastTextBaseline) { dimensions in dimensions[.top] }
                Text(metric.unit.uppercased())
                    .font(.system(size: compact ? 9 : 12, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(warning ? Color.tougeRed : widget.accent.color)
                    .padding(.bottom, compact ? 7 : 12)
            }

            DashboardLinearScale(progress: progress, range: range, metric: metric, tint: warning ? .tougeRed : widget.accent.color, compact: compact)

            let secondary = Array(widget.metrics.dropFirst().prefix(3))
            if !secondary.isEmpty {
                HStack(spacing: 0) {
                    ForEach(secondary) { item in
                        DashboardInlineMetric(metric: item, snapshot: snapshot, maximum: sessionMaximums[item])
                    }
                }
            }
        }
        .padding(compact ? 13 : 18)
        .cardSurface(warning: warning, accent: warning ? .tougeRed : widget.accent.color)
    }
}

private struct DashboardLinearScale: View {
    let progress: Double
    let range: ClosedRange<Double>
    let metric: DashboardMetric
    let tint: Color
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.075))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.62), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, proxy.size.width * progress))
                        .shadow(color: tint.opacity(0.55), radius: 8)
                }
            }
            .frame(height: compact ? 7 : 9)

            HStack {
                Text(scaleLabel(range.lowerBound))
                Spacer()
                Text(scaleLabel((range.lowerBound + range.upperBound) / 2))
                Spacer()
                Text("\(scaleLabel(range.upperBound)) \(metric.unit.uppercased())")
            }
            .font(.system(size: compact ? 6 : 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
    }

    private func scaleLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(metric.precision > 0 ? 1 : 0)))
    }
}

private struct DashboardInlineMetric: View {
    let metric: DashboardMetric
    let snapshot: TelemetrySnapshot
    let maximum: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.shortTitle)
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(metric.value(in: snapshot).formatted(.number.precision(.fractionLength(metric.precision))))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                DashboardSessionMaximum(metric: metric, maximum: maximum, compact: true)
                    .alignmentGuide(.lastTextBaseline) { dimensions in dimensions[.top] }
                Text(metric.unit)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardGroupWidget: View {
    let widget: DashboardWidget
    let snapshot: TelemetrySnapshot
    let sessionMaximums: [DashboardMetric: Double]
    let compact: Bool
    let prominent: Bool

    private var metrics: [DashboardMetric] { Array(widget.metrics.prefix(3)) }
    private var warning: Bool { metrics.contains { $0.isWarning(in: snapshot) } }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 15) {
            HStack(spacing: 8) {
                Label((widget.title?.isEmpty == false ? widget.title! : localized("Grupa parametrów")).uppercased(), systemImage: "heart.text.clipboard.fill")
                    .font(.system(size: compact ? 9 : 11, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                DashboardStatusTag(title: warning ? localized("SPRAWDŹ") : localized("NOMINALNIE"), tint: warning ? .tougeRed : widget.accent.color)
            }

            HStack(alignment: .bottom, spacing: compact ? 8 : 13) {
                ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                    if index > 0 {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).padding(.vertical, 4)
                    }
                    DashboardGroupValue(metric: metric, snapshot: snapshot, maximum: sessionMaximums[metric], tint: widget.accent.color, compact: compact, prominent: prominent)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(compact ? 13 : 18)
        .cardSurface(warning: warning, accent: warning ? .tougeRed : widget.accent.color)
    }
}

private struct DashboardGroupValue: View {
    let metric: DashboardMetric
    let snapshot: TelemetrySnapshot
    let maximum: Double?
    let tint: Color
    let compact: Bool
    let prominent: Bool

    private var warning: Bool { metric.isWarning(in: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            HStack(spacing: 4) {
                Image(systemName: metric.icon)
                    .font(.system(size: compact ? 8 : 10, weight: .bold))
                    .foregroundStyle(warning ? Color.tougeRed : tint)
                Text(metric.shortTitle)
                    .font(.system(size: compact ? 6 : 8, weight: .black))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(metric.value(in: snapshot).formatted(.number.precision(.fractionLength(metric.precision))))
                    .font(.system(size: compact ? 25 : (prominent ? 54 : 36), weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.48)
                    .lineLimit(1)
                    .foregroundStyle(warning ? Color.tougeRed : Color.primary)
                DashboardSessionMaximum(metric: metric, maximum: maximum, compact: true)
                    .alignmentGuide(.lastTextBaseline) { dimensions in dimensions[.top] }
                Text(metric.unit)
                    .font(.system(size: compact ? 7 : (prominent ? 12 : 9), weight: .black))
                    .foregroundStyle(warning ? Color.tougeRed : tint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

private struct DashboardValueWidget: View {
    let widget: DashboardWidget
    let snapshot: TelemetrySnapshot
    let sessionMaximums: [DashboardMetric: Double]
    let compact: Bool
    let prominent: Bool

    private var metric: DashboardMetric { widget.primaryMetric }
    private var warning: Bool { metric.isWarning(in: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 9) {
            HStack {
                Text((widget.title?.isEmpty == false ? widget.title! : metric.shortTitle).uppercased())
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: metric.icon).foregroundStyle(warning ? Color.tougeRed : widget.accent.color)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 4) {
                Text(metric.value(in: snapshot).formatted(.number.precision(.fractionLength(metric.precision))))
                    .font(.system(size: compact ? 25 : (prominent ? 49 : 34), weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(warning ? Color.tougeRed : Color.primary)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                DashboardSessionMaximum(metric: metric, maximum: sessionMaximums[metric], compact: compact)
            }
            Text(secondaryLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(compact ? 11 : 14)
        .cardSurface(warning: warning, accent: warning ? .tougeRed : widget.accent.color)
    }

    private var secondaryLabel: String {
        if metric == .afr {
            return "λ " + snapshot.lambda.formatted(.number.precision(.fractionLength(2)))
        }
        return metric.unit
    }
}

private struct DashboardCompactWidget: View {
    let widget: DashboardWidget
    let snapshot: TelemetrySnapshot
    let sessionMaximums: [DashboardMetric: Double]
    let compact: Bool

    private var metric: DashboardMetric { widget.primaryMetric }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((widget.title?.isEmpty == false ? widget.title! : metric.shortTitle).uppercased())
                .font(.system(size: compact ? 7 : 9, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(metric.value(in: snapshot).formatted(.number.precision(.fractionLength(metric.precision))))
                    .font(.system(size: compact ? 14 : 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.58)
                    .lineLimit(1)
                DashboardSessionMaximum(metric: metric, maximum: sessionMaximums[metric], compact: true)
                    .alignmentGuide(.lastTextBaseline) { dimensions in dimensions[.top] }
                Text(metric.unit)
                    .font(.system(size: compact ? 6 : 8, weight: .bold))
            }
            .foregroundStyle(metric.isWarning(in: snapshot) ? Color.tougeRed : widget.accent.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(compact ? 8 : 11)
        .cardSurface(warning: metric.isWarning(in: snapshot), accent: widget.accent.color)
    }
}

private struct DashboardGaugeWidget: View {
    let widget: DashboardWidget
    let snapshot: TelemetrySnapshot
    let sessionMaximums: [DashboardMetric: Double]
    let compact: Bool

    private var metric: DashboardMetric { widget.primaryMetric }
    private var range: ClosedRange<Double> {
        let fallback = metric.defaultRange
        let minimum = widget.gaugeMinimum ?? fallback.lowerBound
        return minimum...max(minimum + 0.01, widget.gaugeMaximum ?? fallback.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label((widget.title?.isEmpty == false ? widget.title! : metric.title).uppercased(), systemImage: metric.icon)
                .font(.system(size: compact ? 8 : 10, weight: .black))
                .tracking(1)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            DashboardNeedleGauge(
                value: metric.value(in: snapshot),
                maximum: sessionMaximums[metric],
                range: range,
                metric: metric,
                tint: metric.isWarning(in: snapshot) ? .tougeRed : widget.accent.color,
                compact: compact
            )
        }
        .padding(compact ? 10 : 14)
        .cardSurface(warning: metric.isWarning(in: snapshot), accent: widget.accent.color)
    }
}

private struct DashboardNeedleGauge: View {
    let value: Double
    let maximum: Double?
    let range: ClosedRange<Double>
    let metric: DashboardMetric
    let tint: Color
    let compact: Bool

    private var progress: Double {
        min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height * 1.28)
            let radius = size * 0.4
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.58)

            Canvas { context, _ in
                var track = Path()
                track.addArc(center: center, radius: radius, startAngle: .degrees(150), endAngle: .degrees(390), clockwise: false)
                context.stroke(track, with: .color(.white.opacity(0.1)), style: StrokeStyle(lineWidth: compact ? 7 : 10, lineCap: .round))

                var active = Path()
                active.addArc(center: center, radius: radius, startAngle: .degrees(150), endAngle: .degrees(150 + 240 * progress), clockwise: false)
                context.stroke(active, with: .color(tint), style: StrokeStyle(lineWidth: compact ? 7 : 10, lineCap: .round))

                for index in 0...10 {
                    let angle = (150 + Double(index) * 24) * Double.pi / 180
                    let outer = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    let inner = CGPoint(x: center.x + cos(angle) * (radius - (compact ? 7 : 11)), y: center.y + sin(angle) * (radius - (compact ? 7 : 11)))
                    var tick = Path()
                    tick.move(to: inner)
                    tick.addLine(to: outer)
                    context.stroke(tick, with: .color(.white.opacity(index % 5 == 0 ? 0.75 : 0.25)), lineWidth: index % 5 == 0 ? 2 : 1)
                }

                let needleAngle = (150 + 240 * progress) * Double.pi / 180
                let needleEnd = CGPoint(x: center.x + cos(needleAngle) * radius * 0.78, y: center.y + sin(needleAngle) * radius * 0.78)
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: needleEnd)
                context.stroke(needle, with: .color(tint), style: StrokeStyle(lineWidth: compact ? 3 : 4, lineCap: .round))
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(tint))
            }

            VStack(spacing: 0) {
                Spacer()
                HStack(alignment: .top, spacing: 3) {
                    Text(value.formatted(.number.precision(.fractionLength(metric.precision))))
                        .font(.system(size: compact ? 23 : 34, weight: .black, design: .rounded))
                        .fontWidth(.expanded)
                        .monospacedDigit()
                    DashboardSessionMaximum(metric: metric, maximum: maximum, compact: compact)
                }
                Text(metric.unit)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, compact ? 0 : 2)
        }
    }
}

private struct DashboardChartWidget: View {
    let widget: DashboardWidget
    let snapshot: TelemetrySnapshot
    let sessionMaximums: [DashboardMetric: Double]
    @ObservedObject var telemetryBuffer: DashboardTelemetryBuffer
    let compact: Bool

    private var metric: DashboardMetric { widget.primaryMetric }
    private var duration: DashboardChartDuration { widget.chartDuration ?? .thirtySeconds }
    private var points: [DashboardTelemetryPoint] { telemetryBuffer.points(for: duration) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 9) {
            HStack {
                Label((widget.title?.isEmpty == false ? widget.title! : metric.title).uppercased(), systemImage: metric.icon)
                    .font(.system(size: compact ? 8 : 10, weight: .black))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(duration.title.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(widget.accent.color)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.value(in: snapshot).formatted(.number.precision(.fractionLength(metric.precision))))
                    .font(.system(size: compact ? 20 : 28, weight: .black, design: .rounded))
                    .monospacedDigit()
                DashboardSessionMaximum(metric: metric, maximum: sessionMaximums[metric], compact: true)
                    .alignmentGuide(.firstTextBaseline) { dimensions in dimensions[.top] }
                Text(metric.unit)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(widget.accent.color)
            }

            Chart(points) { point in
                AreaMark(
                    x: .value("Time", point.recordedAt),
                    y: .value(metric.shortTitle, metric.value(in: point.snapshot))
                )
                .foregroundStyle(LinearGradient(colors: [widget.accent.color.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))

                LineMark(
                    x: .value("Time", point.recordedAt),
                    y: .value(metric.shortTitle, metric.value(in: point.snapshot))
                )
                .foregroundStyle(widget.accent.color)
                .lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel().font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(compact ? 10 : 14)
        .cardSurface(warning: metric.isWarning(in: snapshot), accent: widget.accent.color)
    }
}

private struct DashboardSessionMaximum: View {
    let metric: DashboardMetric
    let maximum: Double?
    let compact: Bool

    var body: some View {
        if let maximum {
            Text("\(compact ? "↑" : "MAX ")\(maximum.formatted(.number.precision(.fractionLength(metric.precision))))")
                .font(.system(size: compact ? 6 : 8, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct DashboardStatusTag: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 5, height: 5).shadow(color: tint.opacity(0.8), radius: 4)
            Text(title).font(.system(size: 8, weight: .black)).tracking(0.7)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.22)))
    }
}

extension DashboardAccent {
    var color: Color {
        switch self {
        case .cyan: .tougeCyan
        case .mint: .tougeMint
        case .blue: .tougeBlue
        case .ice: .tougeIce
        case .orange: .tougeOrange
        case .yellow: .tougeYellow
        case .red: .tougeRed
        case .white: .white
        }
    }
}
