import Charts
import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

struct IncidentReportView: View {
    let incident: DriveIncident
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @Query(sort: \TimelineAnnotation.timestamp) private var allAnnotations: [TimelineAnnotation]
    @State private var selectedIndex = 0
    @State private var showingNoteComposer = false
    @State private var showingShare = false

    private let samples: [CapturedTelemetryPoint]
    private let chartSamples: [CapturedTelemetryPoint]
    private let containsLocation: Bool

    init(
        incident: DriveIncident,
        cloudAccount: CloudAccountService,
        cloudSync: CloudSyncManager
    ) {
        self.incident = incident
        _cloudAccount = ObservedObject(wrappedValue: cloudAccount)
        _cloudSync = ObservedObject(wrappedValue: cloudSync)

        // `DriveIncident.samples` decodes JSON. Keep one decoded copy for the whole
        // report instead of doing the same work for every card and every redraw.
        let decoded = incident.samples.sorted { $0.timestamp < $1.timestamp }
        samples = decoded
        chartSamples = decoded.downsampled(maxPoints: 140)
        containsLocation = decoded.contains { $0.latitude != nil && $0.longitude != nil }
        let initialIndex = decoded.indices.min {
            abs(decoded[$0].timestamp.timeIntervalSince(incident.triggeredAt)) <
                abs(decoded[$1].timestamp.timeIntervalSince(incident.triggeredAt))
        } ?? 0
        _selectedIndex = State(initialValue: initialIndex)
    }

    private var selectedSample: CapturedTelemetryPoint? {
        guard !samples.isEmpty else { return nil }
        return samples[min(max(0, selectedIndex), samples.count - 1)]
    }
    private var notes: [TimelineAnnotation] {
        allAnnotations.filter { $0.incidentID == incident.id }
    }

    var body: some View {
        ZStack {
            DashboardBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    IncidentHeroCard(incident: incident)

                    CloudSyncItemCard(
                        itemName: "RAPORT INCYDENTU",
                        sampleCount: incident.sampleCount,
                        status: cloudSync.incidentStatus(for: incident),
                        onRetry: { Task { await cloudSync.retrySynchronization() } }
                    )

                    if let selectedSample {
                        IncidentMomentCard(
                            sample: selectedSample,
                            incident: incident,
                            selectedIndex: $selectedIndex,
                            sampleCount: samples.count,
                            onAddNote: { showingNoteComposer = true }
                        )
                    }

                    IncidentChartCard(
                        title: "TEMPERATURY",
                        subtitle: "Olej i płyn chłodniczy",
                        unit: "°C",
                        samples: chartSamples,
                        triggerAt: incident.triggeredAt,
                        series: [
                            .init(name: localized("Olej"), color: .tougeOrange, value: \.oilTemperatureCelsius),
                            .init(name: localized("Płyn"), color: .tougeIce, value: \.coolantCelsius)
                        ]
                    )

                    IncidentChartCard(
                        title: "CIŚNIENIA",
                        subtitle: "Olej i doładowanie",
                        unit: "bar",
                        samples: chartSamples,
                        triggerAt: incident.triggeredAt,
                        series: [
                            .init(name: localized("Ciśnienie oleju"), color: .tougeMint, value: \.oilPressureBar),
                            .init(name: localized("Boost"), color: .tougeCyan, value: \.boostBar)
                        ]
                    )

                    IncidentChartCard(
                        title: "MIESZANKA I OBCIĄŻENIE",
                        subtitle: "AFR oraz pozycja przepustnicy",
                        unit: "",
                        samples: chartSamples,
                        triggerAt: incident.triggeredAt,
                        series: [
                            .init(name: "AFR", color: .white, value: \.afr),
                            .init(name: localized("Przepustnica / 10"), color: .tougeYellow, value: { $0.throttlePercent / 10 })
                        ]
                    )

                    IncidentChartCard(
                        title: "WARUNKI JAZDY",
                        subtitle: "Obroty i prędkość w chwili zdarzenia",
                        unit: "",
                        samples: chartSamples,
                        triggerAt: incident.triggeredAt,
                        series: [
                            .init(name: localized("RPM / 100"), color: .tougeYellow, value: { $0.rpm / 100 }),
                            .init(name: localized("Prędkość"), color: .tougeIce, value: \.speedKPH)
                        ]
                    )

                    if containsLocation {
                        IncidentMapCard(samples: samples, triggerAt: incident.triggeredAt)
                    }

                    IncidentNotesCard(notes: notes)

                    Button {
                        showingShare = true
                    } label: {
                        Label("Wyślij mechanikowi", systemImage: "paperplane.fill")
                            .font(.headline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.tougeCyan)

                    ProductCreditFooter()
                        .padding(.top, 8)
                }
                .frame(maxWidth: 1_100)
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        }
        .navigationTitle(localized("Raport incydentu"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNoteComposer) {
            if let selectedSample {
                TimelineNoteComposer(
                    vehicleID: incident.vehicleID,
                    sessionID: incident.sessionID,
                    incidentID: incident.id,
                    timestamp: selectedSample.timestamp,
                    cloudSync: cloudSync
                )
            }
        }
        .sheet(isPresented: $showingShare) {
            IncidentShareView(incident: incident, account: cloudAccount, cloudSync: cloudSync)
        }
    }
}

struct IncidentListRow: View {
    let incident: DriveIncident
    @ObservedObject var cloudSync: CloudSyncManager

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill((incident.severity == .critical ? Color.tougeRed : .tougeOrange).opacity(0.14))
                Image(systemName: incident.kind.symbol)
                    .font(.title3.weight(.black))
                    .foregroundStyle(incident.severity == .critical ? Color.tougeRed : .tougeOrange)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(incident.kind.title)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.primary)
                Text(incident.triggeredAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(
                    format: localized("%@ %@ · %@ próbek · %.0f Hz"),
                    incident.triggerValue.formatted(.number.precision(.fractionLength(incident.triggerUnit == "bar" ? 2 : 1))),
                    incident.triggerUnit,
                    incident.sampleCount.formatted(),
                    incident.sampleRateHz
                ))
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
            CloudSyncItemBadge(status: cloudSync.incidentStatus(for: incident))
            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .cardSurface(warning: incident.severity == .critical, accent: incident.severity == .critical ? .tougeRed : .tougeOrange)
    }
}

