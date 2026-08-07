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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .digital: localized("Wartość cyfrowa")
        case .gauge: localized("Zegar")
        case .bar: localized("Pasek")
        }
    }

    var icon: String {
        switch self {
        case .digital: "number"
        case .gauge: "gauge.with.dots.needle.67percent"
        case .bar: "chart.bar.fill"
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

    var effectiveScale: Double { scale.multiplier * sizeMultiplier }

    private static func clampedSizeMultiplier(_ value: Double) -> Double {
        min(2.5, max(0.45, value))
    }

    private enum CodingKeys: String, CodingKey {
        case id, metric, slot, scale, sizeMultiplier, accent, kind, landscapePosition, portraitPosition
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
    var modifiedAt: Date
    var layoutVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        style: VideoOverlayStyle,
        elements: [VideoOverlayElement],
        modifiedAt: Date = .now,
        layoutVersion: Int = 2
    ) {
        self.id = id
        self.name = name
        self.style = style
        self.elements = elements
        self.modifiedAt = modifiedAt
        self.layoutVersion = layoutVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, style, elements, modifiedAt, layoutVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        style = try container.decode(VideoOverlayStyle.self, forKey: .style)
        elements = try container.decode([VideoOverlayElement].self, forKey: .elements)
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

    static let factoryTemplates: [VideoOverlayTemplate] = [.racing, .arcade, .minimal, .portrait]

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
            storedTemplates = decoded.map { $0.migratedToFreeformLayout() }
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
                    accent: $0.accent,
                    kind: $0.kind,
                    landscapePosition: $0.landscapePosition,
                    portraitPosition: $0.portraitPosition
                )
            }
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
