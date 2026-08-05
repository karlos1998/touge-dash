import Charts
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DriveSession.startedAt, order: .reverse) private var sessions: [DriveSession]
    @Query(sort: \DriveIncident.triggeredAt, order: .reverse) private var incidents: [DriveIncident]
    @Query(sort: \DriveVideoRecording.startedAt, order: .reverse) private var videos: [DriveVideoRecording]
    @Query(sort: \AccelerationAttempt.startedAt, order: .reverse) private var accelerationAttempts: [AccelerationAttempt]
    @ObservedObject var locationTracker: LocationTrackingService
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @ObservedObject var videoRecorder: DriveVideoRecorder
    @ObservedObject var videoOverlays: VideoOverlayTemplateStore
    let onShowDashboard: (() -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        CloudSyncCard(account: cloudAccount, sync: cloudSync)
                        LocationRecordingCard(locationTracker: locationTracker)
                        DriveVideoRecordingCard(recorder: videoRecorder)

                        if !incidents.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("RAPORTY INCYDENTÓW")
                                        .font(.system(size: 13, weight: .black))
                                        .tracking(1.4)
                                    Text("30 sekund przed · 60 sekund po zdarzeniu")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(incidents.count.formatted())
                                    .font(.headline.monospacedDigit().weight(.black))
                                    .foregroundStyle(Color.tougeRed)
                            }
                            .padding(.top, 4)

                            ForEach(Array(incidents.prefix(5))) { incident in
                                NavigationLink {
                                    IncidentReportView(
                                        incident: incident,
                                        cloudAccount: cloudAccount,
                                        cloudSync: cloudSync
                                    )
                                } label: {
                                    IncidentListRow(incident: incident, cloudSync: cloudSync)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if sessions.isEmpty {
                            HistoryEmptyState()
                        } else {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("PRZEJAZDY")
                                        .font(.system(size: 13, weight: .black))
                                        .tracking(1.4)
                                    Text("Lokalne archiwum telemetrii")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(sessions.count)")
                                    .font(.headline.monospacedDigit().weight(.black))
                                    .foregroundStyle(Color.tougeCyan)
                            }
                            .padding(.top, 4)

                            ForEach(sessions) { session in
                                NavigationLink {
                                    DriveSessionDetailView(
                                        session: session,
                                        cloudAccount: cloudAccount,
                                        cloudSync: cloudSync,
                                        videoOverlays: videoOverlays
                                    )
                                } label: {
                                    DriveSessionRow(
                                        session: session,
                                        recordings: videos.filter { $0.sessionID == session.id },
                                        cloudSync: cloudSync
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        delete(session)
                                    } label: {
                                        Label("Usuń przejazd", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        ProductCreditFooter()
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: 1_000)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Historia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onShowDashboard {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onShowDashboard) {
                            Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                        }
                    }
                }
            }
        }
    }

    private func delete(_ session: DriveSession) {
        for video in videos where video.sessionID == session.id {
            try? DriveVideoFileStore.delete(video)
            modelContext.delete(video)
        }
        for incident in incidents where incident.sessionID == session.id {
            modelContext.delete(incident)
        }
        for attempt in accelerationAttempts where attempt.sessionID == session.id {
            modelContext.delete(attempt)
        }
        let sessionID = session.id
        let annotations = (try? modelContext.fetch(FetchDescriptor<TimelineAnnotation>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))) ?? []
        annotations.forEach(modelContext.delete)
        modelContext.delete(session)
        try? modelContext.save()
    }
}

