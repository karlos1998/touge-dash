import Combine
import CoreGraphics
import Foundation

enum VideoOverlayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case racing
    case arcade
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .racing: localized("Racing HUD")
        case .arcade: localized("Arcade telemetry")
        case .minimal: localized("Minimal")
        }
    }
}

enum VideoOverlayElementKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case digital
    case gauge
    case bar
    case speedCluster
    case oilCluster
    case neonTach
    case blacklistTach
    case carbonTach
    case streetShiftTach
    case routeMap
    case routeMapCircular
    case routeMapFollow
    case routeMapLight
    case routeMapLightCircular
    case routeMapAmber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .digital: localized("Wartość cyfrowa")
        case .gauge: localized("Zegar")
        case .bar: localized("Pasek")
        case .speedCluster: localized("Zegar prędkości + boost + RPM")
        case .oilCluster: localized("Zegar oleju + ciśnienie")
        case .neonTach: localized("Neonowy obrotomierz")
        case .blacklistTach: localized("Klasyczny obrotomierz uliczny")
        case .carbonTach: localized("Karbonowy obrotomierz")
        case .streetShiftTach: localized("Zegar uliczny z biegiem")
        case .routeMap: localized("Minimapa trasy")
        case .routeMapCircular: localized("Okrągła minimapa trasy")
        case .routeMapFollow: localized("Minimapa śledząca")
        case .routeMapLight: localized("Jasna mapa ulic")
        case .routeMapLightCircular: localized("Okrągła jasna mapa")
        case .routeMapAmber: localized("Bursztynowa mapa")
        }
    }

    var icon: String {
        switch self {
        case .digital: "number"
        case .gauge: "gauge.with.dots.needle.67percent"
        case .bar: "chart.bar.fill"
        case .speedCluster: "speedometer"
        case .oilCluster: "oilcan.fill"
        case .neonTach: "gauge.open.with.lines.needle.67percent.and.arrowtriangle"
        case .blacklistTach: "gauge.with.dots.needle.67percent"
        case .carbonTach: "circle.hexagongrid.fill"
        case .streetShiftTach: "dial.high.fill"
        case .routeMap: "map.fill"
        case .routeMapCircular: "circle.hexagongrid.fill"
        case .routeMapFollow: "location.north.circle.fill"
        case .routeMapLight: "map.fill"
        case .routeMapLightCircular: "circle.grid.cross.fill"
        case .routeMapAmber: "location.north.line.fill"
        }
    }

    var isRouteMap: Bool {
        switch self {
        case .routeMap, .routeMapCircular, .routeMapFollow, .routeMapLight, .routeMapLightCircular, .routeMapAmber: true
        default: false
        }
    }

    var isCircularRouteMap: Bool {
        self == .routeMapCircular || self == .routeMapFollow || self == .routeMapLightCircular
    }

    var usesLightMap: Bool {
        self == .routeMapLight || self == .routeMapLightCircular || self == .routeMapAmber
    }
}

struct VideoOverlayGaugeConfiguration: Codable, Hashable, Sendable {
    var maximumSpeedKPH: Double = 300
    var maximumOilTemperatureCelsius: Double = 140
    var maximumRPM: Double = 8_000
    var maximumBoostBar: Double = 2

    func range(for metric: DashboardMetric) -> ClosedRange<Double> {
        switch metric {
        case .speed: 0...max(100, maximumSpeedKPH)
        case .oilTemperature: 0...max(80, maximumOilTemperatureCelsius)
        case .rpm: 0...max(4_000, maximumRPM)
        case .boost: metric.defaultRange.lowerBound...max(0.5, maximumBoostBar)
        default: metric.defaultRange
        }
    }
}

enum VideoOverlayCanvasOrientation: String, Codable, Sendable {
    case landscape
    case portrait

    init(size: CGSize) {
        self = size.width >= size.height ? .landscape : .portrait
    }
}

struct VideoOverlayPosition: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(0.94, max(0.06, x))
        self.y = min(0.94, max(0.06, y))
    }

    static func fallback(for slot: VideoOverlaySlot) -> VideoOverlayPosition {
        switch slot {
        case .topLeading: .init(x: 0.18, y: 0.17)
        case .topCenter: .init(x: 0.5, y: 0.17)
        case .topTrailing: .init(x: 0.82, y: 0.17)
        case .bottomLeading: .init(x: 0.18, y: 0.8)
        case .bottomCenter: .init(x: 0.5, y: 0.8)
        case .bottomTrailing: .init(x: 0.82, y: 0.8)
        }
    }
}

