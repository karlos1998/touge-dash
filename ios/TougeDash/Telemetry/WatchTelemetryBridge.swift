@preconcurrency import WatchConnectivity
import Foundation

@MainActor
final class WatchTelemetryBridge: NSObject, WCSessionDelegate {
    static let shared = WatchTelemetryBridge()

    private let session: WCSession?
    private var latestPayload: WatchTelemetryPayload?
    private var pendingPayload: WatchTelemetryPayload?
    private var updateTask: Task<Void, Never>?
    private var lastUpdate = Date.distantPast
    private let minimumUpdateInterval: TimeInterval = 0.5

    private override init() {
        if WCSession.isSupported() {
            session = .default
        } else {
            session = nil
        }
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func enqueue(_ snapshot: TelemetrySnapshot, activeAlerts: [EngineAlertEvent] = []) {
        let payload = WatchTelemetryPayload(snapshot: snapshot, activeAlerts: activeAlerts)
        latestPayload = payload
        pendingPayload = payload
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            await self?.drainPendingUpdates()
        }
    }

    private func drainPendingUpdates() async {
        while !Task.isCancelled, pendingPayload != nil {
            guard session?.activationState == .activated else {
                updateTask = nil
                return
            }
            let remainingDelay = minimumUpdateInterval - Date().timeIntervalSince(lastUpdate)
            if remainingDelay > 0 {
                try? await Task.sleep(for: .seconds(remainingDelay))
            }
            guard !Task.isCancelled, let latest = pendingPayload else { break }
            pendingPayload = nil
            send(latest)
        }
        updateTask = nil
    }

    func sendAlertEvents(_ events: [EngineAlertEvent], snapshot: TelemetrySnapshot) {
        guard !events.isEmpty else { return }
        let payload = WatchTelemetryPayload(snapshot: snapshot, activeAlerts: events)
        latestPayload = payload
        guard let session,
              session.activationState == .activated,
              let data = try? JSONEncoder().encode(payload) else { return }
        let envelope = [
            WatchTelemetryPayload.contextKey: data,
            "tougeDashAlertEvent": true
        ] as [String: Any]
        try? session.updateApplicationContext([WatchTelemetryPayload.contextKey: data])
        if session.isReachable {
            session.sendMessage(envelope, replyHandler: nil)
        }
        session.transferUserInfo(envelope)
    }

    private func send(_ payload: WatchTelemetryPayload) {
        guard let session,
              let data = try? JSONEncoder().encode(payload) else { return }

        lastUpdate = .now
        try? session.updateApplicationContext([WatchTelemetryPayload.contextKey: data])
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor [weak self] in
            guard let self, let latestPayload = self.latestPayload else { return }
            self.pendingPayload = latestPayload
            guard self.updateTask == nil else { return }
            self.updateTask = Task { [weak self] in await self?.drainPendingUpdates() }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        resendLatestSnapshot()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        guard session.isWatchAppInstalled else { return }
        resendLatestSnapshot()
    }

    nonisolated private func resendLatestSnapshot() {
        Task { @MainActor [weak self] in
            guard let self, let latestPayload = self.latestPayload else { return }
            self.pendingPayload = latestPayload
            guard self.updateTask == nil else { return }
            self.updateTask = Task { [weak self] in await self?.drainPendingUpdates() }
        }
    }
}
