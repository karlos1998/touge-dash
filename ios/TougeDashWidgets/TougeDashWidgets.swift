import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TougeDashWidgetBundle: WidgetBundle {
    var body: some Widget {
        TougeDashTelemetryWidget()
        TougeDashLiveActivity()
    }
}

struct TelemetryTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: TelemetrySnapshot
}

struct TelemetryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TelemetryTimelineEntry {
        TelemetryTimelineEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (TelemetryTimelineEntry) -> Void) {
        completion(TelemetryTimelineEntry(date: .now, snapshot: context.isPreview ? .preview : SharedTelemetryStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TelemetryTimelineEntry>) -> Void) {
        let entry = TelemetryTimelineEntry(date: .now, snapshot: SharedTelemetryStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(60))))
    }
}

struct TougeDashTelemetryWidget: Widget {
    let kind = "TougeDashTelemetryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TelemetryTimelineProvider()) { entry in
            TelemetryWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    WidgetBackground()
                }
        }
        .configurationDisplayName("Touge Dash")
        .description("RPM, boost and essential EMU engine telemetry at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TelemetryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: TelemetrySnapshot

    var body: some View {
        if family == .systemMedium {
            MediumTelemetryWidget(snapshot: snapshot)
        } else {
            SmallTelemetryWidget(snapshot: snapshot)
        }
    }
}

private struct SmallTelemetryWidget: View {
    let snapshot: TelemetrySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("TOUGE", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(WidgetPalette.cyan)
                Spacer()
                Circle()
                    .fill(snapshot.isFresh ? WidgetPalette.mint : Color.gray)
                    .frame(width: 6, height: 6)
            }

            Spacer(minLength: 2)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(Int(snapshot.rpm).formatted(.number.grouping(.never)))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                Text("RPM")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("BOOST").font(.system(size: 8, weight: .black)).foregroundStyle(.secondary)
                    Text(snapshot.boostBar.formatted(.number.precision(.fractionLength(2))) + " bar")
                        .font(.caption.monospacedDigit().weight(.bold))
                }
                Spacer()
                Text("OIL " + Int(snapshot.oilTemperatureCelsius).formatted() + "°")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(snapshot.oilTemperatureCelsius > 135 ? WidgetPalette.orange : WidgetPalette.cyan)
            }
        }
    }
}

private struct MediumTelemetryWidget: View {
    let snapshot: TelemetrySnapshot

    var body: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 3) {
                Label("TOUGE DASH", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(WidgetPalette.cyan)
                Spacer()
                Text(Int(snapshot.rpm).formatted(.number.grouping(.never)))
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                Text("RPM")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 7) {
                WidgetMetric(title: "BOOST", value: snapshot.boostBar.formatted(.number.precision(.fractionLength(2))), unit: "bar", tint: WidgetPalette.cyan)
                WidgetMetric(title: "AFR", value: snapshot.afr.formatted(.number.precision(.fractionLength(1))), unit: "", tint: WidgetPalette.mint)
                WidgetMetric(title: "COOLANT", value: snapshot.coolantCelsius.formatted(.number.precision(.fractionLength(0))), unit: "°C", tint: snapshot.coolantCelsius > 108 ? WidgetPalette.orange : .white)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 1) {
                Text(Int(snapshot.oilTemperatureCelsius).formatted() + "°")
                    .font(.system(size: 39, weight: .black, design: .rounded))
                    .foregroundStyle(snapshot.oilTemperatureCelsius > 135 ? WidgetPalette.orange : WidgetPalette.cyan)
                Text("OIL TEMP")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.secondary)
                Text(Int(snapshot.speedKPH).formatted() + " km/h")
                    .font(.caption2.monospacedDigit().weight(.bold))
            }
            .frame(width: 63)
        }
    }
}

private struct WidgetMetric: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(tint)
            Text(unit)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

