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
        XCTAssertEqual(store.templates.count, 3)
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