private struct IncidentHeroCard: View {
    let incident: DriveIncident

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: incident.kind.symbol)
                    .font(.title.weight(.black))
                    .foregroundStyle(Color.tougeRed)
                VStack(alignment: .leading, spacing: 4) {
                    Text(incident.severity == .critical ? "INCYDENT KRYTYCZNY" : "OSTRZEŻENIE")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.3)
                        .foregroundStyle(incident.severity == .critical ? Color.tougeRed : .tougeOrange)
                    Text(incident.kind.title)
                        .font(.title2.weight(.black))
                    Text(incident.triggeredAt.formatted(date: .complete, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("TYLKO ODCZYT", systemImage: "lock.shield.fill")
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.7)
                    .foregroundStyle(Color.tougeMint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.tougeMint.opacity(0.1), in: Capsule())
            }

            HStack(spacing: 8) {
                IncidentSummaryValue(title: "WARTOŚĆ", value: incident.triggerValue, unit: incident.triggerUnit, tint: .tougeRed)
                IncidentSummaryValue(title: "PRÓG", value: incident.thresholdValue, unit: incident.triggerUnit, tint: .tougeOrange)
                IncidentSummaryValue(title: "RPM", value: incident.triggerRPM, unit: "rpm", tint: .tougeYellow, decimals: 0)
                IncidentSummaryValue(title: "BOOST", value: incident.triggerBoostBar, unit: "bar", tint: .tougeCyan)
            }

            HStack(spacing: 8) {
                IncidentSummaryValue(title: "CZAS TRWANIA", value: incident.conditionDurationSeconds, unit: "s", tint: .tougeRed)
                IncidentSummaryValue(title: "CIŚNIENIE PALIWA", value: incident.triggerFuelPressureBar, unit: "bar", tint: .tougeMint)
            }

            HStack {
                Label(localized("30 s przed"), systemImage: "backward.end.fill")
                Spacer()
                Label(String(format: localized("%@ próbek"), incident.sampleCount.formatted()), systemImage: "waveform.path.ecg")
                Spacer()
                Label(localized("60 s po"), systemImage: "forward.end.fill")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .cardSurface(warning: incident.severity == .critical, accent: incident.severity == .critical ? .tougeRed : .tougeOrange)
    }
}

