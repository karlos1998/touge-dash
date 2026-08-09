import Combine
import Foundation
import UIKit
import WidgetKit

enum TelemetryUpdateCadence {
    static let processingInterval: TimeInterval = 1.0 / 25.0
    static let normalDisplayInterval: TimeInterval = 1.0 / 20.0
    static let recordingDisplayInterval: TimeInterval = 1.0 / 8.0
    static let diagnosticsInterval: TimeInterval = 0.2
}

enum TelemetryActivityInactivityPolicy {
    static let timeout: TimeInterval = 15 * 60

    static func deadline(after lastCommunicationAt: Date) -> Date {
        lastCommunicationAt.addingTimeInterval(timeout)
    }

    static func isExpired(lastCommunicationAt: Date, now: Date) -> Bool {
        now >= deadline(after: lastCommunicationAt)
    }
}

@MainActor
final class TelemetryController: ObservableObject {
    @Published private(set) var snapshot = SharedTelemetryStore.load()
    @Published private(set) var parserStats = EMUParserStats()
    @Published private(set) var receivedBytes = 0
    @Published var showingDevicePicker = false

    let bluetooth = BluetoothTelemetryService()
    let activityManager = TelemetryActivityManager()
    let historyRecorder: TelemetryHistoryRecorder
    let incidentRecorder: TelemetryIncidentRecorder
    let locationTracker: LocationTrackingService
    let cloudSync: CloudSyncManager
    let videoRecorder: DriveVideoRecorder
    let accelerationEngine: AccelerationEngine
    let ecuControls = ECUControlCoordinator()
    private let watchBridge = WatchTelemetryBridge.shared
    private let engineAlertManager = EngineAlertManager()

    private var parser = EMUFrameParser()
    private var accumulator = EMUTelemetryAccumulator()
    private var cancellables: Set<AnyCancellable> = []
    private var lastSharedWrite = Date.distantPast
    private var lastWidgetReload = Date.distantPast
    private var lastTelemetryProcess = Date.distantPast
    private var lastSnapshotPublish = Date.distantPast
    private var lastDiagnosticsPublish = Date.distantPast
    private var lastVideoHeartbeat = Date.distantPast
    private var lastVideoSessionID: UUID?
    private var totalReceivedBytes = 0
    private var pendingRawSnapshot: TelemetrySnapshot?
    private var telemetryDrainTask: Task<Void, Never>?
    private var lastTelemetryCommunication = Date.now
    private var activityInactivityTask: Task<Void, Never>?
    private var activityReconciliationTask: Task<Void, Never>?
    private var activityStateVersion = 0
    private var activityManuallySuppressed = false

