@preconcurrency import WatchConnectivity
import Foundation

@MainActor
final class WatchTelemetryBridge: NSObject, WCSessionDelegate {
    static let shared = WatchTelemetryBridge()

    private let session: WCSession?
    private var latestSnapshot: TelemetrySnapshot?
    private var pendingSnapshot: TelemetrySnapshot?
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

    func enqueue(_ snapshot: TelemetrySnapshot) {
        latestSnapshot = snapshot
        pendingSnapshot = snapshot
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            await self?.drainPendingUpdates()
        }
    }

    private func drainPendingUpdates() async {
        while !Task.isCancelled, pendingSnapshot != nil {
            guard session?.activationState == .activated else {
                updateTask = nil
                return
            }
            let remainingDelay = minimumUpdateInterval - Date().timeIntervalSince(lastUpdate)
            if remainingDelay > 0 {
                try? await Task.sleep(for: .seconds(remainingDelay))
            }
            guard !Task.isCancelled, let latest = pendingSnapshot else { break }
            pendingSnapshot = nil
            send(latest)
        }
        updateTask = nil
    }

    private func send(_ snapshot: TelemetrySnapshot) {
        guard let session,
              let data = try? JSONEncoder().encode(WatchTelemetryPayload(snapshot: snapshot)) else { return }

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
            guard let self, let latestSnapshot = self.latestSnapshot else { return }
            self.enqueue(latestSnapshot)
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
            guard let self, let latestSnapshot = self.latestSnapshot else { return }
            self.enqueue(latestSnapshot)
        }
    }
}
