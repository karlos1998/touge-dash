import Combine
import Foundation

@MainActor
final class DashboardTemplateStore: ObservableObject {
    enum SyncState: Equatable {
        case localOnly
        case pending
        case syncing
        case synchronized(Date)
        case failed(String)
    }

    @Published private(set) var records: [DashboardTemplateRecord]
    @Published var activeTemplateID: UUID {
        didSet {
            defaults.set(activeTemplateID.uuidString, forKey: activeTemplateKey)
        }
    }
    @Published private(set) var syncState: SyncState = .localOnly

    private let defaults: UserDefaults
    private let recordsKey: String
    private let activeTemplateKey: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "TougeDash.dashboard") {
        self.defaults = defaults
        recordsKey = "\(keyPrefix).templates.v1"
        activeTemplateKey = "\(keyPrefix).activeTemplate.v1"

        var initialRecords: [DashboardTemplateRecord]
        if let data = defaults.data(forKey: recordsKey),
           let decoded = try? JSONDecoder.tougeDashCloud().decode([DashboardTemplateRecord].self, from: data),
           !decoded.isEmpty {
            initialRecords = decoded
        } else {
            initialRecords = [.factory()]
        }

        #if DEBUG
        if ProcessInfo.processInfo.environment["TOUGE_DASH_DASHBOARD_STRESS_PREVIEW"] == "1" {
            var stress = DashboardTemplateRecord.factory()
            if let boostIndex = stress.definition.widgets.firstIndex(where: { $0.primaryMetric == .boost }) {
                stress.definition.widgets[boostIndex].kind = .gauge
                stress.definition.widgets[boostIndex].wideKind = nil
                stress.definition.widgets[boostIndex].landscapeSpan = .third
            }
            initialRecords = [stress]
        }
        #endif

        if initialRecords.allSatisfy({ $0.deletedAt != nil }) {
            initialRecords.append(.factory())
        }
        let needsPageOrderMigration = initialRecords.contains {
            $0.deletedAt == nil && $0.definition.pageOrder == nil
        }
        if needsPageOrderMigration {
            var nextOrder = 0
            for index in initialRecords.indices where initialRecords[index].deletedAt == nil {
                initialRecords[index].definition.pageOrder = nextOrder
                initialRecords[index].modifiedAt = .now
                nextOrder += 1
            }
        }
        let storedActive = defaults.string(forKey: activeTemplateKey).flatMap(UUID.init(uuidString:))
        let visibleIDs = Set(initialRecords.filter { $0.deletedAt == nil }.map(\.id))
        records = initialRecords
        activeTemplateID = storedActive.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? initialRecords.first(where: { $0.deletedAt == nil })?.id
            ?? DashboardTemplateRecord.factoryID
        persist()
        if needsPageOrderMigration {
            syncState = .pending
        }
    }

    var templates: [DashboardTemplateRecord] {
        records
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.id == $1.id { return false }
                let lhsOrder = $0.definition.pageOrder ?? .max
                let rhsOrder = $1.definition.pageOrder ?? .max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    var activePageIndex: Int {
        templates.firstIndex(where: { $0.id == activeTemplateID }) ?? 0
    }

    var activeTemplate: DashboardTemplateRecord {
        templates.first(where: { $0.id == activeTemplateID })
            ?? templates.first
            ?? .factory()
    }

    var synchronizationRecords: [DashboardTemplateRecord] { records }

    @discardableResult
    func createCopy(of source: DashboardTemplateRecord? = nil, name: String? = nil) -> DashboardTemplateRecord {
        let source = source ?? activeTemplate
        var newRecord = DashboardTemplateRecord(
            name: name ?? String(format: localized("Kopia %@"), source.name),
            definition: source.definition
        )
        newRecord.definition.pageOrder = templates.count
        records.append(newRecord)
        activeTemplateID = newRecord.id
        markLocalChange()
        return newRecord
    }

    @discardableResult
    func createPage(atStart: Bool) -> DashboardTemplateRecord {
        let source = activeTemplate
        var newRecord = DashboardTemplateRecord(
            name: String(format: localized("Ekran %d"), templates.count + 1),
            definition: source.definition
        )
        newRecord.definition.pageOrder = atStart ? 0 : templates.count
        records.append(newRecord)
        reorderPages(moving: newRecord.id, to: atStart ? 0 : templates.count)
        activeTemplateID = newRecord.id
        markLocalChange()
        return newRecord
    }

    func save(_ record: DashboardTemplateRecord) {
        var updated = record
        updated.schemaVersion = DashboardTemplateRecord.schemaVersion
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.name.isEmpty { updated.name = localized("Mój dashboard") }
        updated.modifiedAt = .now
        updated.deletedAt = nil
        normalize(&updated)

        if let index = records.firstIndex(where: { $0.id == updated.id }) {
            records[index] = updated
        } else {
            records.append(updated)
        }
        activeTemplateID = updated.id
        markLocalChange()
    }

    @discardableResult
    func updateActiveWidget(_ widget: DashboardWidget) -> Bool {
        var template = activeTemplate
        guard let index = template.definition.widgets.firstIndex(where: { $0.id == widget.id }) else {
            return false
        }
        template.definition.widgets[index] = widget
        save(template)
        return true
    }

    @discardableResult
    func removeActiveWidget(_ id: UUID) -> Bool {
        var template = activeTemplate
        guard template.definition.widgets.count > 1,
              let index = template.definition.widgets.firstIndex(where: { $0.id == id }) else {
            return false
        }
        template.definition.widgets.remove(at: index)
        normalizeOrdersAfterListChange(&template)
        save(template)
        return true
    }

    @discardableResult
    func swapActiveWidgets(_ sourceID: UUID, _ destinationID: UUID, isWide: Bool) -> Bool {
        guard sourceID != destinationID else { return false }
        var template = activeTemplate
        guard let sourceIndex = template.definition.widgets.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = template.definition.widgets.firstIndex(where: { $0.id == destinationID }) else {
            return false
        }

        if isWide {
            let sourceOrder = template.definition.widgets[sourceIndex].landscapeOrder
            template.definition.widgets[sourceIndex].landscapeOrder = template.definition.widgets[destinationIndex].landscapeOrder
            template.definition.widgets[destinationIndex].landscapeOrder = sourceOrder
        } else {
            let sourceOrder = template.definition.widgets[sourceIndex].portraitOrder
            template.definition.widgets[sourceIndex].portraitOrder = template.definition.widgets[destinationIndex].portraitOrder
            template.definition.widgets[destinationIndex].portraitOrder = sourceOrder
        }
        save(template)
        return true
    }

    func select(_ id: UUID) {
        guard records.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        activeTemplateID = id
    }

    @discardableResult
    func selectAdjacentPage(offset: Int) -> Bool {
        let pages = templates
        guard let index = pages.firstIndex(where: { $0.id == activeTemplateID }) else { return false }
        let destination = index + offset
        guard pages.indices.contains(destination) else { return false }
        activeTemplateID = pages[destination].id
        return true
    }

    func delete(_ id: UUID) {
        let pagesBeforeDeletion = templates
        guard pagesBeforeDeletion.count > 1,
              let index = records.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        let deletedPageIndex = pagesBeforeDeletion.firstIndex(where: { $0.id == id }) ?? 0
        let now = Date.now
        records[index].deletedAt = now
        records[index].modifiedAt = now
        if activeTemplateID == id {
            let remaining = pagesBeforeDeletion.filter { $0.id != id }
            activeTemplateID = remaining[min(deletedPageIndex, remaining.count - 1)].id
        }
        normalizePageOrders(modifiedAt: now)
        markLocalChange()
    }

    func restoreFactoryTemplate() {
        var factory = DashboardTemplateRecord.factory(modifiedAt: .now)
        factory.definition.pageOrder = records.first(where: { $0.id == DashboardTemplateRecord.factoryID })?.definition.pageOrder ?? 0
        if let index = records.firstIndex(where: { $0.id == DashboardTemplateRecord.factoryID }) {
            records[index] = factory
        } else {
            records.append(factory)
        }
        activeTemplateID = factory.id
        markLocalChange()
    }

    func markSyncing() {
        syncState = .syncing
    }

    func markSignedOut() {
        syncState = .localOnly
    }

    func markSyncFailed(_ error: Error) {
        syncState = .failed(error.localizedDescription)
    }

    func mergeFromServer(_ remote: [DashboardTemplateRecord], synchronizedAt: Date = .now) {
        for incoming in remote where incoming.schemaVersion <= DashboardTemplateRecord.schemaVersion {
            if let index = records.firstIndex(where: { $0.id == incoming.id }) {
                if incoming.modifiedAt >= records[index].modifiedAt {
                    records[index] = incoming
                }
            } else {
                records.append(incoming)
            }
        }

        if !records.contains(where: { $0.id == activeTemplateID && $0.deletedAt == nil }) {
            activeTemplateID = records.first(where: { $0.deletedAt == nil })?.id ?? DashboardTemplateRecord.factoryID
        }
        if records.allSatisfy({ $0.deletedAt != nil }) {
            records.append(.factory())
            activeTemplateID = DashboardTemplateRecord.factoryID
        }
        normalizeMissingPageOrders()
        persist()
        syncState = .synchronized(synchronizedAt)
    }

    private func markLocalChange() {
        persist()
        syncState = .pending
    }

    private func persist() {
        guard let data = try? JSONEncoder.tougeDashCloud().encode(records) else { return }
        defaults.set(data, forKey: recordsKey)
        defaults.set(activeTemplateID.uuidString, forKey: activeTemplateKey)
    }

    private func normalize(_ record: inout DashboardTemplateRecord) {
        record.definition.widgets = record.definition.widgets.map { widget in
            var value = widget
            let isControl = value.kind == .ecuSwitch || value.kind == .ecuRotary
            if value.metrics.isEmpty && value.kind != .performance && !isControl { value.metrics = [.boost] }
            if value.kind == .performance || isControl { value.metrics = [] }
            if value.kind == .group { value.metrics = Array(value.metrics.prefix(3)) }
            if value.kind != .group && value.kind != .hero && value.kind != .performance && !isControl {
                value.metrics = [value.primaryMetric]
            }
            if isControl {
                value.controlChannel = min(8, max(1, value.controlChannel ?? 1))
                value.wideKind = nil
            } else {
                value.controlChannel = nil
            }
            return value
        }
        normalizeOrder(in: &record, isWide: false)
        normalizeOrder(in: &record, isWide: true)
    }

    private func normalizeOrdersAfterListChange(_ record: inout DashboardTemplateRecord) {
        normalizeOrder(in: &record, isWide: false)
        normalizeOrder(in: &record, isWide: true)
    }

    private func normalizeOrder(in record: inout DashboardTemplateRecord, isWide: Bool) {
        let orderedIDs = record.definition.widgets
            .sorted { lhs, rhs in
                let lhsOrder = isWide ? lhs.landscapeOrder : lhs.portraitOrder
                let rhsOrder = isWide ? rhs.landscapeOrder : rhs.portraitOrder
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(\.id)

        for (order, id) in orderedIDs.enumerated() {
            guard let index = record.definition.widgets.firstIndex(where: { $0.id == id }) else { continue }
            if isWide {
                record.definition.widgets[index].landscapeOrder = order
            } else {
                record.definition.widgets[index].portraitOrder = order
            }
        }
    }

    private func reorderPages(moving id: UUID, to destination: Int) {
        var pageIDs = templates.map(\.id).filter { $0 != id }
        pageIDs.insert(id, at: min(max(0, destination), pageIDs.count))
        let now = Date.now
        for (order, pageID) in pageIDs.enumerated() {
            guard let index = records.firstIndex(where: { $0.id == pageID }) else { continue }
            records[index].definition.pageOrder = order
            records[index].modifiedAt = now
        }
    }

    private func normalizePageOrders(modifiedAt: Date) {
        let pageIDs = templates.map(\.id)
        for (order, pageID) in pageIDs.enumerated() {
            guard let index = records.firstIndex(where: { $0.id == pageID }) else { continue }
            records[index].definition.pageOrder = order
            records[index].modifiedAt = modifiedAt
        }
    }

    private func normalizeMissingPageOrders() {
        let ordered = records
            .filter { $0.deletedAt == nil }
            .sorted {
                let lhs = $0.definition.pageOrder ?? .max
                let rhs = $1.definition.pageOrder ?? .max
                return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
            }
        for (order, page) in ordered.enumerated() {
            guard let index = records.firstIndex(where: { $0.id == page.id }) else { continue }
            records[index].definition.pageOrder = order
        }
    }
}
