import CoreBluetooth
import SwiftData
import XCTest
@testable import TougeDash

final class EMUProtocolTests: XCTestCase {
    func testParsesFrameSplitAcrossBluetoothNotifications() {
        var parser = EMUFrameParser()
        let frame = Array(EMUFrameParser.encode(channel: 1, rawValue: 6_420))

        XCTAssertTrue(parser.feed(Data(frame.prefix(2))).isEmpty)
        XCTAssertEqual(parser.feed(Data(frame.dropFirst(2))), [EMUFrame(channel: 1, rawValue: 6_420)])
        XCTAssertEqual(parser.stats.validFrames, 1)
        XCTAssertEqual(parser.stats.badChecksums, 0)
    }

    func testRecoversAfterNoiseAndBadChecksum() {
        var parser = EMUFrameParser()
        var payload = Data([0xDE, 0xAD, 0xBE])
        var damaged = Array(EMUFrameParser.encode(channel: 3, rawValue: 84))
        damaged[4] &+= 1
        payload.append(contentsOf: damaged)
        payload.append(EMUFrameParser.encode(channel: 5, rawValue: 511))

        XCTAssertEqual(parser.feed(payload), [EMUFrame(channel: 5, rawValue: 511)])
        XCTAssertEqual(parser.stats.validFrames, 1)
        XCTAssertGreaterThanOrEqual(parser.stats.badChecksums, 1)
        XCTAssertGreaterThanOrEqual(parser.stats.droppedBytes, 4)
    }

    func testMapsScaledEngineChannels() {
        var accumulator = EMUTelemetryAccumulator()
        accumulator.apply(EMUFrame(channel: 14, rawValue: 100))
        accumulator.apply(EMUFrame(channel: 2, rawValue: 220))
        accumulator.apply(EMUFrame(channel: 5, rawValue: 511))
        accumulator.apply(EMUFrame(channel: 21, rawValue: 64))
        accumulator.apply(EMUFrame(channel: 27, rawValue: 128))
        accumulator.apply(EMUFrame(channel: 28, rawValue: 512))

        XCTAssertEqual(accumulator.snapshot.boostBar, 1.2, accuracy: 0.001)
        XCTAssertEqual(accumulator.snapshot.batteryVoltage, 511.0 / 37.0, accuracy: 0.001)
        XCTAssertEqual(accumulator.snapshot.oilPressureBar, 4, accuracy: 0.001)
        XCTAssertEqual(accumulator.snapshot.lambda, 1, accuracy: 0.001)
        XCTAssertEqual(accumulator.snapshot.speedKPH, 128, accuracy: 0.001)
    }

    func testMapsSignedTemperaturesAndCelMask() {
        var accumulator = EMUTelemetryAccumulator()
        let minusFive = UInt16(bitPattern: Int16(-5))
        accumulator.apply(EMUFrame(channel: 24, rawValue: minusFive))
        accumulator.apply(EMUFrame(channel: 4, rawValue: UInt16(UInt8(bitPattern: -12))))
        accumulator.apply(EMUFrame(channel: 255, rawValue: 0x0040))

        XCTAssertEqual(accumulator.snapshot.coolantCelsius, -5)
        XCTAssertEqual(accumulator.snapshot.intakeCelsius, -12)
        XCTAssertTrue(accumulator.snapshot.hasCheckEngine)
        XCTAssertTrue(accumulator.snapshot.hasCriticalWarning)
    }

    func testEncoderUsesProtocolMarkerAndChecksum() {
        let encoded = Array(EMUFrameParser.encode(channel: 12, rawValue: 124))

        XCTAssertEqual(encoded.count, 5)
        XCTAssertEqual(encoded[1], 0xA3)
        XCTAssertEqual(encoded[4], UInt8(truncatingIfNeeded: encoded[0...3].reduce(0) { $0 + Int($1) }))
    }

