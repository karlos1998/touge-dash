import Foundation

enum DashboardMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case rpm
    case boost
    case map
    case throttle
    case coolant
    case intake
    case oilTemperature
    case oilPressure
    case fuelPressure
    case afr
    case lambda
    case batteryVoltage
    case ignition
    case injectorDuty
    case speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rpm: localized("Obroty silnika")
        case .boost: localized("Ciśnienie doładowania")
        case .map: "MAP"
        case .throttle: localized("Przepustnica")
        case .coolant: localized("Temperatura płynu")
        case .intake: localized("Temperatura dolotu")
        case .oilTemperature: localized("Temperatura oleju")
        case .oilPressure: localized("Ciśnienie oleju")
        case .fuelPressure: localized("Ciśnienie paliwa")
        case .afr: "AFR"
        case .lambda: localized("Lambda")
        case .batteryVoltage: localized("Napięcie instalacji")
        case .ignition: localized("Kąt zapłonu")
        case .injectorDuty: localized("Wtryskiwacze")
        case .speed: localized("Prędkość")
        }
    }

    var shortTitle: String {
        switch self {
        case .rpm: "RPM"
        case .boost: "BOOST"
        case .map: "MAP"
        case .throttle: "TPS"
        case .coolant: "COOLANT"
        case .intake: "IAT"
        case .oilTemperature: "OIL TEMP"
        case .oilPressure: "OIL P"
        case .fuelPressure: "FUEL"
        case .afr: "AFR"
        case .lambda: "LAMBDA"
        case .batteryVoltage: "BATTERY"
        case .ignition: "IGN"
        case .injectorDuty: "INJ"
        case .speed: "SPEED"
        }
    }

    var unit: String {
        switch self {
        case .rpm: "rpm"
        case .boost, .oilPressure, .fuelPressure: "bar"
        case .map: "kPa"
        case .throttle, .injectorDuty: "%"
        case .coolant, .intake, .oilTemperature: "°C"
        case .afr: "AFR"
        case .lambda: "λ"
        case .batteryVoltage: "V"
        case .ignition: "°"
        case .speed: "km/h"
        }
    }

    var icon: String {
        switch self {
        case .rpm: "gauge.with.dots.needle.67percent"
        case .boost: "wind"
        case .map: "waveform.path"
        case .throttle: "pedal.accelerator"
        case .coolant: "thermometer.high"
        case .intake: "thermometer.low"
        case .oilTemperature: "thermometer.medium"
        case .oilPressure: "oilcan.fill"
        case .fuelPressure: "fuelpump.fill"
        case .afr, .lambda: "waveform.path.ecg"
        case .batteryVoltage: "bolt.fill"
        case .ignition: "sparkles"
        case .injectorDuty: "drop.degreesign.fill"
        case .speed: "speedometer"
        }
    }

    var precision: Int {
        switch self {
        case .boost: 2
        case .oilPressure, .fuelPressure, .afr, .lambda, .batteryVoltage, .ignition: 1
        default: 0
        }
    }

    var defaultRange: ClosedRange<Double> {
        switch self {
        case .rpm: 0...10_000
        case .boost: -1...2
        case .map: 0...300
        case .throttle, .injectorDuty: 0...100
        case .coolant: 0...130
        case .intake: -20...100
        case .oilTemperature: 0...150
        case .oilPressure: 0...10
        case .fuelPressure: 0...10
        case .afr: 8...20
        case .lambda: 0.5...1.5
        case .batteryVoltage: 8...16
        case .ignition: -20...60
        case .speed: 0...300
        }
    }

    func value(in snapshot: TelemetrySnapshot) -> Double {
        switch self {
        case .rpm: snapshot.rpm
        case .boost: snapshot.boostBar
        case .map: snapshot.mapKPa
        case .throttle: snapshot.throttlePercent
        case .coolant: snapshot.coolantCelsius
        case .intake: snapshot.intakeCelsius
        case .oilTemperature: snapshot.oilTemperatureCelsius
        case .oilPressure: snapshot.oilPressureBar
        case .fuelPressure: snapshot.fuelPressureBar
        case .afr: snapshot.afr
        case .lambda: snapshot.lambda
        case .batteryVoltage: snapshot.batteryVoltage
        case .ignition: snapshot.ignitionDegrees
        case .injectorDuty: snapshot.injectorDutyPercent
        case .speed: snapshot.speedKPH
        }
    }

    func isWarning(in snapshot: TelemetrySnapshot) -> Bool {
        switch self {
        case .boost: snapshot.boostBar > 1.6
        case .coolant: snapshot.hasCoolantWarning
        case .oilTemperature: snapshot.hasOilTemperatureWarning
        case .oilPressure: snapshot.rpm > 1_200 && snapshot.oilPressureBar > 0 && snapshot.oilPressureBar < 0.5
        case .afr: snapshot.afr > 0 && (snapshot.afr < 10.5 || snapshot.afr > 16)
        case .batteryVoltage: snapshot.hasBatteryVoltageWarning
        default: false
        }
    }
}