    init(
        historyRecorder: TelemetryHistoryRecorder,
        incidentRecorder: TelemetryIncidentRecorder,
        cloudSync: CloudSyncManager,
        videoRecorder: DriveVideoRecorder,
        accelerationEngine: AccelerationEngine
    ) {
        self.historyRecorder = historyRecorder
        self.incidentRecorder = incidentRecorder
        self.cloudSync = cloudSync
        self.videoRecorder = videoRecorder
        self.accelerationEngine = accelerationEngine
        locationTracker = historyRecorder.locationTracker

        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["TOUGE_DASH_PREVIEW_TELEMETRY"] == "1" || environment["TOUGE_DASH_PREVIEW_ALERT"] == "1" {
            var preview = TelemetrySnapshot.preview
            if environment["TOUGE_DASH_PREVIEW_ALERT"] == "1" {
                preview.coolantCelsius = 112
                preview.oilTemperatureCelsius = 124
            }
            preview.updatedAt = .now.addingTimeInterval(300)
            snapshot = preview
            SharedTelemetryStore.save(preview)
        }
        #endif

        bluetooth.onBytes = { [weak self] data in self?.ingest(data) }
        ecuControls.writer = { [weak bluetooth] data, completion in
            guard let bluetooth else {
                completion(.failure(NSError(
                    domain: "TougeDash.ECUControl",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: localized("Bluetooth jest niedostępny.")]
                )))
                return
            }
            bluetooth.writeControlFrame(data, completion: completion)
        }
        bluetooth.onControlTransportChanged = { [weak self] available in
            self?.ecuControls.transportAvailabilityChanged(available)
        }
        bluetooth.onConnectionChanged = { [weak self] state in
            guard let self else { return }
            self.ecuControls.connectionChanged(isConnected: state.isConnected)
            if state.isConnected {
                let wasManuallySuppressed = self.activityManuallySuppressed
                self.activityManuallySuppressed = false
                self.noteTelemetryCommunication(at: .now)
                if wasManuallySuppressed {
                    self.activityStateDidChange()
                }
                self.ecuControls.transportAvailabilityChanged(self.bluetooth.controlTransportAvailable)
            }
            self.locationTracker.setDriveActive(state.isConnected)
            UIApplication.shared.isIdleTimerDisabled = state.isConnected
            if state.isConnected {
                self.showingDevicePicker = false
                if let identifier = self.bluetooth.connectedIdentifier {
                    let historyIdentifier = self.bluetooth.connectedIsSimulator
                        ? LocalVehicleIdentity.simulatorID
                        : identifier
                    self.historyRecorder.activateVehicle(historyIdentifier)
                    self.incidentRecorder.activateVehicle(historyIdentifier)
                    Task { await self.cloudSync.prepareVehicle(hardwareIdentifier: historyIdentifier) }
                }
            } else {
                self.incidentRecorder.finish(sessionID: self.historyRecorder.activeSessionID)
                self.videoRecorder.connectionDidEnd()
                self.lastVideoSessionID = nil
                self.lastVideoHeartbeat = .distantPast
                self.accelerationEngine.reset()
            }
            if self.activityManager.isRunning {
                self.activityManager.enqueueUpdate(self.snapshot, connectionLabel: state.label)
            }
            self.objectWillChange.send()
        }
        bluetooth.objectWillChange
            .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        activityManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        videoRecorder.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        Task { [weak self] in
            guard let self else { return }
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGE_DASH_PREVIEW_TELEMETRY"] == "1" {
                await self.activityManager.stop()
            }
            #endif
            self.ensureActivityInactivityMonitor()
            self.requestActivityReconciliation()
            // On iOS 26 an active Live Activity gives CoreBluetooth the same
            // privileges in the background that it has in the foreground.
            // Begin scanning after requesting ActivityKit so the initial
            // 15-minute connection window also works with the phone locked.
            self.bluetooth.startScanning()
        }
        watchBridge.enqueue(snapshot)
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOUGE_DASH_PREVIEW_ALERT"] == "1" {
            let rules = cloudSync.alertRules.activeRules
            snapshot = rules.applyingWarningState(to: snapshot)
            _ = engineAlertManager.evaluate(snapshot, rules: rules, now: snapshot.updatedAt.addingTimeInterval(-5))
            _ = engineAlertManager.evaluate(snapshot, rules: rules, now: snapshot.updatedAt)
        }
        #endif
    }

    var connectionLabel: String {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOUGE_DASH_PREVIEW_TELEMETRY"] == "1" {
            return "EMULOGGER"
        }
        #endif
        return bluetooth.state.label
    }

    var isConnected: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOUGE_DASH_PREVIEW_TELEMETRY"] == "1" {
            return true
        }
        #endif
        return bluetooth.state.isConnected
    }

    func useBluetooth() {
        if !isConnected {
            parser = EMUFrameParser()
            accumulator = EMUTelemetryAccumulator()
            telemetryDrainTask?.cancel()
            telemetryDrainTask = nil
            pendingRawSnapshot = nil
            totalReceivedBytes = 0
            lastTelemetryProcess = .distantPast
            lastSnapshotPublish = .distantPast
            lastDiagnosticsPublish = .distantPast
            parserStats = .init()
            receivedBytes = 0
        }
        showBluetoothDetails()
    }

    func showBluetoothDetails() {
        showingDevicePicker = true
        if !isConnected {
            bluetooth.startScanning()
        }
    }

    func connect(to device: DiscoveredTelemetryDevice) {
        bluetooth.connect(to: device)
        showingDevicePicker = false
    }

    func toggleLiveActivity() {
        if activityManager.isRunning {
            activityManuallySuppressed = true
            activityInactivityTask?.cancel()
            activityInactivityTask = nil
            activityStateDidChange()
        } else {
            activityManuallySuppressed = false
            noteTelemetryCommunication(at: .now)
        }
    }

    @discardableResult
    func splitActiveDrive() -> Bool {
        guard isConnected, let sessionID = historyRecorder.activeSessionID else { return false }
        let boundaryAt = Date.now
        incidentRecorder.finish(sessionID: sessionID)
        guard historyRecorder.finishActiveSessionForManualSplit(at: boundaryAt) != nil else { return false }
        accelerationEngine.reset()
        videoRecorder.telemetrySessionDidEnd(at: boundaryAt)
        lastVideoSessionID = nil
        lastVideoHeartbeat = .distantPast
        Task { await cloudSync.syncNow() }
        objectWillChange.send()
        return true
    }

    private func ingest(_ data: Data) {
        totalReceivedBytes += data.count
        if ECUControlSnapshot.isValidStatusFrame(data) {
            ecuControls.ingestStatusFrame(data)
            noteTelemetryCommunication(at: .now)
            return
        }
        let frames = parser.feed(data)
        let now = Date.now
        if now.timeIntervalSince(lastDiagnosticsPublish) >= TelemetryUpdateCadence.diagnosticsInterval {
            receivedBytes = totalReceivedBytes
            parserStats = parser.stats
            lastDiagnosticsPublish = now
        }
        guard !frames.isEmpty else { return }
        noteTelemetryCommunication(at: now)
        for frame in frames {
            ecuControls.ingest(frame, receivedAt: now)
            accumulator.apply(frame)
        }
        enqueueTelemetryProcessing(accumulator.snapshot, now: now)
    }

    private func enqueueTelemetryProcessing(_ rawValue: TelemetrySnapshot, now: Date) {
        pendingRawSnapshot = rawValue
        guard telemetryDrainTask == nil else { return }

        let elapsed = now.timeIntervalSince(lastTelemetryProcess)
        let delay = max(0, TelemetryUpdateCadence.processingInterval - elapsed)
        if delay == 0 {
            drainPendingTelemetry(at: now)
            return
        }

        telemetryDrainTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.drainPendingTelemetry(at: .now)
        }
    }

    private func drainPendingTelemetry(at now: Date) {
        telemetryDrainTask = nil
        guard let rawValue = pendingRawSnapshot else { return }
        pendingRawSnapshot = nil
        lastTelemetryProcess = now
        process(rawValue, at: now)
    }

    private func process(_ rawValue: TelemetrySnapshot, at now: Date) {
        let rules = cloudSync.alertRules.activeRules
        let value = rules.applyingWarningState(to: rawValue)
        let displayInterval = videoRecorder.isRecording
            ? TelemetryUpdateCadence.recordingDisplayInterval
            : TelemetryUpdateCadence.normalDisplayInterval
        let warningStateChanged = value.hasCriticalWarning != snapshot.hasCriticalWarning ||
            value.hasTemperatureWarning != snapshot.hasTemperatureWarning
        if warningStateChanged || now.timeIntervalSince(lastSnapshotPublish) >= displayInterval {
            snapshot = value
            lastSnapshotPublish = now
        }
        let alertEvaluation = engineAlertManager.evaluate(value, rules: rules, now: now)
        watchBridge.enqueue(value, activeAlerts: alertEvaluation.active)
        if !alertEvaluation.triggered.isEmpty {
            watchBridge.sendAlertEvents(alertEvaluation.triggered, snapshot: value)
        }
        if let change = historyRecorder.record(value, at: now) {
            cloudSync.noteLocalSampleRecorded(
                sessionID: change.sessionID,
                sessionBecamePending: change.sessionBecamePending
            )
            if let previousSessionID = change.previousSessionID,
               let boundaryAt = change.boundaryAt {
                incidentRecorder.finish(sessionID: previousSessionID)
                accelerationEngine.reset()
                videoRecorder.handleTelemetry(sessionID: change.sessionID, at: boundaryAt)
                lastVideoSessionID = change.sessionID
                lastVideoHeartbeat = boundaryAt
                Task { await cloudSync.syncNow() }
            }
        }
        if let sessionID = historyRecorder.activeSessionID {
            if let attempt = accelerationEngine.sample(value, at: now, sessionID: sessionID) {
                historyRecorder.recordAcceleration(attempt)
                cloudSync.noteLocalAccelerationRecorded(sessionID: sessionID)
            }
            if sessionID != lastVideoSessionID || now.timeIntervalSince(lastVideoHeartbeat) >= 1 {
                videoRecorder.handleTelemetry(sessionID: sessionID, at: now)
                lastVideoSessionID = sessionID
                lastVideoHeartbeat = now
            }
            incidentRecorder.record(value, sessionID: sessionID)
        }
        cloudSync.publishLive(value, performance: accelerationEngine)
        if now.timeIntervalSince(lastSharedWrite) >= 0.2 {
            SharedTelemetryStore.save(value)
            lastSharedWrite = now
        }
        if now.timeIntervalSince(lastWidgetReload) >= 15 {
            WidgetCenter.shared.reloadTimelines(ofKind: "TougeDashTelemetryWidget")
            lastWidgetReload = now
        }
        if activityManager.isRunning {
            activityManager.enqueueUpdate(value, connectionLabel: connectionLabel)
        }
    }

    private var shouldRunTelemetryActivity: Bool {
        !activityManuallySuppressed && !TelemetryActivityInactivityPolicy.isExpired(
            lastCommunicationAt: lastTelemetryCommunication,
            now: .now
        )
    }

    private func noteTelemetryCommunication(at date: Date) {
        let activityNeedsRestart = !activityManuallySuppressed && (
            !activityManager.isRunning || TelemetryActivityInactivityPolicy.isExpired(
                lastCommunicationAt: lastTelemetryCommunication,
                now: date
            )
        )
        lastTelemetryCommunication = date
        ensureActivityInactivityMonitor()
        if activityNeedsRestart {
            activityStateDidChange()
        }
    }

    private func ensureActivityInactivityMonitor() {
        guard !activityManuallySuppressed, activityInactivityTask == nil else { return }
        activityInactivityTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let deadline = TelemetryActivityInactivityPolicy.deadline(
                    after: self.lastTelemetryCommunication
                )
                let delay = max(0, deadline.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }

                if TelemetryActivityInactivityPolicy.isExpired(
                    lastCommunicationAt: self.lastTelemetryCommunication,
                    now: .now
                ) {
                    self.activityInactivityTask = nil
                    self.activityStateDidChange()
                    return
                }
            }
        }
    }

    private func activityStateDidChange() {
        activityStateVersion += 1
        requestActivityReconciliation()
    }

    private func requestActivityReconciliation() {
        guard activityReconciliationTask == nil else { return }
        activityReconciliationTask = Task { [weak self] in
            guard let self else { return }

            while true {
                let reconciledVersion = self.activityStateVersion
                let shouldRun = self.shouldRunTelemetryActivity
                if shouldRun, !self.activityManager.isRunning {
                    await self.activityManager.start(
                        with: self.snapshot,
                        connectionLabel: self.connectionLabel
                    )
                } else if !shouldRun, self.activityManager.isRunning {
                    await self.activityManager.stop()
                }

                guard reconciledVersion != self.activityStateVersion else { break }
            }
            self.activityReconciliationTask = nil
        }
    }

}
