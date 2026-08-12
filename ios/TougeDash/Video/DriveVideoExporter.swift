@preconcurrency import AVFoundation
@preconcurrency import BackgroundTasks
import CoreImage
import Foundation
import MapKit
import Photos
import SwiftUI
import UIKit

struct VideoTelemetryFrame: Sendable {
    let timestamp: Date
    let rpm: Double
    let boost: Double
    let map: Double
    let throttle: Double
    let coolant: Double
    let intake: Double
    let oilTemperature: Double
    let oilPressure: Double
    let fuelPressure: Double
    let egt1: Double
    let egt2: Double
    let afr: Double
    let lambda: Double
    let battery: Double
    let ignition: Double
    let injectorDuty: Double
    let speed: Double
    let latitude: Double?
    let longitude: Double?

    init(sample: TelemetryHistorySample) {
        timestamp = sample.timestamp
        rpm = sample.rpm
        boost = sample.boostBar
        map = sample.mapKPa
        throttle = sample.throttlePercent
        coolant = sample.coolantCelsius
        intake = sample.intakeCelsius
        oilTemperature = sample.oilTemperatureCelsius
        oilPressure = sample.oilPressureBar
        fuelPressure = sample.fuelPressureBar
        egt1 = sample.egt1Celsius
        egt2 = sample.egt2Celsius
        afr = sample.afr
        lambda = sample.lambda
        battery = sample.batteryVoltage
        ignition = sample.ignitionDegrees
        injectorDuty = sample.injectorDutyPercent
        speed = sample.speedKPH
        latitude = sample.latitude
        longitude = sample.longitude
    }

    func value(for metric: DashboardMetric) -> Double {
        switch metric {
        case .rpm: rpm
        case .boost: boost
        case .map: map
        case .throttle: throttle
        case .coolant: coolant
        case .intake: intake
        case .oilTemperature: oilTemperature
        case .oilPressure: oilPressure
        case .fuelPressure: fuelPressure
        case .egt1: egt1
        case .egt2: egt2
        case .afr: afr
        case .lambda: lambda
        case .batteryVoltage: battery
        case .ignition: ignition
        case .injectorDuty: injectorDuty
        case .speed: speed
        }
    }
}

@MainActor
final class DriveVideoExporter: ObservableObject {
    typealias PhotoLibrarySaver = @Sendable (URL, Date) async throws -> Void

    enum State: Equatable {
        case idle
        case rendering(Double)
        case savingToPhotos
        case completed
        case failed(String)

        var isWorking: Bool {
            switch self {
            case .rendering, .savingToPhotos: true
            default: false
            }
        }
    }

    static let shared = DriveVideoExporter()

    @Published private(set) var state: State = .idle
    private var activeExport: AVAssetExportSession?
    private var wasCancelled = false
    private let photoLibrarySaver: PhotoLibrarySaver
    private let usesContinuedProcessingTask: Bool

    init() {
        photoLibrarySaver = { url, creationDate in
            try await DriveVideoPhotoLibrarySaver.save(url, creationDate: creationDate)
        }
        usesContinuedProcessingTask = true
    }

    init(photoLibrarySaver: @escaping PhotoLibrarySaver) {
        self.photoLibrarySaver = photoLibrarySaver
        usesContinuedProcessingTask = false
    }

    func export(
        recording: DriveVideoRecording,
        samples: [TelemetryHistorySample],
        template: VideoOverlayTemplate?,
        alignment: DriveVideoTimelineAlignment? = nil,
        telemetryStartDate: Date? = nil
    ) async {
        guard !state.isWorking else { return }
        wasCancelled = false
        state = .rendering(0)
        let operation: @MainActor (BGContinuedProcessingTask?) async throws -> Void = { [self] task in
            try await performExport(
                recording: recording,
                samples: samples,
                template: template,
                alignment: alignment,
                telemetryStartDate: telemetryStartDate,
                continuedTask: task
            )
        }

        do {
            if usesContinuedProcessingTask {
                do {
                    try await VideoExportBackgroundCoordinator.shared.run(
                        title: localized("Eksport filmu"),
                        subtitle: localized("Przygotowywanie eksportu…"),
                        onExpiration: { [weak self] in self?.cancelRendering() },
                        operation: operation
                    )
                } catch is VideoExportBackgroundSubmissionError {
                    // Background launches may be disabled by the user or unavailable
                    // on Simulator. Keep foreground export functional in that case.
                    try await operation(nil)
                }
            } else {
                try await operation(nil)
            }
            state = .completed
        } catch {
            if wasCancelled || error is CancellationError {
                state = .idle
            } else {
                state = .failed(error.localizedDescription)
            }
        }
        activeExport = nil
    }

