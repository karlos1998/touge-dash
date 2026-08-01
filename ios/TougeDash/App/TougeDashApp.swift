import SwiftUI

@main
struct TougeDashApp: App {
    @StateObject private var controller = TelemetryController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .preferredColorScheme(.dark)
        }
    }
}