private struct LocationRecordingCard: View {
    @ObservedObject var locationTracker: LocationTrackingService

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { locationTracker.isEnabled },
            set: { locationTracker.setEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    CutCornerPanel(cut: 9)
                        .fill(Color.tougeBlue.opacity(0.14))
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.tougeIce)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("ZAPIS TRASY")
                        .font(.system(size: 12, weight: .black))
                        .tracking(1)
                    Text(localized(locationTracker.isTracking ? "GPS aktywny · zapis działa w tle" : locationTracker.authorizationLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .tint(.tougeCyan)
            }

            Text("Po włączeniu każda próbka przejazdu może zawierać pozycję. Dane są przechowywane lokalnie, a przy aktywnym koncie także synchronizowane z Touge Dash Cloud.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let error = locationTracker.lastError {
                Text(error)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.tougeOrange)
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeIce)
    }
}

private struct HistoryEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.tougeCyan)
            Text("Pierwszy wykres powstanie sam")
                .font(.headline.weight(.black))
            Text("Touge Dash rozpocznie przejazd po odebraniu danych z EMU i zapisze 10 próbek na sekundę.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 24)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct DriveSessionRow: View {
    let session: DriveSession
    let recordings: [DriveVideoRecording]
    @ObservedObject var cloudSync: CloudSyncManager

    private var videoBytes: Int64 { recordings.reduce(0) { $0 + $1.fileSizeBytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.startedAt.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                    ))
                        .font(.headline.weight(.black))
                    Text(String(
                        format: localized("%@ · %@ próbek"),
                        formatDuration(session.duration),
                        session.sampleCount.formatted()
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.containsLocation {
                    Label("TRASA", systemImage: "location.fill")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.7)
                        .foregroundStyle(Color.tougeIce)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.tougeBlue.opacity(0.12), in: Capsule())
                }
                CloudSyncItemBadge(status: cloudSync.sessionStatus(for: session))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                SessionStat(title: "MAX BOOST", value: session.maxBoostBar.formatted(.number.precision(.fractionLength(2))), unit: "bar", tint: .tougeCyan)
                SessionStat(title: "MAX SPEED", value: Int(session.maxSpeedKPH).formatted(), unit: "km/h", tint: .tougeIce)
                SessionStat(title: "OIL MAX", value: Int(session.maxOilTemperatureCelsius).formatted(), unit: "°C", tint: .tougeOrange)
                SessionStat(title: "COOLANT", value: Int(session.maxCoolantCelsius).formatted(), unit: "°C", tint: .tougeMint)
            }

            if session.distanceMeters > 0 {
                Label(
                    String(
                        format: localized("%@ km zapisanej trasy"),
                        (session.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1)))
                    ),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            }

            if !recordings.isEmpty {
                Label(
                    String(
                        format: localized("Nagrania: %@ · %@ lokalnie"),
                        recordings.count.formatted(),
                        DriveVideoFileStore.formattedSize(videoBytes)
                    ),
                    systemImage: "video.fill"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.tougeRed)
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct SessionStat: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 7, weight: .black))
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(unit)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DriveSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let session: DriveSession
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @ObservedObject var videoOverlays: VideoOverlayTemplateStore
    @Query(sort: \DriveIncident.triggeredAt) private var allIncidents: [DriveIncident]
    @Query(sort: \TimelineAnnotation.timestamp) private var allAnnotations: [TimelineAnnotation]
    @Query(sort: \DriveVideoRecording.startedAt) private var allVideos: [DriveVideoRecording]
    @Query(sort: \AccelerationAttempt.startedAt) private var allAccelerationAttempts: [AccelerationAttempt]
    @State private var selectedTime: Date?
    @State private var cachedSamples: [TelemetryHistorySample] = []
    @State private var chartSamples: [TelemetryHistorySample] = []
    @State private var locatedSamples: [TelemetryHistorySample] = []
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeHasMovement = false
    @State private var showingNoteComposer = false
    private let chartColumns = [GridItem(.adaptive(minimum: 460), spacing: 14)]

    private var selectedSample: TelemetryHistorySample? {
        guard let selectedTime else { return cachedSamples.last }
        return cachedSamples.nearest(to: selectedTime)
    }

    private var incidents: [DriveIncident] {
        allIncidents.filter { $0.sessionID == session.id }
    }

    private var notes: [TimelineAnnotation] {
        allAnnotations.filter { $0.sessionID == session.id && $0.incidentID == nil }
    }

    private var recordings: [DriveVideoRecording] {
        allVideos.filter { $0.sessionID == session.id }
    }

    private var accelerationAttempts: [AccelerationAttempt] {
        allAccelerationAttempts.filter { $0.sessionID == session.id }
    }

    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let selectedTime,
              let sample = locatedSamples.nearest(to: selectedTime),
              let latitude = sample.latitude,
              let longitude = sample.longitude else { return routeCoordinates.last }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        ZStack {
            DashboardBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    SessionDetailHeader(session: session)

                    CloudSyncItemCard(
                        itemName: "PRZEJAZD",
                        sampleCount: session.sampleCount,
                        status: cloudSync.sessionStatus(for: session),
                        onRetry: { Task { await cloudSync.retrySynchronization() } }
                    )

                    DriveVideoHistorySection(
                        session: session,
                        recordings: recordings,
                        samples: cachedSamples,
                        selectedTime: $selectedTime,
                        overlayStore: videoOverlays,
                        onDelete: deleteVideo
                    )

                    if let selectedSample {
                        SelectedTelemetryStrip(sample: selectedSample, startedAt: session.startedAt)

                        Button {
                            showingNoteComposer = true
                        } label: {
                            Label("Dodaj notatkę do wybranego momentu", systemImage: "note.text.badge.plus")
                                .font(.subheadline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.bordered)
                        .tint(.tougeCyan)
                    }

                    if !incidents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INCYDENTY W TYM PRZEJEŹDZIE")
                                .font(.system(size: 11, weight: .black))
                                .tracking(1.1)
                            ForEach(incidents) { incident in
                                NavigationLink {
                                    IncidentReportView(
                                        incident: incident,
                                        cloudAccount: cloudAccount,
                                        cloudSync: cloudSync
                                    )
                                } label: {
                                    IncidentListRow(incident: incident, cloudSync: cloudSync)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !accelerationAttempts.isEmpty {
                        AccelerationAttemptsCard(attempts: accelerationAttempts, selectedTime: $selectedTime)
                    }

                    LazyVGrid(columns: chartColumns, spacing: 14) {
                        HistoryChartCard(
                            title: "TEMPERATURY",
                            subtitle: "Olej i płyn chłodniczy",
                            unit: "°C",
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [
                                HistoryChartSeries(name: "Olej", color: .tougeOrange, value: { $0.oilTemperatureCelsius }),
                                HistoryChartSeries(name: "Płyn", color: .tougeIce, value: { $0.coolantCelsius })
                            ],
                            selectedTime: $selectedTime
                        )

                        HistoryChartCard(
                            title: "CIŚNIENIA",
                            subtitle: "Boost i ciśnienie oleju",
                            unit: "bar",
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [
                                HistoryChartSeries(name: "Boost", color: .tougeCyan, value: { $0.boostBar }),
                                HistoryChartSeries(name: "Olej", color: .tougeMint, value: { $0.oilPressureBar })
                            ],
                            selectedTime: $selectedTime
                        )

                        HistoryChartCard(
                            title: "PRĘDKOŚĆ",
                            subtitle: "Prędkość pojazdu",
                            unit: "km/h",
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [HistoryChartSeries(name: "Prędkość", color: .tougeIce, value: { $0.speedKPH })],
                            selectedTime: $selectedTime
                        )

                        HistoryChartCard(
                            title: "OBROTY SILNIKA",
                            subtitle: "RPM w czasie",
                            unit: "rpm",
                            samples: chartSamples,
                            attempts: accelerationAttempts,
                            series: [HistoryChartSeries(name: "RPM", color: .tougeYellow, value: { $0.rpm })],
                            selectedTime: $selectedTime
                        )
                    }

                    if session.containsLocation {
                        SessionRouteMap(
                            coordinates: routeCoordinates,
                            selectedCoordinate: selectedCoordinate,
                            hasMovement: routeHasMovement
                        )
                    }

                    IncidentNotesCard(notes: notes)

                    ProductCreditFooter()
                        .padding(.top, 8)
                }
                .frame(maxWidth: 1_200)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle(session.startedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
        ))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let sessionID = session.id
            let descriptor = FetchDescriptor<TelemetryHistorySample>(
                predicate: #Predicate { sample in
                    sample.session?.id == sessionID && sample.chartEligible == true
                },
                sortBy: [SortDescriptor(\.timestamp)]
            )
            let previewSamples = (try? modelContext.fetch(descriptor)) ?? []
            // Records created by versions predating the preview flag use the
            // old relationship fallback once. New 10 Hz drives stay lightweight.
            let sorted = previewSamples.isEmpty
                ? session.samples.sorted { $0.timestamp < $1.timestamp }.downsampled(maxPoints: 7_200)
                : previewSamples.downsampled(maxPoints: 7_200)
            cachedSamples = sorted
            chartSamples = sorted.downsampled(maxPoints: 300)
            locatedSamples = sorted.filter { $0.latitude != nil && $0.longitude != nil }
            routeCoordinates = locatedSamples.downsampled(maxPoints: 2_000).compactMap { sample in
                guard let latitude = sample.latitude, let longitude = sample.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            routeHasMovement = Set(routeCoordinates.map {
                "\($0.latitude.formatted(.number.precision(.fractionLength(5)))):\($0.longitude.formatted(.number.precision(.fractionLength(5))))"
            }).count > 1
            if selectedTime == nil {
                selectedTime = sorted.last?.timestamp
            }
        }
        .sheet(isPresented: $showingNoteComposer) {
            if let selectedSample {
                TimelineNoteComposer(
                    vehicleID: session.vehicleID,
                    sessionID: session.id,
                    incidentID: nil,
                    timestamp: selectedSample.timestamp,
                    cloudSync: cloudSync
                )
            }
        }
    }

    private func deleteVideo(_ recording: DriveVideoRecording) {
        try? DriveVideoFileStore.delete(recording)
        modelContext.delete(recording)
        try? modelContext.save()
    }
}

