import SwiftData
import SwiftUI
import UIKit

@MainActor
final class TougeDashAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == SeventyMaiBackgroundDownloadCoordinator.sessionIdentifier else {
            completionHandler()
            return
        }
        SeventyMaiBackgroundDownloadCoordinator.shared.storeBackgroundCompletionHandler(completionHandler)
    }
}

@main
@MainActor
struct TougeDashApp: App {
    @UIApplicationDelegateAdaptor(TougeDashAppDelegate.self) private var appDelegate
    @AppStorage(AppAppearance.defaultsKey) private var appearanceValue = AppAppearance.system.rawValue
    private let modelContainer: ModelContainer
    @StateObject private var controller: TelemetryController
    @StateObject private var cloudAccount: CloudAccountService
    @StateObject private var cloudSync: CloudSyncManager
    @StateObject private var dashboardTemplates: DashboardTemplateStore
    @StateObject private var dashboardBuffer: DashboardTelemetryBuffer
    @StateObject private var videoRecorder: DriveVideoRecorder
    @StateObject private var videoOverlays: VideoOverlayTemplateStore

    init() {
        do {
            let container = try ModelContainer(
                for: DriveSession.self,
                TelemetryHistorySample.self,
                DriveVideoRecording.self,
                DriveIncident.self,
                TimelineAnnotation.self,
                AccelerationAttempt.self
            )
            let locationTracker = LocationTrackingService()
            let historyRecorder = TelemetryHistoryRecorder(
                container: container,
                locationTracker: locationTracker
            )
            let accelerationEngine = AccelerationEngine()
            let account = CloudAccountService()
            let alertRules = VehicleAlertRuleStore()
            let templates = DashboardTemplateStore()
            let dashboardBuffer = DashboardTelemetryBuffer()
            let videoSettings = DriveVideoSettingsStore()
            let videoRecorder = DriveVideoRecorder(container: container, settings: videoSettings)
            let videoOverlays = VideoOverlayTemplateStore()
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
            _videoRecorder = StateObject(wrappedValue: videoRecorder)
            _videoOverlays = StateObject(wrappedValue: videoOverlays)
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
                cloudSync: sync,
                videoRecorder: videoRecorder,
                accelerationEngine: accelerationEngine
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
                dashboardBuffer: dashboardBuffer,
                videoRecorder: videoRecorder,
                videoOverlays: videoOverlays,
                appearance: appearanceBinding
            )
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(modelContainer)
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceValue) ?? .system
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { appearance },
            set: { appearanceValue = $0.rawValue }
        )
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    static let defaultsKey = "tougeDash.appearance"

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: localized("Systemowy")
        case .light: localized("Jasny")
        case .dark: localized("Ciemny")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
