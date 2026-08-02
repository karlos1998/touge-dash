import SwiftUI

@main
struct TougeDashWatchApp: App {
    @StateObject private var controller = WatchTelemetryController()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView(controller: controller)
        }
    }
}
