import AVFoundation
import Combine
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum DriveVideoSourceKind: String, Codable, Sendable {
    case camera
    case photoLibrary
    case dashCamera

    var title: String {
        switch self {
        case .camera: localized("Kamera telefonu")
        case .photoLibrary: localized("Film z biblioteki")
        case .dashCamera: localized("Kamera samochodowa")
        }
    }
}

enum DriveVideoTimelineSynchronization {
    static func clippedDuration(
        videoStartedAt: Date,
        videoDuration: TimeInterval,
        telemetryBoundaryAt: Date?
    ) -> TimeInterval {
        let safeVideoDuration = max(0, videoDuration)
        guard let telemetryBoundaryAt else { return safeVideoDuration }
        return min(safeVideoDuration, max(0, telemetryBoundaryAt.timeIntervalSince(videoStartedAt)))
    }
}

struct DriveVideoTimelineAlignment: Equatable, Sendable {
    var videoStartSeconds: Double
    var telemetryStartSeconds: Double
    var duration: Double

    var videoEndSeconds: Double { videoStartSeconds + duration }
    var telemetryEndSeconds: Double { telemetryStartSeconds + duration }

    init(
        videoStartSeconds: Double,
        telemetryStartSeconds: Double,
        duration: Double,
        videoDuration: Double,
        telemetryDuration: Double
    ) {
        self.videoStartSeconds = videoStartSeconds
        self.telemetryStartSeconds = telemetryStartSeconds
        self.duration = duration
        clamp(videoDuration: videoDuration, telemetryDuration: telemetryDuration)
    }

    init(recording: DriveVideoRecording, session: DriveSession) {
        let videoStart = recording.videoTrimStartSeconds ?? 0
        let telemetryStart = recording.telemetryTrimStartSeconds
            ?? max(0, recording.startedAt.timeIntervalSince(session.startedAt))
        let telemetryDuration = session.duration > 0 ? session.duration : recording.duration
        let available = min(
            max(0, recording.duration - videoStart),
            max(0, telemetryDuration - telemetryStart)
        )
        self.init(
            videoStartSeconds: videoStart,
            telemetryStartSeconds: telemetryStart,
            duration: recording.exportDurationSeconds.flatMap { $0 > 0 ? $0 : nil } ?? available,
            videoDuration: recording.duration,
            telemetryDuration: telemetryDuration
        )
    }

    mutating func clamp(videoDuration: Double, telemetryDuration: Double) {
        let safeVideoDuration = max(0, videoDuration)
        let safeTelemetryDuration = max(0, telemetryDuration)
        videoStartSeconds = min(max(0, videoStartSeconds), safeVideoDuration)
        telemetryStartSeconds = min(max(0, telemetryStartSeconds), safeTelemetryDuration)
        let maximumDuration = min(
            max(0, safeVideoDuration - videoStartSeconds),
            max(0, safeTelemetryDuration - telemetryStartSeconds)
        )
        duration = min(max(0, duration), maximumDuration)
    }

    func telemetryStartDate(session: DriveSession) -> Date {
        session.startedAt.addingTimeInterval(telemetryStartSeconds)
    }

    func trimming(
        relativeStart: Double,
        duration requestedDuration: Double,
        videoDuration: Double,
        telemetryDuration: Double
    ) -> Self {
        let safeRelativeStart = min(max(0, relativeStart), duration)
        return Self(
            videoStartSeconds: videoStartSeconds + safeRelativeStart,
            telemetryStartSeconds: telemetryStartSeconds + safeRelativeStart,
            duration: min(max(0, requestedDuration), duration - safeRelativeStart),
            videoDuration: videoDuration,
            telemetryDuration: telemetryDuration
        )
    }

    func persist(to recording: DriveVideoRecording) {
        recording.videoTrimStartSeconds = videoStartSeconds
        recording.telemetryTrimStartSeconds = telemetryStartSeconds
        recording.exportDurationSeconds = duration
    }
}

struct DriveVideoTransfer: Transferable, Sendable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { value in
            SentTransferredFile(value.fileURL)
        } importing: { received in
            let sourceExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let temporaryURL = FileManager.default.temporaryDirectory
                .appending(path: "touge-dash-import-\(UUID().uuidString).\(sourceExtension)")
            try FileManager.default.copyItem(at: received.file, to: temporaryURL)
            return DriveVideoTransfer(fileURL: temporaryURL)
        }
    }
}