private struct IncidentSummaryValue: View {
    let title: String
    let value: Double
    let unit: String
    let tint: Color
    var decimals = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 7, weight: .black))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            Text(value.formatted(.number.precision(.fractionLength(decimals))))
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IncidentMomentCard: View {
    let sample: CapturedTelemetryPoint
    let incident: DriveIncident
    @Binding var selectedIndex: Int
    let sampleCount: Int
    let onAddNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WYBRANY MOMENT")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text(relativeTime(sample.timestamp))
                        .font(.headline.monospacedDigit().weight(.black))
                        .foregroundStyle(Color.tougeCyan)
                }
                Spacer()
                Button(action: onAddNote) {
                    Label("Dodaj notatkę", systemImage: "note.text.badge.plus")
                        .font(.caption.weight(.black))
                }
                .buttonStyle(.bordered)
                .tint(.tougeCyan)
            }

            Slider(
                value: Binding(
                    get: { Double(selectedIndex) },
                    set: { selectedIndex = Int($0.rounded()) }
                ),
                in: 0...Double(max(1, sampleCount - 1)),
                step: 1
            )
            .tint(.tougeCyan)

            HStack(spacing: 7) {
                IncidentMomentValue(title: "RPM", value: sample.rpm, unit: "rpm", tint: .tougeYellow, decimals: 0)
                IncidentMomentValue(title: "BOOST", value: sample.boostBar, unit: "bar", tint: .tougeCyan)
                IncidentMomentValue(title: "OIL P", value: sample.oilPressureBar, unit: "bar", tint: .tougeMint)
                IncidentMomentValue(title: "OIL T", value: sample.oilTemperatureCelsius, unit: "°C", tint: .tougeOrange, decimals: 0)
                IncidentMomentValue(title: "COOLANT", value: sample.coolantCelsius, unit: "°C", tint: .tougeIce, decimals: 0)
                IncidentMomentValue(title: "AFR", value: sample.afr, unit: "", tint: .white, decimals: 1)
            }
        }
        .padding(15)
        .cardSurface(accent: .tougeCyan)
    }

    private func relativeTime(_ timestamp: Date) -> String {
        let interval = timestamp.timeIntervalSince(incident.triggeredAt)
        return String(format: "%@%.2f s", interval >= 0 ? "+" : "−", abs(interval))
    }
}

private struct IncidentMomentValue: View {
    let title: String
    let value: Double
    let unit: String
    let tint: Color
    var decimals = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value.formatted(.number.precision(.fractionLength(decimals))))
                .font(.system(size: 14, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(unit)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IncidentChartSeries {
    let name: String
    let color: Color
    let value: (CapturedTelemetryPoint) -> Double
}

private struct IncidentChartCard: View {
    let title: String
    let subtitle: String
    let unit: String
    let samples: [CapturedTelemetryPoint]
    let triggerAt: Date
    let series: [IncidentChartSeries]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized(title))
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                    Text(localized(subtitle))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 9) {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, item in
                        Label {
                            Text(item.name).font(.caption2.weight(.bold))
                        } icon: {
                            Circle().fill(item.color).frame(width: 6, height: 6)
                        }
                    }
                }
            }

            Chart {
                ForEach(Array(series.enumerated()), id: \.offset) { _, item in
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value(item.name, item.value(sample))
                        )
                        .foregroundStyle(item.color)
                        .interpolationMethod(.linear)
                        .lineStyle(.init(lineWidth: 2))
                    }
                }
                RuleMark(x: .value(localized("Incydent"), triggerAt))
                    .foregroundStyle(Color.tougeRed)
                    .lineStyle(.init(lineWidth: 2, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("ALERT")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color.tougeRed)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                    AxisValueLabel(format: .dateTime.minute().second())
                }
            }
            .chartYAxisLabel(unit)
            .frame(height: 220)
            .allowsHitTesting(false)
        }
        .padding(16)
        .cardSurface(accent: series.first?.color ?? .tougeCyan)
    }
}

private struct IncidentMapCard: View {
    @State private var camera: MapCameraPosition = .automatic
    private let coordinates: [CLLocationCoordinate2D]
    private let triggerCoordinate: CLLocationCoordinate2D?

    init(samples: [CapturedTelemetryPoint], triggerAt: Date) {
        coordinates = samples.downsampled(maxPoints: 600).compactMap {
            guard let latitude = $0.latitude, let longitude = $0.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        let located = samples.filter { $0.latitude != nil && $0.longitude != nil }
        if let sample = located.min(by: {
            abs($0.timestamp.timeIntervalSince(triggerAt)) < abs($1.timestamp.timeIntervalSince(triggerAt))
        }), let latitude = sample.latitude, let longitude = sample.longitude {
            triggerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            triggerCoordinate = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIEJSCE ZDARZENIA")
                .font(.system(size: 11, weight: .black))
                .tracking(1.1)
            Map(position: $camera) {
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.tougeCyan, style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let triggerCoordinate {
                    Annotation(localized("Incydent"), coordinate: triggerCoordinate) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.8)).frame(width: 34, height: 34)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.tougeRed)
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .allowsHitTesting(false)
        }
        .padding(16)
        .cardSurface(accent: .tougeIce)
    }
}

