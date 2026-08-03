import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: TelemetryController
    let onShowHistory: (() -> Void)?

    var body: some View {
        ZStack {
            DashboardBackground()

            GeometryReader { proxy in
                let isWide = proxy.size.width > 680
                let isCompactWide = isWide && proxy.size.height < 600

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: isCompactWide ? 8 : 16) {
                        DashboardHeader(controller: controller, compact: isCompactWide)
                        if isWide {
                            LandscapeDashboard(snapshot: controller.snapshot, compact: isCompactWide)
                        } else {
                            PortraitDashboard(snapshot: controller.snapshot)
                        }
                        ControlBar(
                            controller: controller,
                            compact: isCompactWide,
                            onShowHistory: isCompactWide ? onShowHistory : nil
                        )
                        ProductCreditFooter(compact: isCompactWide)
                    }
                    .padding(.horizontal, max(16, min(28, proxy.size.width * 0.035)))
                    .padding(.vertical, isCompactWide ? 7 : 14)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $controller.showingDevicePicker) {
            DevicePickerView(controller: controller)
        }
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

            ConnectionBadge(
                title: controller.connectionLabel,
                isConnected: controller.isConnected
            )
        }
    }
}

private struct LandscapeDashboard: View {
    let snapshot: TelemetrySnapshot
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 9 : 12) {
            EngineHealthCard(snapshot: snapshot, compact: compact, prominent: !compact)
                .frame(minHeight: compact ? 112 : 180, maxHeight: compact ? 112 : .infinity)

            HStack(spacing: compact ? 9 : 12) {
                MetricCard(
                    title: "BOOST",
                    value: snapshot.boostBar,
                    unit: "bar",
                    precision: 2,
                    icon: "wind",
                    tint: .tougeCyan,
                    warning: snapshot.boostBar > 1.6,
                    compact: compact,
                    prominent: !compact
                )
                MetricCard(
                    title: "AFR",
                    value: snapshot.afr,
                    unit: "λ " + snapshot.lambda.formatted(.number.precision(.fractionLength(2))),
                    precision: 1,
                    icon: "waveform.path.ecg",
                    tint: .tougeMint,
                    warning: snapshot.afr > 0 && (snapshot.afr < 10.5 || snapshot.afr > 16),
                    compact: compact,
                    prominent: !compact
                )
                MetricCard(
                    title: "BATTERY",
                    value: snapshot.batteryVoltage,
                    unit: "V",
                    precision: 1,
                    icon: "bolt.fill",
                    tint: .tougeYellow,
                    warning: snapshot.rpm > 500 && snapshot.batteryVoltage > 0 && snapshot.batteryVoltage < 11.5,
                    compact: compact,
                    prominent: !compact
                )
            }
            .frame(minHeight: compact ? 88 : 145, maxHeight: compact ? 88 : .infinity)

            HStack(spacing: compact ? 7 : 10) {
                CompactMetric(title: "MAP", value: snapshot.mapKPa, suffix: " kPa", tint: .tougeIce, compact: compact)
                CompactMetric(title: "TPS", value: snapshot.throttlePercent, suffix: "%", tint: .tougeCyan, compact: compact)
                CompactMetric(title: "RPM", value: snapshot.rpm, suffix: "", tint: .white, compact: compact)
                CompactMetric(title: "INJ", value: snapshot.injectorDutyPercent, suffix: "%", tint: .tougeOrange, compact: compact)
                CompactMetric(title: "IAT", value: snapshot.intakeCelsius, suffix: "°C", tint: .tougeBlue, compact: compact)
                CompactMetric(title: "FUEL", value: snapshot.fuelPressureBar, suffix: " bar", tint: .tougeMint, precision: 1, compact: compact)
            }
        }
        .frame(minHeight: compact ? 245 : 430, maxHeight: .infinity)
    }
}

