@preconcurrency import AVFoundation
import Foundation

struct DriveVideoCaptureStartResult: Sendable {
    let cameraName: String
    let hasAudio: Bool
}

/// Owns every blocking AVCaptureSession operation on one serial queue.
/// AVCaptureSession.startRunning/stopRunning must never compete with SwiftUI's
/// main thread while live telemetry is updating the dashboard.
final class DriveVideoCaptureEngine: NSObject, @unchecked Sendable {
    typealias StartHandler = @Sendable (URL, Date) -> Void
    typealias FinishHandler = @Sendable (URL, Error?) -> Void

    var onStarted: StartHandler?
    var onFinished: FinishHandler?

    private let queue = DispatchQueue(
        label: "it.letscode.touge-dash.video-capture",
        qos: .userInitiated
    )
    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()

    func configureAndStart(
        cameraID: String,
        quality: DriveVideoQuality,
        includeAudio: Bool,
        rotationAngle: CGFloat,
        outputURL: URL,
        maximumFileSize: Int64
    ) async throws -> DriveVideoCaptureStartResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard !movieOutput.isRecording else {
                        throw DriveVideoRecorderError.recordingAlreadyActive
                    }
                    let result = try configure(
                        cameraID: cameraID,
                        quality: quality,
                        includeAudio: includeAudio,
                        rotationAngle: rotationAngle
                    )
                    movieOutput.maxRecordedFileSize = maximumFileSize
                    if !captureSession.isRunning {
                        captureSession.startRunning()
                    }
                    movieOutput.startRecording(to: outputURL, recordingDelegate: self)
                    continuation.resume(returning: result)
                } catch {
                    if captureSession.isRunning { captureSession.stopRunning() }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopRecording() {
        queue.async { [self] in
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            } else if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    func stopSession() {
        queue.async { [self] in
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            } else if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    private func configure(
        cameraID: String,
        quality: DriveVideoQuality,
        includeAudio: Bool,
        rotationAngle: CGFloat
    ) throws -> DriveVideoCaptureStartResult {
        guard let camera = AVCaptureDevice(uniqueID: cameraID) else {
            throw DriveVideoRecorderError.noCamera
        }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.inputs.forEach(captureSession.removeInput)
        if !captureSession.outputs.contains(movieOutput) {
            guard captureSession.canAddOutput(movieOutput) else {
                throw DriveVideoRecorderError.outputUnavailable
            }
            captureSession.addOutput(movieOutput)
        }

        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard captureSession.canAddInput(videoInput) else {
            throw DriveVideoRecorderError.cameraUnavailable
        }
        captureSession.addInput(videoInput)

        var audioAttached = false
        if includeAudio, let microphone = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: microphone)
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
                audioAttached = true
            }
        }

        let requestedPreset = quality.sessionPreset
        if captureSession.canSetSessionPreset(requestedPreset) {
            captureSession.sessionPreset = requestedPreset
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        } else {
            captureSession.sessionPreset = .high
        }

        try configureCameraForEfficientRecording(camera)
        movieOutput.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        if let connection = movieOutput.connection(with: .video) {
            if movieOutput.availableVideoCodecTypes.contains(.hevc) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
            connection.preferredVideoStabilizationMode = .auto
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
        }

        return DriveVideoCaptureStartResult(cameraName: camera.localizedName, hasAudio: audioAttached)
    }

    private func configureCameraForEfficientRecording(_ camera: AVCaptureDevice) throws {
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }

        // Diagnostic drive footage does not benefit from 60/120 FPS. A fixed
        // 30 FPS materially lowers encoder, thermal and storage pressure.
        let thirtyFPS = CMTime(value: 1, timescale: 30)
        let supportsThirtyFPS = camera.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
        }
        if supportsThirtyFPS {
            camera.activeVideoMinFrameDuration = thirtyFPS
            camera.activeVideoMaxFrameDuration = thirtyFPS
        }

        // Keep capture in SDR. HDR tone processing competes with the live
        // dashboard but does not improve the diagnostic value of the video.
        camera.automaticallyAdjustsVideoHDREnabled = false
        if camera.activeFormat.isVideoHDRSupported {
            camera.isVideoHDREnabled = false
        }
    }
}

extension DriveVideoCaptureEngine: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        onStarted?(outputFileURL, .now)
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        queue.async { [self] in
            if captureSession.isRunning { captureSession.stopRunning() }
            onFinished?(outputFileURL, error)
        }
    }
}