    private func performExport(
        recording: DriveVideoRecording,
        samples: [TelemetryHistorySample],
        template: VideoOverlayTemplate?,
        alignment: DriveVideoTimelineAlignment?,
        telemetryStartDate: Date?,
        continuedTask: BGContinuedProcessingTask?
    ) async throws {
        var temporaryURL: URL?
        defer {
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        }

        do {
            let sourceURL = try DriveVideoFileStore.url(for: recording)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw DriveVideoExportError.fileMissing
            }

            let outputURL: URL
            if template != nil || alignment != nil {
                let renderedURL = FileManager.default.temporaryDirectory
                    .appending(path: "touge-dash-export-\(UUID().uuidString).mp4")
                temporaryURL = renderedURL
                outputURL = try await renderVideo(
                    sourceURL: sourceURL,
                    telemetryStart: telemetryStartDate ?? recording.startedAt,
                    samples: samples.map(VideoTelemetryFrame.init(sample:)),
                    template: template,
                    videoStartSeconds: alignment?.videoStartSeconds ?? 0,
                    duration: alignment?.duration,
                    outputURL: renderedURL,
                    progressHandler: { [weak continuedTask] progress in
                        Self.updateSystemProgress(continuedTask, fraction: progress * 0.94)
                    }
                )
            } else {
                state = .rendering(1)
                Self.updateSystemProgress(continuedTask, fraction: 0.94)
                outputURL = sourceURL
            }

            state = .savingToPhotos
            continuedTask?.updateTitle(
                localized("Eksport filmu"),
                subtitle: localized("Zapisywanie w aplikacji Zdjęcia…")
            )
            Self.updateSystemProgress(continuedTask, fraction: 0.96)
            try await photoLibrarySaver(outputURL, Date())
            Self.updateSystemProgress(continuedTask, fraction: 1)
        } catch {
            throw error
        }
    }

    func cancel() {
        wasCancelled = true
        cancelRendering()
        if usesContinuedProcessingTask {
            VideoExportBackgroundCoordinator.shared.cancel()
        }
        state = .idle
    }

    private func cancelRendering() {
        activeExport?.cancelExport()
        activeExport = nil
    }

    func reset() {
        guard !state.isWorking else { return }
        wasCancelled = false
        state = .idle
    }

    func renderOverlay(
        sourceURL: URL,
        recordingStart: Date,
        samples: [VideoTelemetryFrame],
        template: VideoOverlayTemplate,
        outputURL: URL
    ) async throws -> URL {
        try await renderVideo(
            sourceURL: sourceURL,
            telemetryStart: recordingStart,
            samples: samples,
            template: template,
            videoStartSeconds: 0,
            duration: nil,
            outputURL: outputURL
        )
    }

    func renderVideo(
        sourceURL: URL,
        telemetryStart: Date,
        samples: [VideoTelemetryFrame],
        template: VideoOverlayTemplate?,
        videoStartSeconds: Double,
        duration requestedDuration: Double?,
        outputURL: URL,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let assetDuration = try await asset.load(.duration).seconds
        let startSeconds = min(max(0, videoStartSeconds), max(0, assetDuration))
        let availableDuration = max(0, assetDuration - startSeconds)
        let exportDuration = min(max(0, requestedDuration ?? availableDuration), availableDuration)
        guard exportDuration > 0 else { throw DriveVideoExportError.emptyTimeRange }

        let preset = template == nil ? AVAssetExportPresetHighestQuality : AVAssetExportPresetHEVCHighestQuality
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw DriveVideoExportError.exportUnavailable
        }
        activeExport = exporter
        if let template {
            let routeMap: VideoRouteMapSnapshot? = if template.elements.contains(where: {
                $0.kind == .routeMap || $0.kind == .routeMapCircular
            }) {
                await VideoRouteMapSnapshotter.make(samples: samples)
            } else {
                nil
            }
            let cache = VideoOverlayFrameCache(
                recordingStart: telemetryStart,
                sourceStartSeconds: startSeconds,
                samples: samples,
                template: template,
                routeMap: routeMap
            )
            exporter.videoComposition = try await makeVideoComposition(asset: asset, cache: cache)
        }
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: exportDuration, preferredTimescale: 600)
        )
        state = .rendering(0)

        let progressTask = Task { @MainActor [weak self, weak exporter] in
            while let self, let exporter, self.activeExport === exporter {
                self.state = .rendering(Double(exporter.progress))
                progressHandler?(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
        defer { progressTask.cancel() }

        try await exporter.export(to: outputURL, as: .mp4)
        state = .rendering(1)
        progressHandler?(1)
        return outputURL
    }

    private static func updateSystemProgress(
        _ task: BGContinuedProcessingTask?,
        fraction: Double
    ) {
        guard let task else { return }
        task.progress.totalUnitCount = 1_000
        task.progress.completedUnitCount = Int64(min(max(0, fraction), 1) * 1_000)
    }

    private func makeVideoComposition(
        asset: AVAsset,
        cache: VideoOverlayFrameCache
    ) async throws -> AVVideoComposition {
        try await AVVideoComposition.videoComposition(
            with: asset,
            applyingCIFiltersWithHandler: { request in
                autoreleasepool {
                    let source = request.sourceImage
                    guard let overlay = cache.image(
                        at: request.compositionTime.seconds,
                        size: source.extent.size
                    ) else {
                        request.finish(with: source, context: nil)
                        return
                    }
                    let positioned = overlay.transformed(
                        by: CGAffineTransform(translationX: source.extent.origin.x, y: source.extent.origin.y)
                    )
                    request.finish(with: positioned.composited(over: source), context: nil)
                }
            }
        )
    }

}

private struct VideoExportBackgroundSubmissionError: LocalizedError {
    let underlyingDescription: String

    var errorDescription: String? { underlyingDescription }
}

private struct VideoExportBackgroundBusyError: LocalizedError {
    var errorDescription: String? { localized("Inny eksport filmu jest już w toku.") }
}

@MainActor
final class VideoExportBackgroundCoordinator {
    typealias Operation = @MainActor (BGContinuedProcessingTask) async throws -> Void

    static let shared = VideoExportBackgroundCoordinator()
    static let permittedIdentifier = "it.letscode.touge-dash.video-export.*"

    private var pendingOperation: Operation?
    private var expirationHandler: (@MainActor () -> Void)?
    private var completion: CheckedContinuation<Void, Error>?
    private var submittedIdentifier: String?
    private var activeTask: BGContinuedProcessingTask?
    private var executionTask: Task<Void, Never>?

    private init() {}

    func run(
        title: String,
        subtitle: String,
        onExpiration: @escaping @MainActor () -> Void,
        operation: @escaping Operation
    ) async throws {
        guard pendingOperation == nil, activeTask == nil else {
            throw VideoExportBackgroundBusyError()
        }

        try await withCheckedThrowingContinuation { continuation in
            let identifier = Self.permittedIdentifier.dropLast() + UUID().uuidString
            pendingOperation = operation
            expirationHandler = onExpiration
            completion = continuation
            submittedIdentifier = String(identifier)

            let registered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: String(identifier),
                using: .main
            ) { [weak self] task in
                guard let continuedTask = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    self?.begin(continuedTask)
                }
            }
            guard registered else {
                clearPendingRequest()
                continuation.resume(throwing: VideoExportBackgroundSubmissionError(
                    underlyingDescription: localized("System nie pozwolił uruchomić eksportu w tle.")
                ))
                return
            }

            let request = BGContinuedProcessingTaskRequest(
                identifier: String(identifier),
                title: title,
                subtitle: subtitle
            )
            request.strategy = .queue
            request.requiredResources = []

            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                clearPendingRequest()
                continuation.resume(throwing: VideoExportBackgroundSubmissionError(
                    underlyingDescription: error.localizedDescription
                ))
            }
        }
    }

    func cancel() {
        expirationHandler?()
        if let submittedIdentifier, activeTask == nil {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: submittedIdentifier)
            let continuation = completion
            clearPendingRequest()
            continuation?.resume(throwing: CancellationError())
            return
        }
        executionTask?.cancel()
    }

    private func begin(_ task: BGContinuedProcessingTask) {
        guard let pendingOperation else {
            task.setTaskCompleted(success: false)
            return
        }
        activeTask = task
        task.progress.totalUnitCount = 1_000
        task.progress.completedUnitCount = 0
        task.expirationHandler = { @Sendable [weak self, weak task] in
            guard let task else { return }
            Task { @MainActor in
                self?.expire(task)
            }
        }

        executionTask = Task { @MainActor [weak self, weak task] in
            guard let self, let task else { return }
            do {
                try await pendingOperation(task)
                finish(task, success: true, error: nil)
            } catch {
                finish(task, success: false, error: error)
            }
        }
    }

    private func expire(_ task: BGContinuedProcessingTask) {
        guard activeTask === task else { return }
        expirationHandler?()
        executionTask?.cancel()
    }

    private func finish(
        _ task: BGContinuedProcessingTask,
        success: Bool,
        error: Error?
    ) {
        guard activeTask === task else { return }
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
        let continuation = completion
        clearPendingRequest()
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    private func clearPendingRequest() {
        pendingOperation = nil
        expirationHandler = nil
        completion = nil
        submittedIdentifier = nil
        activeTask = nil
        executionTask = nil
    }
}

/// Photos executes its change block on a private queue. Keep the block outside
/// `DriveVideoExporter`'s MainActor isolation or Swift 6 traps at runtime when
/// the export reaches 100% and the asset is added to the photo library.
enum DriveVideoPhotoLibrarySaver {
    nonisolated static func save(_ url: URL, creationDate: Date) async throws {
        let authorization = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized || authorization == .limited else {
            throw DriveVideoExportError.photoAccessDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                request?.creationDate = creationDate
            }, completionHandler: { succeeded, error in
                if succeeded {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? DriveVideoExportError.photoSaveFailed)
                }
            })
        }
    }
}