enum VideoOverlaySlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeading
    case topCenter
    case topTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading: localized("Góra · lewa")
        case .topCenter: localized("Góra · środek")
        case .topTrailing: localized("Góra · prawa")
        case .bottomLeading: localized("Dół · lewa")
        case .bottomCenter: localized("Dół · środek")
        case .bottomTrailing: localized("Dół · prawa")
        }
    }
}

enum VideoOverlayScale: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: localized("Mały")
        case .medium: localized("Średni")
        case .large: localized("Duży")
        case .extraLarge: localized("Bardzo duży")
        }
    }

    var multiplier: Double {
        switch self {
        case .small: 0.72
        case .medium: 1
        case .large: 1.36
        case .extraLarge: 1.72
        }
    }
}

struct VideoOverlayElement: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var metric: DashboardMetric
    var slot: VideoOverlaySlot
    var scale: VideoOverlayScale
    var sizeMultiplier: Double
    var mapZoom: Double
    var accent: DashboardAccent
    var kind: VideoOverlayElementKind
    var landscapePosition: VideoOverlayPosition?
    var portraitPosition: VideoOverlayPosition?

    init(
        id: UUID = UUID(),
        metric: DashboardMetric,
        slot: VideoOverlaySlot,
        scale: VideoOverlayScale = .medium,
        sizeMultiplier: Double = 1,
        mapZoom: Double = 1,
        accent: DashboardAccent = .cyan,
        kind: VideoOverlayElementKind = .digital,
        landscapePosition: VideoOverlayPosition? = nil,
        portraitPosition: VideoOverlayPosition? = nil
    ) {
        self.id = id
        self.metric = metric
        self.slot = slot
        self.scale = scale
        self.sizeMultiplier = Self.clampedSizeMultiplier(sizeMultiplier)
        self.mapZoom = Self.clampedMapZoom(mapZoom)
        self.accent = accent
        self.kind = kind
        self.landscapePosition = landscapePosition
        self.portraitPosition = portraitPosition
    }

    func position(for orientation: VideoOverlayCanvasOrientation) -> VideoOverlayPosition {
        switch orientation {
        case .landscape: landscapePosition ?? VideoOverlayPosition.fallback(for: slot)
        case .portrait: portraitPosition ?? landscapePosition ?? VideoOverlayPosition.fallback(for: slot)
        }
    }

    mutating func setPosition(_ position: VideoOverlayPosition, for orientation: VideoOverlayCanvasOrientation) {
        switch orientation {
        case .landscape: landscapePosition = position
        case .portrait: portraitPosition = position
        }
    }

    mutating func setSizeMultiplier(_ value: Double) {
        sizeMultiplier = Self.clampedSizeMultiplier(value)
    }

    mutating func setMapZoom(_ value: Double) {
        mapZoom = Self.clampedMapZoom(value)
    }

    var effectiveScale: Double { scale.multiplier * sizeMultiplier }

    private static func clampedSizeMultiplier(_ value: Double) -> Double {
        min(2.5, max(0.45, value))
    }

    private static func clampedMapZoom(_ value: Double) -> Double {
        min(1.85, max(0.65, value))
    }

    private enum CodingKeys: String, CodingKey {
        case id, metric, slot, scale, sizeMultiplier, mapZoom, accent, kind, landscapePosition, portraitPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        metric = try container.decode(DashboardMetric.self, forKey: .metric)
        slot = try container.decode(VideoOverlaySlot.self, forKey: .slot)
        scale = try container.decode(VideoOverlayScale.self, forKey: .scale)
        sizeMultiplier = Self.clampedSizeMultiplier(
            try container.decodeIfPresent(Double.self, forKey: .sizeMultiplier) ?? 1
        )
        mapZoom = Self.clampedMapZoom(
            try container.decodeIfPresent(Double.self, forKey: .mapZoom) ?? 1
        )
        accent = try container.decode(DashboardAccent.self, forKey: .accent)
        kind = try container.decodeIfPresent(VideoOverlayElementKind.self, forKey: .kind) ?? .digital
        landscapePosition = try container.decodeIfPresent(VideoOverlayPosition.self, forKey: .landscapePosition)
        portraitPosition = try container.decodeIfPresent(VideoOverlayPosition.self, forKey: .portraitPosition)
    }
}