struct IncidentNotesCard: View {
    let notes: [TimelineAnnotation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NOTATKI NA OSI CZASU")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.1)
                Spacer()
                Text(notes.count.formatted())
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(Color.tougeCyan)
            }
            if notes.isEmpty {
                Text("Wybierz moment suwakiem i dodaj notatkę. Zapisze się razem z dokładnym czasem i warunkami pracy silnika.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes) { note in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "note.text")
                            .foregroundStyle(Color.tougeCyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(note.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospacedDigit().weight(.black))
                                .foregroundStyle(Color.tougeCyan)
                            Text(note.body)
                                .font(.subheadline)
                        }
                        Spacer()
                        Image(systemName: note.syncState == .synced ? "icloud.fill" : "icloud.and.arrow.up")
                            .font(.caption)
                            .foregroundStyle(note.syncState == .synced ? Color.tougeMint : .tougeOrange)
                    }
                    if note.id != notes.last?.id { Divider().opacity(0.3) }
                }
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeCyan)
    }
}

struct TimelineNoteComposer: View {
    let vehicleID: UUID
    let sessionID: UUID
    let incidentID: UUID?
    let timestamp: Date
    @ObservedObject var cloudSync: CloudSyncManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var bodyText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Moment") {
                    LabeledContent("Czas", value: timestamp.formatted(date: .abbreviated, time: .standard))
                }
                Section("Notatka") {
                    TextField("Co warto sprawdzić lub zapamiętać?", text: $bodyText, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("Nowa notatka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        modelContext.insert(TimelineAnnotation(
                            vehicleID: vehicleID,
                            sessionID: sessionID,
                            incidentID: incidentID,
                            timestamp: timestamp,
                            body: trimmed
                        ))
                        try? modelContext.save()
                        cloudSync.noteLocalAnnotationRecorded()
                        dismiss()
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct IncidentShareView: View {
    let incident: DriveIncident
    @ObservedObject var account: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var unit = "DAYS"
    @State private var amount = 7
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Ważność linku") {
                    Picker("Okres", selection: $unit) {
                        Text("Godziny").tag("HOURS")
                        Text("Dni").tag("DAYS")
                        Text("Bezterminowo").tag("FOREVER")
                    }
                    if unit != "FOREVER" {
                        Stepper(value: $amount, in: 1...(unit == "HOURS" ? 168 : 365)) {
                            Text("\(amount) \(unit == "HOURS" ? localized("godz.") : localized("dni"))")
                        }
                    }
                }
                Section {
                    Text("Link otwiera tylko ten raport. Nie wymaga konta i nie daje dostępu do auta ani pozostałych przejazdów.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.tougeRed) }
                }
                if let shareURL {
                    Section("Gotowy link") {
                        ShareLink(item: shareURL) {
                            Label("Wyślij mechanikowi", systemImage: "paperplane.fill")
                        }
                        Text(shareURL.absoluteString)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Udostępnij raport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
                if shareURL == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Utwórz link") { Task { await createLink() } }
                            .disabled(isCreating || !account.isAuthenticated)
                    }
                }
            }
            .overlay {
                if isCreating { ProgressView().controlSize(.large) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func createLink() async {
        await cloudSync.syncNow()
        guard let vehicleID = cloudSync.remoteVehicleID(for: incident.vehicleID) else {
            errorMessage = localized("Najpierw zsynchronizuj auto z kontem.")
            return
        }
        isCreating = true
        defer { isCreating = false }
        do {
            let response: CloudIncidentShare = try await account.send(
                endpoint: "/api/v1/vehicles/\(vehicleID.uuidString)/incidents/\(incident.id.uuidString)/shares",
                body: CloudIncidentShareRequest(unit: unit, amount: unit == "FOREVER" ? nil : amount)
            )
            let base = account.webAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            shareURL = URL(string: "\(base)/shared/incidents/\(response.token)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

private extension Array where Element == CapturedTelemetryPoint {
    func downsampled(maxPoints: Int) -> [CapturedTelemetryPoint] {
        guard count > maxPoints, maxPoints > 2 else { return self }
        let step = Double(count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { self[Swift.min(count - 1, Int((Double($0) * step).rounded()))] }
    }
}