private struct PortraitDashboard: View {
    let snapshot: TelemetrySnapshot

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 12) {
            BoostHeroCard(snapshot: snapshot, compact: false)
                .frame(height: 250)

            EngineHealthCard(snapshot: snapshot, compact: false)
                .frame(height: 190)

            LazyVGrid(columns: columns, spacing: 12) {
                MetricCard(title: "AFR", value: snapshot.afr, unit: "λ " + snapshot.lambda.formatted(.number.precision(.fractionLength(2))), precision: 1, icon: "waveform.path.ecg", tint: .tougeMint, warning: snapshot.afr > 0 && (snapshot.afr < 10.5 || snapshot.afr > 16))
                MetricCard(title: "BATTERY", value: snapshot.batteryVoltage, unit: "V", precision: 1, icon: "bolt.fill", tint: .tougeYellow, warning: snapshot.rpm > 500 && snapshot.batteryVoltage > 0 && snapshot.batteryVoltage < 11.5)
            }
            .frame(height: 145)

            HStack(spacing: 10) {
                CompactMetric(title: "INJ", value: snapshot.injectorDutyPercent, suffix: "%", tint: .tougeOrange)
                CompactMetric(title: "TPS", value: snapshot.throttlePercent, suffix: "%", tint: .tougeCyan)
                CompactMetric(title: "IAT", value: snapshot.intakeCelsius, suffix: "°C", tint: .tougeBlue)
                CompactMetric(title: "FUEL", value: snapshot.fuelPressureBar, suffix: " bar", tint: .tougeMint, precision: 1)
            }
        }
    }
}

private struct BoostHeroCard: View {
    let snapshot: TelemetrySnapshot
    let compact: Bool

    private var warning: Bool { snapshot.boostBar > 1.6 }
    private var progress: Double { min(max(snapshot.boostBar / 2, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Label("BOOST PRESSURE", systemImage: "wind")
                    .font(.system(size: compact ? 9 : 11, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusTag(
                    title: warning ? "HIGH" : "LIVE DATA",
                    tint: warning ? .tougeRed : .tougeCyan
                )
            }

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(snapshot.boostBar.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: compact ? 57 : 80, weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                    .foregroundStyle(warning ? Color.tougeRed : Color.white)
                Text("BAR")
                    .font(.system(size: compact ? 10 : 12, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(warning ? Color.tougeRed : Color.tougeCyan)
                    .padding(.bottom, compact ? 8 : 13)
            }

            BoostScale(progress: progress, warning: warning, compact: compact)

            HStack(spacing: 0) {
                InlineTelemetry(title: "MAP", value: Int(snapshot.mapKPa).formatted(), unit: "kPa")
                InlineTelemetry(title: "THROTTLE", value: Int(snapshot.throttlePercent).formatted(), unit: "%")
                InlineTelemetry(title: "ENGINE", value: Int(snapshot.rpm).formatted(.number.grouping(.never)), unit: "rpm")
            }
        }
        .padding(compact ? 14 : 18)
        .cardSurface(warning: warning, accent: warning ? .tougeRed : .tougeCyan)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill((warning ? Color.tougeRed : Color.tougeCyan).opacity(0.32))
                        .frame(width: 3, height: compact ? 19 : 25)
                        .rotationEffect(.degrees(35))
                }
            }
            .padding(.trailing, compact ? 42 : 54)
            .accessibilityHidden(true)
        }
    }
}

private struct BoostScale: View {
    let progress: Double
    let warning: Bool
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.075))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: warning ? [.tougeOrange, .tougeRed] : [.tougeBlue, .tougeCyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * progress))
                        .shadow(color: (warning ? Color.tougeRed : Color.tougeCyan).opacity(0.55), radius: 8)
                }
            }
            .frame(height: compact ? 7 : 9)

            HStack {
                Text("0")
                Spacer()
                Text("1.0")
                Spacer()
                Text("2.0 BAR")
            }
            .font(.system(size: compact ? 7 : 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
    }
}

