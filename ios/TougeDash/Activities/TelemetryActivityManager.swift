@preconcurrency import ActivityKit
import Combine
import Foundation

@MainActor
final class TelemetryActivityManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var activity: Activity<TelemetryActivityAttributes>?
    private var lastUpdate = Date.distantPast

    init() {
        activity = Activity<TelemetryActivityAttributes>.activities.first
        isRunning = activity != nil
    }

    func start(with snapshot: TelemetrySnapshot, connectionLabel: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities are disabled in Settings"
            return
        }
        if activity != nil {
            await update(snapshot, connectionLabel: connectionLabel, force: true)
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
                content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(3)),
                pushType: nil
            )
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func update(_ snapshot: TelemetrySnapshot, connectionLabel: String, force: Bool = false) async {
        guard let activity else { return }
        guard force || Date().timeIntervalSince(lastUpdate) >= 1 else { return }
        lastUpdate = .now
        let state = TelemetryActivityAttributes.ContentState(
            telemetry: snapshot,
            connectionLabel: connectionLabel
        )
        await activity.update(
            ActivityContent(
                state: state,
                staleDate: .now.addingTimeInterval(3),
                relevanceScore: snapshot.hasCriticalWarning ? 100 : 50
            )
        )
    }

    func stop() async {
        guard let activity else { return }
        let finalState = TelemetryActivityAttributes.ContentState(
            telemetry: SharedTelemetryStore.load(),
            connectionLabel: "Drive ended"
        )
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        self.activity = nil
        isRunning = false
    }
}
