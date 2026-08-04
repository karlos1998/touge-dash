import SwiftUI

struct SimulatorRootView: View {
    @StateObject private var model = EMUSimulatorViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            SimulatorBackground()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 16) {
                            connectionPanel
                            scenarioPanel
                            diagnosticsPanel
                        }
                        .frame(width: 330)

                        VStack(spacing: 16) {
                            telemetryGrid
                            manualControls
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(22)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cyan.opacity(0.14))
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.cyan)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("TOUGE DASH")
                    .font(.system(size: 21, weight: .black))
                    .tracking(3)
                Text("EMU LOGGER SIMULATOR · FFE0 / FFE1")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(model.statusTint).frame(width: 9, height: 9)
                .shadow(color: model.statusTint, radius: 7)
            Text(model.peripheral.statusText.uppercased())
                .font(.system(size: 11, weight: .black))
                .tracking(1)
                .foregroundStyle(model.statusTint)
        }
    }

    private var connectionPanel: some View {
        panel(accent: model.isRunning ? .cyan : .gray) {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("LOGGER BLE", symbol: "antenna.radiowaves.left.and.right")

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BLEPeripheralSimulator.advertisedName)
                            .font(.headline.weight(.black))
                        Text("Usługa FFE0 · notify/read FFE1")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.peripheral.subscriberCount.formatted())
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(model.statusTint)
                    Text("TEL.")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.secondary)
                }

                Picker("Częstotliwość", selection: $model.sampleRate) {
                    Text("10 Hz").tag(10)
                    Text("25 Hz").tag(25)
                }
                .pickerStyle(.segmented)

                Button {
                    model.isRunning ? model.stop() : model.start()
                } label: {
                    Label(model.isRunning ? "ZATRZYMAJ LOGGER" : "URUCHOM LOGGER", systemImage: model.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRunning ? .red : .cyan)

                Button {
                    model.restartConnection()
                } label: {
                    Label("Rozłącz i połącz ponownie", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.isRunning)
            }
        }
    }

    private var scenarioPanel: some View {
        panel(accent: model.scenario.isWarning ? .orange : .mint) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("SCENARIUSZ JAZDY", symbol: model.scenario.symbol)
                Picker("Scenariusz", selection: $model.scenario) {
                    ForEach(SimulationScenario.allCases) { scenario in
                        Label(scenario.title, systemImage: scenario.symbol).tag(scenario)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Text(model.scenario.isWarning
                     ? "Scenariusz celowo przekracza próg, aby sprawdzić alert, raport incydentu i reakcję zegarka."
                     : "Wartości zmieniają się automatycznie. Przesunięcie dowolnego suwaka przełącza tryb na ręczny.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var diagnosticsPanel: some View {
        panel(accent: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("DIAGNOSTYKA", symbol: "waveform.path.ecg")
                    Spacer()
                    Button("Wyzeruj") { model.resetCounters() }
                        .font(.caption.weight(.bold))
                }
                diagnosticRow("Zestawy ramek", model.generatedFrameSets.formatted())
                diagnosticRow("Notyfikacje BLE", model.peripheral.notificationCount.formatted())
                diagnosticRow("Wysłane dane", ByteCountFormatter.string(fromByteCount: Int64(model.peripheral.byteCount), countStyle: .file))
                VStack(alignment: .leading, spacing: 4) {
                    Text("OSTATNI PAKIET")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text(model.peripheral.lastPacketHex)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .lineLimit(2)
                }
            }
        }
    }

    private var telemetryGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            metricCard("RPM", model.telemetry.rpm, "rpm", .yellow, fraction: 0)
            metricCard("BOOST", model.telemetry.boostBar, "bar", .cyan, fraction: 2)
            metricCard("PRĘDKOŚĆ", model.telemetry.speedKPH, "km/h", .blue, fraction: 0)
            metricCard("CIŚNIENIE OLEJU", model.telemetry.oilPressureBar, "bar", .mint, fraction: 2)
            metricCard("TEMP. OLEJU", model.telemetry.oilTemperatureCelsius, "°C", .orange, fraction: 0)
            metricCard("PŁYN", model.telemetry.coolantCelsius, "°C", .blue, fraction: 0)
            metricCard("AFR", model.telemetry.afr, "AFR", .white, fraction: 1)
            metricCard("PALIWO", model.telemetry.fuelPressureBar, "bar", .mint, fraction: 2)
            metricCard("AKUMULATOR", model.telemetry.batteryVoltage, "V", .yellow, fraction: 1)
        }
    }

    private var manualControls: some View {
        panel(accent: .cyan) {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("RĘCZNE PARAMETRY", symbol: "slider.horizontal.3")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    slider("Obroty", value: model.binding(\.rpm), range: 0...9_000, unit: "rpm")
                    slider("Boost", value: model.binding(\.boostBar), range: -1...2.5, unit: "bar")
                    slider("Prędkość", value: model.binding(\.speedKPH), range: 0...300, unit: "km/h")
                    slider("Przepustnica", value: model.binding(\.throttlePercent), range: 0...100, unit: "%")
                    slider("Ciśnienie oleju", value: model.binding(\.oilPressureBar), range: 0...10, unit: "bar")
                    slider("Temperatura oleju", value: model.binding(\.oilTemperatureCelsius), range: 0...160, unit: "°C")
                    slider("Temperatura płynu", value: model.binding(\.coolantCelsius), range: -20...140, unit: "°C")
                    slider("AFR", value: model.binding(\.afr), range: 8...20, unit: "AFR")
                    slider("Ciśnienie paliwa", value: model.binding(\.fuelPressureBar), range: 0...10, unit: "bar")
                    slider("Napięcie", value: model.binding(\.batteryVoltage), range: 8...16, unit: "V")
                }
            }
        }
    }

    private func panel<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.035, green: 0.055, blue: 0.07).opacity(0.94))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(accent.opacity(0.28), lineWidth: 1)
                    }
            }
            .overlay(alignment: .topLeading) {
                Capsule().fill(accent).frame(width: 52, height: 3).padding(.leading, 18)
            }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .black))
            .tracking(1.3)
            .foregroundStyle(.secondary)
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.black).monospacedDigit()
        }
        .font(.caption)
    }

    private func metricCard(_ title: String, _ value: Double, _ unit: String, _ tint: Color, fraction: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .black))
                .tracking(1)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(value.formatted(.number.precision(.fractionLength(fraction))))
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(unit).font(.caption.weight(.black)).foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.18)))
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.bold))
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(1)))) \(unit)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(.cyan)
            }
            Slider(value: value, in: range)
                .tint(.cyan)
        }
    }
}

private struct SimulatorBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.015, green: 0.025, blue: 0.035)
            LinearGradient(
                colors: [Color.cyan.opacity(0.08), .clear, Color.blue.opacity(0.07)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
        .ignoresSafeArea()
    }
}
