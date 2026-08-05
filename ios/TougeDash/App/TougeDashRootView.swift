import SwiftUI

struct TougeDashRootView: View {
    @ObservedObject var controller: TelemetryController
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @ObservedObject var dashboardTemplates: DashboardTemplateStore
    @ObservedObject var dashboardBuffer: DashboardTelemetryBuffer
    @ObservedObject var videoRecorder: DriveVideoRecorder
    @ObservedObject var videoOverlays: VideoOverlayTemplateStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selection: Int

    init(
        controller: TelemetryController,
        cloudAccount: CloudAccountService,
        cloudSync: CloudSyncManager,
        dashboardTemplates: DashboardTemplateStore,
        dashboardBuffer: DashboardTelemetryBuffer,
        videoRecorder: DriveVideoRecorder,
        videoOverlays: VideoOverlayTemplateStore
    ) {
        self.controller = controller
        self.cloudAccount = cloudAccount
        self.cloudSync = cloudSync
        self.dashboardTemplates = dashboardTemplates
        self.dashboardBuffer = dashboardBuffer
        self.videoRecorder = videoRecorder
        self.videoOverlays = videoOverlays
        #if DEBUG
        let historyPreview = ProcessInfo.processInfo.environment["TOUGE_DASH_HISTORY_PREVIEW"] == "1"
        _selection = State(initialValue: historyPreview ? 1 : 0)
        #else
        _selection = State(initialValue: 0)
        #endif
    }

    var body: some View {
        let compactLandscape = horizontalSizeClass == .compact && verticalSizeClass == .compact

        TabView(selection: $selection) {
            ContentView(
                controller: controller,
                templates: dashboardTemplates,
                telemetryBuffer: dashboardBuffer,
                onTemplateChanged: { Task { await cloudSync.syncNow() } },
                onShowHistory: compactLandscape ? { selection = 1 } : nil
            )
                .toolbarVisibility(compactLandscape ? .hidden : .automatic, for: .tabBar)
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(0)

            HistoryView(
                locationTracker: controller.locationTracker,
                cloudAccount: cloudAccount,
                cloudSync: cloudSync,
                videoRecorder: videoRecorder,
                videoOverlays: videoOverlays,
                canSplitActiveDrive: controller.isConnected && controller.historyRecorder.activeSessionID != nil,
                activeSessionSampleCount: controller.historyRecorder.activeSessionSampleCount,
                onSplitActiveDrive: controller.splitActiveDrive,
                onShowDashboard: compactLandscape ? { selection = 0 } : nil
            )
                .toolbarVisibility(compactLandscape ? .hidden : .automatic, for: .tabBar)
                .tabItem {
                    Label("Historia", systemImage: "chart.xyaxis.line")
                }
                .tag(1)

            AlertCenterView(cloudSync: cloudSync)
                .toolbarVisibility(compactLandscape ? .hidden : .automatic, for: .tabBar)
                .tabItem {
                    Label("Alerty", systemImage: "exclamationmark.shield.fill")
                }
                .tag(2)
        }
        .tint(.tougeCyan)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                controller.historyRecorder.saveNow()
                Task { await cloudSync.syncNow() }
            }
            if phase == .background {
                videoRecorder.applicationDidEnterBackground()
            } else if phase == .active {
                videoRecorder.applicationDidBecomeActive()
            }
        }
        .onChange(of: cloudAccount.isAuthenticated) { _, _ in
            Task { await cloudSync.accountDidChange() }
        }
        .onReceive(controller.$snapshot) { dashboardBuffer.record($0) }
    }
}