struct VideoOverlayTemplate: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var style: VideoOverlayStyle
    var elements: [VideoOverlayElement]
    var gaugeConfiguration: VideoOverlayGaugeConfiguration
    var modifiedAt: Date
    var layoutVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        style: VideoOverlayStyle,
        elements: [VideoOverlayElement],
        gaugeConfiguration: VideoOverlayGaugeConfiguration = .init(),
        modifiedAt: Date = .now,
        layoutVersion: Int = 2
    ) {
        self.id = id
        self.name = name
        self.style = style
        self.elements = elements
        self.gaugeConfiguration = gaugeConfiguration
        self.modifiedAt = modifiedAt
        self.layoutVersion = layoutVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, style, elements, gaugeConfiguration, modifiedAt, layoutVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        style = try container.decode(VideoOverlayStyle.self, forKey: .style)
        elements = try container.decode([VideoOverlayElement].self, forKey: .elements)
        gaugeConfiguration = try container.decodeIfPresent(VideoOverlayGaugeConfiguration.self, forKey: .gaugeConfiguration) ?? .init()
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        layoutVersion = try container.decodeIfPresent(Int.self, forKey: .layoutVersion) ?? 1
    }
}

extension VideoOverlayTemplate {
    static let racing = VideoOverlayTemplate(
        id: UUID(uuidString: "A3244DA4-BF04-4CD1-88C7-040049050409")!,
        name: localized("Touge Pro"),
        style: .racing,
        elements: [
            VideoOverlayElement(
                metric: .rpm,
                slot: .topCenter,
                scale: .large,
                accent: .yellow,
                kind: .bar,
                landscapePosition: .init(x: 0.5, y: 0.09),
                portraitPosition: .init(x: 0.5, y: 0.08)
            ),
            VideoOverlayElement(
                metric: .speed,
                slot: .bottomLeading,
                scale: .extraLarge,
                accent: .ice,
                kind: .gauge,
                landscapePosition: .init(x: 0.15, y: 0.76),
                portraitPosition: .init(x: 0.5, y: 0.79)
            ),
            VideoOverlayElement(
                metric: .boost,
                slot: .bottomTrailing,
                scale: .large,
                accent: .cyan,
                kind: .gauge,
                landscapePosition: .init(x: 0.85, y: 0.76),
                portraitPosition: .init(x: 0.5, y: 0.43)
            ),
            VideoOverlayElement(
                metric: .oilPressure,
                slot: .topLeading,
                accent: .mint,
                landscapePosition: .init(x: 0.13, y: 0.18),
                portraitPosition: .init(x: 0.19, y: 0.21)
            ),
            VideoOverlayElement(
                metric: .oilTemperature,
                slot: .topCenter,
                accent: .orange,
                landscapePosition: .init(x: 0.5, y: 0.18),
                portraitPosition: .init(x: 0.5, y: 0.21)
            ),
            VideoOverlayElement(
                metric: .coolant,
                slot: .topTrailing,
                accent: .ice,
                landscapePosition: .init(x: 0.87, y: 0.18),
                portraitPosition: .init(x: 0.81, y: 0.21)
            )
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    static let arcade = VideoOverlayTemplate(
        id: UUID(uuidString: "6876D0C8-3A6E-4E4B-B149-2D69D80C6260")!,
        name: localized("Night Run"),
        style: .arcade,
        elements: [
            VideoOverlayElement(
                metric: .rpm,
                slot: .topCenter,
                scale: .extraLarge,
                accent: .orange,
                kind: .bar,
                landscapePosition: .init(x: 0.5, y: 0.1),
                portraitPosition: .init(x: 0.5, y: 0.08)
            ),
            VideoOverlayElement(
                metric: .speed,
                slot: .bottomTrailing,
                scale: .extraLarge,
                accent: .cyan,
                kind: .gauge,
                landscapePosition: .init(x: 0.82, y: 0.72),
                portraitPosition: .init(x: 0.5, y: 0.76)
            ),
            VideoOverlayElement(
                metric: .boost,
                slot: .bottomLeading,
                scale: .large,
                accent: .mint,
                kind: .gauge,
                landscapePosition: .init(x: 0.18, y: 0.75),
                portraitPosition: .init(x: 0.5, y: 0.42)
            ),
            VideoOverlayElement(
                metric: .afr,
                slot: .topLeading,
                scale: .medium,
                accent: .white,
                landscapePosition: .init(x: 0.13, y: 0.2),
                portraitPosition: .init(x: 0.23, y: 0.2)
            ),
            VideoOverlayElement(
                metric: .oilPressure,
                slot: .topTrailing,
                scale: .medium,
                accent: .yellow,
                landscapePosition: .init(x: 0.87, y: 0.2),
                portraitPosition: .init(x: 0.77, y: 0.2)
            )
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    static let minimal = VideoOverlayTemplate(
        id: UUID(uuidString: "8F68844A-F195-46F4-817E-94A8040B75C1")!,
        name: localized("Clean Drive"),
        style: .minimal,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .bottomLeading,
                scale: .extraLarge,
                accent: .white,
                landscapePosition: .init(x: 0.15, y: 0.82),
                portraitPosition: .init(x: 0.5, y: 0.82)
            ),
            VideoOverlayElement(
                metric: .boost,
                slot: .bottomTrailing,
                scale: .large,
                accent: .cyan,
                kind: .bar,
                landscapePosition: .init(x: 0.82, y: 0.85),
                portraitPosition: .init(x: 0.5, y: 0.62)
            ),
            VideoOverlayElement(
                metric: .oilTemperature,
                slot: .topTrailing,
                accent: .orange,
                landscapePosition: .init(x: 0.87, y: 0.15),
                portraitPosition: .init(x: 0.78, y: 0.16)
            ),
            VideoOverlayElement(
                metric: .coolant,
                slot: .topLeading,
                accent: .ice,
                landscapePosition: .init(x: 0.13, y: 0.15),
                portraitPosition: .init(x: 0.22, y: 0.16)
            )
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    static let portrait = VideoOverlayTemplate(
        id: UUID(uuidString: "DD08006F-53A8-46D5-A334-B7D23F50B858")!,
        name: localized("Portrait Rally"),
        style: .racing,
        elements: [
            VideoOverlayElement(
                metric: .rpm,
                slot: .topCenter,
                scale: .large,
                accent: .yellow,
                kind: .bar,
                landscapePosition: .init(x: 0.5, y: 0.09),
                portraitPosition: .init(x: 0.5, y: 0.08)
            ),
            VideoOverlayElement(
                metric: .speed,
                slot: .bottomCenter,
                scale: .extraLarge,
                accent: .white,
                kind: .gauge,
                landscapePosition: .init(x: 0.5, y: 0.76),
                portraitPosition: .init(x: 0.5, y: 0.77)
            ),
            VideoOverlayElement(
                metric: .boost,
                slot: .bottomLeading,
                scale: .large,
                accent: .cyan,
                kind: .gauge,
                landscapePosition: .init(x: 0.17, y: 0.74),
                portraitPosition: .init(x: 0.5, y: 0.4)
            ),
            VideoOverlayElement(
                metric: .oilPressure,
                slot: .topLeading,
                accent: .mint,
                landscapePosition: .init(x: 0.13, y: 0.19),
                portraitPosition: .init(x: 0.2, y: 0.2)
            ),
            VideoOverlayElement(
                metric: .oilTemperature,
                slot: .topCenter,
                accent: .orange,
                landscapePosition: .init(x: 0.5, y: 0.19),
                portraitPosition: .init(x: 0.5, y: 0.2)
            ),
            VideoOverlayElement(
                metric: .coolant,
                slot: .topTrailing,
                accent: .ice,
                landscapePosition: .init(x: 0.87, y: 0.19),
                portraitPosition: .init(x: 0.8, y: 0.2)
            )
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    static let streetLegends = VideoOverlayTemplate(
        id: UUID(uuidString: "4DC93C91-E785-4D73-959B-3CC5A1DC02D9")!,
        name: localized("Street Legends"),
        style: .arcade,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .bottomLeading,
                scale: .extraLarge,
                accent: .cyan,
                kind: .speedCluster,
                landscapePosition: .init(x: 0.2, y: 0.72),
                portraitPosition: .init(x: 0.5, y: 0.73)
            ),
            VideoOverlayElement(
                metric: .oilTemperature,
                slot: .bottomTrailing,
                scale: .large,
                accent: .orange,
                kind: .oilCluster,
                landscapePosition: .init(x: 0.8, y: 0.72),
                portraitPosition: .init(x: 0.5, y: 0.38)
            )
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_785_890_400)
    )

    static let neonCircuit = VideoOverlayTemplate(
        id: UUID(uuidString: "DFF220B2-549F-4BA0-9DF8-2E367EA9F1D5")!,
        name: localized("Neon Circuit"),
        style: .arcade,
        elements: [
            VideoOverlayElement(
                metric: .rpm,
                slot: .bottomTrailing,
                scale: .small,
                accent: .cyan,
                kind: .neonTach,
                landscapePosition: .init(x: 0.82, y: 0.73),
                portraitPosition: .init(x: 0.5, y: 0.77)
            )
        ],
        gaugeConfiguration: .init(maximumRPM: 10_000),
        modifiedAt: Date(timeIntervalSince1970: 1_786_615_200)
    )

    static let blacklistClassic = VideoOverlayTemplate(
        id: UUID(uuidString: "294F8665-9FE6-42C4-AE79-74E7C0BDBA39")!,
        name: localized("Blacklist Classic"),
        style: .racing,
        elements: [
            VideoOverlayElement(
                metric: .rpm,
                slot: .bottomTrailing,
                scale: .small,
                accent: .red,
                kind: .blacklistTach,
                landscapePosition: .init(x: 0.82, y: 0.73),
                portraitPosition: .init(x: 0.5, y: 0.77)
            )
        ],
        gaugeConfiguration: .init(maximumRPM: 10_000),
        modifiedAt: Date(timeIntervalSince1970: 1_786_615_200)
    )

    static let carbonGold = VideoOverlayTemplate(
        id: UUID(uuidString: "6B96EBE8-56B7-4156-A911-57A710B1BBA2")!,
        name: localized("Carbon Gold"),
        style: .racing,
        elements: [
            VideoOverlayElement(
                metric: .rpm,
                slot: .bottomTrailing,
                scale: .small,
                accent: .yellow,
                kind: .carbonTach,
                landscapePosition: .init(x: 0.82, y: 0.73),
                portraitPosition: .init(x: 0.5, y: 0.77)
            )
        ],
        gaugeConfiguration: .init(maximumRPM: 9_000),
        modifiedAt: Date(timeIntervalSince1970: 1_786_615_200)
    )

    static let streetShift = VideoOverlayTemplate(
        id: UUID(uuidString: "06E045CC-8BD3-47DE-965F-9404A5B3CE40")!,
        name: localized("Street Shift"),
        style: .arcade,
        elements: [
            VideoOverlayElement(
                metric: .rpm,
                slot: .bottomTrailing,
                scale: .small,
                accent: .orange,
                kind: .streetShiftTach,
                landscapePosition: .init(x: 0.82, y: 0.73),
                portraitPosition: .init(x: 0.5, y: 0.77)
            )
        ],
        gaugeConfiguration: .init(maximumRPM: 10_000),
        modifiedAt: Date(timeIntervalSince1970: 1_786_615_200)
    )

    static let routeRadar = VideoOverlayTemplate(
        id: UUID(uuidString: "516457E1-B465-4E96-8D29-19876C940719")!,
        name: localized("Route Radar"),
        style: .arcade,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .topLeading,
                scale: .medium,
                accent: .cyan,
                kind: .routeMap,
                landscapePosition: .init(x: 0.19, y: 0.24),
                portraitPosition: .init(x: 0.5, y: 0.18)
            ),
            VideoOverlayElement(
                metric: .rpm,
                slot: .bottomTrailing,
                scale: .small,
                accent: .cyan,
                kind: .neonTach,
                landscapePosition: .init(x: 0.82, y: 0.73),
                portraitPosition: .init(x: 0.5, y: 0.78)
            )
        ],
        gaugeConfiguration: .init(maximumRPM: 10_000),
        modifiedAt: Date(timeIntervalSince1970: 1_786_701_600)
    )

    static let routeOrbit = VideoOverlayTemplate(
        id: UUID(uuidString: "3636E889-118A-4B63-AE78-C2664E289AB0")!,
        name: localized("Route Orbit"),
        style: .arcade,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .topLeading,
                scale: .medium,
                accent: .mint,
                kind: .routeMapCircular,
                landscapePosition: .init(x: 0.18, y: 0.26),
                portraitPosition: .init(x: 0.5, y: 0.2)
            ),
            VideoOverlayElement(
                metric: .rpm,
                slot: .bottomTrailing,
                scale: .small,
                accent: .orange,
                kind: .carbonTach,
                landscapePosition: .init(x: 0.83, y: 0.73),
                portraitPosition: .init(x: 0.5, y: 0.79)
            )
        ],
        gaugeConfiguration: .init(maximumRPM: 9_000),
        modifiedAt: Date(timeIntervalSince1970: 1_786_788_000)
    )

