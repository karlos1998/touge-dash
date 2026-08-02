@preconcurrency import WatchConnectivity
import Combine
import Foundation
import WatchKit

@MainActor
final class WatchTelemetryController: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot = WatchTelemetryPayload.empty
    @Published private(set) var isReachable = false

    private static let storedSnapshotKey = "watchTelemetrySnapshot"
    private let session: WCSession?

    override init() {
        if let data = UserDefaults.standard.data(forKey: Self.storedSnapshotKey),
           let stored = try? JSONDecoder().decode(WatchTelemetryPayload.self, from: data) {
            snapshot = stored
        }
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["TOUGE_DASH_WATCH_PREVIEW"] == "1" || environment["TOUGE_DASH_WATCH_ALERT_PREVIEW"] == "1" {
            var preview = WatchTelemetryPayload.preview
            if environment["TOUGE_DASH_WATCH_ALERT_PREVIEW"] == "1" {
                preview.coolantCelsius = 112
                preview.oilTemperatureCelsius = 124
                preview.hasCriticalWarning = true
            }
            preview.updatedAt = .now.addingTimeInterval(300)
            snapshot = preview
        }
        #endif

        if WCSession.isSupported() {
            session = .default
        } else {
            session = nil
        }
        super.init()
        session?.delegate = self
        session?.activate()
    }

    private func ingest(_ data: Data) {
        guard let value = try? JSONDecoder().decode(WatchTelemetryPayload.self, from: data) else { return }
        let shouldPlayTemperatureAlert = value.hasTemperatureWarning && !snapshot.hasTemperatureWarning
        let shouldPlayEngineAlert = value.hasCriticalWarning && !snapshot.hasCriticalWarning
        snapshot = value
        UserDefaults.standard.set(data, forKey: Self.storedSnapshotKey)
        if shouldPlayTemperatureAlert {
            WKInterfaceDevice.current().play(.failure)
        } else if shouldPlayEngineAlert {
            WKInterfaceDevice.current().play(.notification)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let context = session.receivedApplicationContext
        let data = context[WatchTelemetryPayload.contextKey] as? Data
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            if let data {
                self?.ingest(data)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor [weak self] in
            self?.ingest(messageData)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[WatchTelemetryPayload.contextKey] as? Data else { return }
        Task { @MainActor [weak self] in
            self?.ingest(data)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
        }
    }
}
