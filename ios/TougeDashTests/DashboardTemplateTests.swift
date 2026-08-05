import XCTest
@testable import TougeDash

final class DashboardTemplateTests: XCTestCase {
    func testFactoryTemplateReproducesAdaptiveDashboardLayout() {
        let template = DashboardTemplateRecord.factory()
        let portrait = template.definition.widgets
            .filter { $0.portraitSpan != .hidden }
            .sorted { $0.portraitOrder < $1.portraitOrder }
        let landscape = template.definition.widgets
            .filter { $0.landscapeSpan != .hidden }
            .sorted { $0.landscapeOrder < $1.landscapeOrder }

        XCTAssertEqual(portrait.first?.primaryMetric, .boost)
        XCTAssertEqual(portrait.first?.kind, .hero)
        XCTAssertEqual(portrait[1].metrics, [.oilPressure, .oilTemperature, .coolant])
        XCTAssertEqual(landscape.first?.kind, .group)
        XCTAssertEqual(landscape[1].primaryMetric, .boost)
        XCTAssertEqual(landscape[1].wideKind, .value)
        XCTAssertEqual(portrait.count, 8)
        XCTAssertEqual(landscape.count, 10)
    }

    func testEveryMetricReadsCorrectSnapshotValue() {
        let snapshot = TelemetrySnapshot.preview

        XCTAssertEqual(DashboardMetric.rpm.value(in: snapshot), 6_420)
        XCTAssertEqual(DashboardMetric.boost.value(in: snapshot), 1.18)
        XCTAssertEqual(DashboardMetric.oilPressure.value(in: snapshot), 4.2)
        XCTAssertEqual(DashboardMetric.coolant.value(in: snapshot), 91)
        XCTAssertEqual(DashboardMetric.speed.value(in: snapshot), 128)
    }