private struct InlineTelemetry: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localized(title))
                .font(.system(size: 8, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EngineHealthCard: View {
    let snapshot: TelemetrySnapshot
    let compact: Bool
    var prominent = false

    private var oilPressureWarning: Bool {
        snapshot.rpm > 1_200 && snapshot.oilPressureBar > 0 && snapshot.oilPressureBar < 0.5
    }

    private var warning: Bool { snapshot.hasTemperatureWarning || oilPressureWarning }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 11 : 16) {
            HStack(spacing: 8) {
                Label("ENGINE HEALTH", systemImage: "heart.text.clipboard.fill")
                    .font(.system(size: compact ? 9 : 11, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusTag(
                    title: snapshot.hasTemperatureWarning ? "TEMP ALERT" : (warning ? "CHECK ENGINE" : "NOMINAL"),
                    tint: warning ? .tougeRed : .tougeMint
                )
            }

            HStack(alignment: .bottom, spacing: compact ? 9 : 14) {
                HealthValue(
                    title: "OIL PRESSURE",
                    value: snapshot.oilPressureBar,
                    unit: "bar",
                    precision: 1,
                    icon: "oilcan.fill",
                    tint: .tougeMint,
                    warning: oilPressureWarning,
                    compact: compact,
                    prominent: prominent
                )

                HealthDivider()

                HealthValue(
                    title: "OIL TEMP",
                    value: snapshot.oilTemperatureCelsius,
                    unit: "°C",
                    precision: 0,
                    icon: "thermometer.medium",
                    tint: .tougeOrange,
                    warning: snapshot.oilTemperatureCelsius >= EngineTemperatureLimits.oilWarningCelsius,
                    compact: compact,
                    prominent: prominent
                )

                HealthDivider()

                HealthValue(
                    title: "COOLANT",
                    value: snapshot.coolantCelsius,
                    unit: "°C",
                    precision: 0,
                    icon: "thermometer.high",
                    tint: .tougeIce,
                    warning: snapshot.coolantCelsius >= EngineTemperatureLimits.coolantWarningCelsius,
                    compact: compact,
                    prominent: prominent
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(compact ? 14 : 18)
        .cardSurface(warning: warning, accent: warning ? .tougeRed : .tougeMint)
    }
}

private struct HealthValue: View {
    let title: String
    let value: Double
    let unit: String
    let precision: Int
    let icon: String
    let tint: Color
    let warning: Bool
    let compact: Bool
    let prominent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 9 : 11, weight: .bold))
                    .foregroundStyle(warning ? Color.tougeRed : tint)
                Text(localized(title))
                    .font(.system(size: compact ? 7 : 8, weight: .black))
                    .tracking(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value.formatted(.number.precision(.fractionLength(precision))))
                    .font(.system(size: compact ? 28 : (prominent ? 58 : 38), weight: .black, design: .rounded))
                    .fontWidth(.expanded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .foregroundStyle(warning ? Color.tougeRed : Color.white)
                Text(unit)
                    .font(.system(size: compact ? 8 : (prominent ? 13 : 10), weight: .black))
                    .foregroundStyle(warning ? Color.tougeRed : tint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

private struct HealthDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 4)
    }
}

private struct StatusTag: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .shadow(color: tint.opacity(0.8), radius: 4)
            Text(localized(title))
                .font(.system(size: 8, weight: .black))
                .tracking(0.7)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.22)))
    }
}

private struct MetricCard: View {
    let title: String
    let value: Double
    let unit: String
    let precision: Int
    let icon: String
    let tint: Color
    let warning: Bool
    var compact = false
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 9) {
            HStack {
                Text(localized(title))
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(warning ? Color.tougeRed : tint)
            }
            Spacer(minLength: 0)
            Text(value.formatted(.number.precision(.fractionLength(precision))))
                .font(.system(size: compact ? 26 : (prominent ? 52 : 34), weight: .black, design: .rounded))
                .fontWidth(.expanded)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(warning ? Color.tougeRed : Color.white)
                .minimumScaleFactor(0.65)
            Text(unit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(compact ? 11 : 14)
        .cardSurface(warning: warning, accent: warning ? .tougeRed : tint)
    }
}

private struct CompactMetric: View {
    let title: String
    let value: Double
    let suffix: String
    let tint: Color
    var precision = 0
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized(title))
                .font(.system(size: compact ? 8 : 10, weight: .black))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value.formatted(.number.precision(.fractionLength(precision))) + suffix)
                .font(.system(size: compact ? 15 : 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 9 : 12)
        .cardSurface(accent: tint)
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
