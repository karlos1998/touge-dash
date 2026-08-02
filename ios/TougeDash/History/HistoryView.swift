import Charts
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DriveSession.startedAt, order: .reverse) private var sessions: [DriveSession]
    @ObservedObject var locationTracker: LocationTrackingService
    let onShowDashboard: (() -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        LocationRecordingCard(locationTracker: locationTracker)

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
                                    DriveSessionDetailView(session: session)
                                } label: {
                                    DriveSessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        modelContext.delete(session)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Usuń przejazd", systemImage: "trash")
                                    }
                                }
                            }
                        }
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
                    Text(locationTracker.isTracking ? "GPS aktywny · zapis działa w tle" : locationTracker.authorizationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .tint(.tougeCyan)
            }

            Text("Po włączeniu każda próbka przejazdu może zawierać pozycję. Dane zostają wyłącznie na tym urządzeniu.")
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
            Text("Touge Dash rozpocznie przejazd po odebraniu danych z EMU i zapisze jedną próbkę na sekundę.")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.startedAt.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                            .locale(Locale(identifier: "pl_PL"))
                    ))
                        .font(.headline.weight(.black))
                    Text("\(formatDuration(session.duration)) · \(session.sampleCount.formatted()) próbek")
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
                    (session.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(1))) + " km zapisanej trasy",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
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
            Text(title)
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
    let session: DriveSession
    @State private var selectedTime: Date?
    private let chartColumns = [GridItem(.adaptive(minimum: 460), spacing: 14)]

    private var samples: [TelemetryHistorySample] {
        session.samples.sorted { $0.timestamp < $1.timestamp }
    }

    private var chartSamples: [TelemetryHistorySample] {
        samples.downsampled(maxPoints: 900)
    }

    private var selectedSample: TelemetryHistorySample? {
        guard let selectedTime else { return samples.last }
        return samples.min {
            abs($0.timestamp.timeIntervalSince(selectedTime)) < abs($1.timestamp.timeIntervalSince(selectedTime))
        }
    }

    var body: some View {
        ZStack {
            DashboardBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    SessionDetailHeader(session: session)

                    if let selectedSample {
                        SelectedTelemetryStrip(sample: selectedSample, startedAt: session.startedAt)
                    }

                    LazyVGrid(columns: chartColumns, spacing: 14) {
                        HistoryChartCard(
                            title: "TEMPERATURY",
                            subtitle: "Olej i płyn chłodniczy",
                            unit: "°C",
                            samples: chartSamples,
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
                            series: [HistoryChartSeries(name: "Prędkość", color: .tougeIce, value: { $0.speedKPH })],
                            selectedTime: $selectedTime
                        )

                        HistoryChartCard(
                            title: "OBROTY SILNIKA",
                            subtitle: "RPM w czasie",
                            unit: "rpm",
                            samples: chartSamples,
                            series: [HistoryChartSeries(name: "RPM", color: .tougeYellow, value: { $0.rpm })],
                            selectedTime: $selectedTime
                        )
                    }

                    if session.containsLocation {
                        SessionRouteMap(samples: samples, selectedSample: selectedSample)
                    }
                }
                .frame(maxWidth: 1_200)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle(session.startedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(Locale(identifier: "pl_PL"))
        ))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedTime = samples.last?.timestamp
        }
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
                            .locale(Locale(identifier: "pl_PL"))
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
            Text(title)
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    MomentValue(title: "SPEED", value: Int(sample.speedKPH).formatted(), unit: "km/h", tint: .tougeIce)
                    MomentValue(title: "RPM", value: Int(sample.rpm).formatted(), unit: "rpm", tint: .tougeYellow)
                    MomentValue(title: "BOOST", value: sample.boostBar.formatted(.number.precision(.fractionLength(2))), unit: "bar", tint: .tougeCyan)
                    MomentValue(title: "OIL", value: Int(sample.oilTemperatureCelsius).formatted(), unit: "°C", tint: .tougeOrange)
                    MomentValue(title: "COOLANT", value: Int(sample.coolantCelsius).formatted(), unit: "°C", tint: .tougeMint)
                    MomentValue(title: "AFR", value: sample.afr.formatted(.number.precision(.fractionLength(1))), unit: "", tint: .white)
                }
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
            Text(title)
                .font(.system(size: 7, weight: .black))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(tint)
                Text(unit)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 82, alignment: .leading)
    }
}

private struct HistoryChartSeries: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let value: (TelemetryHistorySample) -> Double
}

private struct HistoryChartCard: View {
    let title: String
    let subtitle: String
    let unit: String
    let samples: [TelemetryHistorySample]
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
                    Text(title)
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(series) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 6, height: 6)
                            Text(item.name)
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Chart {
                ForEach(series) { item in
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Czas", sample.timestamp),
                            y: .value(item.name, item.value(sample)),
                            series: .value("Seria", item.name)
                        )
                        .foregroundStyle(item.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                    }
                }

                if let selectedTime {
                    RuleMark(x: .value("Wybrany czas", selectedTime))
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
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = geometry[plotFrame]
                                    let xPosition = value.location.x - frame.origin.x
                                    guard xPosition >= 0,
                                          xPosition <= frame.width,
                                          let timestamp: Date = proxy.value(atX: xPosition) else { return }
                                    selectedTime = timestamp
                                }
                        )
                }
            }
            .frame(height: 210)
        }
        .padding(16)
        .cardSurface(accent: series.first?.color ?? .tougeCyan)
    }
}

private struct SessionRouteMap: View {
    let samples: [TelemetryHistorySample]
    let selectedSample: TelemetryHistorySample?

    private var coordinates: [CLLocationCoordinate2D] {
        samples.compactMap { sample in
            guard let latitude = sample.latitude, let longitude = sample.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let latitude = selectedSample?.latitude,
              let longitude = selectedSample?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRASA")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                    Text("Pozycja jest zsynchronizowana z kursorem wykresów")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "map.fill")
                    .foregroundStyle(Color.tougeIce)
            }

            Map {
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
        }
        .padding(16)
        .cardSurface(accent: .tougeIce)
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
