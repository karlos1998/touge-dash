import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: TelemetryController

    var body: some View {
        ZStack {
            DashboardBackground()

            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        DashboardHeader(controller: controller)
                        if proxy.size.width > 760 {
                            LandscapeDashboard(snapshot: controller.snapshot)
                        } else {
                            PortraitDashboard(snapshot: controller.snapshot)
                        }
                        ControlBar(controller: controller)
                    }
                    .padding(.horizontal, max(16, min(28, proxy.size.width * 0.035)))
                    .padding(.vertical, 14)
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

private struct DashboardHeader: View {
    @ObservedObject var controller: TelemetryController

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tougeCyan.opacity(0.12))
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.tougeCyan)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("TOUGE DASH")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .tracking(1.5)
                Text("ECUMaster EMU Black")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            TachometerCard(snapshot: snapshot)
                .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    MetricCard(title: "BOOST", value: snapshot.boostBar, unit: "bar", precision: 2, icon: "wind", tint: .tougeCyan, warning: snapshot.boostBar > 1.6)
                    MetricCard(title: "AFR", value: snapshot.afr, unit: "λ " + snapshot.lambda.formatted(.number.precision(.fractionLength(2))), precision: 1, icon: "waveform.path.ecg", tint: .tougeMint, warning: snapshot.afr > 0 && (snapshot.afr < 10.5 || snapshot.afr > 16))
                    OilTemperatureCard(temperature: snapshot.oilTemperatureCelsius)
                }
                HStack(spacing: 12) {
                    MetricCard(title: "COOLANT", value: snapshot.coolantCelsius, unit: "°C", precision: 0, icon: "thermometer.high", tint: .tougeOrange, warning: snapshot.coolantCelsius > 108)
                    MetricCard(title: "BATTERY", value: snapshot.batteryVoltage, unit: "V", precision: 1, icon: "battery.100percent", tint: .tougeYellow, warning: snapshot.rpm > 500 && snapshot.batteryVoltage > 0 && snapshot.batteryVoltage < 11.5)
                    MetricCard(title: "OIL PRESS", value: snapshot.oilPressureBar, unit: "bar", precision: 1, icon: "oilcan.fill", tint: .tougeMint, warning: snapshot.rpm > 1_200 && snapshot.oilPressureBar < 0.5)
                }
                HStack(spacing: 12) {
                    CompactMetric(title: "TPS", value: snapshot.throttlePercent, suffix: "%", tint: .tougeCyan)
                    CompactMetric(title: "IAT", value: snapshot.intakeCelsius, suffix: "°C", tint: .tougeBlue)
                    CompactMetric(title: "FUEL", value: snapshot.fuelPressureBar, suffix: " bar", tint: .tougeMint, precision: 1)
                    CompactMetric(title: "IGNITION", value: snapshot.ignitionDegrees, suffix: "°", tint: .tougeYellow, precision: 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 380)
    }
}

private struct PortraitDashboard: View {
    let snapshot: TelemetrySnapshot

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 12) {
            TachometerCard(snapshot: snapshot)
                .frame(height: 300)

            HStack(spacing: 12) {
                MetricCard(title: "BOOST", value: snapshot.boostBar, unit: "bar", precision: 2, icon: "wind", tint: .tougeCyan, warning: snapshot.boostBar > 1.6)
                OilTemperatureCard(temperature: snapshot.oilTemperatureCelsius)
            }
            .frame(height: 154)

            LazyVGrid(columns: columns, spacing: 12) {
                MetricCard(title: "AFR", value: snapshot.afr, unit: "λ " + snapshot.lambda.formatted(.number.precision(.fractionLength(2))), precision: 1, icon: "waveform.path.ecg", tint: .tougeMint, warning: snapshot.afr > 0 && (snapshot.afr < 10.5 || snapshot.afr > 16))
                MetricCard(title: "COOLANT", value: snapshot.coolantCelsius, unit: "°C", precision: 0, icon: "thermometer.high", tint: .tougeOrange, warning: snapshot.coolantCelsius > 108)
                MetricCard(title: "BATTERY", value: snapshot.batteryVoltage, unit: "V", precision: 1, icon: "battery.100percent", tint: .tougeYellow, warning: snapshot.rpm > 500 && snapshot.batteryVoltage > 0 && snapshot.batteryVoltage < 11.5)
                MetricCard(title: "OIL PRESS", value: snapshot.oilPressureBar, unit: "bar", precision: 1, icon: "oilcan.fill", tint: .tougeMint, warning: snapshot.rpm > 1_200 && snapshot.oilPressureBar < 0.5)
            }
            .frame(minHeight: 320)

            HStack(spacing: 10) {
                CompactMetric(title: "TPS", value: snapshot.throttlePercent, suffix: "%", tint: .tougeCyan)
                CompactMetric(title: "IAT", value: snapshot.intakeCelsius, suffix: "°C", tint: .tougeBlue)
                CompactMetric(title: "SPEED", value: snapshot.speedKPH, suffix: " km/h", tint: .tougeYellow)
            }
        }
    }
}

