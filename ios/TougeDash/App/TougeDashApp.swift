import SwiftData
import SwiftUI

@main
@MainActor
struct TougeDashApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var controller: TelemetryController
    @StateObject private var cloudAccount: CloudAccountService
    @StateObject private var cloudSync: CloudSyncManager
    @StateObject private var dashboardTemplates: DashboardTemplateStore
    @StateObject private var dashboardBuffer: DashboardTelemetryBuffer

    init() {
        do {
            let container = try ModelContainer(
                for: DriveSession.self,
                TelemetryHistorySample.self,
                DriveIncident.self,
                TimelineAnnotation.self
            )
            let locationTracker = LocationTrackingService()
            let historyRecorder = TelemetryHistoryRecorder(
                container: container,
                locationTracker: locationTracker
            )
            let account = CloudAccountService()
            let alertRules = VehicleAlertRuleStore()
            let templates = DashboardTemplateStore()
            let dashboardBuffer = DashboardTelemetryBuffer()
            let sync = CloudSyncManager(
                container: container,
                account: account,
                locationTracker: locationTracker,
                dashboardTemplates: templates,
                alertRules: alertRules
            )
            #if DEBUG
            if ProcessInfo.processInfo.environment["TOUGE_DASH_HISTORY_PREVIEW"] == "1" {
                historyRecorder.seedPreviewDataIfNeeded()
            }
            #endif
            modelContainer = container
            _cloudAccount = StateObject(wrappedValue: account)
            _cloudSync = StateObject(wrappedValue: sync)
            _dashboardTemplates = StateObject(wrappedValue: templates)
            _dashboardBuffer = StateObject(wrappedValue: dashboardBuffer)
            let incidentRecorder = TelemetryIncidentRecorder(
                container: container,
                locationTracker: locationTracker,
                alertRules: alertRules
            )
            incidentRecorder.onIncidentStored = { sampleCount in
                sync.noteLocalIncidentRecorded(sampleCount: sampleCount)
            }
            _controller = StateObject(wrappedValue: TelemetryController(
                historyRecorder: historyRecorder,
                incidentRecorder: incidentRecorder,
                cloudSync: sync
            ))
        } catch {
            fatalError("Unable to create telemetry history store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TougeDashRootView(
                controller: controller,
                cloudAccount: cloudAccount,
                cloudSync: cloudSync,
                dashboardTemplates: dashboardTemplates,
                dashboardBuffer: dashboardBuffer
            )
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}