struct DriveVideoAssetMetadata: Sendable {
    let duration: Double
    let width: Int
    let height: Int
    let framesPerSecond: Double
    let hasAudio: Bool
}

enum DriveVideoAssetInspector {
    nonisolated static func metadata(for url: URL) async throws -> DriveVideoAssetMetadata {
        let asset = AVURLAsset(url: url)
        let rawDuration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DriveVideoImportError.invalidVideo
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = size.applying(transform)
        let rate = try await track.load(.nominalFrameRate)
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        let duration = rawDuration.isFinite ? max(0, rawDuration) : 0
        guard duration > 0, abs(transformed.width) > 0, abs(transformed.height) > 0 else {
            throw DriveVideoImportError.invalidVideo
        }
        return DriveVideoAssetMetadata(
            duration: duration,
            width: Int(abs(transformed.width).rounded()),
            height: Int(abs(transformed.height).rounded()),
            framesPerSecond: Double(rate),
            hasAudio: hasAudio
        )
    }
}

struct PreparedDriveVideoImport: Sendable {
    let fileName: String
    let displayName: String
    let fileSizeBytes: Int64
    let metadata: DriveVideoAssetMetadata
}

enum DriveVideoPreparationStage: Sendable {
    case inspecting
    case copying(Double)
}

enum DriveVideoImportService {
    nonisolated static func prepare(
        from transfer: DriveVideoTransfer,
        onProgress: (@MainActor @Sendable (DriveVideoPreparationStage) -> Void)? = nil
    ) async throws -> PreparedDriveVideoImport {
        defer { try? FileManager.default.removeItem(at: transfer.fileURL) }
        await onProgress?(.inspecting)
        let metadata = try await DriveVideoAssetInspector.metadata(for: transfer.fileURL)
        let sourceExtension = transfer.fileURL.pathExtension.isEmpty ? "mov" : transfer.fileURL.pathExtension.lowercased()
        let destination = try DriveVideoFileStore.newRecordingURL(fileExtension: sourceExtension)

        do {
            let bytes = try await copyFile(
                from: transfer.fileURL,
                to: destination,
                onProgress: onProgress
            )
            return PreparedDriveVideoImport(
                fileName: destination.lastPathComponent,
                displayName: transfer.fileURL.deletingPathExtension().lastPathComponent,
                fileSizeBytes: bytes,
                metadata: metadata
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private nonisolated static func copyFile(
        from source: URL,
        to destination: URL,
        onProgress: (@MainActor @Sendable (DriveVideoPreparationStage) -> Void)?
    ) async throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let totalBytes = max(0, (attributes[.size] as? NSNumber)?.int64Value ?? 0)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let sourceHandle = try FileHandle(forReadingFrom: source)
        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }

        // Four-megabyte chunks keep memory bounded without flooding SwiftUI with
        // hundreds of progress updates per second on fast local storage.
        let chunkSize = 4_194_304
        var copiedBytes: Int64 = 0
        await onProgress?(.copying(0))

        while let data = try sourceHandle.read(upToCount: chunkSize), !data.isEmpty {
            try Task.checkCancellation()
            try destinationHandle.write(contentsOf: data)
            copiedBytes += Int64(data.count)
            let fraction = totalBytes > 0
                ? min(1, Double(copiedBytes) / Double(totalBytes))
                : 0
            await onProgress?(.copying(fraction))
        }

        try destinationHandle.synchronize()
        await onProgress?(.copying(1))
        return copiedBytes
    }
}

enum DriveVideoImportError: LocalizedError {
    case invalidVideo
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidVideo: localized("Wybrany plik nie zawiera prawidłowego obrazu wideo.")
        case .unavailable: localized("Nie udało się pobrać filmu z biblioteki Zdjęć.")
        }
    }
}

enum DriveVideoQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case storageSaver
    case fullHD
    case ultraHD

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storageSaver: localized("720p · mniej pamięci")
        case .fullHD: localized("1080p · zalecane")
        case .ultraHD: localized("4K · duży plik")
        }
    }

    var detail: String {
        switch self {
        case .storageSaver: localized("Najdłuższe przejazdy i najmniejsze pliki")
        case .fullHD: localized("Dobry balans jakości i rozmiaru")
        case .ultraHD: localized("Najwyższa jakość, jeśli kamera ją obsługuje")
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .storageSaver: .hd1280x720
        case .fullHD: .hd1920x1080
        case .ultraHD: .hd4K3840x2160
        }
    }
}

