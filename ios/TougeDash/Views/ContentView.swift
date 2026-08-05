import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: TelemetryController
    @ObservedObject var templates: DashboardTemplateStore
    @ObservedObject var telemetryBuffer: DashboardTelemetryBuffer
    let onTemplateChanged: () -> Void
    let onShowHistory: (() -> Void)?

    @State private var isEditingDashboard = false
    @State private var quickEditorWidget: DashboardWidget?
    @State private var widgetPendingDeletion: DashboardWidget?

    var body: some View {
        ZStack {
            DashboardBackground()

            GeometryReader { proxy in
                let viewport = DashboardViewport(size: proxy.size)
                let isWide = viewport.usesLandscapeLayout
                let isCompactWide = viewport.isCompactLandscape

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: isCompactWide ? 8 : 16) {
                        DashboardHeader(controller: controller, compact: isCompactWide)
                        DashboardTemplateBar(
                            store: templates,
                            isEditingDashboard: $isEditingDashboard,
                            compact: isCompactWide,
                            onTemplateChanged: onTemplateChanged
                        )
                        ConfigurableDashboardView(
                            template: templates.activeTemplate,
                            snapshot: controller.snapshot,
                            telemetryBuffer: telemetryBuffer,
                            accelerationEngine: controller.accelerationEngine,
                            isWide: isWide,
                            compact: isCompactWide,
                            isEditing: isEditingDashboard,
                            canDeleteWidgets: templates.activeTemplate.definition.widgets.count > 1,
                            onEditWidget: { quickEditorWidget = $0 },
                            onDeleteWidget: { widget in
                                widgetPendingDeletion = widget
                            },
                            onSwapWidgets: { sourceID, destinationID in
                                withAnimation(.snappy(duration: 0.24)) {
                                    if templates.swapActiveWidgets(sourceID, destinationID, isWide: isWide) {
                                        onTemplateChanged()
                                    }
                                }
                            }
                        )
                        .transaction { transaction in
                            if controller.videoRecorder.isRecording {
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }
                        ControlBar(
                            controller: controller,
                            compact: isCompactWide,
                            onShowHistory: isCompactWide ? onShowHistory : nil
                        )
                        ProductCreditFooter(compact: isCompactWide)
                    }
                    .padding(.horizontal, viewport.horizontalPadding)
                    .padding(.vertical, isCompactWide ? 7 : 14)
                    .frame(maxWidth: proxy.size.width)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $controller.showingDevicePicker) {
            DevicePickerView(controller: controller)
        }
        .sheet(item: $quickEditorWidget) { widget in
            DashboardWidgetQuickEditor(initial: widget) { updated in
                if templates.updateActiveWidget(updated) {
                    onTemplateChanged()
                }
                quickEditorWidget = nil
            }
        }
        .confirmationDialog(
            localized("Usunąć tę kartę z dashboardu?"),
            isPresented: Binding(
                get: { widgetPendingDeletion != nil },
                set: { if !$0 { widgetPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(localized("Usuń kartę"), role: .destructive) {
                guard let widget = widgetPendingDeletion else { return }
                withAnimation(.snappy(duration: 0.22)) {
                    if templates.removeActiveWidget(widget.id) {
                        onTemplateChanged()
                    }
                }
                widgetPendingDeletion = nil
            }
            Button(localized("Anuluj"), role: .cancel) {
                widgetPendingDeletion = nil
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGE_DASH_DASHBOARD_EDIT_PREVIEW"] == "1" {
                isEditingDashboard = true
            }
            #endif
        }
    }
}

struct DashboardViewport: Equatable {
    let size: CGSize

    var usesLandscapeLayout: Bool {
        size.width > size.height && size.width >= 680
    }

    var isCompactLandscape: Bool {
        usesLandscapeLayout && size.height < 600
    }

    var horizontalPadding: CGFloat {
        if isCompactLandscape { return 12 }
        return max(16, min(28, size.width * 0.035))
    }
}

struct ProductCreditFooter: View {
    var compact = false

    private let website = URL(string: "https://letscode.it")!

    var body: some View {
        Link(destination: website) {
            HStack(spacing: compact ? 3 : 4) {
                Text(localized("Stworzono z"))
                Image(systemName: "heart.fill")
                    .font(.system(size: compact ? 7 : 8, weight: .bold))
                    .foregroundStyle(Color.tougeRed)
                Text(localized("przez"))
                Text("Let's Code It — Karol Sójka")
                    .foregroundStyle(Color.tougeCyan)
            }
            .font(.system(size: compact ? 7 : 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .accessibilityLabel(localized("Stworzono z sercem przez Let's Code It — Karol Sójka"))
    }
}

private struct DashboardHeader: View {
    @ObservedObject var controller: TelemetryController
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 9 : 12) {
            ZStack {
                CutCornerPanel(cut: 10)
                    .fill(Color.tougeCyan.opacity(0.13))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: compact ? 18 : 23, weight: .bold))
                    .foregroundStyle(Color.tougeCyan)
            }
            .frame(width: compact ? 38 : 46, height: compact ? 38 : 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("TOUGE DASH")
                    .font(.system(size: compact ? 15 : 17, weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .tracking(1.5)
                if !compact {
                    Text("EMU BLACK  /  DRIVER DISPLAY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                controller.showBluetoothDetails()
            } label: {
                ConnectionBadge(
                    title: controller.connectionLabel,
                    isConnected: controller.isConnected
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("Połączenie z EMU"))
        }
    }
}

private struct ControlBar: View {
    @ObservedObject var controller: TelemetryController
    let compact: Bool
    let onShowHistory: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    controller.useBluetooth()
                } label: {
                    ActionLabel(title: controller.isConnected ? "Połączono" : "Połączenie", icon: "antenna.radiowaves.left.and.right", active: controller.isConnected, compact: compact)
                }

                Button {
                    controller.toggleLiveActivity()
                } label: {
                    ActionLabel(title: controller.activityManager.isRunning ? "Stop card" : "CarPlay card", icon: "car.side.fill", active: controller.activityManager.isRunning, compact: compact)
                }

                if let onShowHistory {
                    Button(action: onShowHistory) {
                        ActionLabel(title: "Historia", icon: "chart.xyaxis.line", active: false, compact: compact)
                    }
                }
            }
            .buttonStyle(.plain)

            if let error = controller.activityManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.tougeOrange)
            }

            if controller.isConnected {
                Label("Szybki podgląd aktywny · ekran iPhone’a nie wygasi się automatycznie", systemImage: "bolt.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.tougeMint)
            }
        }
    }
}

private struct ActionLabel: View {
    let title: String
    let icon: String
    let active: Bool
    let compact: Bool

    var body: some View {
        Label(localized(title), systemImage: icon)
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 8 : 13)
            .foregroundStyle(active ? Color.black : Color.white)
            .background(active ? Color.tougeCyan : Color.white.opacity(0.07), in: CutCornerPanel(cut: 10))
            .overlay(CutCornerPanel(cut: 10).stroke(Color.white.opacity(active ? 0 : 0.08)))
    }
}

private struct ConnectionBadge: View {
    let title: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isConnected ? Color.tougeMint : Color.tougeRed)
                .frame(width: 7, height: 7)
                .shadow(color: (isConnected ? Color.tougeMint : Color.tougeRed).opacity(0.8), radius: 5)
            Text(localized(title).uppercased())
                .font(.caption2.weight(.black))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.09)))
    }
}

