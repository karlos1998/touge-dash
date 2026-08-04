@preconcurrency import AVFoundation
import Foundation
import SwiftData
import UIKit

@MainActor
final class DriveVideoRecorder: NSObject, ObservableObject {
    enum State: Equatable {
        case disabled
        case ready
        case requestingPermission
        case preparing
        case recording(sessionID: UUID, startedAt: Date)
        case stopping
        case failed(String)
    }

    @Published private(set) var state: State
    @Published private(set) var cameras: [DriveVideoCamera] = []
    @Published private(set) var lastRecording: DriveVideoRecording?
    @Published private(set) var freeDiskBytes: Int64?

    let settings: DriveVideoSettingsStore

    private let context: ModelContext
    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var pendingSessionID: UUID?
    private var currentSessionID: UUID?
    private var currentURL: URL?
    private var currentStartedAt: Date?
    private var currentCameraName = ""
    private var currentHasAudio = false
    private var permissionRequestID = UUID()
    private var isConfigured = false
    private var latestTelemetrySessionID: UUID?
    private var latestTelemetryAt = Date.distantPast
    private var isApplicationActive = true

    init(container: ModelContainer, settings: DriveVideoSettingsStore) {
        self.settings = settings
        context = ModelContext(container)
        context.autosaveEnabled = true
        state = settings.isEnabled ? .ready : .disabled
        super.init()
        refreshCameras()
        refreshDiskCapacity()
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var currentSession: UUID? {
        if case .recording(let sessionID, _) = state { return sessionID }
        return nil
    }

    var activeTelemetrySessionID: UUID? {
        Date.now.timeIntervalSince(latestTelemetryAt) < 3 ? latestTelemetrySessionID : nil
    }

    var statusLabel: String {
        switch state {
        case .disabled: localized("Nagrywanie wyłączone")
        case .ready: localized("Gotowe · film rozpocznie się z przejazdem")
        case .requestingPermission: localized("Oczekiwanie na dostęp do kamery")
        case .preparing: localized("Przygotowywanie kamery…")
        case .recording: localized("Nagrywanie przejazdu")
        case .stopping: localized("Zapisywanie filmu…")
        case .failed(let message): message
        }
    }

    var selectedCamera: DriveVideoCamera? {
        if let selectedID = settings.selectedCameraID,
           let selected = cameras.first(where: { $0.id == selectedID }) {
            return selected
        }
        return cameras.first(where: { $0.position == .back && $0.deviceType == .builtInWideAngleCamera })
            ?? cameras.first(where: { $0.position == .back })
            ?? cameras.first
    }

    func refreshCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: .unspecified
        )
        cameras = discovery.devices.map {
            DriveVideoCamera(id: $0.uniqueID, name: $0.localizedName, position: $0.position, deviceType: $0.deviceType)
        }
        .sorted {
            if $0.position != $1.position { return $0.position == .back }
            return cameraOrder($0.deviceType) < cameraOrder($1.deviceType)
        }

