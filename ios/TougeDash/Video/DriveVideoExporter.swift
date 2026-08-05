@preconcurrency import AVFoundation
import CoreImage
import Foundation
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
    let afr: Double
    let lambda: Double
    let battery: Double
    let ignition: Double
    let injectorDuty: Double
    let speed: Double

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
        afr = sample.afr
        lambda = sample.lambda
        battery = sample.batteryVoltage
        ignition = sample.ignitionDegrees
        injectorDuty = sample.injectorDutyPercent
        speed = sample.speedKPH
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

    @Published private(set) var state: State = .idle
    private var activeExport: AVAssetExportSession?
    private var wasCancelled = false
    private let photoLibrarySaver: PhotoLibrarySaver

    init(photoLibrarySaver: @escaping PhotoLibrarySaver = DriveVideoPhotoLibrarySaver.save) {
        self.photoLibrarySaver = photoLibrarySaver
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
        var temporaryURL: URL?
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
                    outputURL: renderedURL
                )
            } else {
                state = .rendering(1)
                outputURL = sourceURL
            }

            state = .savingToPhotos
            try await photoLibrarySaver(outputURL, Date())
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
            state = .completed
        } catch {
            if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
            if wasCancelled || (error as? CancellationError) != nil {
                state = .idle
            } else {
                state = .failed(error.localizedDescription)
            }
        }
        activeExport = nil
    }

    func cancel() {
        wasCancelled = true
        activeExport?.cancelExport()
        activeExport = nil
        state = .idle
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
        outputURL: URL
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
            let cache = VideoOverlayFrameCache(
                recordingStart: telemetryStart,
                sourceStartSeconds: startSeconds,
                samples: samples,
                template: template
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
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
        defer { progressTask.cancel() }

        try await exporter.export(to: outputURL, as: .mp4)
        state = .rendering(1)
        return outputURL
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

private final class VideoOverlayFrameCache: @unchecked Sendable {
    private let recordingStart: Date
    private let sourceStartSeconds: Double
    private let samples: [VideoTelemetryFrame]
    private let template: VideoOverlayTemplate
    private let lock = NSLock()
    private var cachedIndex = -1
    private var cachedSize = CGSize.zero
    private var cachedImage: CIImage?

    init(
        recordingStart: Date,
        sourceStartSeconds: Double,
        samples: [VideoTelemetryFrame],
        template: VideoOverlayTemplate
    ) {
        self.recordingStart = recordingStart
        self.sourceStartSeconds = sourceStartSeconds
        self.samples = samples
        self.template = template
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
            template: template
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

private enum VideoOverlayCGRenderer {
    static func render(size: CGSize, sample: VideoTelemetryFrame, template: VideoOverlayTemplate) -> CGImage? {
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
                    sample: sample,
                    rect: rect,
                    context: context,
                    baseScale: baseScale
                )
            }
        }.cgImage
    }

    private static func elementSize(for element: VideoOverlayElement, baseScale: CGFloat) -> CGSize {
        let scale = baseScale * CGFloat(element.scale.multiplier)
        switch element.kind {
        case .digital: return CGSize(width: 94 * scale, height: 56 * scale)
        case .gauge: return CGSize(width: 112 * scale, height: 112 * scale)
        case .bar: return CGSize(width: 190 * scale, height: 48 * scale)
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
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext,
        baseScale: CGFloat
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        switch element.kind {
        case .digital:
            drawDigital(element: element, style: style, sample: sample, rect: rect, context: context, baseScale: baseScale)
        case .gauge:
            drawGauge(element: element, style: style, sample: sample, rect: rect, context: context, baseScale: baseScale)
        case .bar:
            drawBar(element: element, style: style, sample: sample, rect: rect, context: context, baseScale: baseScale)
        }
    }

    private static func drawDigital(
        element: VideoOverlayElement,
        style: VideoOverlayStyle,
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
            let progress = progress(for: element.metric, value: value)
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
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext,
        baseScale: CGFloat
    ) {
        let accent = element.accent.uiColor
        let value = sample.value(for: element.metric)
        let progress = progress(for: element.metric, value: value)
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

        let localScale = rect.width / 112
        let titleFont = UIFont.systemFont(ofSize: 6.5 * localScale, weight: .black)
        let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 22 * localScale, weight: .black)
        let unitFont = UIFont.systemFont(ofSize: 6 * localScale, weight: .black)
        drawCentered(element.metric.shortTitle, font: titleFont, color: accent, centerX: rect.midX, y: rect.midY - 17 * localScale)
        let valueText = value.formatted(.number.precision(.fractionLength(element.metric.precision)))
        let valueSize = (valueText as NSString).size(withAttributes: [.font: valueFont])
        let unitSize = (element.metric.unit as NSString).size(withAttributes: [.font: unitFont])
        let totalWidth = valueSize.width + 3 * localScale + unitSize.width
        let originX = rect.midX - totalWidth / 2
        (valueText as NSString).draw(
            at: CGPoint(x: originX, y: rect.midY - 5 * localScale),
            withAttributes: [.font: valueFont, .foregroundColor: UIColor.white]
        )
        (element.metric.unit as NSString).draw(
            at: CGPoint(x: originX + valueSize.width + 3 * localScale, y: rect.midY + 8 * localScale),
            withAttributes: [.font: unitFont, .foregroundColor: UIColor.white.withAlphaComponent(0.65)]
        )
    }

    private static func drawBar(
        element: VideoOverlayElement,
        style: VideoOverlayStyle,
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext,
        baseScale: CGFloat
    ) {
        let accent = element.accent.uiColor
        let value = sample.value(for: element.metric)
        let progress = progress(for: element.metric, value: value)
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

    private static func progress(for metric: DashboardMetric, value: Double) -> CGFloat {
        let range = metric.defaultRange
        let raw = (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
        return CGFloat(min(1, max(0, raw)))
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
