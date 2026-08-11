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
                cloudAccount: cloudAccount,
                cloudSync: cloudSync,
                videoOverlays: videoOverlays,
                activeSessionID: controller.historyRecorder.activeSessionID,
                canSplitActiveDrive: controller.isConnected && controller.historyRecorder.activeSessionID != nil,
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

            AppSettingsView(
                locationTracker: controller.locationTracker,
                cloudAccount: cloudAccount,
                cloudSync: cloudSync,
                videoRecorder: videoRecorder,
                segmentSettings: controller.historyRecorder.segmentSettings
            )
                .toolbarVisibility(compactLandscape ? .hidden : .automatic, for: .tabBar)
                .tabItem {
                    Label("Ustawienia", systemImage: "gearshape.fill")
                }
                .tag(3)
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

private struct AppSettingsView: View {
    @ObservedObject var locationTracker: LocationTrackingService
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @ObservedObject var videoRecorder: DriveVideoRecorder
    @ObservedObject var segmentSettings: DriveSegmentSettingsStore

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        settingsSection(
                            title: localized("KONTO I SYNCHRONIZACJA"),
                            subtitle: localized("Touge Dash Cloud i dane online")
                        )
                        CloudSyncCard(account: cloudAccount, sync: cloudSync)

                        settingsSection(
                            title: localized("REJESTROWANIE PRZEJAZDÓW"),
                            subtitle: localized("Trasa GPS, podział sesji i kamera")
                        )
                        LocationRecordingCard(locationTracker: locationTracker)
                        DriveSegmentationCard(settings: segmentSettings)
                        DriveVideoRecordingCard(recorder: videoRecorder)

                        ProductCreditFooter()
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: 1_000)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle(localized("Ustawienia"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func settingsSection(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .black))
                .tracking(1.4)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}
