import CoreBluetooth
import SwiftData
import XCTest
@testable import TougeDash

final class EMUProtocolTests: XCTestCase {
    func testDriveShareSelectionClampsToANonEmptyRange() {
        XCTAssertEqual(
            DriveShareSelection(startOffsetMillis: 9_999, endOffsetMillis: 10_000),
            DriveShareSelection.normalized(
                driveDurationMillis: 10_000,
                startOffsetMillis: 20_000,
                endOffsetMillis: -5
            )
        )
    }

    func testDriveMetadataKeepsNameAndMultipleColoredTags() throws {
        let session = DriveSession(vehicleID: UUID(), startedAt: .now)
        let tags = [
            CloudDriveTag(id: UUID(), name: "Track", color: "#18D7E3"),
            CloudDriveTag(id: UUID(), name: "Wet", color: "#45E6A8")
        ]

        session.customName = "Boost run"
        session.driveTags = tags
        session.metadataDirty = true

        XCTAssertEqual(session.customName, "Boost run")
        XCTAssertEqual(session.driveTags, tags)
        XCTAssertEqual(session.metadataDirty, true)
    }

    @MainActor
    func testLiveActivityStartsBeforeBackgroundBluetoothScanning() async {
        var events: [String] = []

        await TelemetryBackgroundBootstrapper.start {
            events.append("activity")
            await Task.yield()
            events.append("activity-ready")
        } bluetooth: {
            events.append("bluetooth")
        }

        XCTAssertEqual(events, ["activity", "activity-ready", "bluetooth"])
    }

