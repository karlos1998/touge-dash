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