    func testWatchPayloadKeepsDashboardMetrics() {
        let payload = WatchTelemetryPayload(snapshot: .preview)

        XCTAssertEqual(payload.boostBar, 1.18)
        XCTAssertEqual(payload.afr, 12.4)
        XCTAssertEqual(payload.oilPressureBar, 4.2)
        XCTAssertEqual(payload.oilTemperatureCelsius, 104)
        XCTAssertEqual(payload.coolantCelsius, 91)
        XCTAssertFalse(payload.hasCriticalWarning)
    }

    func testWatchPayloadDetectsOilWarnings() {
        let lowPressure = WatchTelemetryPayload(
            boostBar: 0,
            afr: 14.7,
            oilPressureBar: 0.3,
            oilTemperatureCelsius: 100,
            coolantCelsius: 90,
            rpm: 3_000,
            hasCriticalWarning: true,
            updatedAt: .now
        )
        let hotOil = WatchTelemetryPayload(
            boostBar: 0,
            afr: 14.7,
            oilPressureBar: 4,
            oilTemperatureCelsius: 145,
            coolantCelsius: 90,
            rpm: 3_000,
            hasCriticalWarning: true,
            updatedAt: .now
        )

        XCTAssertTrue(lowPressure.hasOilPressureWarning)
        XCTAssertFalse(lowPressure.hasOilTemperatureWarning)
        XCTAssertFalse(hotOil.hasOilPressureWarning)
        XCTAssertTrue(hotOil.hasOilTemperatureWarning)
    }

    func testWatchPayloadDetectsHotCoolant() {
        let payload = WatchTelemetryPayload(
            boostBar: 0,
            afr: 14.7,
            oilPressureBar: 4,
            oilTemperatureCelsius: 100,
            coolantCelsius: 112,
            rpm: 3_000,
            hasCriticalWarning: true,
            updatedAt: .now
        )

        XCTAssertTrue(payload.hasCoolantWarning)
    }

    func testTemperatureWarningsStartAtConfiguredLimits() {
        var snapshot = TelemetrySnapshot.preview
        snapshot.coolantCelsius = EngineTemperatureLimits.coolantWarningCelsius
        snapshot.oilTemperatureCelsius = EngineTemperatureLimits.oilWarningCelsius - 1

        XCTAssertTrue(snapshot.hasTemperatureWarning)

        snapshot.coolantCelsius = EngineTemperatureLimits.coolantWarningCelsius - 1
        snapshot.oilTemperatureCelsius = EngineTemperatureLimits.oilWarningCelsius

        XCTAssertTrue(snapshot.hasTemperatureWarning)
        XCTAssertTrue(WatchTelemetryPayload(snapshot: snapshot).hasTemperatureWarning)

        snapshot.oilTemperatureCelsius = EngineTemperatureLimits.oilWarningCelsius - 1

        XCTAssertFalse(snapshot.hasTemperatureWarning)
        XCTAssertFalse(WatchTelemetryPayload(snapshot: snapshot).hasTemperatureWarning)
    }