struct VideoRouteMapPoint: Sendable {
    let timestamp: Date
    let position: CGPoint
}

struct VideoRouteMapSnapshot: @unchecked Sendable {
    let image: CGImage
    let points: [VideoRouteMapPoint]

    func pointIndex(at timestamp: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if points[middle].timestamp < timestamp { lower = middle + 1 } else { upper = middle }
        }
        if lower == 0 { return 0 }
        if lower == points.count { return points.count - 1 }
        return abs(points[lower - 1].timestamp.timeIntervalSince(timestamp)) <=
            abs(points[lower].timestamp.timeIntervalSince(timestamp)) ? lower - 1 : lower
    }
}

enum VideoRouteMapSnapshotter {
    static let snapshotSize = CGSize(width: 642, height: 408)

    static func make(samples: [VideoTelemetryFrame]) async -> VideoRouteMapSnapshot? {
        let located = samples.compactMap { sample -> (VideoTelemetryFrame, CLLocationCoordinate2D)? in
            guard let latitude = sample.latitude,
                  let longitude = sample.longitude,
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else { return nil }
            return (sample, CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        guard !located.isEmpty else { return nil }

        let latitudes = located.map { $0.1.latitude }
        let longitudes = located.map { $0.1.longitude }
        guard let minimumLatitude = latitudes.min(), let maximumLatitude = latitudes.max(),
              let minimumLongitude = longitudes.min(), let maximumLongitude = longitudes.max() else { return nil }
        let latitudeDelta = max(0.0032, (maximumLatitude - minimumLatitude) * 1.42)
        let longitudeDelta = max(0.0048, (maximumLongitude - minimumLongitude) * 1.42)

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
        options.size = snapshotSize
        options.scale = 1
        options.mapType = .mutedStandard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        if let snapshot = try? await MKMapSnapshotter(options: options).start(),
           let image = snapshot.image.cgImage {
            let points = located.map { sample, coordinate in
                let point = snapshot.point(for: coordinate)
                return VideoRouteMapPoint(
                    timestamp: sample.timestamp,
                    position: CGPoint(
                        x: min(1, max(0, point.x / snapshotSize.width)),
                        y: min(1, max(0, point.y / snapshotSize.height))
                    )
                )
            }
            return VideoRouteMapSnapshot(image: image, points: points)
        }

        let fallback = UIGraphicsImageRenderer(size: snapshotSize).image { rendererContext in
            UIColor(red: 0.018, green: 0.05, blue: 0.064, alpha: 1).setFill()
            rendererContext.fill(CGRect(origin: .zero, size: snapshotSize))
            rendererContext.cgContext.setStrokeColor(UIColor.systemCyan.withAlphaComponent(0.1).cgColor)
            rendererContext.cgContext.setLineWidth(1)
            stride(from: 0.0, through: snapshotSize.width, by: 54).forEach { x in
                rendererContext.cgContext.move(to: CGPoint(x: x, y: 0))
                rendererContext.cgContext.addLine(to: CGPoint(x: x, y: snapshotSize.height))
            }
            stride(from: 0.0, through: snapshotSize.height, by: 54).forEach { y in
                rendererContext.cgContext.move(to: CGPoint(x: 0, y: y))
                rendererContext.cgContext.addLine(to: CGPoint(x: snapshotSize.width, y: y))
            }
            rendererContext.cgContext.strokePath()
        }
        guard let fallbackImage = fallback.cgImage else { return nil }
        let latitudeCenter = (minimumLatitude + maximumLatitude) / 2
        let longitudeCenter = (minimumLongitude + maximumLongitude) / 2
        let latitudeRange = (latitudeCenter - latitudeDelta / 2)...(latitudeCenter + latitudeDelta / 2)
        let longitudeRange = (longitudeCenter - longitudeDelta / 2)...(longitudeCenter + longitudeDelta / 2)
        let fallbackPoints = located.map { sample, coordinate in
            VideoRouteMapPoint(
                timestamp: sample.timestamp,
                position: CGPoint(
                    x: 0.1 + 0.8 * (coordinate.longitude - longitudeRange.lowerBound) / max(0.000001, longitudeRange.upperBound - longitudeRange.lowerBound),
                    y: 0.9 - 0.8 * (coordinate.latitude - latitudeRange.lowerBound) / max(0.000001, latitudeRange.upperBound - latitudeRange.lowerBound)
                )
            )
        }
        return VideoRouteMapSnapshot(image: fallbackImage, points: fallbackPoints)
    }
}

private final class VideoOverlayFrameCache: @unchecked Sendable {
    private let recordingStart: Date
    private let sourceStartSeconds: Double
    private let samples: [VideoTelemetryFrame]
    private let template: VideoOverlayTemplate
    private let routeMap: VideoRouteMapSnapshot?
    private let lock = NSLock()
    private var cachedIndex = -1
    private var cachedSize = CGSize.zero
    private var cachedImage: CIImage?

    init(
        recordingStart: Date,
        sourceStartSeconds: Double,
        samples: [VideoTelemetryFrame],
        template: VideoOverlayTemplate,
        routeMap: VideoRouteMapSnapshot? = nil
    ) {
        self.recordingStart = recordingStart
        self.sourceStartSeconds = sourceStartSeconds
        self.samples = samples
        self.template = template
        self.routeMap = routeMap
    }

    func image(at seconds: Double, size: CGSize) -> CIImage? {
        guard size.width > 0, size.height > 0, !samples.isEmpty else { return nil }
        let timestamp = recordingStart.addingTimeInterval(max(0, seconds - sourceStartSeconds))
        let index = nearestIndex(to: timestamp)

        lock.lock()
        defer { lock.unlock() }
        if index == cachedIndex, size == cachedSize { return cachedImage }
        guard let cgImage = VideoOverlayCGRenderer.render(
            size: size,
            sample: samples[index],
            template: template,
            routeMap: routeMap
        ) else { return nil }
        let image = CIImage(cgImage: cgImage)
        cachedIndex = index
        cachedSize = size
        cachedImage = image
        return image
    }

    private func nearestIndex(to timestamp: Date) -> Int {
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if samples[middle].timestamp < timestamp { lower = middle + 1 } else { upper = middle }
        }
        if lower == 0 { return 0 }
        if lower == samples.count { return samples.count - 1 }
        let before = lower - 1
        return abs(samples[before].timestamp.timeIntervalSince(timestamp)) <=
            abs(samples[lower].timestamp.timeIntervalSince(timestamp)) ? before : lower
    }
}

enum VideoOverlayCGRenderer {
    static func renderRouteMap(
        size: CGSize,
        sample: VideoTelemetryFrame,
        element: VideoOverlayElement,
        routeMap: VideoRouteMapSnapshot?
    ) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            drawRouteMap(
                element: element,
                sample: sample,
                routeMap: routeMap,
                rect: CGRect(origin: .zero, size: size),
                context: rendererContext.cgContext
            )
        }.cgImage
    }

    static func render(
        size: CGSize,
        sample: VideoTelemetryFrame,
        template: VideoOverlayTemplate,
        routeMap: VideoRouteMapSnapshot? = nil
    ) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            let orientation = VideoOverlayCanvasOrientation(size: size)
            let baseScale = max(0.48, min(size.width / 390, size.height / 220))
            for element in template.elements {
                let position = element.position(for: orientation)
                let elementSize = elementSize(for: element, baseScale: baseScale)
                let rect = clampedRect(
                    centeredAt: CGPoint(x: size.width * position.x, y: size.height * position.y),
                    size: elementSize,
                    canvasSize: size
                )
                draw(
                    element: element,
                    style: template.style,
                    configuration: template.gaugeConfiguration,
                    sample: sample,
                    routeMap: routeMap,
                    rect: rect,
                    context: context,
                    baseScale: baseScale
                )
            }
        }.cgImage
    }

    private static func elementSize(for element: VideoOverlayElement, baseScale: CGFloat) -> CGSize {
        let scale = baseScale * CGFloat(element.effectiveScale)
        switch element.kind {
        case .digital: return CGSize(width: 94 * scale, height: 56 * scale)
        case .gauge: return CGSize(width: 112 * scale, height: 112 * scale)
        case .bar: return CGSize(width: 190 * scale, height: 48 * scale)
        case .speedCluster: return CGSize(width: 126 * scale, height: 126 * scale)
        case .oilCluster: return CGSize(width: 116 * scale, height: 116 * scale)
        case .neonTach: return CGSize(width: 184 * scale, height: 150 * scale)
        case .streetShiftTach: return CGSize(width: 190 * scale, height: 150 * scale)
        case .blacklistTach, .carbonTach: return CGSize(width: 150 * scale, height: 150 * scale)
        case .routeMap: return CGSize(width: 214 * scale, height: 136 * scale)
        case .routeMapCircular: return CGSize(width: 154 * scale, height: 154 * scale)
        }
    }

    private static func clampedRect(centeredAt center: CGPoint, size: CGSize, canvasSize: CGSize) -> CGRect {
        let width = min(size.width, canvasSize.width * 0.94)
        let height = min(size.height, canvasSize.height * 0.94)
        let halfWidth = width / 2
        let halfHeight = height / 2
        let safeCenter = CGPoint(
            x: min(max(halfWidth, center.x), canvasSize.width - halfWidth),
            y: min(max(halfHeight, center.y), canvasSize.height - halfHeight)
        )
        return CGRect(x: safeCenter.x - halfWidth, y: safeCenter.y - halfHeight, width: width, height: height)
    }

    private static func draw(
        element: VideoOverlayElement,
        style: VideoOverlayStyle,
        configuration: VideoOverlayGaugeConfiguration,
        sample: VideoTelemetryFrame,
        routeMap: VideoRouteMapSnapshot?,
        rect: CGRect,
        context: CGContext,
        baseScale: CGFloat
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        switch element.kind {
        case .digital:
            drawDigital(element: element, style: style, configuration: configuration, sample: sample, rect: rect, context: context, baseScale: baseScale)
        case .gauge:
            drawGauge(element: element, style: style, configuration: configuration, sample: sample, rect: rect, context: context, baseScale: baseScale)
        case .bar:
            drawBar(element: element, style: style, configuration: configuration, sample: sample, rect: rect, context: context, baseScale: baseScale)
        case .speedCluster:
            drawSpeedCluster(element: element, configuration: configuration, sample: sample, rect: rect, context: context)
        case .oilCluster:
            drawOilCluster(element: element, configuration: configuration, sample: sample, rect: rect, context: context)
        case .neonTach, .blacklistTach, .carbonTach, .streetShiftTach:
            drawArcadeTach(element: element, configuration: configuration, sample: sample, rect: rect, context: context)
        case .routeMap, .routeMapCircular:
            drawRouteMap(element: element, sample: sample, routeMap: routeMap, rect: rect, context: context)
        }
    }

    private static func drawRouteMap(
        element: VideoOverlayElement,
        sample: VideoTelemetryFrame,
        routeMap: VideoRouteMapSnapshot?,
        rect: CGRect,
        context: CGContext
    ) {
        let accent = element.accent.uiColor
        let isCircular = element.kind == .routeMapCircular
        let radius = isCircular ? min(rect.width, rect.height) / 2 : max(8, rect.width * 0.065)
        let mapRect = rect.insetBy(dx: rect.width * 0.018, dy: rect.width * 0.018)
        let clippingPath = isCircular
            ? UIBezierPath(ovalIn: mapRect)
            : UIBezierPath(roundedRect: mapRect, cornerRadius: radius)

        context.saveGState()
        context.addPath(clippingPath.cgPath)
        context.clip()
        var mapContentRect = mapRect
        if let routeMap {
            let imageSize = CGSize(width: routeMap.image.width, height: routeMap.image.height)
            let imageScale = max(mapRect.width / imageSize.width, mapRect.height / imageSize.height)
            let scaledSize = CGSize(width: imageSize.width * imageScale, height: imageSize.height * imageScale)
            mapContentRect = CGRect(
                x: mapRect.midX - scaledSize.width / 2,
                y: mapRect.midY - scaledSize.height / 2,
                width: scaledSize.width,
                height: scaledSize.height
            )
            UIImage(cgImage: routeMap.image).draw(in: mapContentRect)
        } else {
            context.setFillColor(UIColor(red: 0.02, green: 0.055, blue: 0.07, alpha: 0.96).cgColor)
            context.fill(mapRect)
            context.setStrokeColor(accent.withAlphaComponent(0.11).cgColor)
            context.setLineWidth(max(0.6, rect.width * 0.003))
            let grid = rect.width * 0.1
            stride(from: mapRect.minX, through: mapRect.maxX, by: grid).forEach { x in
                context.move(to: CGPoint(x: x, y: mapRect.minY))
                context.addLine(to: CGPoint(x: x, y: mapRect.maxY))
            }
            stride(from: mapRect.minY, through: mapRect.maxY, by: grid).forEach { y in
                context.move(to: CGPoint(x: mapRect.minX, y: y))
                context.addLine(to: CGPoint(x: mapRect.maxX, y: y))
            }
            context.strokePath()
        }
        context.setFillColor(UIColor.black.withAlphaComponent(routeMap == nil ? 0.18 : 0.38).cgColor)
        context.fill(mapRect)

        if let routeMap, !routeMap.points.isEmpty {
            let mapped = routeMap.points.map { point in
                CGPoint(
                    x: mapContentRect.minX + point.position.x * mapContentRect.width,
                    y: mapContentRect.minY + point.position.y * mapContentRect.height
                )
            }
            strokeRoute(mapped, color: UIColor.black.withAlphaComponent(0.78), width: rect.width * 0.026, context: context)
            strokeRoute(mapped, color: UIColor.white.withAlphaComponent(0.36), width: rect.width * 0.011, context: context)

            if let currentIndex = routeMap.pointIndex(at: sample.timestamp) {
                let travelled = Array(mapped.prefix(currentIndex + 1))
                strokeRoute(travelled, color: accent.withAlphaComponent(0.3), width: rect.width * 0.032, context: context)
                strokeRoute(travelled, color: accent, width: rect.width * 0.013, context: context)

                let current = mapped[currentIndex]
                let previous = mapped[max(0, currentIndex - 1)]
                let next = mapped[min(mapped.count - 1, currentIndex + 1)]
                let direction = CGPoint(x: next.x - previous.x, y: next.y - previous.y)
                let angle = atan2(direction.y, direction.x) + .pi / 2
                let markerSize = rect.width * 0.052
                context.saveGState()
                context.translateBy(x: current.x, y: current.y)
                context.rotate(by: angle)
                let marker = UIBezierPath()
                marker.move(to: CGPoint(x: 0, y: -markerSize))
                marker.addLine(to: CGPoint(x: markerSize * 0.68, y: markerSize * 0.78))
                marker.addLine(to: CGPoint(x: 0, y: markerSize * 0.46))
                marker.addLine(to: CGPoint(x: -markerSize * 0.68, y: markerSize * 0.78))
                marker.close()
                context.setShadow(offset: .zero, blur: markerSize * 0.9, color: accent.cgColor)
                context.setFillColor(UIColor.white.cgColor)
                context.addPath(marker.cgPath)
                context.fillPath()
                context.setStrokeColor(accent.cgColor)
                context.setLineWidth(max(1, rect.width * 0.008))
                context.addPath(marker.cgPath)
                context.strokePath()
                context.restoreGState()
            }
        }
        context.restoreGState()

        context.setStrokeColor(UIColor.black.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(max(4, rect.width * 0.026))
        context.addPath(clippingPath.cgPath)
        context.strokePath()
        context.setStrokeColor(accent.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(max(1.2, rect.width * 0.008))
        context.addPath(clippingPath.cgPath)
        context.strokePath()

        if routeMap == nil {
            drawCentered(
                localized("BRAK GPS"),
                font: .monospacedSystemFont(ofSize: rect.width * 0.06, weight: .black),
                color: .systemOrange,
                centerX: mapRect.midX,
                y: mapRect.midY - rect.width * 0.03
            )
        }
    }

    private static func strokeRoute(_ points: [CGPoint], color: UIColor, width: CGFloat, context: CGContext) {
        guard points.count > 1 else { return }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(max(1, width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: points[0])
        points.dropFirst().forEach { context.addLine(to: $0) }
        context.strokePath()
    }

    private static func drawDigital(
        element: VideoOverlayElement,
        style: VideoOverlayStyle,
        configuration: VideoOverlayGaugeConfiguration,
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext,
        baseScale: CGFloat
    ) {
        let accent = element.accent.uiColor
        drawBackground(rect: rect, style: style, accent: accent, context: context, baseScale: baseScale)
        let value = sample.value(for: element.metric)
        let valueText = value.formatted(.number.precision(.fractionLength(element.metric.precision)))
        let localScale = rect.width / 94
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 19 * localScale, weight: .black)
        let smallFont = UIFont.systemFont(ofSize: 7 * localScale, weight: .black)
        let padding = 9 * localScale

        (valueText as NSString).draw(
            at: CGPoint(x: rect.minX + padding, y: rect.minY + 6 * localScale),
            withAttributes: [.font: valueFont, .foregroundColor: UIColor.white]
        )
        let valueWidth = (valueText as NSString).size(withAttributes: [.font: valueFont]).width
        (element.metric.unit as NSString).draw(
            at: CGPoint(x: rect.minX + padding + valueWidth + 4 * localScale, y: rect.minY + 17 * localScale),
            withAttributes: [.font: smallFont, .foregroundColor: accent]
        )
        (element.metric.shortTitle as NSString).draw(
            at: CGPoint(x: rect.minX + padding, y: rect.maxY - 17 * localScale),
            withAttributes: [.font: smallFont, .foregroundColor: accent]
        )

        if style != .minimal {
            let progress = progress(for: element.metric, value: value, configuration: configuration)
            let bar = CGRect(x: rect.minX + padding, y: rect.maxY - 7 * localScale, width: rect.width - padding * 2, height: max(2, 2.5 * localScale))
            context.setFillColor(UIColor.white.withAlphaComponent(0.15).cgColor)
            fillRoundedRect(bar, context: context)
            context.setFillColor(accent.cgColor)
            let fill = CGRect(x: bar.minX, y: bar.minY, width: max(2, bar.width * progress), height: bar.height)
            fillRoundedRect(fill, context: context)
        }
    }

    private static func drawGauge(
        element: VideoOverlayElement,
        style: VideoOverlayStyle,
        configuration: VideoOverlayGaugeConfiguration,
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext,
        baseScale: CGFloat
    ) {
        let accent = element.accent.uiColor
        let value = sample.value(for: element.metric)
        let progress = progress(for: element.metric, value: value, configuration: configuration)
        let lineWidth = max(3, rect.width * 0.054)
        let circleRect = rect.insetBy(dx: lineWidth * 1.25, dy: lineWidth * 1.25)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(circleRect.width, circleRect.height) / 2
        let start = CGFloat.pi * 0.75
        let sweep = CGFloat.pi * 1.5

        context.setFillColor(UIColor.black.withAlphaComponent(style == .minimal ? 0.28 : 0.52).cgColor)
        context.fillEllipse(in: rect)
        context.setLineCap(.round)
        context.setLineWidth(lineWidth)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.14).cgColor)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: start + sweep, clockwise: false)
        context.strokePath()
        context.setStrokeColor(accent.cgColor)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: start + sweep * progress, clockwise: false)
        context.strokePath()
        drawDialNeedle(center: center, radius: radius, start: start, sweep: sweep, progress: progress, metric: element.metric, configuration: configuration, accent: accent, context: context)

        let localScale = rect.width / 112
        let titleFont = UIFont.systemFont(ofSize: 6.5 * localScale, weight: .black)
        let valueFontSize: CGFloat = switch element.metric {
        case .speed: 18
        case .boost: 16
        default: 20
        }
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: valueFontSize * localScale, weight: .black)
        let unitFont = UIFont.systemFont(ofSize: 6 * localScale, weight: .black)
        drawCentered(element.metric.shortTitle, font: titleFont, color: accent, centerX: rect.midX, y: rect.midY + 10 * localScale)
        let valueText = value.formatted(.number.precision(.fractionLength(element.metric.precision)))
        drawCentered(valueText, font: valueFont, color: .white, centerX: rect.midX, y: rect.midY + 20 * localScale)
        drawCentered(element.metric.unit, font: unitFont, color: UIColor.white.withAlphaComponent(0.65), centerX: rect.midX, y: rect.midY + 43 * localScale)
    }

    private static func drawBar(
        element: VideoOverlayElement,
        style: VideoOverlayStyle,
        configuration: VideoOverlayGaugeConfiguration,
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext,
        baseScale: CGFloat
    ) {
        let accent = element.accent.uiColor
        let value = sample.value(for: element.metric)
        let progress = progress(for: element.metric, value: value, configuration: configuration)
        drawBackground(rect: rect, style: style, accent: accent, context: context, baseScale: baseScale)
        let localScale = rect.width / 190
        let padding = 10 * localScale
        let titleFont = UIFont.systemFont(ofSize: 7 * localScale, weight: .black)
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 14 * localScale, weight: .black)
        let unitFont = UIFont.systemFont(ofSize: 6 * localScale, weight: .black)
        (element.metric.shortTitle as NSString).draw(
            at: CGPoint(x: rect.minX + padding, y: rect.minY + 7 * localScale),
            withAttributes: [.font: titleFont, .foregroundColor: accent]
        )
        let valueText = value.formatted(.number.precision(.fractionLength(element.metric.precision)))
        let valueSize = (valueText as NSString).size(withAttributes: [.font: valueFont])
        let unitSize = (element.metric.unit as NSString).size(withAttributes: [.font: unitFont])
        (valueText as NSString).draw(
            at: CGPoint(x: rect.maxX - padding - valueSize.width - unitSize.width - 4 * localScale, y: rect.minY + 3 * localScale),
            withAttributes: [.font: valueFont, .foregroundColor: UIColor.white]
        )
        (element.metric.unit as NSString).draw(
            at: CGPoint(x: rect.maxX - padding - unitSize.width, y: rect.minY + 10 * localScale),
            withAttributes: [.font: unitFont, .foregroundColor: UIColor.white.withAlphaComponent(0.65)]
        )

        let bar = CGRect(x: rect.minX + padding, y: rect.maxY - 14 * localScale, width: rect.width - padding * 2, height: 6 * localScale)
        if style == .arcade, element.metric == .rpm {
            let segments = 12
            let gap = 2 * localScale
            let width = (bar.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            for index in 0..<segments {
                let segment = CGRect(x: bar.minX + CGFloat(index) * (width + gap), y: bar.minY, width: width, height: bar.height)
                let threshold = CGFloat(index + 1) / CGFloat(segments)
                let color: UIColor
                if threshold > progress {
                    color = UIColor.white.withAlphaComponent(0.12)
                } else if index >= 10 {
                    color = DashboardAccent.red.uiColor
                } else if index >= 7 {
                    color = DashboardAccent.orange.uiColor
                } else {
                    color = accent
                }
                context.setFillColor(color.cgColor)
                fillRoundedRect(segment, context: context)
            }
        } else {
            context.setFillColor(UIColor.white.withAlphaComponent(0.14).cgColor)
            fillRoundedRect(bar, context: context)
            let fill = CGRect(x: bar.minX, y: bar.minY, width: max(2, bar.width * progress), height: bar.height)
            context.setFillColor(accent.cgColor)
            fillRoundedRect(fill, context: context)
        }
    }

    private static func drawSpeedCluster(
        element: VideoOverlayElement,
        configuration: VideoOverlayGaugeConfiguration,
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext
    ) {
        let accent = element.accent.uiColor
        context.setFillColor(UIColor.black.withAlphaComponent(0.8).cgColor)
        context.fillEllipse(in: rect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.39
        let value = sample.value(for: .speed)
        drawDialNeedle(center: center, radius: radius, start: .pi * 0.83, sweep: .pi * 1.34, progress: progress(for: .speed, value: value, configuration: configuration), metric: .speed, configuration: configuration, accent: accent, context: context)
        let localScale = rect.width / 126
        drawCentered("RPM \(Int(sample.value(for: .rpm)))", font: .monospacedSystemFont(ofSize: 6 * localScale, weight: .black), color: UIColor.white.withAlphaComponent(0.72), centerX: rect.midX, y: rect.midY - 22 * localScale)
        drawCentered(Int(value).formatted(), font: .monospacedDigitSystemFont(ofSize: 25 * localScale, weight: .black), color: .white, centerX: rect.midX, y: rect.midY - 7 * localScale)
        drawCentered("km/h", font: .systemFont(ofSize: 6 * localScale, weight: .black), color: accent, centerX: rect.midX, y: rect.midY + 19 * localScale)
        let boost = sample.value(for: .boost)
        drawCentered("BOOST \(boost.formatted(.number.precision(.fractionLength(1))))", font: .monospacedSystemFont(ofSize: 5.5 * localScale, weight: .black), color: DashboardAccent.mint.uiColor, centerX: rect.midX, y: rect.midY + 32 * localScale)
        let bar = CGRect(x: rect.midX - 25 * localScale, y: rect.midY + 42 * localScale, width: 50 * localScale, height: 3 * localScale)
        context.setFillColor(UIColor.white.withAlphaComponent(0.15).cgColor)
        fillRoundedRect(bar, context: context)
        context.setFillColor(DashboardAccent.mint.uiColor.cgColor)
        fillRoundedRect(CGRect(x: bar.minX, y: bar.minY, width: max(2, bar.width * progress(for: .boost, value: boost, configuration: configuration)), height: bar.height), context: context)
    }

    private static func drawOilCluster(
        element: VideoOverlayElement,
        configuration: VideoOverlayGaugeConfiguration,
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext
    ) {
        let accent = element.accent.uiColor
        context.setFillColor(UIColor(red: 0.08, green: 0.025, blue: 0.015, alpha: 0.9).cgColor)
        context.fillEllipse(in: rect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.39
        let temperature = sample.value(for: .oilTemperature)
        drawDialNeedle(center: center, radius: radius, start: .pi * 0.83, sweep: .pi * 1.34, progress: progress(for: .oilTemperature, value: temperature, configuration: configuration), metric: .oilTemperature, configuration: configuration, accent: accent, context: context)
        let localScale = rect.width / 116
        drawCentered("OIL TEMP", font: .systemFont(ofSize: 6 * localScale, weight: .black), color: accent, centerX: rect.midX, y: rect.midY - 20 * localScale)
        drawCentered("\(Int(temperature))°", font: .monospacedDigitSystemFont(ofSize: 23 * localScale, weight: .black), color: .white, centerX: rect.midX, y: rect.midY - 5 * localScale)
        let pressure = sample.value(for: .oilPressure)
        drawCentered("OIL P  \(pressure.formatted(.number.precision(.fractionLength(1)))) bar", font: .monospacedSystemFont(ofSize: 6 * localScale, weight: .black), color: UIColor.white.withAlphaComponent(0.8), centerX: rect.midX, y: rect.midY + 23 * localScale)
    }

    private static func drawArcadeTach(
        element: VideoOverlayElement,
        configuration: VideoOverlayGaugeConfiguration,
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext
    ) {
        let kind = element.kind
        let localScale = rect.height / 150
        let faceDimension = 150 * localScale
        let faceRect: CGRect = switch kind {
        case .neonTach: CGRect(x: rect.maxX - faceDimension, y: rect.minY, width: faceDimension, height: faceDimension)
        case .streetShiftTach: CGRect(x: rect.minX, y: rect.minY, width: faceDimension, height: faceDimension)
        default: CGRect(x: rect.midX - faceDimension / 2, y: rect.minY, width: faceDimension, height: faceDimension)
        }
        let center = CGPoint(x: faceRect.midX, y: faceRect.midY)
        let radius = faceDimension * 0.41
        let accent: UIColor = switch kind {
        case .neonTach: UIColor(red: 0.09, green: 0.75, blue: 1, alpha: 1)
        case .blacklistTach: UIColor(red: 0.84, green: 0.18, blue: 0.18, alpha: 1)
        case .carbonTach: UIColor(red: 0.89, green: 0.64, blue: 0.25, alpha: 1)
        default: UIColor(red: 0.94, green: 0.63, blue: 0.29, alpha: 1)
        }
        let face: UIColor = switch kind {
        case .neonTach: UIColor(red: 0.015, green: 0.04, blue: 0.06, alpha: 0.94)
        case .carbonTach: UIColor(red: 0.09, green: 0.075, blue: 0.045, alpha: 0.94)
        case .streetShiftTach: UIColor(red: 0.03, green: 0.04, blue: 0.03, alpha: 0.92)
        default: UIColor(red: 0.035, green: 0.04, blue: 0.045, alpha: 0.94)
        }

        context.setFillColor(face.cgColor)
        context.fillEllipse(in: faceRect)
        if kind == .carbonTach {
            context.saveGState()
            context.addEllipse(in: faceRect.insetBy(dx: 2 * localScale, dy: 2 * localScale))
            context.clip()
            context.setLineWidth(1 * localScale)
            for offset in stride(from: -faceDimension, through: faceDimension * 2, by: 10 * localScale) {
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.035).cgColor)
                context.move(to: CGPoint(x: faceRect.minX + offset, y: faceRect.maxY))
                context.addLine(to: CGPoint(x: faceRect.minX + offset + faceDimension, y: faceRect.minY))
                context.strokePath()
            }
            context.restoreGState()
        }
        context.setStrokeColor(accent.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(max(1, 1.5 * localScale))
        context.strokeEllipse(in: faceRect.insetBy(dx: localScale, dy: localScale))

        let start = CGFloat.pi * 0.778
        let sweep = CGFloat.pi * 1.444
        context.setLineCap(.square)
        for index in 0...40 {
            let fraction = CGFloat(index) / 40
            let angle = start + sweep * fraction
            let major = index.isMultiple(of: 4)
            let length = faceDimension * (major ? 0.075 : 0.04)
            let isRedline = (kind == .blacklistTach || kind == .streetShiftTach) && fraction > 0.78
            context.setStrokeColor((isRedline ? DashboardAccent.red.uiColor : UIColor.white.withAlphaComponent(major ? 0.9 : 0.35)).cgColor)
            context.setLineWidth(max(0.7, faceDimension * (major ? 0.014 : 0.007)))
            context.move(to: CGPoint(x: center.x + cos(angle) * (radius - length), y: center.y + sin(angle) * (radius - length)))
            context.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            context.strokePath()
        }
        let divisions = min(12, max(4, Int((configuration.maximumRPM / 1_000).rounded())))
        for index in 0...divisions {
            let fraction = CGFloat(index) / CGFloat(divisions)
            let angle = start + sweep * fraction
            drawCentered(
                "\(index)",
                font: .systemFont(ofSize: 7 * localScale, weight: .bold),
                color: UIColor.white.withAlphaComponent(0.8),
                centerX: center.x + cos(angle) * radius * 0.69,
                y: center.y + sin(angle) * radius * 0.69 - 4 * localScale
            )
        }
        let rpmProgress = progress(for: .rpm, value: sample.value(for: .rpm), configuration: configuration)
        context.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(max(1.5, faceDimension * 0.018))
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius + faceDimension * 0.035, startAngle: start, endAngle: start + sweep * rpmProgress, clockwise: false)
        context.strokePath()
        let needleAngle = start + sweep * rpmProgress
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(max(2, faceDimension * 0.018))
        context.move(to: center)
        context.addLine(to: CGPoint(x: center.x + cos(needleAngle) * radius * 0.72, y: center.y + sin(needleAngle) * radius * 0.72))
        context.strokePath()
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 3 * localScale, y: center.y - 3 * localScale, width: 6 * localScale, height: 6 * localScale))

        let titleColor = kind == .carbonTach ? UIColor(red: 1, green: 0.82, blue: 0.51, alpha: 1) : accent
        drawCentered("RPM ×1000", font: .systemFont(ofSize: 6.5 * localScale, weight: .black), color: titleColor, centerX: center.x, y: center.y - 32 * localScale)

        if kind == .streetShiftTach {
            let throttle = progress(for: .throttle, value: sample.value(for: .throttle), configuration: configuration)
            context.setStrokeColor(UIColor(red: 0.57, green: 0.93, blue: 0.22, alpha: 1).cgColor)
            context.setLineWidth(max(3, faceDimension * 0.045))
            context.setLineCap(.butt)
            context.addArc(center: center, radius: faceDimension * 0.47, startAngle: .pi * 0.194, endAngle: .pi * (0.194 + 0.611 * throttle), clockwise: false)
            context.strokePath()
            let boxColor = UIColor(red: 0.91, green: 0.66, blue: 0.37, alpha: 1)
            let sideCenterX = rect.minX + 160 * localScale
            let gearRect = CGRect(x: sideCenterX - 21 * localScale, y: center.y - 38 * localScale, width: 42 * localScale, height: 27 * localScale)
            let speedRect = CGRect(x: sideCenterX - 27 * localScale, y: center.y + 13 * localScale, width: 54 * localScale, height: 31 * localScale)
            context.setFillColor(boxColor.cgColor)
            context.addPath(UIBezierPath(roundedRect: gearRect, cornerRadius: 4 * localScale).cgPath); context.fillPath()
            context.addPath(UIBezierPath(roundedRect: speedRect, cornerRadius: 4 * localScale).cgPath); context.fillPath()
            let dark = UIColor(red: 0.14, green: 0.09, blue: 0.04, alpha: 1)
            drawCentered("GEAR", font: .systemFont(ofSize: 5.5 * localScale, weight: .black), color: UIColor(red: 1, green: 0.76, blue: 0.49, alpha: 1), centerX: gearRect.midX, y: gearRect.minY - 9 * localScale)
            drawCentered("–", font: .systemFont(ofSize: 22 * localScale, weight: .black), color: dark, centerX: gearRect.midX, y: gearRect.minY)
            drawCentered(Int(sample.value(for: .speed)).formatted(), font: .monospacedDigitSystemFont(ofSize: 20 * localScale, weight: .black), color: dark, centerX: speedRect.midX, y: speedRect.minY + 3 * localScale)
            drawCentered("KM/H", font: .systemFont(ofSize: 5.5 * localScale, weight: .black), color: .white, centerX: speedRect.midX, y: speedRect.maxY + 2 * localScale)
            drawCentered("THROTTLE \(Int(sample.value(for: .throttle)))%", font: .monospacedSystemFont(ofSize: 6.5 * localScale, weight: .black), color: UIColor(red: 0.61, green: 0.92, blue: 0.29, alpha: 1), centerX: center.x, y: center.y + 58 * localScale)
        } else {
            let speed = Int(sample.value(for: .speed)).formatted()
            drawCentered(speed, font: .monospacedDigitSystemFont(ofSize: 28 * localScale, weight: .black), color: kind == .blacklistTach ? .white : accent, centerX: center.x, y: center.y + 2 * localScale)
            drawCentered("KM/H", font: .systemFont(ofSize: 6.5 * localScale, weight: .black), color: kind == .carbonTach ? .white : accent, centerX: center.x, y: center.y + 32 * localScale)
            if kind == .neonTach {
                let podCenter = CGPoint(x: rect.minX + 25.5 * localScale, y: rect.minY + 112.5 * localScale)
                let podRadius = 26 * localScale
                context.setFillColor(UIColor(red: 0.015, green: 0.04, blue: 0.06, alpha: 0.97).cgColor)
                context.fillEllipse(in: CGRect(x: podCenter.x - podRadius, y: podCenter.y - podRadius, width: podRadius * 2, height: podRadius * 2))
                context.setLineWidth(max(2, podRadius * 0.13))
                context.setLineCap(.round)
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.14).cgColor)
                context.addArc(center: podCenter, radius: podRadius * 0.76, startAngle: .pi * 0.75, endAngle: .pi * 2.25, clockwise: false)
                context.strokePath()
                context.setStrokeColor(UIColor(red: 0.15, green: 0.91, blue: 0.44, alpha: 1).cgColor)
                context.addArc(center: podCenter, radius: podRadius * 0.76, startAngle: .pi * 0.75, endAngle: .pi * (0.75 + 1.5 * progress(for: .boost, value: sample.value(for: .boost), configuration: configuration)), clockwise: false)
                context.strokePath()
                drawCentered("BOOST", font: .systemFont(ofSize: 5.5 * localScale, weight: .black), color: UIColor(red: 0.49, green: 0.96, blue: 0.65, alpha: 1), centerX: podCenter.x, y: podCenter.y - 12 * localScale)
                drawCentered(sample.value(for: .boost).formatted(.number.precision(.fractionLength(1))), font: .monospacedDigitSystemFont(ofSize: 10 * localScale, weight: .black), color: .white, centerX: podCenter.x, y: podCenter.y - 1 * localScale)
                drawCentered("BAR", font: .systemFont(ofSize: 4.5 * localScale, weight: .black), color: UIColor.white.withAlphaComponent(0.7), centerX: podCenter.x, y: podCenter.y + 11 * localScale)
                return
            }
            let secondary: String
            let secondaryColor: UIColor
            if kind == .carbonTach {
                secondary = "OIL \(Int(sample.value(for: .oilTemperature)))°C"
                secondaryColor = UIColor(red: 1, green: 0.81, blue: 0.47, alpha: 1)
            } else {
                secondary = "BOOST \(sample.value(for: .boost).formatted(.number.precision(.fractionLength(1)))) bar"
                secondaryColor = UIColor.white.withAlphaComponent(0.8)
            }
            drawCentered(secondary, font: .monospacedSystemFont(ofSize: 6 * localScale, weight: .black), color: secondaryColor, centerX: center.x, y: center.y + 44 * localScale)
        }
    }

    private static func drawDialNeedle(
        center: CGPoint,
        radius: CGFloat,
        start: CGFloat,
        sweep: CGFloat,
        progress: CGFloat,
        metric: DashboardMetric,
        configuration: VideoOverlayGaugeConfiguration,
        accent: UIColor,
        context: CGContext
    ) {
        context.setLineCap(.round)
        for index in 0...24 {
            let angle = start + sweep * CGFloat(index) / 24
            let length = index.isMultiple(of: 4) ? radius * 0.15 : radius * 0.09
            context.setStrokeColor(UIColor.white.withAlphaComponent(index.isMultiple(of: 4) ? 0.9 : 0.32).cgColor)
            context.setLineWidth(index.isMultiple(of: 4) ? max(1.2, radius * 0.025) : max(0.7, radius * 0.014))
            context.move(to: CGPoint(x: center.x + cos(angle) * (radius - length), y: center.y + sin(angle) * (radius - length)))
            context.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            context.strokePath()
        }
        let range = configuration.range(for: metric)
        for index in 0...6 {
            let angle = start + sweep * CGFloat(index) / 6
            let labelRadius = radius * 0.68
            let labelValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(index) / 6
            drawCentered(
                scaleLabel(labelValue, metric: metric),
                font: .systemFont(ofSize: max(5, radius * 0.1), weight: .bold),
                color: UIColor.white.withAlphaComponent(0.72),
                centerX: center.x + cos(angle) * labelRadius,
                y: center.y + sin(angle) * labelRadius - max(3, radius * 0.05)
            )
        }
        let angle = start + sweep * progress
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(max(2, radius * 0.035))
        context.move(to: center)
        context.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.72, y: center.y + sin(angle) * radius * 0.72))
        context.strokePath()
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius * 0.055, y: center.y - radius * 0.055, width: radius * 0.11, height: radius * 0.11))
    }

    private static func drawBackground(
        rect: CGRect,
        style: VideoOverlayStyle,
        accent: UIColor,
        context: CGContext,
        baseScale: CGFloat
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: max(5, 7 * baseScale))
        context.setFillColor(UIColor.black.withAlphaComponent(style == .minimal ? 0.42 : 0.68).cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        if style == .arcade {
            context.setStrokeColor(accent.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(max(1, 1.2 * baseScale))
            context.addPath(path.cgPath)
            context.strokePath()
        } else if style == .racing {
            context.setFillColor(accent.cgColor)
            context.fill(CGRect(x: rect.minX + 9 * baseScale, y: rect.minY, width: min(rect.width * 0.34, 34 * baseScale), height: max(2, 2 * baseScale)))
        }
    }

    private static func progress(for metric: DashboardMetric, value: Double, configuration: VideoOverlayGaugeConfiguration) -> CGFloat {
        let range = configuration.range(for: metric)
        let raw = (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
        return CGFloat(min(1, max(0, raw)))
    }

    private static func scaleLabel(_ value: Double, metric: DashboardMetric) -> String {
        if metric == .rpm { return "\(Int(value / 1_000))k" }
        if metric == .boost { return value.formatted(.number.precision(.fractionLength(1))) }
        return Int(value).formatted()
    }

    private static func drawCentered(_ text: String, font: UIFont, color: UIColor, centerX: CGFloat, y: CGFloat) {
        let size = (text as NSString).size(withAttributes: [.font: font])
        (text as NSString).draw(
            at: CGPoint(x: centerX - size.width / 2, y: y),
            withAttributes: [.font: font, .foregroundColor: color]
        )
    }

    private static func fillRoundedRect(_ rect: CGRect, context: CGContext) {
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).cgPath)
        context.fillPath()
    }
}