private struct TachometerCard: View {
    let snapshot: TelemetrySnapshot

    private var progress: Double { min(max(snapshot.rpm / 8_500, 0), 1) }
    private var gaugeColor: Color { snapshot.rpm > 7_400 ? .tougeRed : .tougeCyan }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("ENGINE SPEED", systemImage: "engine.combustion.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.hasCriticalWarning ? "WARNING" : "LIVE")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(snapshot.hasCriticalWarning ? Color.tougeRed : Color.tougeMint)
            }

            Spacer(minLength: 4)

            ZStack {
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(Color.white.opacity(0.075), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(90))
                Circle()
                    .trim(from: 0.12, to: 0.12 + 0.76 * progress)
                    .stroke(
                        AngularGradient(colors: [.tougeBlue, gaugeColor, gaugeColor], center: .center),
                        style: StrokeStyle(lineWidth: 22, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .shadow(color: gaugeColor.opacity(0.45), radius: 13)

                VStack(spacing: -3) {
                    Text(Int(snapshot.rpm).formatted(.number.grouping(.never)))
                        .font(.system(size: 61, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.65)
                    Text("RPM")
                        .font(.caption.weight(.black))
                        .tracking(3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)

            HStack {
                Text("0")
                Spacer()
                Text("REDLINE  8.5")
            }
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .cardSurface()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(warning ? Color.tougeRed : tint)
            }
            Spacer(minLength: 0)
            Text(value.formatted(.number.precision(.fractionLength(precision))))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(warning ? Color.tougeRed : Color.white)
                .minimumScaleFactor(0.65)
            Text(unit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(warning: warning)
    }
}

private struct OilTemperatureCard: View {
    let temperature: Double

    private var warning: Bool { temperature > 135 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("OIL TEMP")
                .font(.caption2.weight(.black))
                .tracking(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(Int(temperature).formatted())
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text("°C")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(warning ? Color.tougeRed : Color.tougeOrange)
            .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(warning: warning)
    }
}

private struct CompactMetric: View {
    let title: String
    let value: Double
    let suffix: String
    let tint: Color
    var precision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.black))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value.formatted(.number.precision(.fractionLength(precision))) + suffix)
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardSurface()
    }
}

private struct ControlBar: View {
    @ObservedObject var controller: TelemetryController

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    controller.useBluetooth()
                } label: {
                    ActionLabel(title: controller.isConnected ? "Połączono" : "Połączenie", icon: "antenna.radiowaves.left.and.right", active: controller.isConnected)
                }

                Button {
                    controller.toggleLiveActivity()
                } label: {
                    ActionLabel(title: controller.activityManager.isRunning ? "Stop card" : "CarPlay card", icon: "car.side.fill", active: controller.activityManager.isRunning)
                }
            }
            .buttonStyle(.plain)

            if let error = controller.activityManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.tougeOrange)
            }
        }
    }
}

private struct ActionLabel: View {
    let title: String
    let icon: String
    let active: Bool

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(active ? Color.black : Color.white)
            .background(active ? Color.tougeCyan : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(active ? 0 : 0.08)))
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
            Text(title.uppercased())
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
                            Text("\(controller.bluetooth.receivedPacketCount) packets · \(controller.receivedBytes) bytes")
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

private struct DashboardBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.026, blue: 0.035)
            RadialGradient(colors: [Color.tougeCyan.opacity(0.11), .clear], center: .topTrailing, startRadius: 10, endRadius: 480)
            LinearGradient(colors: [.clear, Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

private extension View {
    func cardSurface(warning: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.045, green: 0.058, blue: 0.072).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(warning ? Color.tougeRed.opacity(0.55) : Color.white.opacity(0.075), lineWidth: 1)
                )
        )
    }
}

extension Color {
    static let tougeCyan = Color(red: 0.05, green: 0.88, blue: 0.94)
    static let tougeBlue = Color(red: 0.16, green: 0.48, blue: 1)
    static let tougeMint = Color(red: 0.21, green: 0.91, blue: 0.62)
    static let tougeOrange = Color(red: 1, green: 0.47, blue: 0.19)
    static let tougeYellow = Color(red: 1, green: 0.77, blue: 0.19)
    static let tougeRed = Color(red: 1, green: 0.22, blue: 0.25)
}
