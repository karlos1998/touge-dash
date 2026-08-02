import SwiftData
import SwiftUI

@main
@MainActor
struct TougeDashApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var controller: TelemetryController

    init() {
        do {
            let container = try ModelContainer(for: DriveSession.self, TelemetryHistorySample.self)
            let locationTracker = LocationTrackingService()
            let historyRecorder = TelemetryHistoryRecorder(
                container: container,
                locationTracker: locationTracker
            )
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGE_DASH_HISTORY_PREVIEW"] == "1" {
                historyRecorder.seedPreviewDataIfNeeded()
            }
            #endif
            modelContainer = container
            _controller = StateObject(wrappedValue: TelemetryController(historyRecorder: historyRecorder))
        } catch {
            fatalError("Unable to create telemetry history store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TougeDashRootView(controller: controller)
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}
