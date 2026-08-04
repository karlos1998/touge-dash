import Combine
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: localized("Mały")
        case .medium: localized("Średni")
        case .large: localized("Duży")
        }
    }

    var multiplier: Double {
        switch self {
        case .small: 0.72
        case .medium: 1
        case .large: 1.36
        }
    }
}

struct VideoOverlayElement: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var metric: DashboardMetric
    var slot: VideoOverlaySlot
    var scale: VideoOverlayScale
    var accent: DashboardAccent

    init(
        id: UUID = UUID(),
        metric: DashboardMetric,
        slot: VideoOverlaySlot,
        scale: VideoOverlayScale = .medium,
        accent: DashboardAccent = .cyan
    ) {
        self.id = id
        self.metric = metric
        self.slot = slot
        self.scale = scale
        self.accent = accent
    }
}

struct VideoOverlayTemplate: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var style: VideoOverlayStyle
    var elements: [VideoOverlayElement]
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        style: VideoOverlayStyle,
        elements: [VideoOverlayElement],
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.style = style
        self.elements = elements
        self.modifiedAt = modifiedAt
    }
}

extension VideoOverlayTemplate {
    static let racing = VideoOverlayTemplate(
        id: UUID(uuidString: "A3244DA4-BF04-4CD1-88C7-040049050409")!,
        name: localized("Touge Racing"),
        style: .racing,
        elements: [
            VideoOverlayElement(metric: .speed, slot: .bottomLeading, scale: .large, accent: .ice),
            VideoOverlayElement(metric: .rpm, slot: .bottomCenter, scale: .large, accent: .yellow),
            VideoOverlayElement(metric: .boost, slot: .bottomTrailing, scale: .large, accent: .cyan),
            VideoOverlayElement(metric: .oilPressure, slot: .topLeading, accent: .mint),
            VideoOverlayElement(metric: .oilTemperature, slot: .topCenter, accent: .orange),
            VideoOverlayElement(metric: .coolant, slot: .topTrailing, accent: .ice)
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    static let arcade = VideoOverlayTemplate(
        id: UUID(uuidString: "6876D0C8-3A6E-4E4B-B149-2D69D80C6260")!,
        name: localized("Neon Arcade"),
        style: .arcade,
        elements: [
            VideoOverlayElement(metric: .speed, slot: .topLeading, scale: .large, accent: .cyan),
            VideoOverlayElement(metric: .rpm, slot: .topTrailing, scale: .large, accent: .orange),
            VideoOverlayElement(metric: .boost, slot: .bottomLeading, scale: .large, accent: .mint),
            VideoOverlayElement(metric: .afr, slot: .bottomCenter, accent: .white),
            VideoOverlayElement(metric: .oilPressure, slot: .bottomTrailing, accent: .yellow)
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    static let minimal = VideoOverlayTemplate(
        id: UUID(uuidString: "8F68844A-F195-46F4-817E-94A8040B75C1")!,
        name: localized("Clean Drive"),
        style: .minimal,
        elements: [
            VideoOverlayElement(metric: .speed, slot: .bottomLeading, scale: .large, accent: .white),
            VideoOverlayElement(metric: .boost, slot: .bottomTrailing, accent: .cyan),
            VideoOverlayElement(metric: .oilTemperature, slot: .topTrailing, accent: .orange)
        ],
        modifiedAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    static let factoryTemplates: [VideoOverlayTemplate] = [.racing, .arcade, .minimal]
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
            storedTemplates = decoded
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
                VideoOverlayElement(metric: $0.metric, slot: $0.slot, scale: $0.scale, accent: $0.accent)
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
