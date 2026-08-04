import SwiftUI

@main
@MainActor
struct EMULoggerSimulatorApp: App {
    var body: some Scene {
        WindowGroup {
            SimulatorRootView()
        }
        .defaultSize(width: 1_080, height: 760)
        .windowResizability(.contentMinSize)
    }
}
