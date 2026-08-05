import AVFoundation
import SwiftData
import XCTest
@testable import TougeDash

final class DriveVideoFeatureTests: XCTestCase {
    func testRecordingKeepsFullIncidentCadenceButThrottlesDashboard() {
        XCTAssertEqual(TelemetryUpdateCadence.processingInterval, 1.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(TelemetryUpdateCadence.normalDisplayInterval, 1.0 / 20.0, accuracy: 0.0001)
        XCTAssertEqual(TelemetryUpdateCadence.recordingDisplayInterval, 1.0 / 8.0, accuracy: 0.0001)
        XCTAssertGreaterThan(
            TelemetryUpdateCadence.recordingDisplayInterval,
            TelemetryUpdateCadence.processingInterval
        )
    }

    @MainActor
    func testOverlayTemplatesPersistAndCopiesHaveIndependentIdentifiers() throws {
        let suite = "TougeDashTests.videoOverlay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = VideoOverlayTemplateStore(defaults: defaults, keyPrefix: suite)
        XCTAssertEqual(store.templates.count, 4)
        XCTAssertEqual(store.selectedTemplate.style, .racing)

        let copy = store.createCopy()
        XCTAssertNotEqual(copy.id, store.selectedTemplate.id)
        XCTAssertEqual(copy.elements.map(\.metric), store.selectedTemplate.elements.map(\.metric))
        XCTAssertTrue(zip(copy.elements, store.selectedTemplate.elements).allSatisfy { $0.id != $1.id })

        var edited = copy
        edited.name = "Track HUD"
        edited.elements[0].slot = .topCenter
        store.save(edited)

        let reloaded = VideoOverlayTemplateStore(defaults: defaults, keyPrefix: suite)
        XCTAssertEqual(reloaded.selectedTemplate.name, "Track HUD")
        XCTAssertEqual(reloaded.selectedTemplate.elements[0].slot, .topCenter)
    }

    func testRacingOverlayCoversEssentialDriveMetrics() {
        let metrics = Set(VideoOverlayTemplate.racing.elements.map(\.metric))
        XCTAssertTrue(metrics.isSuperset(of: [
            .speed, .rpm, .boost, .oilPressure, .oilTemperature, .coolant
        ]))
        XCTAssertTrue(VideoOverlayTemplate.racing.elements.contains(where: { $0.kind == .gauge }))
        XCTAssertTrue(VideoOverlayTemplate.racing.elements.contains(where: { $0.kind == .bar }))
        for template in VideoOverlayTemplate.factoryTemplates {
            for element in template.elements {
                let landscape = element.position(for: .landscape)
                let portrait = element.position(for: .portrait)
                XCTAssertTrue((0...1).contains(landscape.x))
                XCTAssertTrue((0...1).contains(landscape.y))
                XCTAssertTrue((0...1).contains(portrait.x))
                XCTAssertTrue((0...1).contains(portrait.y))
            }
        }
    }

    func testTimelineAlignmentSupportsDelayedDashcamAndPersists() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let session = DriveSession(
            vehicleID: UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(180)
        )
        let recording = DriveVideoRecording(
            sessionID: session.id,
            fileName: "dashcam.mov",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(160),
            duration: 160,
            fileSizeBytes: 1,
            pixelWidth: 1_920,
            pixelHeight: 1_080,
            framesPerSecond: 30,
            cameraName: "Dashcam",
            hasAudio: true,
            sourceKind: .photoLibrary
        )
        var alignment = DriveVideoTimelineAlignment(
            videoStartSeconds: 0,
            telemetryStartSeconds: 20,
            duration: 160,
            videoDuration: recording.duration,
            telemetryDuration: session.duration
        )
        XCTAssertEqual(alignment.videoEndSeconds, 160, accuracy: 0.001)
        XCTAssertEqual(alignment.telemetryEndSeconds, 180, accuracy: 0.001)

        alignment.duration = 150
        alignment.persist(to: recording)
        let restored = DriveVideoTimelineAlignment(recording: recording, session: session)
        XCTAssertEqual(restored.videoStartSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(restored.telemetryStartSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(restored.duration, 150, accuracy: 0.001)
        XCTAssertEqual(restored.telemetryStartDate(session: session), startedAt.addingTimeInterval(20))
    }

    func testLegacyOverlayMigratesToFreeformLayout() throws {
        let templateID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let json = """
        {
          "id": "\(templateID.uuidString)",
          "name": "Legacy HUD",
          "style": "racing",
          "elements": [
            {"id":"\(firstID.uuidString)","metric":"speed","slot":"topLeading","scale":"medium","accent":"cyan"},
            {"id":"\(secondID.uuidString)","metric":"rpm","slot":"topLeading","scale":"large","accent":"yellow"}
          ],
          "modifiedAt": "2026-08-05T10:00:00Z"
        }
        """
        let decoded = try JSONDecoder.tougeDashCloud().decode(VideoOverlayTemplate.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.layoutVersion, 1)
        XCTAssertEqual(decoded.elements.map(\.kind), [.digital, .digital])

        let migrated = decoded.migratedToFreeformLayout()
        XCTAssertEqual(migrated.layoutVersion, 2)
        XCTAssertNotEqual(
            migrated.elements[0].position(for: .landscape),
            migrated.elements[1].position(for: .landscape)
        )
    }

    func testTelemetryFrameUsesRecordedSampleInsteadOfLiveState() {
        var snapshot = TelemetrySnapshot.preview
        snapshot.rpm = 7_111
        snapshot.speedKPH = 147
        snapshot.boostBar = 1.42
        snapshot.oilPressureBar = 4.6
        let sample = TelemetryHistorySample(
            snapshot: snapshot,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let frame = VideoTelemetryFrame(sample: sample)
        XCTAssertEqual(frame.value(for: .rpm), 7_111)
        XCTAssertEqual(frame.value(for: .speed), 147)
        XCTAssertEqual(frame.value(for: .boost), 1.42)
        XCTAssertEqual(frame.value(for: .oilPressure), 4.6)
    }

    @MainActor
    func testVideoMetadataCanBeStoredWithoutDriveRelationship() throws {
        let container = try ModelContainer(
            for: DriveVideoRecording.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let sessionID = UUID()
        let recording = DriveVideoRecording(
            sessionID: sessionID,
            fileName: "drive.mov",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_060),
            duration: 60,
            fileSizeBytes: 125_000_000,
            pixelWidth: 1_920,
            pixelHeight: 1_080,
            framesPerSecond: 30,
            cameraName: "Wide camera",
            hasAudio: true
        )
        context.insert(recording)
        try context.save()

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<DriveVideoRecording>()).first)
        XCTAssertEqual(stored.sessionID, sessionID)
        XCTAssertEqual(stored.fileSizeBytes, 125_000_000)
        XCTAssertEqual(stored.pixelWidth, 1_920)
        XCTAssertEqual(stored.duration, 60)
    }

    @MainActor
    func testOverlayRendererProducesPlayableVideo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TougeDashVideoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.mov")
        let outputURL = directory.appending(path: "overlay.mp4")
        try await makeTestVideo(at: sourceURL)

        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var first = TelemetrySnapshot.preview
        first.speedKPH = 72
        var second = first
        second.speedKPH = 128
        second.boostBar = 1.25
        let frames = [
            VideoTelemetryFrame(sample: TelemetryHistorySample(snapshot: first, timestamp: startedAt)),
            VideoTelemetryFrame(sample: TelemetryHistorySample(snapshot: second, timestamp: startedAt.addingTimeInterval(0.5)))
        ]

        let exporter = DriveVideoExporter()
        let rendered = try await exporter.renderOverlay(
            sourceURL: sourceURL,
            recordingStart: startedAt,
            samples: frames,
            template: .racing,
            outputURL: outputURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: rendered.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: rendered.path)
        XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, 1_000)
        let asset = AVURLAsset(url: rendered)
        let duration = try await asset.load(.duration).seconds
        let videoTrackCount = try await asset.loadTracks(withMediaType: .video).count
        XCTAssertGreaterThan(duration, 0.8)
        XCTAssertEqual(videoTrackCount, 1)
    }

    @MainActor
    func testImportedVideoIsInspectedAndCopiedIntoLocalDriveStorage() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "dashcam-\(UUID().uuidString).mov")
        try await makeTestVideo(at: sourceURL)

        var didInspect = false
        var copyProgress: [Double] = []
        let prepared = try await DriveVideoImportService.prepare(
            from: DriveVideoTransfer(fileURL: sourceURL)
        ) { stage in
            switch stage {
            case .inspecting:
                didInspect = true
            case .copying(let fraction):
                copyProgress.append(fraction)
            }
        }
        let destination = try DriveVideoFileStore.directoryURL().appending(path: prepared.fileName)
        defer { try? FileManager.default.removeItem(at: destination) }

        XCTAssertTrue(didInspect)
        XCTAssertEqual(copyProgress.first, 0)
        XCTAssertEqual(copyProgress.last, 1)
        XCTAssertTrue(zip(copyProgress, copyProgress.dropFirst()).allSatisfy { pair in
            pair.0 <= pair.1
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(prepared.metadata.width, 320)
        XCTAssertEqual(prepared.metadata.height, 180)
        XCTAssertEqual(prepared.metadata.duration, 1, accuracy: 0.08)
        XCTAssertGreaterThan(prepared.fileSizeBytes, 1_000)
    }

    @MainActor
    func testRendererTrimsVideoToSelectedCommonRange() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TougeDashVideoTrimTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.mov")
        let outputURL = directory.appending(path: "trimmed.mp4")
        try await makeTestVideo(at: sourceURL)

        let rendered = try await DriveVideoExporter().renderVideo(
            sourceURL: sourceURL,
            telemetryStart: Date(timeIntervalSince1970: 1_800_000_000),
            samples: [],
            template: nil,
            videoStartSeconds: 0.2,
            duration: 0.4,
            outputURL: outputURL
        )
        let duration = try await AVURLAsset(url: rendered).load(.duration).seconds
        XCTAssertEqual(duration, 0.4, accuracy: 0.08)
    }

    @MainActor
    func testExportCompletesAfterPhotoLibrarySaverFinishes() async throws {
        let sourceURL = try DriveVideoFileStore.newRecordingURL()
        try Data("test-video".utf8).write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let probe = PhotoLibrarySaverProbe()
        let exporter = DriveVideoExporter { url in
            await probe.save(url)
        }
        let recording = DriveVideoRecording(
            sessionID: UUID(),
            fileName: sourceURL.lastPathComponent,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_001),
            duration: 1,
            fileSizeBytes: 10,
            pixelWidth: 320,
            pixelHeight: 180,
            framesPerSecond: 30,
            cameraName: "Test camera",
            hasAudio: false
        )

        await exporter.export(recording: recording, samples: [], template: nil)

        XCTAssertEqual(exporter.state, .completed)
        let savedURL = await probe.savedURL
        XCTAssertEqual(savedURL, sourceURL)
    }

    @MainActor
    func testVideoQualityDefaultsToFullHDAndPersists() throws {
        let suite = "TougeDashTests.videoSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = DriveVideoSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.quality, .fullHD)
        XCTAssertTrue(settings.recordsAudio)
        settings.quality = .storageSaver
        settings.isEnabled = true

        let reloaded = DriveVideoSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.quality, .storageSaver)
        XCTAssertTrue(reloaded.isEnabled)
    }

    @MainActor
    private func makeTestVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<30 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                nil,
                320,
                180,
                kCVPixelFormatType_32BGRA,
                nil,
                &buffer
            )
            guard status == kCVReturnSuccess, let buffer else {
                XCTFail("Unable to create test pixel buffer")
                return
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let address = CVPixelBufferGetBaseAddress(buffer) {
                let color = UInt8(30 + frameIndex * 4)
                memset(address, Int32(color), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: 30)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: time))
        }

        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        XCTAssertEqual(writer.status, .completed)
    }
}

private actor PhotoLibrarySaverProbe {
    private(set) var savedURL: URL?

    func save(_ url: URL) {
        savedURL = url
    }
}
