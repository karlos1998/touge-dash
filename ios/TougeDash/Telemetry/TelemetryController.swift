import Combine
import Foundation
import UIKit
import WidgetKit

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
    private let watchBridge = WatchTelemetryBridge.shared
    private let engineAlertManager = EngineAlertManager()

    private var parser = EMUFrameParser()
    private var accumulator = EMUTelemetryAccumulator()
    private var cancellables: Set<AnyCancellable> = []
    private var lastSharedWrite = Date.distantPast
    private var lastWidgetReload = Date.distantPast

    init(
        historyRecorder: TelemetryHistoryRecorder,
        incidentRecorder: TelemetryIncidentRecorder,
        cloudSync: CloudSyncManager,
        videoRecorder: DriveVideoRecorder
    ) {
        self.historyRecorder = historyRecorder
        self.incidentRecorder = incidentRecorder
        self.cloudSync = cloudSync
        self.videoRecorder = videoRecorder
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
        bluetooth.onConnectionChanged = { [weak self] state in
            guard let self else { return }
            self.locationTracker.setDriveActive(state.isConnected)
            UIApplication.shared.isIdleTimerDisabled = state.isConnected
            if state.isConnected {
                self.showingDevicePicker = false
                if let identifier = self.bluetooth.connectedIdentifier {
                    self.historyRecorder.activateVehicle(identifier)
                    self.incidentRecorder.activateVehicle(identifier)
                    Task { await self.cloudSync.prepareVehicle(hardwareIdentifier: identifier) }
                }
            } else {
                self.incidentRecorder.finish(sessionID: self.historyRecorder.activeSessionID)
                self.videoRecorder.connectionDidEnd()
            }
            if self.activityManager.isRunning {
                self.activityManager.enqueueUpdate(self.snapshot, connectionLabel: state.label)
            }
            self.objectWillChange.send()
        }
        bluetooth.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        activityManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        Task { [weak self] in
            guard let self else { return }
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGE_DASH_PREVIEW_TELEMETRY"] == "1" {
                await self.activityManager.stop()
            }
            #endif
            await self.activityManager.start(
                with: self.snapshot,
                connectionLabel: self.connectionLabel
            )
            // On iOS 26 an active Live Activity gives CoreBluetooth the same
            // privileges in the background that it has in the foreground.
            // Start scanning only after ActivityKit has established it.
            self.bluetooth.startScanning()
        }
        watchBridge.enqueue(snapshot)
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOUGE_DASH_PREVIEW_ALERT"] == "1" {
            let rules = cloudSync.alertRules.activeRules
            snapshot = rules.applyingWarningState(to: snapshot)
            engineAlertManager.evaluate(snapshot, rules: rules)
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
        Task {
            if activityManager.isRunning {
                await activityManager.stop()
            } else {
                await activityManager.start(with: snapshot, connectionLabel: connectionLabel)
            }
        }
    }

    private func ingest(_ data: Data) {
        receivedBytes += data.count
        let frames = parser.feed(data)
        guard !frames.isEmpty else {
            parserStats = parser.stats
            return
        }
        for frame in frames { accumulator.apply(frame) }
        parserStats = parser.stats
        publish(accumulator.snapshot)
    }

    private func publish(_ rawValue: TelemetrySnapshot) {
        let rules = cloudSync.alertRules.activeRules
        let value = rules.applyingWarningState(to: rawValue)
        snapshot = value
        watchBridge.enqueue(value)
        engineAlertManager.evaluate(value, rules: rules)
        if let change = historyRecorder.record(value) {
            cloudSync.noteLocalSampleRecorded(sessionBecamePending: change.sessionBecamePending)
        }
        if let sessionID = historyRecorder.activeSessionID {
            videoRecorder.handleTelemetry(sessionID: sessionID)
        }
        if let sessionID = historyRecorder.activeSessionID {
            incidentRecorder.record(value, sessionID: sessionID)
        }
        cloudSync.publishLive(value)
        let now = Date.now
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

}