    @MainActor
    func testLocalHistoryRetentionKeepsTenNewestSessionsAndIncidentsWithTheirChildren() throws {
        let container = try ModelContainer(
            for: DriveSession.self,
            TelemetryHistorySample.self,
            DriveVideoRecording.self,
            DriveIncident.self,
            TimelineAnnotation.self,
            AccelerationAttempt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let vehicleID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var newestSessionIDs: [UUID] = []
        var newestIncidentIDs: [UUID] = []

        for index in 0..<12 {
            let timestamp = start.addingTimeInterval(Double(index))
            let session = DriveSession(vehicleID: vehicleID, startedAt: timestamp)
            let sample = TelemetryHistorySample(
                snapshot: .preview,
                timestamp: timestamp,
                session: session
            )
            let incident = DriveIncident(
                vehicleID: vehicleID,
                sessionID: session.id,
                kind: .overboost,
                severity: .warning,
                triggeredAt: timestamp,
                thresholdValue: 1.5,
                triggerValue: 1.7,
                triggerUnit: "bar",
                samples: []
            )
            context.insert(session)
            context.insert(sample)
            context.insert(incident)
            context.insert(TimelineAnnotation(
                vehicleID: vehicleID,
                sessionID: session.id,
                incidentID: incident.id,
                timestamp: timestamp,
                body: "Test"
            ))
            context.insert(AccelerationAttempt(
                sessionID: session.id,
                type: .zeroTo100,
                startedAt: timestamp,
                endedAt: timestamp.addingTimeInterval(5),
                durationMillis: 5_000,
                sampleRateHz: 10,
                shiftCount: 1,
                quality: "HIGH"
            ))
            context.insert(DriveVideoRecording(
                sessionID: session.id,
                fileName: "missing-\(index).mov",
                startedAt: timestamp,
                endedAt: timestamp.addingTimeInterval(1),
                duration: 1,
                fileSizeBytes: 1,
                pixelWidth: 1,
                pixelHeight: 1,
                framesPerSecond: 30,
                cameraName: "Test",
                hasAudio: false
            ))
            if index >= 2 {
                newestSessionIDs.append(session.id)
                newestIncidentIDs.append(incident.id)
            }
        }
        try context.save()

        try HistoryLocalStore.enforceRetention(in: context)

        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<DriveSession>()).map(\.id)), Set(newestSessionIDs))
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<DriveIncident>()).map(\.id)), Set(newestIncidentIDs))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TelemetryHistorySample>()), 10)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimelineAnnotation>()), 10)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AccelerationAttempt>()), 10)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DriveVideoRecording>()), 10)
    }

    @MainActor
    func testBackgroundHistoryDeletionRemovesDriveDataAndVideoFile() async throws {
        let container = try ModelContainer(
            for: DriveSession.self,
            TelemetryHistorySample.self,
            DriveVideoRecording.self,
            DriveIncident.self,
            TimelineAnnotation.self,
            AccelerationAttempt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let session = DriveSession(vehicleID: UUID(), startedAt: .now)
        let videoURL = try DriveVideoFileStore.newRecordingURL()
        try Data(repeating: 0xA5, count: 4_096).write(to: videoURL)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        context.insert(session)
        context.insert(TelemetryHistorySample(snapshot: .preview, timestamp: .now, session: session))
        context.insert(DriveVideoRecording(
            sessionID: session.id,
            fileName: videoURL.lastPathComponent,
            startedAt: .now,
            endedAt: .now.addingTimeInterval(1),
            duration: 1,
            fileSizeBytes: 4_096,
            pixelWidth: 1,
            pixelHeight: 1,
            framesPerSecond: 30,
            cameraName: "Test",
            hasAudio: false
        ))
        try context.save()

        let worker = HistoryDeletionWorker(modelContainer: container)
        try await worker.deleteSession(id: session.id)

        let verificationContext = ModelContext(container)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<DriveSession>()), 0)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<TelemetryHistorySample>()), 0)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<DriveVideoRecording>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: videoURL.path))
    }

    @MainActor
    func testBackgroundHistoryDeletionRemovesIncidentAndItsAnnotations() async throws {
        let container = try ModelContainer(
            for: DriveSession.self,
            TelemetryHistorySample.self,
            DriveVideoRecording.self,
            DriveIncident.self,
            TimelineAnnotation.self,
            AccelerationAttempt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let incident = DriveIncident(
            vehicleID: UUID(),
            sessionID: UUID(),
            kind: .overboost,
            severity: .warning,
            triggeredAt: .now,
            thresholdValue: 1.5,
            triggerValue: 1.8,
            triggerUnit: "bar",
            samples: []
        )
        context.insert(incident)
        context.insert(TimelineAnnotation(
            vehicleID: incident.vehicleID,
            sessionID: incident.sessionID,
            incidentID: incident.id,
            timestamp: incident.triggeredAt,
            body: "Test"
        ))
        try context.save()

        let worker = HistoryDeletionWorker(modelContainer: container)
        try await worker.deleteIncident(id: incident.id)

        let verificationContext = ModelContext(container)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<DriveIncident>()), 0)
        XCTAssertEqual(try verificationContext.fetchCount(FetchDescriptor<TimelineAnnotation>()), 0)
    }

    func testCloudPendingSamplesPublishInBatchesInsteadOfEveryTelemetrySample() {
        var buffer = CloudPendingSamplePublicationBuffer()

        for _ in 0..<(CloudPendingSamplePublicationBuffer.batchSize - 1) {
            XCTAssertNil(buffer.record())
        }
        XCTAssertEqual(buffer.record(), CloudPendingSamplePublicationBuffer.batchSize)
        XCTAssertEqual(buffer.pendingDelta, 0)
        XCTAssertNil(buffer.drain())
    }

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
    func testHistoryRecorderAutomaticallyStartsANewSegmentAtConfiguredBoundary() throws {
        let suite = "TougeDashTests.driveSegments.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = DriveSegmentSettingsStore(defaults: defaults)
        settings.length = .fifteenMinutes
        let container = try ModelContainer(
            for: DriveSession.self,
            TelemetryHistorySample.self,
            DriveIncident.self,
            TimelineAnnotation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let recorder = TelemetryHistoryRecorder(
            container: container,
            locationTracker: LocationTrackingService(),
            segmentSettings: settings,
            defaults: defaults
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try XCTUnwrap(recorder.record(.preview, at: start))
        for seconds in stride(from: 60.0, through: 840.0, by: 60.0) {
            _ = recorder.record(.preview, at: start.addingTimeInterval(seconds))
        }
        let lastInFirst = try XCTUnwrap(recorder.record(.preview, at: start.addingTimeInterval(899.9)))
        let firstInSecond = try XCTUnwrap(recorder.record(.preview, at: start.addingTimeInterval(900)))
        recorder.saveNow()

        XCTAssertEqual(first.sessionID, lastInFirst.sessionID)
        XCTAssertNotEqual(first.sessionID, firstInSecond.sessionID)
        XCTAssertEqual(firstInSecond.previousSessionID, first.sessionID)
        XCTAssertEqual(firstInSecond.boundaryAt, start.addingTimeInterval(900))
        let sessions = try container.mainContext.fetch(FetchDescriptor<DriveSession>(
            sortBy: [SortDescriptor(\.startedAt)]
        ))
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].endedAt, start.addingTimeInterval(899.9))
        XCTAssertEqual(sessions[1].startedAt, start.addingTimeInterval(900))
    }

    @MainActor
    func testDriveSegmentLengthDefaultsToThirtyMinutesAndPersists() throws {
        let suite = "TougeDashTests.driveSegmentSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = DriveSegmentSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.length, .thirtyMinutes)
        settings.length = .oneHour

        XCTAssertEqual(DriveSegmentSettingsStore(defaults: defaults).length, .oneHour)
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

    @MainActor
    func testManualDriveSplitSurvivesRecorderRestartAndCreatesANewSession() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DriveSession.self,
            TelemetryHistorySample.self,
            DriveIncident.self,
            TimelineAnnotation.self,
            configurations: configuration
        )
        let suiteName = "TougeDashTests.manual-drive-split.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        UserDefaults.standard.set(false, forKey: LocationTrackingService.enabledDefaultsKey)
        let start = Date.now

        let firstRecorder = TelemetryHistoryRecorder(
            container: container,
            locationTracker: LocationTrackingService(),
            defaults: defaults
        )
        let firstChange = try XCTUnwrap(firstRecorder.record(.preview, at: start))
        XCTAssertEqual(firstRecorder.finishActiveSessionForManualSplit(), firstChange.sessionID)
        XCTAssertNil(firstRecorder.activeSessionID)

        let restartedRecorder = TelemetryHistoryRecorder(
            container: container,
            locationTracker: LocationTrackingService(),
            defaults: defaults
        )
        XCTAssertNil(restartedRecorder.activeSessionID)
        let secondChange = try XCTUnwrap(
            restartedRecorder.record(.preview, at: start.addingTimeInterval(0.2))
        )
        restartedRecorder.saveNow()

        let sessions = try container.mainContext.fetch(FetchDescriptor<DriveSession>())
        let samples = try container.mainContext.fetch(FetchDescriptor<TelemetryHistorySample>())
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(samples.count, 2)
        XCTAssertNotEqual(firstChange.sessionID, secondChange.sessionID)
        XCTAssertEqual(Set(samples.compactMap { $0.session?.id }), [firstChange.sessionID, secondChange.sessionID])
    }

    func testPassiveTelemetryPolicyNeverAllowsWrites() {
        let allProperties: CBCharacteristicProperties = [.read, .notify, .write, .writeWithoutResponse]

        XCTAssertTrue(BluetoothTelemetryAccessPolicy.shouldRead(allProperties))
        XCTAssertTrue(BluetoothTelemetryAccessPolicy.shouldSubscribe(to: allProperties))
        XCTAssertFalse(BluetoothTelemetryAccessPolicy.allowsCharacteristicWrites)
    }

    func testTelemetryActivityExpiresAfterFiveMinutesWithoutCommunication() {
        let lastCommunication = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            TelemetryActivityInactivityPolicy.deadline(after: lastCommunication),
            lastCommunication.addingTimeInterval(5 * 60)
        )
        XCTAssertFalse(TelemetryActivityInactivityPolicy.isExpired(
            lastCommunicationAt: lastCommunication,
            now: lastCommunication.addingTimeInterval((5 * 60) - 0.001)
        ))
        XCTAssertTrue(TelemetryActivityInactivityPolicy.isExpired(
            lastCommunicationAt: lastCommunication,
            now: lastCommunication.addingTimeInterval(5 * 60)
        ))
    }

    func testTelemetryActivityRestoresTheRealLastSampleTimeInsteadOfResettingTheTimeout() {
        let lastCommunication = Date(timeIntervalSince1970: 1_800_000_000)
        var restoredSnapshot = TelemetrySnapshot()
        restoredSnapshot.updatedAt = lastCommunication

        let restoredDate = TelemetryActivityInactivityPolicy.restoredLastCommunication(
            from: restoredSnapshot
        )

        XCTAssertEqual(restoredDate, lastCommunication)
        XCTAssertTrue(TelemetryActivityInactivityPolicy.isExpired(
            lastCommunicationAt: restoredDate,
            now: lastCommunication.addingTimeInterval(5 * 60)
        ))
    }

    func testECUControlFrameEncodesWholeStateAndChecksum() throws {
        var state = ECUControlSnapshot()
        state = try XCTUnwrap(state.settingSwitch(channel: 1, to: true))
        state = try XCTUnwrap(state.settingSwitch(channel: 3, to: true))
        state = try XCTUnwrap(state.settingRotary(channel: 1, to: 2))
        state = try XCTUnwrap(state.settingRotary(channel: 2, to: 7))

        let frame = Array(state.encodedStatusFrame())

        XCTAssertEqual(frame, [0x08, 0x55, 0xA0, 0x27, 0x00, 0x00, 0x00, 0x24])
        XCTAssertTrue(ECUControlSnapshot.isValidStatusFrame(Data(frame)))
    }

    func testECUControlLoopbackDecodesSwitchesAndEveryRotaryNibble() throws {
        var loopback = ECUControlLoopbackAccumulator()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        loopback.apply(EMUFrame(channel: 254, rawValue: 0x00A0), receivedAt: now)
        loopback.apply(EMUFrame(channel: 253, rawValue: 0x1234), receivedAt: now)
        loopback.apply(EMUFrame(channel: 252, rawValue: 0xABCD), receivedAt: now)

        let state = try XCTUnwrap(loopback.synchronizedSnapshot())
        XCTAssertEqual(state.switches, [true, false, true, false, false, false, false, false])
        XCTAssertEqual(state.rotaryValues, [1, 2, 3, 4, 10, 11, 12, 13])
        XCTAssertEqual(loopback.synchronizedSnapshot(), state)
    }

    func testECUControlFullStatusFrameInitializesLoopback() throws {
        var loopback = ECUControlLoopbackAccumulator()
        let frame = Data([0x08, 0x55, 0xA0, 0x12, 0x34, 0xAB, 0xCD, 0xBB])

        XCTAssertTrue(loopback.applyStatusFrame(frame))
        let state = try XCTUnwrap(loopback.synchronizedSnapshot())
        XCTAssertEqual(state.switches, [true, false, true, false, false, false, false, false])
        XCTAssertEqual(state.rotaryValues, [1, 2, 3, 4, 10, 11, 12, 13])
    }

    @MainActor
    func testECUControlCoordinatorAcceptsFullStatusFrame() {
        let coordinator = ECUControlCoordinator(notificationCenter: NotificationCenter(), applicationIsActive: true)
        coordinator.connectionChanged(isConnected: true)
        coordinator.transportAvailabilityChanged(true)

        coordinator.ingestStatusFrame(Data([0x08, 0x55, 0x80, 0, 0, 0, 0, 0xDD]))

        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(coordinator.switchValue(channel: 1), true)
    }

    func testECUControlRejectsInvalidChannelRangeAndChecksum() {
        let state = ECUControlSnapshot()
        XCTAssertNil(state.settingSwitch(channel: 0, to: true))
        XCTAssertNil(state.settingSwitch(channel: 9, to: true))
        XCTAssertNil(state.settingRotary(channel: 1, to: 16))

        var frame = state.encodedStatusFrame()
        frame[7] &+= 1
        XCTAssertFalse(ECUControlSnapshot.isValidStatusFrame(frame))
    }

    func testECUControlTransportAllowsOnlyExactKnownProfiles() {
        XCTAssertEqual(ECUControlTransportPolicy.priority(
            service: CBUUID(string: "FFE0"),
            characteristic: CBUUID(string: "FFE1")
        ), 1)
        XCTAssertEqual(ECUControlTransportPolicy.priority(
            service: CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
            characteristic: CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
        ), 2)
        XCTAssertNil(ECUControlTransportPolicy.priority(
            service: CBUUID(string: "FFE0"),
            characteristic: CBUUID(string: "FFE2")
        ))
    }

    @MainActor
    func testECUControlCoordinatorWaitsForLoopbackAndConfirmsExactState() throws {
        let coordinator = ECUControlCoordinator(notificationCenter: NotificationCenter(), applicationIsActive: true)
        var sentFrame: Data?
        coordinator.writer = { frame, completion in
            sentFrame = frame
            completion(.success(()))
        }
        coordinator.connectionChanged(isConnected: true)
        coordinator.transportAvailabilityChanged(true)

        XCTAssertFalse(coordinator.toggleSwitch(channel: 1))
        let now = Date.now
        coordinator.ingest(EMUFrame(channel: 254, rawValue: 0), receivedAt: now)
        coordinator.ingest(EMUFrame(channel: 253, rawValue: 0), receivedAt: now)
        coordinator.ingest(EMUFrame(channel: 252, rawValue: 0), receivedAt: now)
        XCTAssertTrue(coordinator.isReady)

        XCTAssertTrue(coordinator.toggleSwitch(channel: 1))
        XCTAssertTrue(try XCTUnwrap(sentFrame).count == 8)
        XCTAssertNotNil(coordinator.pending)

        let confirmationTime = Date.now.addingTimeInterval(0.01)
        coordinator.ingest(EMUFrame(channel: 254, rawValue: 0x80), receivedAt: confirmationTime)
        XCTAssertEqual(coordinator.switchValue(channel: 1), true)
        XCTAssertNil(coordinator.pending)
    }

    @MainActor
    func testECUControlKeepsSynchronizedStateAcrossSlowLoopbackCycle() {
        let coordinator = ECUControlCoordinator(notificationCenter: NotificationCenter(), applicationIsActive: true)
        coordinator.connectionChanged(isConnected: true)
        coordinator.transportAvailabilityChanged(true)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        coordinator.ingest(EMUFrame(channel: 254, rawValue: 0), receivedAt: start)
        coordinator.ingest(EMUFrame(channel: 253, rawValue: 0), receivedAt: start.addingTimeInterval(3))
        XCTAssertFalse(coordinator.isReady)
        coordinator.ingest(EMUFrame(channel: 252, rawValue: 0), receivedAt: start.addingTimeInterval(6))

        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(coordinator.availabilityLabel, localized("POTWIERDZONE PRZEZ EMU"))
    }

    @MainActor
    func testECURotaryConfirmationWaitsOnlyForItsLoopbackGroup() {
        let coordinator = ECUControlCoordinator(notificationCenter: NotificationCenter(), applicationIsActive: true)
        coordinator.writer = { _, completion in completion(.success(())) }
        coordinator.connectionChanged(isConnected: true)
        coordinator.transportAvailabilityChanged(true)
        coordinator.ingest(EMUFrame(channel: 254, rawValue: 0))
        coordinator.ingest(EMUFrame(channel: 253, rawValue: 0))
        coordinator.ingest(EMUFrame(channel: 252, rawValue: 0))

        XCTAssertTrue(coordinator.setRotary(channel: 6, value: 7))
        coordinator.ingest(EMUFrame(channel: 253, rawValue: 0))
        XCTAssertNotNil(coordinator.pending)
        coordinator.ingest(EMUFrame(channel: 252, rawValue: 0x0700))

        XCTAssertEqual(coordinator.rotaryValue(channel: 6), 7)
        XCTAssertNil(coordinator.pending)
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

@MainActor
final class AccelerationEngineTests: XCTestCase {
    func testContinuousPullRecordsEverySupportedRange() {
        let engine = AccelerationEngine()
        let sessionID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var offset = 0.0
        var results: [AccelerationAttempt] = []

        for _ in 0..<26 {
            _ = engine.sample(snapshot(speed: 0), at: start.addingTimeInterval(offset), sessionID: sessionID)
            offset += 0.04
        }
        for speed in 0...260 {
            if let result = engine.sample(
                snapshot(speed: Double(speed)),
                at: start.addingTimeInterval(offset),
                sessionID: sessionID
            ) {
                results.append(result)
            }
            offset += 0.04
        }

        XCTAssertEqual(results.map(\.type), [.zeroTo100, .hundredTo200, .twoHundredTo250])
    }

    func testStaleBluetoothFrameCannotStartRollingMeasurement() {
        let engine = AccelerationEngine()
        let sessionID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var offset = 0.0

        for speed in 85...99 {
            _ = engine.sample(snapshot(speed: Double(speed)), at: start.addingTimeInterval(offset), sessionID: sessionID)
            offset += 0.04
        }
        offset += 2
        _ = engine.sample(snapshot(speed: 101), at: start.addingTimeInterval(offset), sessionID: sessionID)
        for speed in 102...220 {
            offset += 0.04
            XCTAssertNil(engine.sample(snapshot(speed: Double(speed)), at: start.addingTimeInterval(offset), sessionID: sessionID))
        }
    }

    private func snapshot(speed: Double) -> TelemetrySnapshot {
        TelemetrySnapshot(rpm: 4_500, throttlePercent: 82, speedKPH: speed)
    }
}
