import AVFoundation
import SwiftData
import SwiftUI
import UIKit
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
        XCTAssertEqual(store.templates.count, 16)
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

    func testExportRangeTrimsVideoAndTelemetryByTheSameOffset() {
        let alignment = DriveVideoTimelineAlignment(
            videoStartSeconds: 4,
            telemetryStartSeconds: 19,
            duration: 100,
            videoDuration: 140,
            telemetryDuration: 180
        )

        let trimmed = alignment.trimming(
            relativeStart: 12,
            duration: 35,
            videoDuration: 140,
            telemetryDuration: 180
        )

        XCTAssertEqual(trimmed.videoStartSeconds, 16, accuracy: 0.001)
        XCTAssertEqual(trimmed.telemetryStartSeconds, 31, accuracy: 0.001)
        XCTAssertEqual(trimmed.duration, 35, accuracy: 0.001)
        XCTAssertEqual(trimmed.videoEndSeconds, 51, accuracy: 0.001)
        XCTAssertEqual(trimmed.telemetryEndSeconds, 66, accuracy: 0.001)
    }

    func testExportPreviewCursorCannotLeaveTrimmedRange() {
        XCTAssertEqual(VideoExportRangeMath.clampCursor(4, start: 10, end: 30), 10, accuracy: 0.001)
        XCTAssertEqual(VideoExportRangeMath.clampCursor(18, start: 10, end: 30), 18, accuracy: 0.001)
        XCTAssertEqual(VideoExportRangeMath.clampCursor(42, start: 10, end: 30), 30, accuracy: 0.001)
    }

    func testAutomaticSplitClipsVideoAndTelemetryAtTheSameWallClockBoundary() {
        let videoStartedAt = Date(timeIntervalSince1970: 1_800_000_010)
        let telemetryBoundary = Date(timeIntervalSince1970: 1_800_000_900)

        XCTAssertEqual(
            DriveVideoTimelineSynchronization.clippedDuration(
                videoStartedAt: videoStartedAt,
                videoDuration: 900,
                telemetryBoundaryAt: telemetryBoundary
            ),
            890,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DriveVideoTimelineSynchronization.clippedDuration(
                videoStartedAt: videoStartedAt,
                videoDuration: 880,
                telemetryBoundaryAt: telemetryBoundary
            ),
            880,
            accuracy: 0.001
        )
    }

    func testM300ProtocolBuildsKnownPairingAndSignedRequests() throws {
        let bindURL = try XCTUnwrap(SeventyMaiM300Protocol.bindURL(
            host: "192.168.0.1",
            userID: "123456789"
        ))
        XCTAssertEqual(bindURL.host(), "192.168.0.1")
        XCTAssertTrue(bindURL.absoluteString.contains("BindByBanya.cgi?&-usr=123456789"))
        XCTAssertTrue(bindURL.absoluteString.contains("-signkey=e8c46806a6317270f185fdf1903498d6"))

        let confirmationURL = try XCTUnwrap(SeventyMaiM300Protocol.confirmationURL(
            host: "192.168.0.1",
            timestamp: "1700000000"
        ))
        XCTAssertTrue(confirmationURL.absoluteString.contains("-signkey=bbbf6a64712098c543a59a4aad97bb3f"))

        let listURL = try XCTUnwrap(SeventyMaiM300Protocol.signedURL(
            host: "192.168.0.1",
            endpoint: "getfilelist.cgi",
            parameters: [("start", "1"), ("end", "100"), ("type", SeventyMaiM300Protocol.normalRecordingType)],
            timestamp: 1_700_000_000,
            connectKey: "TOKEN"
        ))
        XCTAssertEqual(
            listURL.absoluteString,
            "http://192.168.0.1/cgi-bin/getfilelist.cgi?&-start=1&-end=100&-type=0&-timestamp=1700000000&-signkey=cb960cbc06237f1c58be011bb185d00c"
        )
    }

    func test70maiCameraProfilesMapNormalRecordingChannels() {
        XCTAssertEqual(SeventyMaiCameraModel.m300.channels, [.front])
        XCTAssertEqual(SeventyMaiCameraModel.m300.recordingType(for: .front), "0")
        XCTAssertNil(SeventyMaiCameraModel.m300.recordingType(for: .rear))

        XCTAssertEqual(SeventyMaiCameraModel.m500.channels, [.front])
        XCTAssertEqual(SeventyMaiCameraModel.m500.recordingType(for: .front), "0")

        let dualChannelModels: [SeventyMaiCameraModel] = [
            .a200, .a400, .a500s, .a510, .a800s, .a810, .s500
        ]
        for camera in dualChannelModels {
            XCTAssertEqual(camera.channels, [.front, .rear], camera.displayName)
            XCTAssertEqual(camera.recordingType(for: .front), "4", camera.displayName)
            XCTAssertEqual(camera.recordingType(for: .rear), "8", camera.displayName)
            XCTAssertNil(camera.recordingType(for: .interior), camera.displayName)
        }
    }

    func testM300ClipParserCorrectsCameraClockAndMatchesDrive() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let sessionStart = try XCTUnwrap(SeventyMaiM300Protocol.parseCameraDate(
            "20260813-080000",
            calendar: calendar
        ))
        let dictionary: [String: Any] = [
            "path": "/mnt/sd/Normal/Front",
            "name": "NO20260813-080500-000001F.MP4",
            "size": "104857600",
            "duration": "60000",
            "width": "2304",
            "height": "1296",
            "fps": "30",
            "videoencode": "hevc"
        ]
        let clip = try XCTUnwrap(SeventyMaiM300Protocol.correctedClip(
            dictionary: dictionary,
            clockOffsetSeconds: 300,
            calendar: calendar
        ))
        XCTAssertEqual(clip.correctedStartedAt, sessionStart)
        XCTAssertEqual(clip.duration, 600, accuracy: 0.001)
        XCTAssertEqual(clip.width, 2_304)
        XCTAssertEqual(clip.height, 1_296)
        XCTAssertEqual(clip.videoCodec, "hevc")

        let matches = SeventyMaiM300Protocol.matchingClips(
            [clip],
            sessionStartedAt: sessionStart.addingTimeInterval(120),
            sessionEndedAt: sessionStart.addingTimeInterval(300)
        )
        XCTAssertEqual(matches.map(\.id), [clip.id])
    }

    func testM300UsesNextTimestampWhenFirmwareReportsShortDuration() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let first = try XCTUnwrap(SeventyMaiM300Protocol.correctedClip(
            dictionary: [
                "path": "/mnt/sd/Normal",
                "name": "NO20260813-222400-000001F.MP4",
                "size": "377500000",
                "duration": "6000"
            ],
            clockOffsetSeconds: 0,
            calendar: calendar
        ))
        let second = try XCTUnwrap(SeventyMaiM300Protocol.correctedClip(
            dictionary: [
                "path": "/mnt/sd/Normal",
                "name": "NO20260813-222700-000002F.MP4",
                "size": "125800000",
                "duration": "6000"
            ],
            clockOffsetSeconds: 0,
            calendar: calendar
        ))

        let normalized = SeventyMaiM300Protocol.normalizedClipDurations([second, first])
        XCTAssertEqual(normalized[0].duration, 180, accuracy: 0.001)
        XCTAssertEqual(normalized[1].duration, 60, accuracy: 0.001)

        let driveStart = first.correctedStartedAt.addingTimeInterval(120)
        let matches = SeventyMaiM300Protocol.matchingClips(
            [first, second],
            sessionStartedAt: driveStart,
            sessionEndedAt: driveStart.addingTimeInterval(30)
        )
        XCTAssertEqual(matches.map(\.id), [first.id])
    }

    @MainActor
    func testM300JoinKeepsRealGapAsEmptyTimelineInsteadOfFailing() async throws {
        let firstURL = try DriveVideoFileStore.newRecordingURL(fileExtension: "mov")
        let secondURL = try DriveVideoFileStore.newRecordingURL(fileExtension: "mov")
        let outputURL = try DriveVideoFileStore.newRecordingURL(fileExtension: "mp4")
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try await makeTestVideo(at: firstURL)
        try await makeTestVideo(at: secondURL)

        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        func clip(name: String, offset: TimeInterval) -> SeventyMaiM300Clip {
            SeventyMaiM300Clip(
                path: "/mnt/sd/Normal",
                name: name,
                sizeBytes: 1,
                cameraStartedAt: startedAt.addingTimeInterval(offset),
                correctedStartedAt: startedAt.addingTimeInterval(offset),
                duration: 1,
                width: 320,
                height: 180,
                framesPerSecond: 30,
                videoCodec: "h264"
            )
        }

        let client = SeventyMaiM300Client(userID: "123456789")
        let outputStartedAt = try await client.join(
            [
                (clip(name: "first.mp4", offset: 0), firstURL),
                (clip(name: "second.mp4", offset: 3), secondURL)
            ],
            sessionStartedAt: startedAt,
            sessionEndedAt: startedAt.addingTimeInterval(4),
            outputURL: outputURL
        )

        XCTAssertEqual(outputStartedAt, startedAt)
        let metadata = try await DriveVideoAssetInspector.metadata(for: outputURL)
        XCTAssertEqual(metadata.duration, 4, accuracy: 0.15)
    }

    func testM300DirectFileURLPreservesCameraPathAndEscapesName() throws {
        let url = try XCTUnwrap(SeventyMaiM300Protocol.directFileURL(
            host: "192.168.0.1",
            path: "/mnt/sd/Normal/Front",
            name: "NO20260813-080500 test.MP4"
        ))
        XCTAssertEqual(
            url.absoluteString,
            "http://192.168.0.1/mnt/sd/Normal/Front/NO20260813-080500%20test.MP4"
        )
    }

    func testDashcamImportActivityClampsByteProgress() {
        var state = DashcamImportActivityAttributes.ContentState(
            phase: .downloading,
            currentClip: 2,
            totalClips: 3,
            fileName: "NO20260813-180000-000001.MP4",
            receivedBytes: 25,
            expectedBytes: 100
        )
        XCTAssertEqual(state.fractionCompleted, 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.percentCompleted, 25)

        state.receivedBytes = 120
        XCTAssertEqual(state.fractionCompleted, 1, accuracy: 0.0001)
        XCTAssertEqual(state.percentCompleted, 100)
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
        XCTAssertEqual(decoded.elements.map(\.sizeMultiplier), [1, 1])
        XCTAssertEqual(decoded.gaugeConfiguration.maximumSpeedKPH, 300)

        let migrated = decoded.migratedToFreeformLayout()
        XCTAssertEqual(migrated.layoutVersion, 2)
        XCTAssertNotEqual(
            migrated.elements[0].position(for: .landscape),
            migrated.elements[1].position(for: .landscape)
        )
    }

    func testStreetLegendsCombinesSpeedBoostRpmAndOilData() {
        XCTAssertEqual(VideoOverlayTemplate.streetLegends.elements.map(\.kind), [.speedCluster, .oilCluster])
        XCTAssertEqual(VideoOverlayTemplate.streetLegends.gaugeConfiguration.range(for: .speed), 0...300)
        XCTAssertEqual(VideoOverlayTemplate.streetLegends.gaugeConfiguration.range(for: .oilTemperature), 0...140)
    }

    func testArcadeEraPresetsUseDedicatedTachometersAndRecordedMetrics() {
        let presets: [VideoOverlayTemplate] = [.neonCircuit, .blacklistClassic, .carbonGold, .streetShift]
        XCTAssertEqual(
            presets.compactMap { $0.elements.first?.kind },
            [.neonTach, .blacklistTach, .carbonTach, .streetShiftTach]
        )
        XCTAssertEqual(VideoOverlayTemplate.neonCircuit.gaugeConfiguration.range(for: .rpm), 0...10_000)
        XCTAssertEqual(VideoOverlayTemplate.carbonGold.gaugeConfiguration.range(for: .rpm), 0...9_000)
        XCTAssertTrue(presets.allSatisfy { $0.elements.count == 1 && $0.elements[0].metric == .rpm })
    }

    @MainActor
    func testRouteRadarRendersMappedRouteWithoutCoveringTachometer() throws {
        XCTAssertEqual(VideoOverlayTemplate.routeRadar.elements.map(\.kind), [.routeMap, .neonTach])
        XCTAssertEqual(VideoOverlayTemplate.routeOrbit.elements.map(\.kind), [.routeMapCircular, .carbonTach])
        XCTAssertEqual(VideoOverlayTemplate.routeOrbit.elements.first?.accent, .mint)
        XCTAssertEqual(VideoOverlayTemplate.pursuitMap.elements.map(\.kind), [.routeMap, .blacklistTach])
        XCTAssertEqual(VideoOverlayTemplate.pursuitMap.elements.first?.accent, .red)
        XCTAssertEqual(VideoOverlayTemplate.routeChase.elements.map(\.kind), [.routeMapFollow, .neonTach])
        XCTAssertEqual(VideoOverlayTemplate.routeChase.elements.first?.accent, .blue)
        XCTAssertEqual(VideoOverlayTemplate.streetAtlas.elements.map(\.kind), [.routeMapLight])
        XCTAssertEqual(VideoOverlayTemplate.iceOrbit.elements.map(\.kind), [.routeMapLightCircular])
        XCTAssertEqual(VideoOverlayTemplate.amberRun.elements.map(\.kind), [.routeMapAmber])
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var telemetry = TelemetrySnapshot.preview
        telemetry.speedKPH = 83
        telemetry.rpm = 4_200
        let sample = TelemetryHistorySample(snapshot: telemetry, timestamp: startedAt.addingTimeInterval(2))
        let background = UIGraphicsImageRenderer(size: VideoRouteMapSnapshotter.snapshotSize).image { context in
            UIColor(red: 0.08, green: 0.10, blue: 0.11, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: VideoRouteMapSnapshotter.snapshotSize))
            UIColor(white: 0.55, alpha: 0.5).setStroke()
            context.cgContext.setLineWidth(10)
            context.cgContext.move(to: CGPoint(x: 0, y: 270))
            context.cgContext.addCurve(
                to: CGPoint(x: 642, y: 130),
                control1: CGPoint(x: 180, y: 350),
                control2: CGPoint(x: 430, y: 30)
            )
            context.cgContext.strokePath()
        }
        let routeMap = VideoRouteMapSnapshot(
            image: try XCTUnwrap(background.cgImage),
            points: [
                .init(timestamp: startedAt, position: CGPoint(x: 0.08, y: 0.72)),
                .init(timestamp: startedAt.addingTimeInterval(1), position: CGPoint(x: 0.31, y: 0.61)),
                .init(timestamp: startedAt.addingTimeInterval(2), position: CGPoint(x: 0.53, y: 0.44)),
                .init(timestamp: startedAt.addingTimeInterval(3), position: CGPoint(x: 0.75, y: 0.30)),
                .init(timestamp: startedAt.addingTimeInterval(4), position: CGPoint(x: 0.92, y: 0.36))
            ]
        )
        for template in [VideoOverlayTemplate.routeRadar, .routeOrbit, .pursuitMap, .routeChase, .streetAtlas, .iceOrbit, .amberRun] {
            let image = try XCTUnwrap(VideoOverlayCGRenderer.render(
                size: CGSize(width: 390, height: 220),
                sample: VideoTelemetryFrame(sample: sample),
                template: template,
                routeMap: routeMap
            ))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "Export-HUD-\(template.name.replacingOccurrences(of: " ", with: "-"))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testRouteMapPoseInterpolatesPositionAndKeepsHeadingStable() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let background = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let routeMap = VideoRouteMapSnapshot(
            image: try XCTUnwrap(background.cgImage),
            points: [
                .init(timestamp: startedAt, position: CGPoint(x: 0.1, y: 0.8)),
                .init(timestamp: startedAt.addingTimeInterval(2), position: CGPoint(x: 0.5, y: 0.4)),
                .init(timestamp: startedAt.addingTimeInterval(4), position: CGPoint(x: 0.9, y: 0.0))
            ]
        )

        let first = try XCTUnwrap(routeMap.pose(at: startedAt.addingTimeInterval(1)))
        let second = try XCTUnwrap(routeMap.pose(at: startedAt.addingTimeInterval(3)))
        XCTAssertEqual(first.position.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(first.position.y, 0.6, accuracy: 0.0001)
        XCTAssertEqual(second.position.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(second.position.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(first.heading, second.heading, accuracy: 0.0001)
    }

    func testRouteMapCollapsesStaleLocationCopiesAndMovesBetweenGpsUpdates() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let background = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let routeMap = VideoRouteMapSnapshot(
            image: try XCTUnwrap(background.cgImage),
            points: [
                .init(timestamp: startedAt, position: CGPoint(x: 0.1, y: 0.5)),
                .init(timestamp: startedAt.addingTimeInterval(0.4), position: CGPoint(x: 0.1, y: 0.5)),
                .init(timestamp: startedAt.addingTimeInterval(0.8), position: CGPoint(x: 0.1, y: 0.5)),
                .init(timestamp: startedAt.addingTimeInterval(1), position: CGPoint(x: 0.5, y: 0.5)),
                .init(timestamp: startedAt.addingTimeInterval(1.4), position: CGPoint(x: 0.5, y: 0.5)),
                .init(timestamp: startedAt.addingTimeInterval(2), position: CGPoint(x: 0.9, y: 0.5))
            ]
        )

        XCTAssertEqual(routeMap.points.count, 3)
        let halfway = try XCTUnwrap(routeMap.pose(at: startedAt.addingTimeInterval(0.5)))
        XCTAssertEqual(halfway.position.x, 0.3, accuracy: 0.0001)
        XCTAssertEqual(halfway.position.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(halfway.heading, 0, accuracy: 0.0001)
    }

    func testRouteMapCameraZoomClampsAndPersists() throws {
        var element = try XCTUnwrap(VideoOverlayTemplate.streetAtlas.elements.first)
        element.setMapZoom(4)
        XCTAssertEqual(element.mapZoom, 3.5, accuracy: 0.0001)
        element.setMapZoom(0.1)
        XCTAssertEqual(element.mapZoom, 0.65, accuracy: 0.0001)

        var template = VideoOverlayTemplate.streetAtlas
        element.setMapZoom(1.45)
        template.elements[0] = element
        let decoded = try JSONDecoder().decode(
            VideoOverlayTemplate.self,
            from: JSONEncoder().encode(template)
        )
        XCTAssertEqual(decoded.elements[0].mapZoom, 1.45, accuracy: 0.0001)
    }

    func testOverlayWidgetCanBeRemovedAndAddedAgain() throws {
        var template = VideoOverlayTemplate.routeRadar
        let removed = try XCTUnwrap(template.elements.first)
        let originalCount = template.elements.count

        template.removeElement(id: removed.id)
        XCTAssertEqual(template.elements.count, originalCount - 1)
        XCTAssertFalse(template.elements.contains { $0.id == removed.id })

        var restored = removed
        restored.id = UUID()
        template.elements.append(restored)
        XCTAssertEqual(template.elements.count, originalCount)
        XCTAssertNotEqual(restored.id, removed.id)
    }

    @MainActor
    func testEditableMapPreviewShowsCameraZoomControls() throws {
        var telemetry = TelemetrySnapshot.preview
        telemetry.speedKPH = 72
        let sample = TelemetryHistorySample(snapshot: telemetry, timestamp: .now)
        let template = VideoOverlayTemplate.routeChase
        let preview = ZStack {
            Color.black
            EditableVideoTelemetryOverlayView(
                template: .constant(template),
                selectedElementID: .constant(template.elements[0].id),
                sample: sample,
                samples: [sample]
            )
        }
        .frame(width: 390, height: 220)
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size, CGSize(width: 390, height: 220))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Editable-Map-Zoom-And-Remove-Controls"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testRouteRadarBuildsRealMapSnapshotOnSimulator() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<18).map { index in
            var telemetry = TelemetrySnapshot.preview
            telemetry.speedKPH = 45 + Double(index) * 2.6
            telemetry.rpm = 2_200 + Double(index) * 135
            let timestamp = startedAt.addingTimeInterval(Double(index))
            return TelemetryHistorySample(
                snapshot: telemetry,
                timestamp: timestamp,
                location: RecordedLocation(
                    latitude: 52.4018 + Double(index) * 0.00022 + sin(Double(index) * 0.5) * 0.00032,
                    longitude: 16.9072 + Double(index) * 0.00041,
                    horizontalAccuracy: 5,
                    altitude: 82,
                    timestamp: timestamp
                )
            )
        }
        let frames = samples.map(VideoTelemetryFrame.init(sample:))
        let generatedRouteMap = await VideoRouteMapSnapshotter.make(samples: frames, includesDetailedLayer: true)
        let routeMap = try XCTUnwrap(generatedRouteMap)
        XCTAssertEqual(routeMap.points.count, samples.count)
        XCTAssertNotNil(routeMap.lightImage)
        XCTAssertNotNil(routeMap.detailedImage)
        XCTAssertNotNil(routeMap.detailedLightImage)
        XCTAssertEqual(routeMap.detailedPoints.count, samples.count)
        for template in [VideoOverlayTemplate.routeRadar, .routeOrbit, .routeChase, .streetAtlas, .iceOrbit, .amberRun] {
            let image = try XCTUnwrap(VideoOverlayCGRenderer.render(
                size: CGSize(width: 390, height: 220),
                sample: try XCTUnwrap(frames.last),
                template: template,
                routeMap: routeMap
            ))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "Simulator-Real-Map-\(template.name.replacingOccurrences(of: " ", with: "-"))"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for index in [6, 13] {
            let image = try XCTUnwrap(VideoOverlayCGRenderer.render(
                size: CGSize(width: 390, height: 220),
                sample: frames[index],
                template: .routeChase,
                routeMap: routeMap
            ))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "Simulator-Route-Chase-Frame-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for zoom in [0.65, 1.85, 3.5] {
            var template = VideoOverlayTemplate.routeChase
            template.elements[0].setMapZoom(zoom)
            let image = try XCTUnwrap(VideoOverlayCGRenderer.render(
                size: CGSize(width: 390, height: 220),
                sample: try XCTUnwrap(frames.last),
                template: template,
                routeMap: routeMap
            ))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "Simulator-Map-Zoom-\(zoom)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testNeonAndStreetShiftPresetPreviewsRenderOnSimulator() throws {
        var snapshot = TelemetrySnapshot.preview
        snapshot.rpm = 2_150
        snapshot.speedKPH = 32
        snapshot.boostBar = -0.3
        snapshot.throttlePercent = 7
        let sample = TelemetryHistorySample(snapshot: snapshot, timestamp: .now)

        for template in [VideoOverlayTemplate.neonCircuit, .streetShift] {
            let preview = ZStack {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.13, blue: 0.13), Color(red: 0.025, green: 0.028, blue: 0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VideoTelemetryOverlayView(template: template, sample: sample)
            }
            .frame(width: 390, height: 220)

            let renderer = ImageRenderer(content: preview)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, CGSize(width: 390, height: 220))
            let attachment = XCTAttachment(image: image)
            attachment.name = "HUD-\(template.name)"
            attachment.lifetime = .keepAlways
            add(attachment)

            let exportedFrame = try XCTUnwrap(
                VideoOverlayCGRenderer.render(
                    size: CGSize(width: 390, height: 220),
                    sample: VideoTelemetryFrame(sample: sample),
                    template: template
                )
            )
            let exportAttachment = XCTAttachment(image: UIImage(cgImage: exportedFrame))
            exportAttachment.name = "Export-HUD-\(template.name)"
            exportAttachment.lifetime = .keepAlways
            add(exportAttachment)
        }
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
        let exporter = DriveVideoExporter { url, creationDate in
            await probe.save(url, creationDate: creationDate)
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

        let exportStartedAt = Date()
        await exporter.export(recording: recording, samples: [], template: nil)
        let exportFinishedAt = Date()

        XCTAssertEqual(exporter.state, .completed)
        let savedURL = await probe.savedURL
        let savedCreationDate = await probe.creationDate
        XCTAssertEqual(savedURL, sourceURL)
        XCTAssertNotNil(savedCreationDate)
        if let savedCreationDate {
            XCTAssertGreaterThanOrEqual(savedCreationDate, exportStartedAt)
            XCTAssertLessThanOrEqual(savedCreationDate, exportFinishedAt)
        }
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
    private(set) var creationDate: Date?

    func save(_ url: URL, creationDate: Date) {
        savedURL = url
        self.creationDate = creationDate
    }
}