struct TougeDashLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TelemetryActivityAttributes.self) { context in
            LiveActivityCard(
                snapshot: context.state.telemetry,
                vehicleName: context.attributes.vehicleName,
                connectionLabel: context.state.connectionLabel
            )
                .activityBackgroundTint(Color(red: 0.02, green: 0.03, blue: 0.04))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveMetric(
                        title: "OIL P",
                        value: context.state.telemetry.oilPressureBar.formatted(.number.precision(.fractionLength(1))),
                        unit: "bar",
                        tint: oilPressureTint(for: context.state.telemetry)
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveMetric(
                        title: "BOOST",
                        value: context.state.telemetry.boostBar.formatted(.number.precision(.fractionLength(2))),
                        unit: "bar",
                        tint: WidgetPalette.cyan
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("TOUGE DASH")
                        .font(.caption2.weight(.black))
                        .tracking(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        LiveMetric(title: "AFR", value: context.state.telemetry.afr.formatted(.number.precision(.fractionLength(1))), tint: WidgetPalette.mint)
                        Spacer()
                        LiveMetric(title: "COOLANT", value: Int(context.state.telemetry.coolantCelsius).formatted() + "°", tint: context.state.telemetry.coolantCelsius > 108 ? WidgetPalette.orange : .white)
                        Spacer()
                        LiveMetric(title: "OIL T", value: Int(context.state.telemetry.oilTemperatureCelsius).formatted(), unit: "°C", tint: oilTemperatureTint(for: context.state.telemetry))
                    }
                }
            } compactLeading: {
                Image(systemName: "oilcan.fill")
                    .foregroundStyle(oilPressureTint(for: context.state.telemetry))
            } compactTrailing: {
                Text(Int(context.state.telemetry.oilTemperatureCelsius).formatted(.number.grouping(.never)))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(oilTemperatureTint(for: context.state.telemetry))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityLabel("Oil temperature \(Int(context.state.telemetry.oilTemperatureCelsius)) degrees Celsius")
            } minimal: {
                Image(systemName: "oilcan.fill")
                    .foregroundStyle(oilPressureTint(for: context.state.telemetry))
            }
            .keylineTint(WidgetPalette.cyan)
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct LiveActivityCard: View {
    @Environment(\.activityFamily) private var activityFamily
    let snapshot: TelemetrySnapshot
    let vehicleName: String
    let connectionLabel: String

    var body: some View {
        TelemetryActivityPanel(
            snapshot: snapshot,
            vehicleName: vehicleName,
            connectionLabel: connectionLabel,
            compact: activityFamily == .small
        )
    }
}

private struct TelemetryActivityPanel: View {
    let snapshot: TelemetrySnapshot
    let vehicleName: String
    let connectionLabel: String
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 6 : 9) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(WidgetPalette.cyan)
                Text("TOUGE DASH")
                    .font(.system(size: compact ? 9 : 11, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(WidgetPalette.cyan)
                if !compact {
                    Text(vehicleName.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Circle()
                    .fill(snapshot.isFresh ? WidgetPalette.mint : Color.gray)
                    .frame(width: 6, height: 6)
                Text(snapshot.isFresh ? "LIVE" : "STALE")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(snapshot.isFresh ? WidgetPalette.mint : .secondary)
            }

            HStack(spacing: compact ? 0 : 7) {
                ActivityOilTile(snapshot: snapshot, compact: compact)
                if compact { ActivityMetricDivider() }
                ActivityMetricTile(
                    title: "BOOST",
                    value: snapshot.boostBar.formatted(.number.precision(.fractionLength(2))),
                    unit: "bar",
                    tint: WidgetPalette.cyan,
                    compact: compact
                )
                if compact { ActivityMetricDivider() }
                ActivityMetricTile(
                    title: "AFR",
                    value: snapshot.afr.formatted(.number.precision(.fractionLength(1))),
                    unit: "",
                    tint: WidgetPalette.mint,
                    compact: compact
                )
            }
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 7 : 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(connectionLabel), oil pressure \(snapshot.oilPressureBar) bar, boost \(snapshot.boostBar) bar, AFR \(snapshot.afr), oil temperature \(Int(snapshot.oilTemperatureCelsius)) degrees Celsius")
    }
}

private struct ActivityOilTile: View {
    let snapshot: TelemetrySnapshot
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 1 : 2) {
            Text("OIL")
                .font(.system(size: compact ? 7 : 8, weight: .black))
                .tracking(0.3)
                .foregroundStyle(.secondary)

            ActivityOilValue(
                symbol: "gauge.with.dots.needle.33percent",
                value: snapshot.oilPressureBar.formatted(.number.precision(.fractionLength(1))),
                unit: compact ? "" : "bar",
                tint: oilPressureTint(for: snapshot),
                compact: compact
            )
            ActivityOilValue(
                symbol: "thermometer.medium",
                value: Int(snapshot.oilTemperatureCelsius).formatted(.number.grouping(.never)),
                unit: compact ? "°" : "°C",
                tint: oilTemperatureTint(for: snapshot),
                compact: compact
            )
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 41 : 49)
        .padding(.horizontal, compact ? 4 : 5)
        .padding(.vertical, compact ? 0 : 5)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.055))
            }
        }
    }
}

private struct ActivityOilValue: View {
    let symbol: String
    let value: String
    let unit: String
    let tint: Color
    let compact: Bool

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: compact ? 2 : 3) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 7 : 8, weight: .bold))
                .foregroundStyle(tint.opacity(0.85))
                .frame(width: compact ? 9 : 11)
            Text(value)
                .font(.system(size: compact ? 11 : 15, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .layoutPriority(1)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: compact ? 6 : 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ActivityMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let tint: Color
    let compact: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: compact ? 7 : 8, weight: .black))
                .tracking(0.3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: compact ? 19 : 23, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
                    .layoutPriority(1)
                if !compact && !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: compact ? 7 : 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 41 : 49)
        .padding(.horizontal, compact ? 4 : 5)
        .padding(.vertical, compact ? 0 : 5)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.055))
            }
        }
    }
}

private struct ActivityMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 32)
    }
}

private struct LiveMetric: View {
    let title: String
    let value: String
    var unit = ""
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private func oilPressureTint(for snapshot: TelemetrySnapshot) -> Color {
    let lowPressure = snapshot.rpm > 1_200 && snapshot.oilPressureBar > 0 && snapshot.oilPressureBar < 0.5
    return lowPressure ? WidgetPalette.red : WidgetPalette.mint
}

private func oilTemperatureTint(for snapshot: TelemetrySnapshot) -> Color {
    snapshot.oilTemperatureCelsius > 135 ? WidgetPalette.red : WidgetPalette.orange
}

private struct WidgetBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.04)
            RadialGradient(colors: [WidgetPalette.cyan.opacity(0.16), .clear], center: .topTrailing, startRadius: 4, endRadius: 230)
        }
    }
}

private enum WidgetPalette {
    static let cyan = Color(red: 0.05, green: 0.88, blue: 0.94)
    static let mint = Color(red: 0.21, green: 0.91, blue: 0.62)
    static let orange = Color(red: 1, green: 0.3, blue: 0.17)
    static let red = Color(red: 1, green: 0.18, blue: 0.2)
}