    static let pursuitMap = VideoOverlayTemplate(
        id: UUID(uuidString: "ED8AE90E-6126-49C0-A1D5-6B636F2CD661")!,
        name: localized("Pursuit Map"),
        style: .racing,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .topTrailing,
                scale: .medium,
                accent: .red,
                kind: .routeMap,
                landscapePosition: .init(x: 0.81, y: 0.24),
                portraitPosition: .init(x: 0.5, y: 0.2)
            ),
            VideoOverlayElement(
                metric: .rpm,
                slot: .bottomLeading,
                scale: .small,
                accent: .red,
                kind: .blacklistTach,
                landscapePosition: .init(x: 0.18, y: 0.73),
                portraitPosition: .init(x: 0.5, y: 0.79)
            )
        ],
        gaugeConfiguration: .init(maximumRPM: 10_000),
        modifiedAt: Date(timeIntervalSince1970: 1_786_788_000)
    )

    static let routeChase = VideoOverlayTemplate(
        id: UUID(uuidString: "A9134DE3-E7CD-4D34-B065-C63386E59EC1")!,
        name: localized("Route Chase"),
        style: .arcade,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .topLeading,
                scale: .medium,
                accent: .blue,
                kind: .routeMapFollow,
                landscapePosition: .init(x: 0.18, y: 0.26),
                portraitPosition: .init(x: 0.5, y: 0.2)
            ),
            VideoOverlayElement(
                metric: .rpm,
                slot: .bottomTrailing,
                scale: .small,
                accent: .blue,
                kind: .neonTach,
                landscapePosition: .init(x: 0.83, y: 0.73),
                portraitPosition: .init(x: 0.5, y: 0.79)
            )
        ],
        gaugeConfiguration: .init(maximumRPM: 10_000),
        modifiedAt: Date(timeIntervalSince1970: 1_786_874_400)
    )

    static let streetAtlas = VideoOverlayTemplate(
        id: UUID(uuidString: "13223B5A-C41A-43EA-8C84-190AE9295C2B")!,
        name: localized("Street Atlas"),
        style: .minimal,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .topLeading,
                scale: .medium,
                accent: .blue,
                kind: .routeMapLight,
                landscapePosition: .init(x: 0.2, y: 0.24),
                portraitPosition: .init(x: 0.5, y: 0.19)
            )
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_786_960_800)
    )

    static let iceOrbit = VideoOverlayTemplate(
        id: UUID(uuidString: "301B2C62-5EA2-4FC3-A765-E818413AE73C")!,
        name: localized("Ice Orbit"),
        style: .minimal,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .topLeading,
                scale: .medium,
                accent: .ice,
                kind: .routeMapLightCircular,
                landscapePosition: .init(x: 0.18, y: 0.26),
                portraitPosition: .init(x: 0.5, y: 0.2)
            )
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_786_960_800)
    )

    static let amberRun = VideoOverlayTemplate(
        id: UUID(uuidString: "A222C1C3-70E8-450A-964E-D13E90D22BCC")!,
        name: localized("Amber Run"),
        style: .racing,
        elements: [
            VideoOverlayElement(
                metric: .speed,
                slot: .topTrailing,
                scale: .medium,
                accent: .orange,
                kind: .routeMapAmber,
                landscapePosition: .init(x: 0.8, y: 0.24),
                portraitPosition: .init(x: 0.5, y: 0.19)
            )
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_786_960_800)
    )

    static let factoryTemplates: [VideoOverlayTemplate] = [
        .racing, .arcade, .minimal, .portrait, .streetLegends,
        .neonCircuit, .blacklistClassic, .carbonGold, .streetShift,
        .routeRadar, .routeOrbit, .pursuitMap, .routeChase,
        .streetAtlas, .iceOrbit, .amberRun
    ]

    func migratedToFreeformLayout() -> VideoOverlayTemplate {
        guard layoutVersion < 2 else { return self }
        if let factory = Self.factoryTemplates.first(where: { $0.id == id }) {
            return factory
        }

        var migrated = self
        var slotCounts: [VideoOverlaySlot: Int] = [:]
        migrated.elements = elements.map { element in
            var value = element
            let index = slotCounts[element.slot, default: 0]
            slotCounts[element.slot] = index + 1
            let base = VideoOverlayPosition.fallback(for: element.slot)
            let direction = element.slot.rawValue.hasPrefix("top") ? 1.0 : -1.0
            value.landscapePosition = .init(x: base.x, y: base.y + direction * Double(index) * 0.14)
            value.portraitPosition = value.landscapePosition
            return value
        }
        migrated.layoutVersion = 2
        migrated.modifiedAt = .now
        return migrated
    }
}