enum DriveVideoExportQuality: String, CaseIterable, Identifiable, Sendable {
    case fastFullHD
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastFullHD: localized("Szybki · 1080p")
        case .original: localized("Oryginalna rozdzielczość")
        }
    }

    var detail: String {
        switch self {
        case .fastFullHD: localized("Szybszy eksport i mniejszy plik, nadal w wysokiej jakości")
        case .original: localized("Pełna rozdzielczość kamery i dłuższy czas renderowania")
        }
    }

    func exportPreset(hasOverlay: Bool) -> String {
        switch self {
        case .fastFullHD:
            AVAssetExportPresetHEVC1920x1080
        case .original:
            hasOverlay ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetPassthrough
        }
    }
}

struct DriveVideoCamera: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let position: AVCaptureDevice.Position
    let deviceType: AVCaptureDevice.DeviceType

    var symbol: String {
        position == .front ? "camera.rotate.fill" : "camera.fill"
    }
}

@MainActor
final class DriveVideoSettingsStore: ObservableObject {
    private enum Key {
        static let enabled = "TougeDash.video.autoRecord"
        static let cameraID = "TougeDash.video.cameraID"
        static let audio = "TougeDash.video.audio"
        static let quality = "TougeDash.video.quality"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.enabled) }
    }
    @Published var selectedCameraID: String? {
        didSet { defaults.set(selectedCameraID, forKey: Key.cameraID) }
    }
    @Published var recordsAudio: Bool {
        didSet { defaults.set(recordsAudio, forKey: Key.audio) }
    }
    @Published var quality: DriveVideoQuality {
        didSet { defaults.set(quality.rawValue, forKey: Key.quality) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        let forcesRecording = ProcessInfo.processInfo.environment["TOUGE_DASH_FORCE_VIDEO_RECORDING"] == "1"
        #else
        let forcesRecording = false
        #endif
        isEnabled = forcesRecording || defaults.bool(forKey: Key.enabled)
        selectedCameraID = defaults.string(forKey: Key.cameraID)
        recordsAudio = defaults.object(forKey: Key.audio) as? Bool ?? true
        quality = defaults.string(forKey: Key.quality)
            .flatMap(DriveVideoQuality.init(rawValue:)) ?? .fullHD
    }
}

enum DriveVideoFileStore {
    static let directoryName = "DriveVideos"

    static func directoryURL(fileManager: FileManager = .default) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appending(path: directoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(resourceValues)
        return directory
    }

    static func newRecordingURL(
        id: UUID = UUID(),
        fileExtension: String = "mov",
        fileManager: FileManager = .default
    ) throws -> URL {
        let safeExtension = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return try directoryURL(fileManager: fileManager)
            .appending(path: "\(id.uuidString).\(safeExtension.isEmpty ? "mov" : safeExtension)", directoryHint: .notDirectory)
    }

    static func url(for recording: DriveVideoRecording, fileManager: FileManager = .default) throws -> URL {
        try directoryURL(fileManager: fileManager)
            .appending(path: recording.fileName, directoryHint: .notDirectory)
    }

    static func delete(_ recording: DriveVideoRecording, fileManager: FileManager = .default) throws {
        let url = try url(for: recording, fileManager: fileManager)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

extension DashboardMetric {
    func value(in sample: TelemetryHistorySample) -> Double {
        switch self {
        case .rpm: sample.rpm
        case .boost: sample.boostBar
        case .map: sample.mapKPa
        case .throttle: sample.throttlePercent
        case .coolant: sample.coolantCelsius
        case .intake: sample.intakeCelsius
        case .egt1: sample.egt1Celsius
        case .egt2: sample.egt2Celsius
        case .oilTemperature: sample.oilTemperatureCelsius
        case .oilPressure: sample.oilPressureBar
        case .fuelPressure: sample.fuelPressureBar
        case .afr: sample.afr
        case .lambda: sample.lambda
        case .batteryVoltage: sample.batteryVoltage
        case .ignition: sample.ignitionDegrees
        case .injectorDuty: sample.injectorDutyPercent
        case .speed: sample.speedKPH
        }
    }
}
