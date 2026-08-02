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

    private var parser = EMUFrameParser()
    private var accumulator = EMUTelemetryAccumulator()
    private var cancellables: Set<AnyCancellable> = []
    private var lastSharedWrite = Date.distantPast
    private var lastWidgetReload = Date.distantPast

    init() {
        #if DEBUG
        UIApplication.shared.isIdleTimerDisabled = true

        if ProcessInfo.processInfo.environment["TOUGE_DASH_PREVIEW_TELEMETRY"] == "1" {
            var preview = TelemetrySnapshot.preview
            preview.updatedAt = .now.addingTimeInterval(300)
            snapshot = preview
            SharedTelemetryStore.save(preview)
        }
        #endif

        bluetooth.onBytes = { [weak self] data in self?.ingest(data) }
        bluetooth.onConnectionChanged = { [weak self] state in
            guard let self else { return }
            if state.isConnected {
                self.showingDevicePicker = false
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
            await self.activityManager.start(
                with: self.snapshot,
                connectionLabel: self.connectionLabel
            )
            // On iOS 26 an active Live Activity gives CoreBluetooth the same
            // privileges in the background that it has in the foreground.
            // Start scanning only after ActivityKit has established it.
            self.bluetooth.startScanning()
        }
    }

    var connectionLabel: String {
        bluetooth.state.label
    }

    var isConnected: Bool {
        bluetooth.state.isConnected
    }

    func useBluetooth() {
        parser = EMUFrameParser()
        accumulator = EMUTelemetryAccumulator()
        parserStats = .init()
        receivedBytes = 0
        bluetooth.startScanning()
        showingDevicePicker = true
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

    private func publish(_ value: TelemetrySnapshot) {
        snapshot = value
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
