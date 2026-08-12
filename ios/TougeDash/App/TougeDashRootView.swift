import SwiftUI

struct TougeDashRootView: View {
    @ObservedObject var controller: TelemetryController
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @ObservedObject var dashboardTemplates: DashboardTemplateStore
    @ObservedObject var dashboardBuffer: DashboardTelemetryBuffer
    @ObservedObject var videoRecorder: DriveVideoRecorder
    @ObservedObject var videoOverlays: VideoOverlayTemplateStore
    @Binding var appearance: AppAppearance
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
        videoOverlays: VideoOverlayTemplateStore,
        appearance: Binding<AppAppearance>
    ) {
        self.controller = controller
        self.cloudAccount = cloudAccount
        self.cloudSync = cloudSync
        self.dashboardTemplates = dashboardTemplates
        self.dashboardBuffer = dashboardBuffer
        self.videoRecorder = videoRecorder
        self.videoOverlays = videoOverlays
        _appearance = appearance
        #if DEBUG
        let historyPreview = ProcessInfo.processInfo.environment["TOUGE_DASH_HISTORY_PREVIEW"] == "1"
        let settingsPreview = ProcessInfo.processInfo.environment["TOUGE_DASH_SETTINGS_PREVIEW"] == "1"
        _selection = State(initialValue: settingsPreview ? 3 : historyPreview ? 1 : 0)
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
                segmentSettings: controller.historyRecorder.segmentSettings,
                appearance: $appearance
            )
                .toolbarVisibility(compactLandscape ? .hidden : .automatic, for: .tabBar)
                .tabItem {
                    Label("Ustawienia", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.tougeCyan)
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
        .onReceive(controller.$snapshot) {
            dashboardBuffer.record($0, includeInSessionMaximums: controller.isConnected)
        }
    }
}

private struct AppSettingsView: View {
    @ObservedObject var locationTracker: LocationTrackingService
    @ObservedObject var cloudAccount: CloudAccountService
    @ObservedObject var cloudSync: CloudSyncManager
    @ObservedObject var videoRecorder: DriveVideoRecorder
    @ObservedObject var segmentSettings: DriveSegmentSettingsStore
    @Binding var appearance: AppAppearance

    var body: some View {
        NavigationStack {
            ZStack {
                DashboardBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        settingsSection(
                            title: localized("WYGLĄD"),
                            subtitle: localized("Motyw interfejsu aplikacji")
                        )
                        AppearanceSettingsCard(appearance: $appearance)

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

private struct AppearanceSettingsCard: View {
    @Binding var appearance: AppAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                ZStack {
                    CutCornerPanel(cut: 9)
                        .fill(Color.tougeBlue.opacity(0.13))
                    Image(systemName: appearance.symbol)
                        .foregroundStyle(Color.tougeBlue)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("MOTYW APLIKACJI"))
                        .font(.system(size: 12, weight: .black))
                        .tracking(1)
                    Text(localized("Domyślnie zgodny z ustawieniem urządzenia"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker(localized("Motyw aplikacji"), selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .cardSurface(accent: .tougeBlue)
    }
}
