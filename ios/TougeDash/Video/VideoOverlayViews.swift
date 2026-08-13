import SwiftUI

private struct VideoOverlayElementFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct VideoTelemetryOverlayView: View {
    let template: VideoOverlayTemplate
    let sample: TelemetryHistorySample?
    var samples: [TelemetryHistorySample] = []
    var routeTimestamp: Date? = nil

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
                    routeSamples: samples,
                    routeTimestamp: routeTimestamp,
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
    var samples: [TelemetryHistorySample] = []
    var routeTimestamp: Date? = nil
    @State private var activeTouchLocations: [SpatialEventCollection.Event.ID: CGPoint] = [:]
    @State private var touchStartedAt: [SpatialEventCollection.Event.ID: TimeInterval] = [:]
    @State private var gestureSessionStarted = false
    @State private var gestureElementID: UUID?
    @State private var elementFrames: [UUID: CGRect] = [:]
    @State private var elementPendingDeletion: UUID?

    var body: some View {
        GeometryReader { proxy in
            let orientation = VideoOverlayCanvasOrientation(size: proxy.size)
            ZStack {
                ForEach(template.elements) { element in
                let position = element.position(for: orientation)
                VideoOverlayElementView(
                    element: element,
                    style: template.style,
                    configuration: template.gaugeConfiguration,
                    sample: sample,
                    routeSamples: samples,
                    routeTimestamp: routeTimestamp,
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
                .onTapGesture {
                    selectedElementID = element.id
                }
                .background {
                    GeometryReader { elementProxy in
                        Color.clear.preference(
                            key: VideoOverlayElementFramesPreferenceKey.self,
                            value: [element.id: elementProxy.frame(in: .named("video-overlay-canvas"))]
                        )
                    }
                }
                .overlay(alignment: deletionControlAlignment(for: position)) {
                    if selectedElementID == element.id {
                        Button {
                            elementPendingDeletion = element.id
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Color.red.opacity(0.92), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .offset(
                            x: position.x < 0.3 ? -8 : 8,
                            y: position.y < 0.3 ? -8 : 8
                        )
                    }
                }
                .overlay(alignment: position.x > 0.7 ? .leading : .trailing) {
                    if element.kind.isRouteMap {
                        VStack(spacing: 3) {
                            mapZoomButton(systemName: "plus") {
                                changeMapZoom(for: element.id, by: 0.15)
                            }
                            Text(element.mapZoom.formatted(.number.precision(.fractionLength(1))))
                                .font(.system(size: 7, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            mapZoomButton(systemName: "minus") {
                                changeMapZoom(for: element.id, by: -0.15)
                            }
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.78), in: Capsule())
                        .overlay(Capsule().stroke(element.accent.color.opacity(0.85), lineWidth: 1))
                        .offset(x: position.x > 0.7 ? -31 : 31)
                    }
                }
                .position(
                    x: proxy.size.width * position.x,
                    y: proxy.size.height * position.y
                )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(
                spatialTransformGesture(canvasSize: proxy.size, orientation: orientation),
                including: .all
            )
            .onPreferenceChange(VideoOverlayElementFramesPreferenceKey.self) {
                elementFrames = $0
            }
        }
        .coordinateSpace(name: "video-overlay-canvas")
        .alert(localized("Usunąć widget?"), isPresented: deletionConfirmationBinding) {
            Button(localized("Anuluj"), role: .cancel) {
                elementPendingDeletion = nil
            }
            Button(localized("Usuń widget"), role: .destructive) {
                if let id = elementPendingDeletion { removeElement(id: id) }
                elementPendingDeletion = nil
            }
        } message: {
            Text(localized("Widget zniknie z układu filmu. Możesz dodać go ponownie przyciskiem plus."))
        }
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { elementPendingDeletion != nil },
            set: { if !$0 { elementPendingDeletion = nil } }
        )
    }

    private func deletionControlAlignment(for position: VideoOverlayPosition) -> Alignment {
        if position.y < 0.3 {
            return position.x < 0.3 ? .bottomTrailing : .bottomLeading
        }
        return position.x < 0.3 ? .topTrailing : .topLeading
    }

    private func spatialTransformGesture(
        canvasSize: CGSize,
        orientation: VideoOverlayCanvasOrientation
    ) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .named("video-overlay-canvas"))
            .onChanged { events in
                updateSpatialTransform(events, canvasSize: canvasSize, orientation: orientation)
            }
            .onEnded { _ in resetSpatialTransform() }
    }

    private func updateSpatialTransform(
        _ events: SpatialEventCollection,
        canvasSize: CGSize,
        orientation: VideoOverlayCanvasOrientation
    ) {
        let previousLocations = activeTouchLocations
        var updatedLocations = activeTouchLocations
        var updatedStartTimes = touchStartedAt

        for event in events where event.kind == .touch {
            switch event.phase {
            case .active:
                updatedLocations[event.id] = event.location
                if updatedStartTimes[event.id] == nil { updatedStartTimes[event.id] = event.timestamp }
            case .ended, .cancelled:
                updatedLocations[event.id] = nil
            @unknown default:
                updatedLocations[event.id] = nil
            }
        }

        activeTouchLocations = updatedLocations
        touchStartedAt = updatedStartTimes

        guard !updatedLocations.isEmpty else {
            resetSpatialTransform()
            return
        }

        let orderedIDs = updatedLocations.keys.sorted {
            (updatedStartTimes[$0] ?? 0) < (updatedStartTimes[$1] ?? 0)
        }

        if !gestureSessionStarted {
            gestureSessionStarted = true
            guard let firstID = orderedIDs.first,
                  let firstLocation = updatedLocations[firstID],
                  let targetID = elementID(at: firstLocation) else { return }
            gestureElementID = targetID
            selectedElementID = targetID
            return
        }

        guard let targetID = gestureElementID,
              let index = template.elements.firstIndex(where: { $0.id == targetID }) else { return }

        if orderedIDs.count == 1,
           previousLocations.count == 1,
           let touchID = orderedIDs.first,
           let previous = previousLocations[touchID],
           let current = updatedLocations[touchID] {
            let oldPosition = template.elements[index].position(for: orientation)
            template.elements[index].setPosition(
                VideoOverlayPosition(
                    x: oldPosition.x + (current.x - previous.x) / max(1, canvasSize.width),
                    y: oldPosition.y + (current.y - previous.y) / max(1, canvasSize.height)
                ),
                for: orientation
            )
        } else if orderedIDs.count >= 2,
                  let first = updatedLocations[orderedIDs[0]],
                  let second = updatedLocations[orderedIDs[1]],
                  let previousFirst = previousLocations[orderedIDs[0]],
                  let previousSecond = previousLocations[orderedIDs[1]] {
            let previousDistance = hypot(previousSecond.x - previousFirst.x, previousSecond.y - previousFirst.y)
            let currentDistance = hypot(second.x - first.x, second.y - first.y)
            if previousDistance > 1, currentDistance > 1 {
                template.elements[index].setSizeMultiplier(
                    template.elements[index].sizeMultiplier * Double(currentDistance / previousDistance)
                )
            }
        }
    }

    private func elementID(at point: CGPoint) -> UUID? {
        let matchingFrames = elementFrames.filter {
            $0.value.insetBy(dx: -12, dy: -12).contains(point)
        }
        return matchingFrames.min {
            squaredDistance(from: CGPoint(x: $0.value.midX, y: $0.value.midY), to: point)
                < squaredDistance(from: CGPoint(x: $1.value.midX, y: $1.value.midY), to: point)
        }?.key
    }

    private func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private func resetSpatialTransform() {
        activeTouchLocations.removeAll()
        touchStartedAt.removeAll()
        gestureSessionStarted = false
        gestureElementID = nil
    }

    private func changeMapZoom(for id: UUID, by delta: Double) {
        guard let index = template.elements.firstIndex(where: { $0.id == id }) else { return }
        selectedElementID = id
        template.elements[index].setMapZoom(template.elements[index].mapZoom + delta)
        template.modifiedAt = .now
    }

    private func removeElement(id: UUID) {
        template.removeElement(id: id)
        if selectedElementID == id { selectedElementID = nil }
    }

    private func mapZoomButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .black))
                .frame(width: 22, height: 22)
                .foregroundStyle(.white)
                .background(Color.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

private struct VideoOverlayElementView: View {
    let element: VideoOverlayElement
    let style: VideoOverlayStyle
    let configuration: VideoOverlayGaugeConfiguration
    let sample: TelemetryHistorySample?
    let routeSamples: [TelemetryHistorySample]
    let routeTimestamp: Date?
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
            case .telemetryTimestamp: telemetryTimestamp
            case .gauge: gaugeValue
            case .bar: barValue
            case .speedCluster: speedCluster
            case .oilCluster: oilCluster
            case .neonTach, .blacklistTach, .carbonTach, .streetShiftTach: arcadeTach
            case .routeMap, .routeMapCircular, .routeMapFollow, .routeMapLight, .routeMapLightCircular, .routeMapAmber:
                VideoRouteMapElementView(
                    element: element,
                    sample: sample,
                    samples: routeSamples,
                    routeTimestamp: routeTimestamp,
                    scale: scale
                )
            }
        }
        .shadow(color: shadowColor, radius: 5 * scale)
    }

    private var telemetryTimestamp: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(localized("CZAS TELEMETRII"))
                .font(.system(size: 6.5 * scale, weight: .black))
                .tracking(0.8 * scale)
                .foregroundStyle(element.accent.color)
            Text(telemetryTimestampText)
                .font(.system(size: 14 * scale, weight: .black, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 7 * scale)
        .frame(width: 184 * scale, alignment: .leading)
        .background(background)
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(element.accent.color)
                .frame(width: 38 * scale, height: max(2, 2 * scale))
                .padding(.leading, 10 * scale)
        }
    }

    private var telemetryTimestampText: String {
        guard let timestamp = routeTimestamp ?? sample?.timestamp else {
            return "---- -- -- --:--:--"
        }
        return VideoTelemetryTimestampFormatter.string(from: timestamp)
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

            VStack(spacing: -1 * scale) {
                Text(element.metric.shortTitle)
                    .font(.system(size: 6.5 * scale, weight: .black))
                    .tracking(0.8 * scale)
                    .foregroundStyle(element.accent.color)
                Text(value.formatted(.number.precision(.fractionLength(element.metric.precision))))
                    .font(.system(size: gaugeValueFontSize * scale, weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .monospacedDigit()
                Text(element.metric.unit)
                    .font(.system(size: 6 * scale, weight: .black))
                    .foregroundStyle(.secondary)
            }
            .offset(y: 25 * scale)
        }
        .foregroundStyle(.white)
        .frame(width: 102 * scale, height: 102 * scale)
        .padding(5 * scale)
        .background(Color.black.opacity(style == .minimal ? 0.28 : 0.5), in: Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: max(0.5, scale * 0.6)))
    }

    private var gaugeValueFontSize: CGFloat {
        switch element.metric {
        case .speed: 18
        case .boost: 16
        default: 20
        }
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

    private var arcadeTach: some View {
        let kind = element.kind
        let accent = arcadeAccent(for: kind)
        let isNeon = kind == .neonTach
        let isStreet = kind == .streetShiftTach
        let width = (isNeon ? 184.0 : isStreet ? 190.0 : 150.0) * scale
        let mainOffset = (isNeon ? 17.0 : isStreet ? -20.0 : 0.0) * scale
        return ZStack {
            Circle()
                .fill(arcadeFaceColor(for: kind))
                .frame(width: 150 * scale, height: 150 * scale)
                .overlay(Circle().stroke(accent.opacity(0.7), lineWidth: 1.5 * scale))
                .offset(x: mainOffset)

            if isNeon {
                Circle()
                    .fill(Color(red: 0.015, green: 0.04, blue: 0.06).opacity(0.97))
                    .frame(width: 52 * scale, height: 52 * scale)
                    .overlay(Circle().stroke(Color(red: 0.15, green: 0.91, blue: 0.44).opacity(0.65), lineWidth: 1.2 * scale))
                    .offset(x: -66 * scale, y: 38 * scale)
            }

            ArcadeTachFace(
                kind: kind,
                rpmProgress: progress(for: .rpm, value: metricValue(.rpm)),
                boostProgress: progress(for: .boost, value: metricValue(.boost)),
                throttleProgress: progress(for: .throttle, value: metricValue(.throttle)),
                maximumRPM: configuration.maximumRPM,
                accent: accent
            )

            Text("RPM ×1000")
                .font(.system(size: 6.5 * scale, weight: .black))
                .foregroundStyle(kind == .carbonTach ? Color(red: 1, green: 0.82, blue: 0.51) : accent)
                .offset(x: mainOffset, y: -29 * scale)

            if isStreet {
                VStack(spacing: 1 * scale) {
                    Text("GEAR")
                        .font(.system(size: 5.5 * scale, weight: .black))
                        .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.49))
                    Text("–")
                        .font(.system(size: 22 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.04))
                        .frame(width: 42 * scale, height: 27 * scale)
                        .background(Color(red: 0.91, green: 0.66, blue: 0.37), in: RoundedRectangle(cornerRadius: 4 * scale))
                }
                .offset(x: 65 * scale, y: -24 * scale)
                VStack(spacing: 1 * scale) {
                    Text(Int(metricValue(.speed)).formatted())
                        .font(.system(size: 21 * scale, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.04))
                        .frame(width: 54 * scale, height: 31 * scale)
                        .background(Color(red: 0.91, green: 0.66, blue: 0.37), in: RoundedRectangle(cornerRadius: 4 * scale))
                    Text("KM/H").font(.system(size: 5.5 * scale, weight: .black)).foregroundStyle(.white)
                }
                .offset(x: 65 * scale, y: 29 * scale)
                Text("THROTTLE \(Int(metricValue(.throttle)))%")
                    .font(.system(size: 6.5 * scale, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.61, green: 0.92, blue: 0.29))
                    .offset(x: mainOffset, y: 58 * scale)
            } else if isNeon {
                VStack(spacing: 0) {
                    Text(Int(metricValue(.speed)).formatted())
                        .font(.system(size: 28 * scale, weight: .black, design: .rounded))
                        .fontWidth(.expanded)
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    Text("KM/H")
                        .font(.system(size: 6.5 * scale, weight: .black))
                        .foregroundStyle(accent)
                }
                .offset(x: mainOffset, y: 23 * scale)
                VStack(spacing: 0) {
                    Text(verbatim: "BOOST")
                        .font(.system(size: 5.5 * scale, weight: .black))
                        .foregroundStyle(Color(red: 0.49, green: 0.96, blue: 0.65))
                    Text(metricValue(.boost).formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 10 * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("BAR")
                        .font(.system(size: 4.5 * scale, weight: .black))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .offset(x: -66 * scale, y: 38 * scale)
            } else {
                VStack(spacing: 0) {
                    Text(Int(metricValue(.speed)).formatted())
                        .font(.system(size: 28 * scale, weight: .black, design: .rounded))
                        .fontWidth(.expanded)
                        .monospacedDigit()
                        .foregroundStyle(kind == .blacklistTach ? .white : accent)
                    Text("KM/H")
                        .font(.system(size: 6.5 * scale, weight: .black))
                        .foregroundStyle(kind == .carbonTach ? .white : accent)
                    Text(arcadeSecondaryText(for: kind))
                        .font(.system(size: 6 * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(arcadeSecondaryColor(for: kind))
                }
                .offset(y: 24 * scale)
            }
        }
        .frame(width: width, height: 150 * scale)
    }

    private func arcadeAccent(for kind: VideoOverlayElementKind) -> Color {
        switch kind {
        case .neonTach: Color(red: 0.09, green: 0.75, blue: 1)
        case .blacklistTach: Color(red: 0.84, green: 0.18, blue: 0.18)
        case .carbonTach: Color(red: 0.89, green: 0.64, blue: 0.25)
        default: Color(red: 0.94, green: 0.63, blue: 0.29)
        }
    }

    private func arcadeFaceColor(for kind: VideoOverlayElementKind) -> Color {
        switch kind {
        case .neonTach: Color(red: 0.015, green: 0.04, blue: 0.06).opacity(0.94)
        case .carbonTach: Color(red: 0.09, green: 0.075, blue: 0.045).opacity(0.94)
        case .streetShiftTach: Color(red: 0.03, green: 0.04, blue: 0.03).opacity(0.92)
        default: Color(red: 0.035, green: 0.04, blue: 0.045).opacity(0.94)
        }
    }

    private func arcadeSecondaryText(for kind: VideoOverlayElementKind) -> String {
        switch kind {
        case .carbonTach: "OIL \(Int(metricValue(.oilTemperature)))°C"
        default: "BOOST \(metricValue(.boost).formatted(.number.precision(.fractionLength(1)))) bar"
        }
    }

    private func arcadeSecondaryColor(for kind: VideoOverlayElementKind) -> Color {
        switch kind {
        case .carbonTach: Color(red: 1, green: 0.81, blue: 0.47)
        default: .white.opacity(0.8)
        }
    }

    private func dialFace(metric: DashboardMetric, value: Double, accent: Color) -> some View {
        RacingDialFace(
            progress: progress(for: metric, value: value),
            range: configuration.range(for: metric),
            metric: metric,
            accent: accent
        )
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

private struct VideoRouteMapElementView: View {
    let element: VideoOverlayElement
    let sample: TelemetryHistorySample?
    let samples: [TelemetryHistorySample]
    let routeTimestamp: Date?
    let scale: CGFloat
    @State private var snapshot: VideoRouteMapSnapshot?

    private var frames: [VideoTelemetryFrame] { samples.map(VideoTelemetryFrame.init(sample:)) }
    private var routeSignature: String {
        let first = samples.first?.timestamp.timeIntervalSince1970 ?? 0
        let last = samples.last?.timestamp.timeIntervalSince1970 ?? 0
        return "\(samples.count):\(first):\(last)"
    }
    private var needsDetailedMap: Bool {
        element.mapZoom > VideoOverlayElement.detailedMapZoomThreshold
    }

    var body: some View {
        let size = element.kind.isCircularRouteMap
            ? CGSize(width: 154 * scale, height: 154 * scale)
            : CGSize(width: 214 * scale, height: 136 * scale)
        Group {
            if let sample,
               let image = VideoOverlayCGRenderer.renderRouteMap(
                    size: size,
                    sample: VideoTelemetryFrame(sample: sample),
                    element: element,
                    routeMap: snapshot,
                    routeTimestamp: routeTimestamp
               ) {
                Image(decorative: image, scale: 1)
                    .resizable()
            } else {
                RoundedRectangle(cornerRadius: 12 * scale)
                    .fill(Color.black.opacity(0.82))
                    .overlay {
                        Text(localized("BRAK GPS"))
                            .font(.system(size: 10 * scale, weight: .black, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: "\(routeSignature):\(needsDetailedMap)") {
            snapshot = await VideoRouteMapSnapshotter.make(
                samples: frames,
                includesDetailedLayer: needsDetailedMap
            )
        }
    }
}

private struct ArcadeTachFace: View, Equatable {
    let kind: VideoOverlayElementKind
    let rpmProgress: Double
    let boostProgress: Double
    let throttleProgress: Double
    let maximumRPM: Double
    let accent: Color

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let dimension = min(size.width, size.height)
            let centerX: CGFloat = switch kind {
            case .neonTach: size.width - dimension / 2
            case .streetShiftTach: dimension / 2
            default: size.width / 2
            }
            let center = CGPoint(x: centerX, y: size.height / 2)
            let radius = dimension * 0.41

            var minor = Path()
            var major = Path()
            var redline = Path()
            for index in 0...40 {
                let fraction = Double(index) / 40
                let angle = radians(140 + 260 * fraction)
                let isMajor = index.isMultiple(of: 4)
                let length = dimension * (isMajor ? 0.075 : 0.04)
                let inner = point(center: center, angle: angle, radius: radius - length)
                let outer = point(center: center, angle: angle, radius: radius)
                if (kind == .blacklistTach || kind == .streetShiftTach), fraction > 0.78 {
                    redline.move(to: inner); redline.addLine(to: outer)
                } else if isMajor {
                    major.move(to: inner); major.addLine(to: outer)
                } else {
                    minor.move(to: inner); minor.addLine(to: outer)
                }
            }
            context.stroke(minor, with: .color(.white.opacity(0.35)), style: .init(lineWidth: max(0.7, dimension * 0.007)))
            context.stroke(major, with: .color(.white.opacity(0.9)), style: .init(lineWidth: max(1, dimension * 0.014)))
            context.stroke(redline, with: .color(Color(red: 0.87, green: 0.19, blue: 0.19)), style: .init(lineWidth: max(1, dimension * 0.016)))

            let divisions = min(12, max(4, Int((maximumRPM / 1_000).rounded())))
            for index in 0...divisions {
                let fraction = Double(index) / Double(divisions)
                let angle = radians(140 + 260 * fraction)
                let label = context.resolve(
                    Text("\(index)")
                        .font(.system(size: dimension * 0.047, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                )
                context.draw(label, at: point(center: center, angle: angle, radius: radius * 0.69), anchor: .center)
            }

            var progressArc = Path()
            progressArc.addArc(center: center, radius: radius + dimension * 0.035, startAngle: .degrees(140), endAngle: .degrees(140 + 260 * rpmProgress), clockwise: false)
            context.stroke(progressArc, with: .color(accent.opacity(0.55)), style: .init(lineWidth: max(1.5, dimension * 0.018), lineCap: .round))

            let needleAngle = radians(140 + 260 * rpmProgress)
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: point(center: center, angle: needleAngle, radius: radius * 0.72))
            context.stroke(needle, with: .color(accent), style: .init(lineWidth: max(2, dimension * 0.018), lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - dimension * 0.022, y: center.y - dimension * 0.022, width: dimension * 0.044, height: dimension * 0.044)), with: .color(.white))

            if kind == .neonTach {
                drawSmallArc(in: &context, center: CGPoint(x: dimension * 0.17, y: dimension * 0.75), radius: dimension * 0.145, progress: boostProgress, color: Color(red: 0.15, green: 0.91, blue: 0.44))
            }
            if kind == .streetShiftTach {
                var throttle = Path()
                throttle.addArc(center: center, radius: dimension * 0.47, startAngle: .degrees(35), endAngle: .degrees(35 + 110 * throttleProgress), clockwise: false)
                context.stroke(throttle, with: .color(Color(red: 0.57, green: 0.93, blue: 0.22)), style: .init(lineWidth: max(3, dimension * 0.045), lineCap: .butt))
            }
        }
    }

    private func drawSmallArc(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, progress: Double, color: Color) {
        var background = Path()
        background.addArc(center: center, radius: radius, startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
        context.stroke(background, with: .color(.white.opacity(0.14)), style: .init(lineWidth: max(2, radius * 0.16), lineCap: .round))
        var foreground = Path()
        foreground.addArc(center: center, radius: radius, startAngle: .degrees(135), endAngle: .degrees(135 + 270 * progress), clockwise: false)
        context.stroke(foreground, with: .color(color), style: .init(lineWidth: max(2, radius * 0.16), lineCap: .round))
    }

    private func point(center: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}

private struct RacingDialFace: View, Equatable {
    let progress: Double
    let range: ClosedRange<Double>
    let metric: DashboardMetric
    let accent: Color

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let geometry = DialGeometry(size: size)
            drawTicks(in: &context, geometry: geometry)
            drawLabels(in: &context, geometry: geometry)
            drawAccentArc(in: &context, geometry: geometry)
            drawNeedle(in: &context, geometry: geometry)
        }
    }

    private func drawTicks(in context: inout GraphicsContext, geometry: DialGeometry) {
        var minorTicks = Path()
        var majorTicks = Path()
        for index in 0..<25 {
            let angle = Self.radians(150 + Double(index) * 10)
            let length = geometry.dimension * (index.isMultiple(of: 4) ? 0.07 : 0.04)
            let inner = geometry.point(angle: angle, radius: geometry.radius - length)
            let outer = geometry.point(angle: angle, radius: geometry.radius)
            if index.isMultiple(of: 4) {
                majorTicks.move(to: inner)
                majorTicks.addLine(to: outer)
            } else {
                minorTicks.move(to: inner)
                minorTicks.addLine(to: outer)
            }
        }
        context.stroke(
            minorTicks,
            with: .color(.white.opacity(0.32)),
            style: .init(lineWidth: max(0.7, geometry.dimension * 0.009), lineCap: .round)
        )
        context.stroke(
            majorTicks,
            with: .color(.white.opacity(0.9)),
            style: .init(lineWidth: max(1, geometry.dimension * 0.014), lineCap: .round)
        )
    }

    private func drawLabels(in context: inout GraphicsContext, geometry: DialGeometry) {
        for index in 0..<7 {
            let angle = Self.radians(150 + Double(index) * 40)
            let value = range.lowerBound + (range.upperBound - range.lowerBound) * Double(index) / 6
            let label = context.resolve(
                Text(scaleLabel(value))
                    .font(.system(size: geometry.dimension * 0.047, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.72))
            )
            context.draw(label, at: geometry.point(angle: angle, radius: geometry.radius * 0.7), anchor: .center)
        }
    }

    private func drawAccentArc(in context: inout GraphicsContext, geometry: DialGeometry) {
        var path = Path()
        path.addArc(
            center: geometry.center,
            radius: geometry.radius + geometry.dimension * 0.035,
            startAngle: .degrees(150),
            endAngle: .degrees(150 + 240 * progress),
            clockwise: false
        )
        context.stroke(
            path,
            with: .color(accent.opacity(0.48)),
            style: .init(lineWidth: max(1.5, geometry.dimension * 0.018), lineCap: .round)
        )
    }

    private func drawNeedle(in context: inout GraphicsContext, geometry: DialGeometry) {
        let angle = Self.radians(150 + 240 * progress)
        var needle = Path()
        needle.move(to: geometry.center)
        needle.addLine(to: geometry.point(angle: angle, radius: geometry.radius * 0.72))
        context.stroke(
            needle,
            with: .color(accent),
            style: .init(lineWidth: max(2, geometry.dimension * 0.022), lineCap: .round)
        )
        context.fill(
            Path(ellipseIn: CGRect(
                x: geometry.center.x - geometry.dimension * 0.03,
                y: geometry.center.y - geometry.dimension * 0.03,
                width: geometry.dimension * 0.06,
                height: geometry.dimension * 0.06
            )),
            with: .color(.white)
        )
    }

    private func scaleLabel(_ value: Double) -> String {
        if metric == .rpm { return "\(Int(value / 1_000))k" }
        if metric == .boost { return value.formatted(.number.precision(.fractionLength(1))) }
        return Int(value).formatted()
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private struct DialGeometry {
        let dimension: CGFloat
        let center: CGPoint
        let radius: CGFloat

        init(size: CGSize) {
            dimension = min(size.width, size.height)
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            radius = dimension * 0.41
        }

        func point(angle: Double, radius: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
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
    }
}

private struct VideoOverlayElementEditor: View {
    @Binding var element: VideoOverlayElement

    var body: some View {
        DisclosureGroup {
            if element.kind != .telemetryTimestamp {
                Picker(localized("Parametr"), selection: $element.metric) {
                    ForEach(DashboardMetric.allCases) { metric in Text(metric.title).tag(metric) }
                }
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
                Image(systemName: element.kind == .telemetryTimestamp ? element.kind.icon : element.metric.icon)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(element.accent.color)
                    .background(element.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.kind == .telemetryTimestamp ? element.kind.title : element.metric.title).font(.headline)
                    Text("\(element.kind.title) · \(element.scale.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