private struct SessionDetailHeader: View {
    let session: DriveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DRIVE SESSION")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(Color.tougeCyan)
                    Text(session.startedAt.formatted(
                        Date.FormatStyle(date: .complete, time: .shortened)
                    ))
                        .font(.title3.weight(.black))
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.tougeCyan)
            }

            HStack(spacing: 10) {
                HeaderSummary(title: "CZAS", value: formatDuration(session.duration), tint: .white)
                HeaderSummary(title: "DYSTANS", value: session.distanceMeters > 0 ? (session.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1))) + " km" : "—", tint: .tougeIce)
                HeaderSummary(title: "MAX BOOST", value: session.maxBoostBar.formatted(.number.precision(.fractionLength(2))) + " bar", tint: .tougeCyan)
                HeaderSummary(title: "MAX RPM", value: Int(session.maxRPM).formatted(), tint: .tougeYellow)
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct HeaderSummary: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 7, weight: .black))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SelectedTelemetryStrip: View {
    let sample: TelemetryHistorySample
    let startedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WYBRANY MOMENT")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("+" + formatDuration(sample.timestamp.timeIntervalSince(startedAt)))
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(Color.tougeCyan)
            }

            HStack(spacing: 7) {
                MomentValue(title: "SPEED", value: Int(sample.speedKPH).formatted(), unit: "km/h", tint: .tougeIce)
                MomentValue(title: "RPM", value: Int(sample.rpm).formatted(), unit: "rpm", tint: .tougeYellow)
                MomentValue(title: "BOOST", value: sample.boostBar.formatted(.number.precision(.fractionLength(2))), unit: "bar", tint: .tougeCyan)
                MomentValue(title: "OIL", value: Int(sample.oilTemperatureCelsius).formatted(), unit: "°C", tint: .tougeOrange)
                MomentValue(title: "COOLANT", value: Int(sample.coolantCelsius).formatted(), unit: "°C", tint: .tougeMint)
                MomentValue(title: "AFR", value: sample.afr.formatted(.number.precision(.fractionLength(1))), unit: "", tint: .white)
            }
        }
        .padding(14)
        .cardSurface(accent: .tougeCyan)
    }
}