private struct DevicePickerView: View {
    @ObservedObject var controller: TelemetryController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if controller.bluetooth.devices.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Szukanie interfejsu ECUMaster…")
                        }
                    } else {
                        ForEach(controller.bluetooth.devices) { device in
                            Button {
                                controller.connect(to: device)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bolt.horizontal.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.tougeCyan)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name).foregroundStyle(.primary)
                                        Text(device.id.uuidString)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(device.rssi) dBm")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Urządzenia ECUMaster")
                } footer: {
                    Text("Lista pokazuje wyłącznie interfejsy ECUMaster. Pierwsze wykryte urządzenie jest łączone automatycznie, a aplikacja zapamiętuje je na kolejne uruchomienia.")
                }

                if !controller.bluetooth.diagnostics.isEmpty {
                    Section("Protocol") {
                        LabeledContent("Received") {
                            Text(String(
                                format: localized("%@ packets · %@ bytes"),
                                controller.bluetooth.receivedPacketCount.formatted(),
                                controller.receivedBytes.formatted()
                            ))
                                .monospacedDigit()
                        }
                        LabeledContent("Valid frames") {
                            Text(controller.parserStats.validFrames.formatted())
                                .monospacedDigit()
                        }
                        LabeledContent("Bad checksums") {
                            Text(controller.parserStats.badChecksums.formatted())
                                .monospacedDigit()
                        }
                        if !controller.bluetooth.lastPacketHex.isEmpty {
                            Text(controller.bluetooth.lastPacketHex)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    Section("Diagnostics") {
                        ForEach(Array(controller.bluetooth.diagnostics.suffix(12).reversed()), id: \.self) { message in
                            Text(message)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Połączenie z EMU")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Skanuj") { controller.bluetooth.startScanning() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct DashboardBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.019, blue: 0.028)
            RadialGradient(colors: [Color.tougeBlue.opacity(0.17), .clear], center: .topTrailing, startRadius: 15, endRadius: 620)
            RadialGradient(colors: [Color.tougeCyan.opacity(0.08), .clear], center: .bottomLeading, startRadius: 20, endRadius: 520)
            GeometryReader { proxy in
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(Color.tougeCyan.opacity(index == 0 ? 0.09 : 0.035))
                            .frame(width: 1, height: proxy.size.height * 1.4)
                            .rotationEffect(.degrees(24))
                            .offset(x: proxy.size.width * (0.18 + CGFloat(index) * 0.19), y: -proxy.size.height * 0.16)
                    }
                }
            }
            .accessibilityHidden(true)
            LinearGradient(colors: [.clear, Color.black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

struct CutCornerPanel: Shape {
    var cut: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let corner: CGFloat = min(15, min(rect.width, rect.height) * 0.12)
        let cut = min(cut, min(rect.width, rect.height) * 0.28)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: corner))
        path.addQuadCurve(to: CGPoint(x: corner, y: 0), control: .zero)
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - corner, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY - cut))
        path.closeSubpath()
        return path
    }
}

