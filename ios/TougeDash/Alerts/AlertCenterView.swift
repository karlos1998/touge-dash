import SwiftUI

struct AlertCenterView: View {
    @ObservedObject private var cloudSync: CloudSyncManager
    @ObservedObject private var store: VehicleAlertRuleStore
    @State private var draft: VehicleAlertRules
    @State private var showingResetConfirmation = false
    @State private var savedConfirmation = false

    init(cloudSync: CloudSyncManager) {
        _cloudSync = ObservedObject(wrappedValue: cloudSync)
        _store = ObservedObject(wrappedValue: cloudSync.alertRules)
        _draft = State(initialValue: cloudSync.alertRules.activeRules)
    }

    private var record: VehicleAlertRuleStore.Record { store.activeRecord }

    private var canEdit: Bool {
        guard let vehicle = cloudSync.activeVehicle else { return true }
        return vehicle.role == "OWNER" || vehicle.role == "MECHANIC"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    safetyNotice
                    if let conflict = record.conflict {
                        conflictBanner(conflict)
                    }

                    AlertRuleEditor(
                        title: "Ciśnienie oleju",
                        subtitle: "Alarm tylko przy pracującym silniku i zadanych obrotach.",
                        symbol: "oilcan.fill",
                        tint: .tougeMint,
                        enabled: $draft.lowOilPressureEnabled,
                        editable: canEdit
                    ) {
                        RuleValueField(
                            label: "MINIMUM",
                            unit: "bar",
                            value: $draft.minimumOilPressureBar,
                            range: 0.1...10,
                            decimals: 1
                        )
                        RuleValueField(
                            label: "OD OBROTÓW",
                            unit: "RPM",
                            value: $draft.lowOilMinimumRPM,
                            range: 0...12_000,
                            decimals: 0
                        )
                        RuleValueField(
                            label: "PRZEZ",
                            unit: "s",
                            value: $draft.lowOilDurationSeconds,
                            range: 0.1...30,
                            decimals: 2
                        )
                    }

                    AlertRuleEditor(
                        title: "Mieszanka pod doładowaniem",
                        subtitle: "Wykrywa zbyt ubogi AFR dopiero po wejściu na boost.",
                        symbol: "aqi.medium",
                        tint: .orange,
                        enabled: $draft.leanUnderBoostEnabled,
                        editable: canEdit
                    ) {
                        RuleValueField(
                            label: "MAKS. AFR",
                            unit: "AFR",
                            value: $draft.maximumAFR,
                            range: 8...25,
                            decimals: 1
                        )
                        RuleValueField(
                            label: "OD BOOSTU",
                            unit: "bar",
                            value: $draft.leanMinimumBoostBar,
                            range: -1...5,
                            decimals: 2
                        )
                        RuleValueField(
                            label: "PRZEZ",
                            unit: "s",
                            value: $draft.leanDurationSeconds,
                            range: 0.1...30,
                            decimals: 2
                        )
                    }

                    AlertRuleEditor(
                        title: "Overboost",
                        subtitle: "Maksymalne dopuszczalne ciśnienie doładowania tego auta.",
                        symbol: "gauge.with.dots.needle.100percent",
                        tint: .tougeCyan,
                        enabled: $draft.overboostEnabled,
                        editable: canEdit
                    ) {
                        RuleValueField(
                            label: "MAKSIMUM",
                            unit: "bar",
                            value: $draft.maximumBoostBar,
                            range: 0...5,
                            decimals: 2
                        )
                        RuleValueField(
                            label: "PRZEZ",
                            unit: "s",
                            value: $draft.overboostDurationSeconds,
                            range: 0.1...30,
                            decimals: 2
                        )
                    }

                    AlertRuleEditor(
                        title: "Temperatura płynu",
                        subtitle: "Osobny próg dla układu chłodzenia silnika.",
                        symbol: "thermometer.and.liquid.waves",
                        tint: .red,
                        enabled: $draft.highCoolantTemperatureEnabled,
                        editable: canEdit
                    ) {
                        RuleValueField(
                            label: "MAKSIMUM",
                            unit: "°C",
                            value: $draft.maximumCoolantCelsius,
                            range: 70...180,
                            decimals: 0
                        )
                        RuleValueField(
                            label: "PRZEZ",
                            unit: "s",
                            value: $draft.coolantDurationSeconds,
                            range: 0.1...30,
                            decimals: 1
                        )
                    }

                    AlertRuleEditor(
                        title: "Temperatura oleju",
                        subtitle: "Może mieć inny limit niż płyn — zależnie od oleju i chłodzenia.",
                        symbol: "oilcan.fill",
                        tint: .orange,
                        enabled: $draft.highOilTemperatureEnabled,
                        editable: canEdit
                    ) {
                        RuleValueField(
                            label: "MAKSIMUM",
                            unit: "°C",
                            value: $draft.maximumOilTemperatureCelsius,
                            range: 70...200,
                            decimals: 0
                        )
                        RuleValueField(
                            label: "PRZEZ",
                            unit: "s",
                            value: $draft.oilTemperatureDurationSeconds,
                            range: 0.1...30,
                            decimals: 1
                        )
                    }

                    AlertRuleEditor(
                        title: "Napięcie instalacji",
                        subtitle: "Pomija zgaszony silnik dzięki minimalnym obrotom aktywacji.",
                        symbol: "battery.25percent",
                        tint: .yellow,
                        enabled: $draft.lowBatteryVoltageEnabled,
                        editable: canEdit
                    ) {
                        RuleValueField(
                            label: "MINIMUM",
                            unit: "V",
                            value: $draft.minimumBatteryVoltage,
                            range: 8...16,
                            decimals: 1
                        )
                        RuleValueField(
                            label: "OD OBROTÓW",
                            unit: "RPM",
                            value: $draft.lowBatteryMinimumRPM,
                            range: 0...12_000,
                            decimals: 0
                        )
                        RuleValueField(
                            label: "PRZEZ",
                            unit: "s",
                            value: $draft.lowBatteryDurationSeconds,
                            range: 0.1...30,
                            decimals: 1
                        )
                    }

                    AlertRuleEditor(
                        title: "Ciśnienie paliwa",
                        subtitle: "Domyślnie wyłączone — włącz po potwierdzeniu, że kanał jest skonfigurowany w EMU.",
                        symbol: "fuelpump.fill",
                        tint: .pink,
                        enabled: $draft.lowFuelPressureEnabled,
                        editable: canEdit
                    ) {
                        RuleValueField(
                            label: "MINIMUM",
                            unit: "bar",
                            value: $draft.minimumFuelPressureBar,
                            range: 0.1...20,
                            decimals: 1
                        )
                        RuleValueField(
                            label: "OD OBROTÓW",
                            unit: "RPM",
                            value: $draft.lowFuelPressureMinimumRPM,
                            range: 0...12_000,
                            decimals: 0
                        )
                        RuleValueField(
                            label: "PRZEZ",
                            unit: "s",
                            value: $draft.lowFuelPressureDurationSeconds,
                            range: 0.1...30,
                            decimals: 1
                        )
                    }

                    cooldownCard
                    actionBar
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black)
            .navigationTitle("Centrum alertów")
            .onAppear(perform: reload)
            .onChange(of: store.activeVehicleID) { _, _ in reload() }
            .onChange(of: store.records) { _, _ in reload() }
            .confirmationDialog(
                "Przywrócić ustawienia domyślne?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Przywróć progi domyślne", role: .destructive) {
                    draft = .standard
                }
                Button("Anuluj", role: .cancel) {}
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                CutCornerPanel(cut: 10).fill(Color.tougeCyan.opacity(0.13))
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2.weight(.black))
                    .foregroundStyle(Color.tougeCyan)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(cloudSync.activeVehicle?.displayName ?? localized("Konfiguracja lokalna"))
                    .font(.headline.weight(.black))
                if record.dirty {
                    Label("Zmiany czekają na synchronizację", systemImage: "icloud.and.arrow.up")
                        .foregroundStyle(Color.orange)
                } else if let date = record.updatedAt {
                    Text(lastEditor(date: date))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Domyślne progi Touge Dash")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            Spacer()
            Text("R\(record.revision)")
                .font(.caption2.monospaced().weight(.black))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(CutCornerPanel(cut: 14).fill(Color.white.opacity(0.055)))
        .overlay(CutCornerPanel(cut: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill").foregroundStyle(Color.tougeMint)
            VStack(alignment: .leading, spacing: 4) {
                Text("WYŁĄCZNIE ANALIZA DANYCH").font(.caption2.weight(.black)).tracking(1)
                Text("Te ustawienia zmieniają tylko sposób wykrywania zdarzeń w Touge Dash. Nic nie jest zapisywane ani wysyłane do sterownika lub EMULOGGERA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.tougeMint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func conflictBanner(_ remote: CloudVehicleAlertConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Konfiguracja została zmieniona online", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.subheadline.weight(.black))
                .foregroundStyle(.orange)
            Text(String(
                format: localized("%@ zapisał(a) nowszą wersję. Wybierz, które ustawienia zachować."),
                remote.updatedByDisplayName ?? localized("Inny użytkownik")
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Button("Użyj wersji online") {
                    cloudSync.acceptRemoteAlertRules()
                    reload()
                }
                .buttonStyle(.bordered)
                Button("Zachowaj moje") {
                    cloudSync.keepLocalAlertRules()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var cooldownCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("ODSTĘP MIĘDZY RAPORTAMI").font(.caption2.weight(.black)).tracking(1)
                Text("Ta sama reguła nie utworzy kolejnego raportu przed upływem tego czasu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(value: $draft.cooldownSeconds, in: 30...3_600, step: 30) {
                Text(durationLabel(draft.cooldownSeconds)).monospacedDigit().fontWeight(.bold)
            }
            .fixedSize()
            .disabled(!canEdit)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.045)))
    }

    private var actionBar: some View {
        HStack {
            Button("Domyślne") { showingResetConfirmation = true }
                .buttonStyle(.bordered)
                .disabled(!canEdit)
            Spacer()
            if savedConfirmation {
                Label("Zapisano", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.tougeMint)
            }
            Button("Zapisz reguły") {
                draft = draft.validated()
                cloudSync.saveAlertRules(draft)
                savedConfirmation = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    savedConfirmation = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.tougeCyan)
            .foregroundStyle(.black)
            .disabled(!canEdit || draft.validated() == record.rules)
        }
        .padding(.bottom, 10)
    }

    private func lastEditor(date: Date) -> String {
        let name = record.updatedByDisplayName ?? localized("Touge Dash")
        return String(
            format: localized("Ostatnia zmiana: %@ · %@"),
            name,
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60) min" : "\(seconds) s"
    }

    private func reload() {
        draft = store.activeRules
    }
}

private struct AlertRuleEditor<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    let tint: Color
    @Binding var enabled: Bool
    let editable: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.black))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled).labelsHidden().tint(tint).disabled(!editable)
            }
            if enabled {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                    content()
                }
                .disabled(!editable)
            }
        }
        .padding(16)
        .background(CutCornerPanel(cut: 12).fill(Color.white.opacity(enabled ? 0.05 : 0.025)))
        .overlay(CutCornerPanel(cut: 12).stroke(enabled ? tint.opacity(0.24) : Color.white.opacity(0.06)))
        .opacity(enabled ? 1 : 0.62)
    }
}

private struct RuleValueField: View {
    let label: LocalizedStringKey
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let decimals: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9, weight: .black)).tracking(0.9).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField(
                    "",
                    value: $value,
                    format: .number.precision(.fractionLength(0...decimals))
                )
                .keyboardType(.decimalPad)
                .font(.title3.monospacedDigit().weight(.black))
                .onChange(of: value) { _, newValue in value = newValue.clampedForField(to: range) }
                Text(unit).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
    }
}

private extension Double {
    func clampedForField(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
