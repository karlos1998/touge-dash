import AVFoundation
import Combine
import Foundation

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

    static func newRecordingURL(id: UUID = UUID(), fileManager: FileManager = .default) throws -> URL {
        try directoryURL(fileManager: fileManager)
            .appending(path: "\(id.uuidString).mov", directoryHint: .notDirectory)
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