        if settings.selectedCameraID == nil || !cameras.contains(where: { $0.id == settings.selectedCameraID }) {
            settings.selectedCameraID = selectedCamera?.id
        }
    }

    func setEnabled(_ enabled: Bool, activeSessionID: UUID?) {
        settings.isEnabled = enabled
        permissionRequestID = UUID()
        if enabled {
            state = .ready
            if let activeSessionID {
                handleTelemetry(sessionID: activeSessionID)
            } else {
                Task { await requestPermissionsForFutureRecording() }
            }
        } else {
            pendingSessionID = nil
            if movieOutput.isRecording {
                stopRecording()
            } else {
                stopCaptureSession()
                state = .disabled
            }
        }
    }

    func selectCamera(_ id: String, activeSessionID: UUID?) {
        guard cameras.contains(where: { $0.id == id }) else { return }
        settings.selectedCameraID = id
        reconfigureForNextClip(activeSessionID: activeSessionID)
    }

    func updateQuality(_ quality: DriveVideoQuality, activeSessionID: UUID?) {
        settings.quality = quality
        reconfigureForNextClip(activeSessionID: activeSessionID)
    }

    func updateAudio(_ enabled: Bool, activeSessionID: UUID?) {
        settings.recordsAudio = enabled
        reconfigureForNextClip(activeSessionID: activeSessionID)
        if enabled, activeSessionID == nil, settings.isEnabled {
            Task { await requestPermissionsForFutureRecording() }
        }
    }

    func handleTelemetry(sessionID: UUID) {
        latestTelemetrySessionID = sessionID
        latestTelemetryAt = .now
        guard settings.isEnabled, isApplicationActive else { return }
        switch state {
        case .recording(let current, _) where current == sessionID:
            return
        case .recording:
            pendingSessionID = sessionID
            stopRecording()
        case .stopping:
            pendingSessionID = sessionID
        case .requestingPermission, .preparing:
            pendingSessionID = sessionID
        default:
            pendingSessionID = sessionID
            Task { await prepareAndStart(sessionID: sessionID) }
        }
    }

    func connectionDidEnd() {
        latestTelemetrySessionID = nil
        latestTelemetryAt = .distantPast
        pendingSessionID = nil
        if movieOutput.isRecording {
            stopRecording()
        } else if settings.isEnabled {
            stopCaptureSession()
            state = .ready
        }
    }

    func applicationDidEnterBackground() {
        isApplicationActive = false
        permissionRequestID = UUID()
        pendingSessionID = nil
        if movieOutput.isRecording {
            stopRecording()
        } else {
            stopCaptureSession()
        }
    }

    func applicationDidBecomeActive() {
        isApplicationActive = true
        if let activeTelemetrySessionID, settings.isEnabled {
            handleTelemetry(sessionID: activeTelemetrySessionID)
        } else if settings.isEnabled, !isRecording {
            state = .ready
        }
    }

    private func reconfigureForNextClip(activeSessionID: UUID?) {
        isConfigured = false
        if movieOutput.isRecording {
            pendingSessionID = activeSessionID
            stopRecording()
        } else if let activeSessionID, settings.isEnabled {
            stopCaptureSession()
            handleTelemetry(sessionID: activeSessionID)
        }
    }

    private func prepareAndStart(sessionID: UUID) async {
        guard settings.isEnabled, !movieOutput.isRecording else { return }
        let requestID = UUID()
        permissionRequestID = requestID
        state = .requestingPermission

        let cameraAllowed = await requestAccess(for: .video)
        guard requestID == permissionRequestID, settings.isEnabled else { return }
        guard cameraAllowed else {
            fail(localized("Brak dostępu do kamery. Włącz go w Ustawieniach iOS."))
            return
        }

        var audioAllowed = false
        if settings.recordsAudio {
            audioAllowed = await requestAccess(for: .audio)
        }
        guard requestID == permissionRequestID, settings.isEnabled else { return }

        refreshDiskCapacity()
        if let freeDiskBytes, freeDiskBytes < 500_000_000 {
            fail(localized("Za mało wolnego miejsca. Nagrywanie wymaga co najmniej 500 MB."))
            return
        }

        state = .preparing
        do {
            try configureSession(includeAudio: audioAllowed)
            guard settings.isEnabled, pendingSessionID == sessionID else {
                state = settings.isEnabled ? .ready : .disabled
                return
            }
            try startRecording(sessionID: sessionID)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func requestPermissionsForFutureRecording() async {
        guard settings.isEnabled, !movieOutput.isRecording else { return }
        let requestID = UUID()
        permissionRequestID = requestID
        state = .requestingPermission

        let cameraAllowed = await requestAccess(for: .video)
        guard requestID == permissionRequestID, settings.isEnabled else { return }
        guard cameraAllowed else {
            fail(localized("Brak dostępu do kamery. Włącz go w Ustawieniach iOS."))
            return
        }

        if settings.recordsAudio {
            _ = await requestAccess(for: .audio)
        }
        guard requestID == permissionRequestID, settings.isEnabled else { return }

        refreshDiskCapacity()
        state = .ready
    }

    private func configureSession(includeAudio: Bool) throws {
        guard let selectedCamera,
              let device = AVCaptureDevice(uniqueID: selectedCamera.id) else {
            throw DriveVideoRecorderError.noCamera
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.inputs.forEach(captureSession.removeInput)
        if captureSession.outputs.contains(movieOutput) == false {
            guard captureSession.canAddOutput(movieOutput) else { throw DriveVideoRecorderError.outputUnavailable }
            captureSession.addOutput(movieOutput)
        }

        let videoInput = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(videoInput) else { throw DriveVideoRecorderError.cameraUnavailable }
        captureSession.addInput(videoInput)

        var audioAttached = false
        if includeAudio, let microphone = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: microphone)
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
                audioAttached = true
            }
        }

        let requestedPreset = settings.quality.sessionPreset
        if captureSession.canSetSessionPreset(requestedPreset) {
            captureSession.sessionPreset = requestedPreset
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        } else {
            captureSession.sessionPreset = .high
        }

        movieOutput.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
        if let connection = movieOutput.connection(with: .video) {
            if movieOutput.availableVideoCodecTypes.contains(.hevc) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
            if connection.isVideoRotationAngleSupported(interfaceRotationAngle) {
                connection.videoRotationAngle = interfaceRotationAngle
            }
        }

        currentCameraName = selectedCamera.name
        currentHasAudio = audioAttached
        isConfigured = true
    }

    private func startRecording(sessionID: UUID) throws {
        guard isConfigured else { throw DriveVideoRecorderError.cameraUnavailable }
        refreshDiskCapacity()
        if let freeDiskBytes {
            let usableBytes = max(1, freeDiskBytes - 500_000_000)
            movieOutput.maxRecordedFileSize = usableBytes
        }
        let url = try DriveVideoFileStore.newRecordingURL()
        currentSessionID = sessionID
        currentURL = url
        currentStartedAt = .now
        pendingSessionID = nil

        if !captureSession.isRunning { captureSession.startRunning() }
        movieOutput.startRecording(to: url, recordingDelegate: self)
        state = .recording(sessionID: sessionID, startedAt: currentStartedAt ?? .now)
    }

    private func stopRecording() {
        guard movieOutput.isRecording else {
            stopCaptureSession()
            state = settings.isEnabled ? .ready : .disabled
            return
        }
        state = .stopping
        movieOutput.stopRecording()
    }

    private func stopCaptureSession() {
        if captureSession.isRunning { captureSession.stopRunning() }
    }

    private func finishRecording(url: URL, error: Error?) async {
        stopCaptureSession()
        let sessionID = currentSessionID
        let startedAt = currentStartedAt
        currentSessionID = nil
        currentURL = nil
        currentStartedAt = nil
        isConfigured = false

        if let error, !isSuccessfulFinishError(error) {
            try? FileManager.default.removeItem(at: url)
            fail(error.localizedDescription)
            return
        }

        guard let sessionID, let startedAt, FileManager.default.fileExists(atPath: url.path) else {
            fail(localized("Nie udało się zapisać pliku filmu."))
            return
        }

        do {
            let metadata = try await metadata(for: url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let recording = DriveVideoRecording(
                sessionID: sessionID,
                fileName: url.lastPathComponent,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(metadata.duration),
                duration: metadata.duration,
                fileSizeBytes: bytes,
                pixelWidth: metadata.width,
                pixelHeight: metadata.height,
                framesPerSecond: metadata.framesPerSecond,
                cameraName: currentCameraName,
                hasAudio: currentHasAudio
            )
            context.insert(recording)
            try context.save()
            lastRecording = recording
            refreshDiskCapacity()
            state = settings.isEnabled ? .ready : .disabled

            if let next = pendingSessionID, settings.isEnabled {
                pendingSessionID = nil
                handleTelemetry(sessionID: next)
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func metadata(for url: URL) async throws -> (duration: Double, width: Int, height: Int, framesPerSecond: Double) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DriveVideoRecorderError.invalidVideo
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = size.applying(transform)
        let rate = try await track.load(.nominalFrameRate)
        return (
            max(0, duration.isFinite ? duration : 0),
            Int(abs(transformed.width).rounded()),
            Int(abs(transformed.height).rounded()),
            Double(rate)
        )
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { continuation.resume(returning: $0) }
            }
        default: return false
        }
    }

    private func refreshDiskCapacity() {
        let values = try? DriveVideoFileStore.directoryURL().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        freeDiskBytes = values?.volumeAvailableCapacityForImportantUsage
    }

    private func fail(_ message: String) {
        stopCaptureSession()
        state = .failed(message)
    }

    private func isSuccessfulFinishError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == AVFoundationErrorDomain &&
            nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
    }

    private var interfaceRotationAngle: CGFloat {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .effectiveGeometry.interfaceOrientation
        return switch orientation {
        case .portraitUpsideDown: 270
        case .landscapeLeft: 0
        case .landscapeRight: 180
        default: 90
        }
    }

    private func cameraOrder(_ type: AVCaptureDevice.DeviceType) -> Int {
        switch type {
        case .builtInUltraWideCamera: 0
        case .builtInWideAngleCamera: 1
        case .builtInTelephotoCamera: 2
        case .builtInTrueDepthCamera: 3
        default: 4
        }
    }
}

extension DriveVideoRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            await self?.finishRecording(url: outputFileURL, error: error)
        }
    }
}

private enum DriveVideoRecorderError: LocalizedError {
    case noCamera
    case cameraUnavailable
    case outputUnavailable
    case invalidVideo

    var errorDescription: String? {
        switch self {
        case .noCamera: localized("Nie znaleziono dostępnej kamery.")
        case .cameraUnavailable: localized("Wybrana kamera jest obecnie niedostępna.")
        case .outputUnavailable: localized("Nie udało się przygotować nagrywania wideo.")
        case .invalidVideo: localized("Zapisany plik nie zawiera obrazu wideo.")
        }
    }
}