    func testControlCardUsesCloudCompatibleDashboardSchema() throws {
        let widget = DashboardWidget(
            kind: .ecuSwitch,
            metrics: [],
            portraitSpan: .half,
            landscapeSpan: .third,
            portraitOrder: 0,
            controlChannel: 7,
            accent: .mint
        )
        let data = try JSONEncoder().encode(widget)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"kind\":\"ecuSwitch\""))
        XCTAssertTrue(json.contains("\"controlChannel\":7"))
        XCTAssertEqual(try JSONDecoder().decode(DashboardWidget.self, from: data), widget)
    }

    func testGridPacksWidgetsWithoutExceedingTwelveColumns() {
        let widgets = DashboardTemplateRecord.factory().definition.widgets
            .filter { $0.landscapeSpan != .hidden }
            .sorted { $0.landscapeOrder < $1.landscapeOrder }
        let rows = DashboardGridLayout.rows(for: widgets, isWide: true)

        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { row in
            row.reduce(0) { $0 + $1.landscapeSpan.rawValue } <= 12
        })
    }

    func testEveryWidgetKindAndSpanFitsACompactLandscapeGrid() {
        let widgets = DashboardWidgetKind.allCases.flatMap { kind in
            DashboardWidgetSpan.allCases.filter { $0 != .hidden }.enumerated().map { index, span in
                DashboardWidget(
                    kind: kind,
                    metrics: kind == .group ? [.oilPressure, .oilTemperature, .coolant] : [.boost],
                    portraitSpan: .full,
                    landscapeSpan: span,
                    portraitOrder: index
                )
            }
        }
        let rows = DashboardGridLayout.rows(for: widgets, isWide: true)

        XCTAssertFalse(rows.isEmpty)
        XCTAssertTrue(rows.allSatisfy { row in
            row.reduce(0) { $0 + $1.landscapeSpan.rawValue } <= 12
        })
        for widget in widgets {
            XCTAssertGreaterThan(DashboardGridLayout.height(for: widget, isWide: true, compact: true), 0)
            XCTAssertLessThanOrEqual(DashboardGridLayout.height(for: widget, isWide: true, compact: true), 150)
        }
    }

    func testViewportUsesLandscapeOnlyForActuallyHorizontalScreens() {
        XCTAssertTrue(DashboardViewport(size: CGSize(width: 844, height: 390)).usesLandscapeLayout)
        XCTAssertTrue(DashboardViewport(size: CGSize(width: 844, height: 390)).isCompactLandscape)
        XCTAssertFalse(DashboardViewport(size: CGSize(width: 390, height: 844)).usesLandscapeLayout)
        XCTAssertFalse(DashboardViewport(size: CGSize(width: 1024, height: 1366)).usesLandscapeLayout)
        XCTAssertTrue(DashboardViewport(size: CGSize(width: 1366, height: 1024)).usesLandscapeLayout)
    }

    @MainActor
    func testLocalTemplatesPersistAndNewestServerVersionWins() throws {
        let suite = "TougeDashTests.dashboard.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardTemplateStore(defaults: defaults, keyPrefix: suite)
        var edited = store.activeTemplate
        edited.name = "Track"
        store.save(edited)

        let reloaded = DashboardTemplateStore(defaults: defaults, keyPrefix: suite)
        XCTAssertEqual(reloaded.activeTemplate.name, "Track")

        let saved = reloaded.activeTemplate
        var stale = saved
        stale.name = "Stale"
        stale.modifiedAt = saved.modifiedAt.addingTimeInterval(-10)
        reloaded.mergeFromServer([stale])
        XCTAssertEqual(reloaded.activeTemplate.name, "Track")

        var newest = saved
        newest.name = "Online"
        newest.modifiedAt = saved.modifiedAt.addingTimeInterval(10)
        reloaded.mergeFromServer([newest])
        XCTAssertEqual(reloaded.activeTemplate.name, "Online")
    }

    @MainActor
    func testDashboardPagesKeepOrderNavigateAndNeverDeleteTheLastPage() throws {
        let suite = "TougeDashTests.dashboard.pages.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardTemplateStore(defaults: defaults, keyPrefix: suite)

        let trailing = store.createPage(atStart: false)
        let leading = store.createPage(atStart: true)
        XCTAssertEqual(store.templates.map(\.id), [leading.id, DashboardTemplateRecord.factoryID, trailing.id])
        XCTAssertEqual(store.activePageIndex, 0)

        XCTAssertTrue(store.selectAdjacentPage(offset: 1))
        XCTAssertEqual(store.activeTemplateID, DashboardTemplateRecord.factoryID)
        XCTAssertTrue(store.selectAdjacentPage(offset: 1))
        XCTAssertEqual(store.activeTemplateID, trailing.id)
        XCTAssertFalse(store.selectAdjacentPage(offset: 1))

        store.delete(trailing.id)
        store.delete(DashboardTemplateRecord.factoryID)
        XCTAssertEqual(store.templates.count, 1)
        store.delete(leading.id)
        XCTAssertEqual(store.templates.map(\.id), [leading.id])

        let reloaded = DashboardTemplateStore(defaults: defaults, keyPrefix: suite)
        XCTAssertEqual(reloaded.templates.map(\.id), [leading.id])
    }

    @MainActor
    func testServerTombstoneRemovesTemplateButKeepsAUsableDashboard() throws {
        let suite = "TougeDashTests.dashboard.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardTemplateStore(defaults: defaults, keyPrefix: suite)
        let second = store.createCopy(name: "Second")

        var tombstone = second
        tombstone.modifiedAt = .now.addingTimeInterval(5)
        tombstone.deletedAt = tombstone.modifiedAt
        store.mergeFromServer([tombstone])

        XCTAssertFalse(store.templates.contains(where: { $0.id == second.id }))
        XCTAssertFalse(store.templates.isEmpty)
        XCTAssertNotEqual(store.activeTemplateID, second.id)
    }

    @MainActor
    func testInlineEditorSwapsOnlyTheCurrentOrientationAndPersists() throws {
        let suite = "TougeDashTests.dashboard.inline.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardTemplateStore(defaults: defaults, keyPrefix: suite)
        let factory = store.activeTemplate
        let boost = try XCTUnwrap(factory.definition.widgets.first(where: { $0.primaryMetric == .boost }))
        let engineHealth = try XCTUnwrap(factory.definition.widgets.first(where: { $0.kind == .group }))

        XCTAssertTrue(store.swapActiveWidgets(boost.id, engineHealth.id, isWide: false))

        let updatedBoost = try XCTUnwrap(store.activeTemplate.definition.widgets.first(where: { $0.id == boost.id }))
        let updatedHealth = try XCTUnwrap(store.activeTemplate.definition.widgets.first(where: { $0.id == engineHealth.id }))
        XCTAssertEqual(updatedBoost.portraitOrder, 1)
        XCTAssertEqual(updatedHealth.portraitOrder, 0)
        XCTAssertEqual(updatedBoost.landscapeOrder, boost.landscapeOrder)
        XCTAssertEqual(updatedHealth.landscapeOrder, engineHealth.landscapeOrder)

        let reloaded = DashboardTemplateStore(defaults: defaults, keyPrefix: suite)
        XCTAssertEqual(reloaded.activeTemplate.definition.widgets.first(where: { $0.id == boost.id })?.portraitOrder, 1)
    }

    @MainActor
    func testInlineEditorUpdatesAndDeletesWidgetsWithoutLeavingAnEmptyDashboard() throws {
        let suite = "TougeDashTests.dashboard.inline-delete.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DashboardTemplateStore(defaults: defaults, keyPrefix: suite)
        var boost = try XCTUnwrap(store.activeTemplate.definition.widgets.first(where: { $0.primaryMetric == .boost }))
        boost.kind = .gauge
        boost.accent = .orange

        XCTAssertTrue(store.updateActiveWidget(boost))
        XCTAssertEqual(store.activeTemplate.definition.widgets.first(where: { $0.id == boost.id })?.kind, .gauge)
        XCTAssertEqual(store.activeTemplate.definition.widgets.first(where: { $0.id == boost.id })?.accent, .orange)

        while store.activeTemplate.definition.widgets.count > 1 {
            let id = try XCTUnwrap(store.activeTemplate.definition.widgets.last?.id)
            XCTAssertTrue(store.removeActiveWidget(id))
        }
        let lastID = try XCTUnwrap(store.activeTemplate.definition.widgets.first?.id)
        XCTAssertFalse(store.removeActiveWidget(lastID))
        XCTAssertEqual(store.activeTemplate.definition.widgets.count, 1)
    }

    @MainActor
    func testChartBufferSamplesAtFiveHertzAndFiltersDuration() {
        let buffer = DashboardTelemetryBuffer(retention: 600, samplesPerSecond: 5)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        buffer.record(.preview, now: start)
        buffer.record(.preview, now: start.addingTimeInterval(0.05))
        buffer.record(.preview, now: start.addingTimeInterval(0.21))
        buffer.record(.preview, now: start.addingTimeInterval(40))

        XCTAssertEqual(buffer.points.count, 3)
        XCTAssertEqual(buffer.points(for: .thirtySeconds, now: start.addingTimeInterval(40)).count, 1)
        XCTAssertEqual(buffer.points(for: .threeMinutes, now: start.addingTimeInterval(40)).count, 3)
    }
}