private extension DashboardAccent {
    var uiColor: UIColor {
        switch self {
        case .cyan: UIColor(red: 0.05, green: 0.88, blue: 0.94, alpha: 1)
        case .mint: UIColor(red: 0.21, green: 0.91, blue: 0.62, alpha: 1)
        case .blue: UIColor(red: 0.16, green: 0.48, blue: 1, alpha: 1)
        case .ice: UIColor(red: 0.38, green: 0.75, blue: 1, alpha: 1)
        case .orange: UIColor(red: 1, green: 0.47, blue: 0.19, alpha: 1)
        case .yellow: UIColor(red: 1, green: 0.77, blue: 0.19, alpha: 1)
        case .red: UIColor(red: 1, green: 0.22, blue: 0.25, alpha: 1)
        case .white: .white
        }
    }
}

private enum DriveVideoExportError: LocalizedError {
    case fileMissing
    case exportUnavailable
    case photoAccessDenied
    case photoSaveFailed
    case emptyTimeRange

    var errorDescription: String? {
        switch self {
        case .fileMissing: localized("Plik filmu nie istnieje już na urządzeniu.")
        case .exportUnavailable: localized("Nie udało się przygotować eksportu filmu.")
        case .photoAccessDenied: localized("Brak zgody na dodawanie filmów do aplikacji Zdjęcia.")
        case .photoSaveFailed: localized("Nie udało się dodać filmu do aplikacji Zdjęcia.")
        case .emptyTimeRange: localized("Wybrany wspólny fragment filmu i danych jest pusty.")
        }
    }
}