extension View {
    func cardSurface(warning: Bool = false, accent: Color = .clear) -> some View {
        background {
            CutCornerPanel()
                .fill(
                    LinearGradient(
                        colors: warning
                            ? [Color.tougeRed.opacity(0.15), Color(red: 0.045, green: 0.052, blue: 0.065)]
                            : [Color(red: 0.055, green: 0.071, blue: 0.088), Color(red: 0.032, green: 0.043, blue: 0.056)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    CutCornerPanel()
                        .stroke(warning ? Color.tougeRed.opacity(0.62) : Color.white.opacity(0.085), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 14, y: 8)
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(accent.opacity(warning ? 0.95 : 0.78))
                .frame(width: 54, height: 2)
                .padding(.leading, 16)
        }
    }
}

extension Color {
    static let tougeCyan = Color(red: 0.05, green: 0.88, blue: 0.94)
    static let tougeBlue = Color(red: 0.16, green: 0.48, blue: 1)
    static let tougeMint = Color(red: 0.21, green: 0.91, blue: 0.62)
    static let tougeOrange = Color(red: 1, green: 0.47, blue: 0.19)
    static let tougeYellow = Color(red: 1, green: 0.77, blue: 0.19)
    static let tougeRed = Color(red: 1, green: 0.22, blue: 0.25)
    static let tougeIce = Color(red: 0.38, green: 0.75, blue: 1)
}
