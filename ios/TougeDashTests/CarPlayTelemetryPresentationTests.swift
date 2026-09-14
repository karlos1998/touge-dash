import XCTest
@testable import TougeDash

final class CarPlayTelemetryPresentationTests: XCTestCase {
    @MainActor
    func testSceneDelegateCanBeResolvedFromTheInfoPlistClassName() {
        XCTAssertNotNil(NSClassFromString("TougeDash.CarPlaySceneDelegate"))
    }

    func testFormatsLiveTelemetryForCarPlay() {
        var snapshot = TelemetrySnapshot.preview
        snapshot.updatedAt = Date(timeIntervalSince1970: 100)

        let presentation = CarPlayTelemetryPresentation(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(presentation.status, .live)
        XCTAssertFalse(presentation.afr.isEmpty)
        XCTAssertTrue(presentation.oilPressure.hasSuffix(" bar"))
        XCTAssertTrue(presentation.oilTemperature.hasSuffix(" °C"))
        XCTAssertTrue(presentation.coolantTemperature.hasSuffix(" °C"))
    }

    func testMarksExpiredTelemetryAsStale() {
        var snapshot = TelemetrySnapshot.preview
        snapshot.updatedAt = Date(timeIntervalSince1970: 100)

        let presentation = CarPlayTelemetryPresentation(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 103)
        )

        XCTAssertEqual(presentation.status, .stale)
    }

    func testPrioritizesCriticalAlertForFreshTelemetry() {
        var snapshot = TelemetrySnapshot.preview
        snapshot.updatedAt = Date(timeIntervalSince1970: 100)
        snapshot.checkEngineMask = 1

        let presentation = CarPlayTelemetryPresentation(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(presentation.status, .criticalAlert)
    }

    func testShowsTemperatureAlertSeparately() {
        var snapshot = TelemetrySnapshot.preview
        snapshot.updatedAt = Date(timeIntervalSince1970: 100)
        snapshot.coolantCelsius = 110

        let presentation = CarPlayTelemetryPresentation(
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 101)
        )

        XCTAssertEqual(presentation.status, .temperatureAlert)
    }
}