private struct MomentValue: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 7, weight: .black))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(unit)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryChartSeries: Identifiable {
    let name: String
    let color: Color
    let value: (TelemetryHistorySample) -> Double

    var id: String { name }
}

private struct HistoryChartCard: View {
    let title: String
    let subtitle: String
    let unit: String
    let samples: [TelemetryHistorySample]
    let attempts: [AccelerationAttempt]
    let series: [HistoryChartSeries]
    @Binding var selectedTime: Date?

    private var yDomain: ClosedRange<Double> {
        let values = series.flatMap { item in samples.map(item.value) }.filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let span = max(0.1, maximum - minimum)
        let padding = max(unit == "°C" ? 3 : 0.1, span * 0.12)
        return (minimum - padding)...(maximum + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized(title))
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                    Text(localized(subtitle))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(series) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 6, height: 6)
                            Text(localized(item.name))
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Chart {
                ForEach(attempts) { attempt in
                    RectangleMark(
                        xStart: .value(localized("Początek pomiaru"), attempt.startedAt),
                        xEnd: .value(localized("Koniec pomiaru"), attempt.endedAt),
                        yStart: .value(localized("Minimum"), yDomain.lowerBound),
                        yEnd: .value(localized("Maksimum"), yDomain.upperBound)
                    )
                    .foregroundStyle(accelerationColor(attempt.type).opacity(0.12))
                }
                ForEach(series) { item in
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value(localized("Czas"), sample.timestamp),
                            y: .value(item.name, item.value(sample)),
                            series: .value(localized("Seria"), localized(item.name))
                        )
                        .foregroundStyle(item.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                    }
                }