enum DashboardWidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hero
    case group
    case value
    case gauge
    case chart
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hero: localized("Duża wartość")
        case .group: localized("Grupa wartości")
        case .value: localized("Karta wartości")
        case .gauge: localized("Wskaźnik zegarowy")
        case .chart: localized("Wykres na żywo")
        case .compact: localized("Mała wartość")
        }
    }
}

enum DashboardWidgetSpan: Int, Codable, CaseIterable, Identifiable, Sendable {
    case hidden = 0
    case sixth = 2
    case quarter = 3
    case third = 4
    case half = 6
    case full = 12

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .hidden: localized("Ukryty")
        case .sixth: "1/6"
        case .quarter: "1/4"
        case .third: "1/3"
        case .half: "1/2"
        case .full: localized("Pełna szerokość")
        }
    }
}

enum DashboardChartDuration: Int, Codable, CaseIterable, Identifiable, Sendable {
    case thirtySeconds = 30
    case threeMinutes = 180
    case tenMinutes = 600

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirtySeconds: localized("30 sekund")
        case .threeMinutes: localized("3 minuty")
        case .tenMinutes: localized("10 minut")
        }
    }
}

enum DashboardAccent: String, Codable, CaseIterable, Identifiable, Sendable {
    case cyan
    case mint
    case blue
    case ice
    case orange
    case yellow
    case red
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cyan: localized("Cyjan")
        case .mint: localized("Miętowy")
        case .blue: localized("Niebieski")
        case .ice: localized("Lodowy")
        case .orange: localized("Pomarańczowy")
        case .yellow: localized("Żółty")
        case .red: localized("Czerwony")
        case .white: localized("Biały")
        }
    }
}

struct DashboardWidget: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var kind: DashboardWidgetKind
    var wideKind: DashboardWidgetKind?
    var title: String?
    var metrics: [DashboardMetric]
    var portraitSpan: DashboardWidgetSpan
    var landscapeSpan: DashboardWidgetSpan
    var portraitOrder: Int
    var landscapeOrder: Int
    var gaugeMinimum: Double?
    var gaugeMaximum: Double?
    var chartDuration: DashboardChartDuration?
    var accent: DashboardAccent

    init(
        id: UUID = UUID(),
        kind: DashboardWidgetKind,
        wideKind: DashboardWidgetKind? = nil,
        title: String? = nil,
        metrics: [DashboardMetric],
        portraitSpan: DashboardWidgetSpan,
        landscapeSpan: DashboardWidgetSpan,
        portraitOrder: Int,
        landscapeOrder: Int? = nil,
        gaugeMinimum: Double? = nil,
        gaugeMaximum: Double? = nil,
        chartDuration: DashboardChartDuration? = nil,
        accent: DashboardAccent = .cyan
    ) {
        self.id = id
        self.kind = kind
        self.wideKind = wideKind
        self.title = title
        self.metrics = metrics
        self.portraitSpan = portraitSpan
        self.landscapeSpan = landscapeSpan
        self.portraitOrder = portraitOrder
        self.landscapeOrder = landscapeOrder ?? portraitOrder
        self.gaugeMinimum = gaugeMinimum
        self.gaugeMaximum = gaugeMaximum
        self.chartDuration = chartDuration
        self.accent = accent
    }

    var primaryMetric: DashboardMetric { metrics.first ?? .boost }
}

