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
            LiveActivityCard(snapshot: context.state.telemetry, vehicleName: context.attributes.vehicleName)
                .activityBackgroundTint(Color(red: 0.02, green: 0.03, blue: 0.04))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveMetric(title: "RPM", value: Int(context.state.telemetry.rpm).formatted(.number.grouping(.never)), tint: WidgetPalette.cyan)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveMetric(title: "BOOST", value: context.state.telemetry.boostBar.formatted(.number.precision(.fractionLength(2))), tint: WidgetPalette.cyan)
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
                        LiveMetric(title: "OIL", value: Int(context.state.telemetry.oilTemperatureCelsius).formatted() + "°", tint: context.state.telemetry.oilTemperatureCelsius > 135 ? WidgetPalette.orange : WidgetPalette.cyan)
                    }
                }
            } compactLeading: {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(WidgetPalette.cyan)
            } compactTrailing: {
                Text(Int(context.state.telemetry.oilTemperatureCelsius).formatted() + "°")
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(context.state.telemetry.oilTemperatureCelsius > 135 ? WidgetPalette.orange : WidgetPalette.cyan)
            } minimal: {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(WidgetPalette.cyan)
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

    var body: some View {
        if activityFamily == .small {
            SmallLiveActivityCard(snapshot: snapshot)
        } else {
            FullLiveActivityCard(snapshot: snapshot, vehicleName: vehicleName)
        }
    }
}

private struct SmallLiveActivityCard: View {
    let snapshot: TelemetrySnapshot

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 0) {
                Text("RPM")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.secondary)
                Text(Int(snapshot.rpm).formatted(.number.grouping(.never)))
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.cyan)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            LiveMetric(title: "BOOST", value: snapshot.boostBar.formatted(.number.precision(.fractionLength(2))), tint: WidgetPalette.cyan)
            LiveMetric(title: "AFR", value: snapshot.afr.formatted(.number.precision(.fractionLength(1))), tint: WidgetPalette.mint)
            VStack(spacing: 0) {
                Text(Int(snapshot.oilTemperatureCelsius).formatted() + "°")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(snapshot.oilTemperatureCelsius > 135 ? WidgetPalette.orange : WidgetPalette.cyan)
                Text("OIL")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct FullLiveActivityCard: View {
    let snapshot: TelemetrySnapshot
    let vehicleName: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Label("TOUGE DASH", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(WidgetPalette.cyan)
                Text(vehicleName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 5)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Int(snapshot.rpm).formatted(.number.grouping(.never)))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("RPM")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            LiveMetric(title: "BOOST", value: snapshot.boostBar.formatted(.number.precision(.fractionLength(2))) + " bar", tint: WidgetPalette.cyan)
            LiveMetric(title: "AFR", value: snapshot.afr.formatted(.number.precision(.fractionLength(1))), tint: WidgetPalette.mint)
            LiveMetric(title: "OIL", value: Int(snapshot.oilTemperatureCelsius).formatted() + "°", tint: snapshot.oilTemperatureCelsius > 135 ? WidgetPalette.orange : WidgetPalette.cyan)
        }
        .padding(15)
    }
}

private struct LiveMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
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
}
