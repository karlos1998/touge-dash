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
        let storedActive = defaults.string(forKey: activeTemplateKey).flatMap(UUID.init(uuidString:))
        let visibleIDs = Set(initialRecords.filter { $0.deletedAt == nil }.map(\.id))
        records = initialRecords
        activeTemplateID = storedActive.flatMap { visibleIDs.contains($0) ? $0 : nil }
            ?? initialRecords.first(where: { $0.deletedAt == nil })?.id
            ?? DashboardTemplateRecord.factoryID
        persist()
    }

    var templates: [DashboardTemplateRecord] {
        records
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.id == $1.id { return false }
                if $0.id == activeTemplateID { return true }
                if $1.id == activeTemplateID { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
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
        let newRecord = DashboardTemplateRecord(
            name: name ?? String(format: localized("Kopia %@"), source.name),
            definition: source.definition
        )
        records.append(newRecord)
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

    func select(_ id: UUID) {
        guard records.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        activeTemplateID = id
    }

    func delete(_ id: UUID) {
        guard templates.count > 1,
              let index = records.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        let now = Date.now
        records[index].deletedAt = now
        records[index].modifiedAt = now
        if activeTemplateID == id {
            activeTemplateID = records.first(where: { $0.deletedAt == nil })?.id ?? DashboardTemplateRecord.factoryID
        }
        markLocalChange()
    }

    func restoreFactoryTemplate() {
        let factory = DashboardTemplateRecord.factory(modifiedAt: .now)
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
        record.definition.widgets = record.definition.widgets.enumerated().map { index, widget in
            var value = widget
            value.portraitOrder = index
            value.landscapeOrder = index
            if value.metrics.isEmpty { value.metrics = [.boost] }
            if value.kind == .group { value.metrics = Array(value.metrics.prefix(3)) }
            if value.kind != .group && value.kind != .hero { value.metrics = [value.primaryMetric] }
            return value
        }
    }
}