                if let selectedTime {
                    RuleMark(x: .value(localized("Wybrany czas"), selectedTime))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(preset: .inset, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.055))
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.055))
                    AxisValueLabel().foregroundStyle(Color.secondary)
                }
            }
            .chartYAxisLabel(unit, position: .top, alignment: .leading)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                                    selectTimestamp(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                        .simultaneousGesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    selectTimestamp(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                }
            }
            .frame(height: 210)
        }
        .padding(16)
        .cardSurface(accent: series.first?.color ?? .tougeCyan)
    }

    private func selectTimestamp(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let xPosition = location.x - frame.origin.x
        guard xPosition >= 0,
              xPosition <= frame.width,
              let timestamp: Date = proxy.value(atX: xPosition) else { return }
        selectedTime = timestamp
    }
}

private struct AccelerationAttemptsCard: View {
    let attempts: [AccelerationAttempt]
    @Binding var selectedTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localized("POMIARY PRZYSPIESZENIA"), systemImage: "stopwatch.fill")
                    .font(.system(size: 11, weight: .black)).tracking(1)
                Spacer()
                Text(localized("Dotknij, aby przejść na oś czasu"))
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            ForEach(AccelerationType.allCases) { type in
                let values = attempts.filter { $0.type == type }
                if let best = values.min(by: { $0.durationMillis < $1.durationMillis }) {
                    attemptRow(type: type, attempts: values, best: best)
                }
            }
        }
        .padding(16)
        .cardSurface(accent: .tougeCyan)
    }

    private func attemptRow(
        type: AccelerationType,
        attempts: [AccelerationAttempt],
        best: AccelerationAttempt
    ) -> some View {
        let color = accelerationColor(type)
        let duration = (Double(best.durationMillis) / 1_000)
            .formatted(.number.precision(.fractionLength(2))) + " s"
        let orderedAttempts = attempts.sorted { $0.startedAt < $1.startedAt }

        return VStack(alignment: .leading, spacing: 8) {
            Button { selectedTime = best.startedAt } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(type.label) km/h")
                            .font(.headline.weight(.black))
                            .foregroundStyle(color)
                        Text("\(attempts.count) \(localized("prób")) · \(localized("najlepszy czas"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(duration)
                        .font(.title3.monospacedDigit().weight(.black))
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(orderedAttempts.enumerated()), id: \.element.id) { index, attempt in
                        Button { selectedTime = attempt.startedAt } label: {
                            Text("#\(index + 1)  \((Double(attempt.durationMillis) / 1_000).formatted(.number.precision(.fractionLength(2)))) s")
                                .font(.caption2.monospacedDigit().weight(.black))
                                .foregroundStyle(attempt.id == best.id ? Color.black : Color.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(attempt.id == best.id ? color : color.opacity(0.13), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(color.opacity(0.08), in: CutCornerPanel(cut: 8))
    }
}

private func accelerationColor(_ type: AccelerationType) -> Color {
    switch type {
    case .zeroTo100: .tougeMint
    case .hundredTo200: .tougeCyan
    case .twoHundredTo250: .tougeOrange
    }
}

private struct SessionRouteMap: View {
    let coordinates: [CLLocationCoordinate2D]
    let selectedCoordinate: CLLocationCoordinate2D?
    let hasMovement: Bool
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRASA")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                    Text(localized(hasMovement ? "Pozycja jest zsynchronizowana z kursorem wykresów" : "Zapisano pozycję postoju · trasa pojawi się po ruszeniu"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("\(coordinates.count)", systemImage: "map.fill")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color.tougeIce)
            }

            Map(position: $cameraPosition) {
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Color.tougeCyan, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let selectedCoordinate {
                    Annotation("Wybrany moment", coordinate: selectedCoordinate) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.72)).frame(width: 28, height: 28)
                            Circle().fill(Color.tougeRed).frame(width: 12, height: 12)
                        }
                        .shadow(color: Color.tougeRed.opacity(0.7), radius: 6)
                    }
                }
            }
            .mapStyle(.standard)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onAppear(perform: updateCamera)
            .onChange(of: coordinates.count) { _, _ in updateCamera() }
        }
        .padding(16)
        .cardSurface(accent: .tougeIce)
    }

    private func updateCamera() {
        guard let first = coordinates.first else { return }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minimumLatitude = latitudes.min(), let maximumLatitude = latitudes.max(),
              let minimumLongitude = longitudes.min(), let maximumLongitude = longitudes.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
        let latitudeDelta = max(0.004, (maximumLatitude - minimumLatitude) * 1.35)
        let longitudeDelta = max(0.004, (maximumLongitude - minimumLongitude) * 1.35)
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinates.count == 1 ? first : center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        ))
    }
}

private extension Array where Element == TelemetryHistorySample {
    func downsampled(maxPoints: Int) -> [TelemetryHistorySample] {
        guard count > maxPoints, maxPoints > 2 else { return self }
        let stride = Double(count - 1) / Double(maxPoints - 1)
        var result: [TelemetryHistorySample] = []
        result.reserveCapacity(maxPoints)
        for index in 0..<maxPoints {
            result.append(self[Swift.min(count - 1, Int((Double(index) * stride).rounded()))])
        }
        return result
    }

    func nearest(to timestamp: Date) -> TelemetryHistorySample? {
        guard !isEmpty else { return nil }
        var lower = 0
        var upper = count
        while lower < upper {
            let middle = (lower + upper) / 2
            if self[middle].timestamp < timestamp {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower == 0 { return self[0] }
        if lower == count { return self[count - 1] }
        let before = self[lower - 1]
        let after = self[lower]
        return abs(before.timestamp.timeIntervalSince(timestamp)) <= abs(after.timestamp.timeIntervalSince(timestamp))
            ? before
            : after
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration.rounded()))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
