import SwiftUI

struct TougeDashRootView: View {
    @ObservedObject var controller: TelemetryController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selection: Int

    init(controller: TelemetryController) {
        self.controller = controller
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
                onShowHistory: compactLandscape ? { selection = 1 } : nil
            )
                .toolbarVisibility(compactLandscape ? .hidden : .automatic, for: .tabBar)
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                }
                .tag(0)

            HistoryView(
                locationTracker: controller.locationTracker,
                onShowDashboard: compactLandscape ? { selection = 0 } : nil
            )
                .toolbarVisibility(compactLandscape ? .hidden : .automatic, for: .tabBar)
                .tabItem {
                    Label("Historia", systemImage: "chart.xyaxis.line")
                }
                .tag(1)
        }
        .tint(.tougeCyan)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                controller.historyRecorder.saveNow()
            }
        }
    }
}
