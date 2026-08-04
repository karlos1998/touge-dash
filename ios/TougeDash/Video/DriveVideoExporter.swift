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
    typealias PhotoLibrarySaver = @Sendable (URL) async throws -> Void

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
        template: VideoOverlayTemplate?
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
            if let template {
                let renderedURL = FileManager.default.temporaryDirectory
                    .appending(path: "touge-dash-export-\(UUID().uuidString).mp4")
                temporaryURL = renderedURL
                outputURL = try await renderOverlay(
                    sourceURL: sourceURL,
                    recordingStart: recording.startedAt,
                    samples: samples.map(VideoTelemetryFrame.init(sample:)),
                    template: template,
                    outputURL: renderedURL
                )
            } else {
                state = .rendering(1)
                outputURL = sourceURL
            }

            state = .savingToPhotos
            try await photoLibrarySaver(outputURL)
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
        let asset = AVURLAsset(url: sourceURL)
        let cache = VideoOverlayFrameCache(
            recordingStart: recordingStart,
            samples: samples,
            template: template
        )
        let composition = try await makeVideoComposition(asset: asset, cache: cache)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw DriveVideoExportError.exportUnavailable
        }
        activeExport = exporter
        exporter.videoComposition = composition
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
    nonisolated static func save(_ url: URL) async throws {
        let authorization = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized || authorization == .limited else {
            throw DriveVideoExportError.photoAccessDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
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
    private let samples: [VideoTelemetryFrame]
    private let template: VideoOverlayTemplate
    private let lock = NSLock()
    private var cachedIndex = -1
    private var cachedSize = CGSize.zero
    private var cachedImage: CIImage?

    init(recordingStart: Date, samples: [VideoTelemetryFrame], template: VideoOverlayTemplate) {
        self.recordingStart = recordingStart
        self.samples = samples
        self.template = template
    }

    func image(at seconds: Double, size: CGSize) -> CIImage? {
        guard size.width > 0, size.height > 0, !samples.isEmpty else { return nil }
        let timestamp = recordingStart.addingTimeInterval(max(0, seconds))
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

            for slot in VideoOverlaySlot.allCases {
                let elements = template.elements.filter { $0.slot == slot }
                guard !elements.isEmpty else { continue }
                draw(elements: elements, slot: slot, style: template.style, sample: sample, size: size, context: context)
            }
        }.cgImage
    }

    private static func draw(
        elements: [VideoOverlayElement],
        slot: VideoOverlaySlot,
        style: VideoOverlayStyle,
        sample: VideoTelemetryFrame,
        size: CGSize,
        context: CGContext
    ) {
        let baseScale = max(0.7, min(size.width / 390, size.height / 220))
        let spacing = 5 * baseScale
        let heights = elements.map { 50 * baseScale * CGFloat($0.scale.multiplier) }
        let totalHeight = heights.reduce(0, +) + spacing * CGFloat(max(0, elements.count - 1))
        let centerX: CGFloat
        switch slot {
        case .topLeading, .bottomLeading: centerX = size.width * 0.23
        case .topCenter, .bottomCenter: centerX = size.width * 0.5
        case .topTrailing, .bottomTrailing: centerX = size.width * 0.77
        }
        var y: CGFloat
        switch slot {
        case .topLeading, .topCenter, .topTrailing: y = size.height * 0.07
        case .bottomLeading, .bottomCenter, .bottomTrailing: y = size.height * 0.93 - totalHeight
        }

        for (index, element) in elements.enumerated() {
            let multiplier = CGFloat(element.scale.multiplier)
            let width = min(size.width * 0.42, 104 * baseScale * multiplier)
            let height = heights[index]
            let rect = CGRect(x: centerX - width / 2, y: y, width: width, height: height)
            draw(element: element, style: style, sample: sample, rect: rect, context: context, baseScale: baseScale)
            y += height + spacing
        }
    }

    private static func draw(
        element: VideoOverlayElement,
        style: VideoOverlayStyle,
        sample: VideoTelemetryFrame,
        rect: CGRect,
        context: CGContext,
        baseScale: CGFloat
    ) {
        let accent = element.accent.uiColor
        let corner = 7 * baseScale
        let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)
        context.addPath(path.cgPath)
        context.setFillColor(UIColor.black.withAlphaComponent(style == .minimal ? 0.42 : 0.7).cgColor)
        context.fillPath()

        if style == .arcade {
            context.addPath(path.cgPath)
            context.setStrokeColor(accent.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(max(1, 1.2 * baseScale))
            context.strokePath()
        } else if style == .racing {
            context.setFillColor(accent.cgColor)
            context.fill(CGRect(x: rect.minX + 9 * baseScale, y: rect.minY, width: min(rect.width * 0.34, 34 * baseScale), height: max(2, 2 * baseScale)))
        }

        let multiplier = CGFloat(element.scale.multiplier)
        let value = sample.value(for: element.metric)
        let valueText = value.formatted(.number.precision(.fractionLength(element.metric.precision)))
        let valueFont = UIFont.systemFont(ofSize: 18 * baseScale * multiplier, weight: .black)
        let smallFont = UIFont.systemFont(ofSize: 7 * baseScale * multiplier, weight: .bold)
        let padding = 8 * baseScale * multiplier

        (valueText as NSString).draw(
            at: CGPoint(x: rect.minX + padding, y: rect.minY + 7 * baseScale * multiplier),
            withAttributes: [.font: valueFont, .foregroundColor: UIColor.white]
        )
        let valueWidth = (valueText as NSString).size(withAttributes: [.font: valueFont]).width
        (element.metric.unit as NSString).draw(
            at: CGPoint(x: rect.minX + padding + valueWidth + 4 * baseScale, y: rect.minY + 15 * baseScale * multiplier),
            withAttributes: [.font: smallFont, .foregroundColor: accent]
        )
        (element.metric.shortTitle as NSString).draw(
            at: CGPoint(x: rect.minX + padding, y: rect.maxY - 15 * baseScale * multiplier),
            withAttributes: [.font: smallFont, .foregroundColor: accent]
        )

        if style != .minimal {
            let range = element.metric.defaultRange
            let progress = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
            let bar = CGRect(x: rect.minX + padding, y: rect.maxY - 7 * baseScale, width: rect.width - padding * 2, height: max(2, 2.5 * baseScale))
            context.setFillColor(UIColor.white.withAlphaComponent(0.15).cgColor)
            context.fillEllipse(in: bar)
            context.setFillColor(accent.cgColor)
            context.fill(CGRect(x: bar.minX, y: bar.minY, width: max(2, bar.width * CGFloat(progress)), height: bar.height))
        }
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

    var errorDescription: String? {
        switch self {
        case .fileMissing: localized("Plik filmu nie istnieje już na urządzeniu.")
        case .exportUnavailable: localized("Nie udało się przygotować eksportu filmu.")
        case .photoAccessDenied: localized("Brak zgody na dodawanie filmów do aplikacji Zdjęcia.")
        case .photoSaveFailed: localized("Nie udało się dodać filmu do aplikacji Zdjęcia.")
        }
    }
}
