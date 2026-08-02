import SwiftData
import SwiftUI

@main
@MainActor
struct TougeDashApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var controller: TelemetryController
    @StateObject private var cloudAccount: CloudAccountService
    @StateObject private var cloudSync: CloudSyncManager

    init() {
        do {
            let container = try ModelContainer(for: DriveSession.self, TelemetryHistorySample.self)
            let locationTracker = LocationTrackingService()
            let historyRecorder = TelemetryHistoryRecorder(
                container: container,
                locationTracker: locationTracker
            )
            let account = CloudAccountService()
            let sync = CloudSyncManager(container: container, account: account, locationTracker: locationTracker)
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGE_DASH_HISTORY_PREVIEW"] == "1" {
                historyRecorder.seedPreviewDataIfNeeded()
            }
            #endif
            modelContainer = container
            _cloudAccount = StateObject(wrappedValue: account)
            _cloudSync = StateObject(wrappedValue: sync)
            _controller = StateObject(wrappedValue: TelemetryController(historyRecorder: historyRecorder, cloudSync: sync))
        } catch {
            fatalError("Unable to create telemetry history store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TougeDashRootView(controller: controller, cloudAccount: cloudAccount, cloudSync: cloudSync)
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}
