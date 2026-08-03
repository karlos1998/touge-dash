@preconcurrency import ActivityKit
import Combine
import Foundation

@MainActor
final class TelemetryActivityManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var activity: Activity<TelemetryActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var pendingUpdate: (snapshot: TelemetrySnapshot, connectionLabel: String)?
    private var updateTask: Task<Void, Never>?
    private let minimumUpdateInterval: TimeInterval = 0.5

    init() {
        activity = Activity<TelemetryActivityAttributes>.activities.first
        isRunning = activity != nil
    }

    func start(with snapshot: TelemetrySnapshot, connectionLabel: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = localized("Live Activities are disabled in Settings")
            return
        }
        if activity != nil {
            await updateImmediately(snapshot, connectionLabel: connectionLabel)
            return
        }
        let attributes = TelemetryActivityAttributes(vehicleName: "EMU Black")
        let state = TelemetryActivityAttributes.ContentState(
            telemetry: snapshot,
            connectionLabel: connectionLabel
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(2)),
                pushType: nil
            )
            lastUpdate = .now
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func enqueueUpdate(_ snapshot: TelemetrySnapshot, connectionLabel: String) {
        guard activity != nil else { return }
        pendingUpdate = (snapshot, connectionLabel)
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            await self?.drainPendingUpdates()
        }
    }

    private func drainPendingUpdates() async {
        while !Task.isCancelled, pendingUpdate != nil {
            let remainingDelay = minimumUpdateInterval - Date().timeIntervalSince(lastUpdate)
            if remainingDelay > 0 {
                try? await Task.sleep(for: .seconds(remainingDelay))
            }
            guard !Task.isCancelled, let latest = pendingUpdate else { break }
            pendingUpdate = nil
            await updateImmediately(latest.snapshot, connectionLabel: latest.connectionLabel)
        }
        updateTask = nil
    }

    private func updateImmediately(_ snapshot: TelemetrySnapshot, connectionLabel: String) async {
        guard let activity else { return }
        lastUpdate = .now
        let state = TelemetryActivityAttributes.ContentState(
            telemetry: snapshot,
            connectionLabel: connectionLabel
        )
        await activity.update(
            ActivityContent(
                state: state,
                staleDate: .now.addingTimeInterval(2),
                relevanceScore: snapshot.hasCriticalWarning ? 100 : 50
            )
        )
    }

    func stop() async {
        updateTask?.cancel()
        updateTask = nil
        pendingUpdate = nil
        guard let activity else { return }
        let finalState = TelemetryActivityAttributes.ContentState(
            telemetry: SharedTelemetryStore.load(),
            connectionLabel: localized("Drive ended")
        )
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        self.activity = nil
        isRunning = false
    }
}