    @MainActor
    func testHistoryRecorderSamplesAtTenHertzAndSplitsLongGaps() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DriveSession.self,
            TelemetryHistorySample.self,
            DriveIncident.self,
            TimelineAnnotation.self,
            configurations: configuration
        )
        UserDefaults.standard.set(false, forKey: LocationTrackingService.enabledDefaultsKey)
        let locationTracker = LocationTrackingService()
        let recorder = TelemetryHistoryRecorder(container: container, locationTracker: locationTracker)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let firstChange = recorder.record(.preview, at: start)
        let throttledChange = recorder.record(.preview, at: start.addingTimeInterval(0.04))
        let sameSessionChange = recorder.record(.preview, at: start.addingTimeInterval(0.11))
        let nextSessionChange = recorder.record(.preview, at: start.addingTimeInterval(TelemetryHistoryRecorder.newSessionGap + 2))
        recorder.saveNow()

        let sessions = try container.mainContext.fetch(FetchDescriptor<DriveSession>())
        let samples = try container.mainContext.fetch(FetchDescriptor<TelemetryHistorySample>())

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(sessions.map(\.sampleCount).reduce(0, +), 3)
        XCTAssertEqual(sessions.map(\.maxRPM).max(), TelemetrySnapshot.preview.rpm)
        XCTAssertEqual(sessions.map(\.maxBoostBar).max(), TelemetrySnapshot.preview.boostBar)
        XCTAssertEqual(firstChange?.sessionBecamePending, true)
        XCTAssertNil(throttledChange)
        XCTAssertEqual(sameSessionChange?.sessionBecamePending, false)
        XCTAssertEqual(nextSessionChange?.sessionBecamePending, true)
        XCTAssertEqual(firstChange?.sessionID, sameSessionChange?.sessionID)
        XCTAssertNotEqual(firstChange?.sessionID, nextSessionChange?.sessionID)
    }

    @MainActor
    func testHistoryRecorderNeverResumesAnotherLoggersRecentSession() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DriveSession.self,
            TelemetryHistorySample.self,
            DriveIncident.self,
            TimelineAnnotation.self,
            configurations: configuration
        )
        UserDefaults.standard.set(false, forKey: LocationTrackingService.enabledDefaultsKey)
        let recorder = TelemetryHistoryRecorder(
            container: container,
            locationTracker: LocationTrackingService()
        )
        let simulatorID = LocalVehicleIdentity.simulatorID
        let realLoggerID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        recorder.activateVehicle(simulatorID)
        let simulatorChange = recorder.record(.preview, at: start)
        recorder.activateVehicle(realLoggerID)
        let realLoggerChange = recorder.record(.preview, at: start.addingTimeInterval(1))
        recorder.saveNow()

        let sessions = try container.mainContext.fetch(FetchDescriptor<DriveSession>())
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(Set(sessions.map(\.vehicleID)), [simulatorID, realLoggerID])
        XCTAssertNotEqual(simulatorChange?.sessionID, realLoggerChange?.sessionID)
    }

    func testBluetoothPolicyNeverAllowsLoggerWrites() {
        let allProperties: CBCharacteristicProperties = [.read, .notify, .write, .writeWithoutResponse]

        XCTAssertTrue(BluetoothTelemetryAccessPolicy.shouldRead(allProperties))
        XCTAssertTrue(BluetoothTelemetryAccessPolicy.shouldSubscribe(to: allProperties))
        XCTAssertFalse(BluetoothTelemetryAccessPolicy.allowsCharacteristicWrites)
    }

    func testCloudSyncProgressTracksSamplesAndEmptySessions() {
        let samples = CloudSyncProgress(
            totalSessions: 2,
            totalIncidents: 1,
            totalAnnotations: 1,
            totalSamples: 1_000,
            completedSessions: 1,
            completedIncidents: 0,
            completedAnnotations: 0,
            completedSamples: 250,
            transferredBytes: 120_000
        )
        let emptySession = CloudSyncProgress(
            totalSessions: 2,
            totalIncidents: 1,
            totalAnnotations: 1,
            totalSamples: 0,
            completedSessions: 1,
            completedIncidents: 1,
            completedAnnotations: 0,
            completedSamples: 0,
            transferredBytes: 1_200
        )

        XCTAssertEqual(samples.fraction, 0.25, accuracy: 0.001)
        XCTAssertEqual(emptySession.fraction, 0.5, accuracy: 0.001)
    }

    func testPerItemCloudProgressTracksOnlyItsOwnSamples() {
        let uploading = CloudSyncItemStatus.uploading(
            completedSamples: 2_500,
            totalSamples: 10_000,
            transferredBytes: 820_000
        )
        let empty = CloudSyncItemStatus.uploading(
            completedSamples: 0,
            totalSamples: 0,
            transferredBytes: 128
        )

        XCTAssertEqual(try XCTUnwrap(uploading.fraction), 0.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(empty.fraction), 1, accuracy: 0.001)
        XCTAssertNil(CloudSyncItemStatus.blocked(.vehicleNotLinked).fraction)
        XCTAssertNil(CloudSyncItemStatus.failed("network").fraction)
    }
}