@MainActor
final class VideoOverlayTemplateStore: ObservableObject {
    @Published private(set) var templates: [VideoOverlayTemplate]
    @Published var selectedTemplateID: UUID {
        didSet { defaults.set(selectedTemplateID.uuidString, forKey: selectedKey) }
    }

    private let defaults: UserDefaults
    private let templatesKey: String
    private let selectedKey: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "TougeDash.videoOverlay") {
        self.defaults = defaults
        templatesKey = "\(keyPrefix).templates.v1"
        selectedKey = "\(keyPrefix).selected.v1"

        let storedTemplates: [VideoOverlayTemplate]
        if let data = defaults.data(forKey: templatesKey),
           let decoded = try? JSONDecoder.tougeDashCloud().decode([VideoOverlayTemplate].self, from: data),
           !decoded.isEmpty {
            let migrated = decoded.map { $0.migratedToFreeformLayout() }
            let existingIDs = Set(migrated.map(\.id))
            storedTemplates = migrated + VideoOverlayTemplate.factoryTemplates.filter { !existingIDs.contains($0.id) }
        } else {
            storedTemplates = VideoOverlayTemplate.factoryTemplates
        }
        templates = storedTemplates

        let requested = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
        selectedTemplateID = requested.flatMap { id in storedTemplates.contains(where: { $0.id == id }) ? id : nil }
            ?? storedTemplates[0].id
        persist()
    }

    var selectedTemplate: VideoOverlayTemplate {
        templates.first(where: { $0.id == selectedTemplateID }) ?? templates[0]
    }

    func template(id: UUID?) -> VideoOverlayTemplate {
        guard let id else { return selectedTemplate }
        return templates.first(where: { $0.id == id }) ?? selectedTemplate
    }

    func select(_ id: UUID) {
        guard templates.contains(where: { $0.id == id }) else { return }
        selectedTemplateID = id
    }

    func save(_ template: VideoOverlayTemplate) {
        var value = template
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.name.isEmpty { value.name = localized("Moja nakładka") }
        value.modifiedAt = .now
        if let index = templates.firstIndex(where: { $0.id == value.id }) {
            templates[index] = value
        } else {
            templates.append(value)
        }
        selectedTemplateID = value.id
        persist()
    }

    func createCopy(of source: VideoOverlayTemplate? = nil) -> VideoOverlayTemplate {
        let source = source ?? selectedTemplate
        return VideoOverlayTemplate(
            name: String(format: localized("Kopia %@"), source.name),
            style: source.style,
            elements: source.elements.map {
                VideoOverlayElement(
                    metric: $0.metric,
                    slot: $0.slot,
                    scale: $0.scale,
                    sizeMultiplier: $0.sizeMultiplier,
                    mapZoom: $0.mapZoom,
                    accent: $0.accent,
                    kind: $0.kind,
                    landscapePosition: $0.landscapePosition,
                    portraitPosition: $0.portraitPosition
                )
            },
            gaugeConfiguration: source.gaugeConfiguration
        )
    }

    func delete(_ id: UUID) {
        guard templates.count > 1 else { return }
        templates.removeAll { $0.id == id }
        if selectedTemplateID == id { selectedTemplateID = templates[0].id }
        persist()
    }

    func restoreFactoryTemplates() {
        templates = VideoOverlayTemplate.factoryTemplates
        selectedTemplateID = templates[0].id
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder.tougeDashCloud().encode(templates) else { return }
        defaults.set(data, forKey: templatesKey)
        defaults.set(selectedTemplateID.uuidString, forKey: selectedKey)
    }
}
