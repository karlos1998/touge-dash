import SwiftUI

struct WatchDashboardView: View {
    @ObservedObject var controller: WatchTelemetryController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            dashboard(snapshot: controller.snapshot)
        }
    }

    private func dashboard(snapshot: WatchTelemetryPayload) -> some View {
        VStack(spacing: 7) {
            header(snapshot: snapshot)

            HStack(spacing: 0) {
                WatchMetric(
                    title: "BOOST",
                    value: snapshot.boostBar.formatted(.number.precision(.fractionLength(2))),
                    unit: "bar",
                    tint: .tougeCyan
                )
                WatchDivider(height: 48)
                WatchMetric(
                    title: "AFR",
                    value: snapshot.afr.formatted(.number.precision(.fractionLength(1))),
                    tint: .tougeMint
                )
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            oilPanel(snapshot: snapshot)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            coolantPanel(snapshot: snapshot)

            if snapshot.hasCriticalWarning {
                Label(localized(snapshot.engineAlerts.isEmpty ? (snapshot.hasTemperatureWarning ? "TEMPERATURE ALERT" : "ENGINE WARNING") : "CRITICAL ENGINE ALERT"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.tougeOrange)
                    .symbolEffect(.pulse, options: .repeating, isActive: snapshot.hasTemperatureWarning)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: snapshot.hasTemperatureWarning
                    ? [Color.tougeOrange.opacity(0.55), Color.tougeAlertNavy, Color.black]
                    : [Color.tougeNavy, Color.black],
                center: .topLeading,
                startRadius: 0,
                endRadius: 210
            )
            .ignoresSafeArea()
        )
    }

    private func header(snapshot: WatchTelemetryPayload) -> some View {
        HStack(spacing: 5) {
            Image(systemName: snapshot.hasTemperatureWarning ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.67percent")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(snapshot.hasTemperatureWarning ? Color.tougeOrange : Color.tougeCyan)
                .symbolEffect(.pulse, options: .repeating, isActive: snapshot.hasTemperatureWarning)
            Text(localized(snapshot.hasTemperatureWarning ? "TEMP ALERT" : "TOUGE DASH"))
                .font(.system(size: 10, weight: .black))
                .tracking(0.7)
                .foregroundStyle(snapshot.hasTemperatureWarning ? Color.tougeOrange : Color.tougeCyan)
            Spacer(minLength: 2)
            Circle()
                .fill(snapshot.hasTemperatureWarning ? Color.tougeOrange : (snapshot.isFresh ? Color.tougeMint : Color.gray))
                .frame(width: 6, height: 6)
            Text(localized(snapshot.hasTemperatureWarning ? "HOT" : (snapshot.isFresh ? "LIVE" : "WAIT")))
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(snapshot.hasTemperatureWarning ? Color.tougeOrange : (snapshot.isFresh ? Color.tougeMint : Color.secondary))
        }
    }

    private func oilPanel(snapshot: WatchTelemetryPayload) -> some View {
        VStack(spacing: 3) {
            Text("OIL")
                .font(.system(size: 9, weight: .black))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                OilMetric(
                    symbol: "gauge.with.dots.needle.33percent",
                    value: snapshot.oilPressureBar.formatted(.number.precision(.fractionLength(1))),
                    unit: "bar",
                    tint: snapshot.hasOilPressureWarning ? .tougeOrange : .tougeMint
                )
                WatchDivider(height: 27)
                OilMetric(
                    symbol: "thermometer.medium",
                    value: Int(snapshot.oilTemperatureCelsius).formatted(.number.grouping(.never)),
                    unit: "°C",
                    tint: snapshot.hasOilTemperatureWarning ? .tougeOrange : .tougeWarm
                )
            }
        }
    }

    private func coolantPanel(snapshot: WatchTelemetryPayload) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "thermometer.and.liquid.waves")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(snapshot.hasCoolantWarning ? Color.tougeOrange : Color.tougeIce)
            Text("COOLANT")
                .font(.system(size: 9, weight: .black))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(Int(snapshot.coolantCelsius).formatted(.number.grouping(.never)))
                .font(.system(size: 21, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(snapshot.hasCoolantWarning ? Color.tougeOrange : Color.tougeIce)
            Text("°C")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct WatchMetric: View {
    let title: String
    let value: String
    var unit = ""
    let tint: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(localized(title))
                .font(.system(size: 9, weight: .black))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OilMetric: View {
    let symbol: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint.opacity(0.85))
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(unit)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WatchDivider: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: height)
    }
}

private extension Color {
    static let tougeCyan = Color(red: 0.08, green: 0.86, blue: 0.92)
    static let tougeMint = Color(red: 0.20, green: 0.89, blue: 0.60)
    static let tougeWarm = Color(red: 1.00, green: 0.36, blue: 0.22)
    static let tougeIce = Color(red: 0.38, green: 0.75, blue: 1.00)
    static let tougeOrange = Color(red: 1.00, green: 0.23, blue: 0.12)
    static let tougeNavy = Color(red: 0.05, green: 0.12, blue: 0.20)
    static let tougeAlertNavy = Color(red: 0.20, green: 0.025, blue: 0.03)
}