struct DashboardDefinition: Codable, Hashable, Sendable {
    var widgets: [DashboardWidget]
}

struct DashboardTemplateRecord: Codable, Hashable, Identifiable, Sendable {
    static let schemaVersion = 1

    var id: UUID
    var schemaVersion: Int
    var name: String
    var definition: DashboardDefinition
    var modifiedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        schemaVersion: Int = DashboardTemplateRecord.schemaVersion,
        name: String,
        definition: DashboardDefinition,
        modifiedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.definition = definition
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }
}

extension DashboardTemplateRecord {
    static let factoryID = UUID(uuidString: "D45D65AA-9D81-47D3-82B5-71C7B6E66A11")!
    private static let factoryBaselineDate = Date(timeIntervalSince1970: 1_735_689_600)

    static func factory(modifiedAt: Date = factoryBaselineDate) -> DashboardTemplateRecord {
        DashboardTemplateRecord(
            id: factoryID,
            name: localized("Fabryczny"),
            definition: DashboardDefinition(widgets: [
                DashboardWidget(
                    kind: .hero,
                    wideKind: .value,
                    metrics: [.boost, .map, .throttle, .rpm],
                    portraitSpan: .full,
                    landscapeSpan: .third,
                    portraitOrder: 0,
                    landscapeOrder: 1,
                    gaugeMinimum: 0,
                    gaugeMaximum: 2,
                    accent: .cyan
                ),
                DashboardWidget(
                    kind: .group,
                    title: localized("Kondycja silnika"),
                    metrics: [.oilPressure, .oilTemperature, .coolant],
                    portraitSpan: .full,
                    landscapeSpan: .full,
                    portraitOrder: 1,
                    landscapeOrder: 0,
                    accent: .mint
                ),
                DashboardWidget(kind: .value, metrics: [.afr], portraitSpan: .half, landscapeSpan: .third, portraitOrder: 2, accent: .mint),
                DashboardWidget(kind: .value, metrics: [.batteryVoltage], portraitSpan: .half, landscapeSpan: .third, portraitOrder: 3, accent: .yellow),
                DashboardWidget(kind: .compact, metrics: [.map], portraitSpan: .hidden, landscapeSpan: .sixth, portraitOrder: 4, landscapeOrder: 4, accent: .ice),
                DashboardWidget(kind: .compact, metrics: [.throttle], portraitSpan: .quarter, landscapeSpan: .sixth, portraitOrder: 5, landscapeOrder: 5, accent: .cyan),
                DashboardWidget(kind: .compact, metrics: [.rpm], portraitSpan: .hidden, landscapeSpan: .sixth, portraitOrder: 6, landscapeOrder: 6, accent: .white),
                DashboardWidget(kind: .compact, metrics: [.injectorDuty], portraitSpan: .quarter, landscapeSpan: .sixth, portraitOrder: 4, landscapeOrder: 7, accent: .orange),
                DashboardWidget(kind: .compact, metrics: [.intake], portraitSpan: .quarter, landscapeSpan: .sixth, portraitOrder: 6, landscapeOrder: 8, accent: .blue),
                DashboardWidget(kind: .compact, metrics: [.fuelPressure], portraitSpan: .quarter, landscapeSpan: .sixth, portraitOrder: 7, landscapeOrder: 9, accent: .mint)
            ]),
            modifiedAt: modifiedAt
        )
    }
}
