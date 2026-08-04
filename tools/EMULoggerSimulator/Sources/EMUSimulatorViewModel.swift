import Combine
import Foundation
import SwiftUI

@MainActor
final class EMUSimulatorViewModel: ObservableObject {
    @Published var telemetry = SimulatorTelemetry()
    @Published var scenario = SimulationScenario.idle {
        didSet {
            scenarioStartedAt = .now
            if scenario != .manual { telemetry = scenario.telemetry(elapsed: 0) }
        }
    }
    @Published var sampleRate = 25
    @Published private(set) var isRunning = false
    @Published private(set) var generatedFrameSets = 0

    let peripheral = BLEPeripheralSimulator()
    private var timer: Timer?
    private var scenarioStartedAt = Date.now
    private var lastSentAt = Date.distantPast

    var statusTint: Color {
        if peripheral.lastError != nil { return .orange }
        if peripheral.subscriberCount > 0 { return Color(red: 0.2, green: 0.92, blue: 0.62) }
        return isRunning ? Color(red: 0.05, green: 0.87, blue: 0.94) : .secondary
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scenarioStartedAt = .now
        lastSentAt = .distantPast
        peripheral.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        peripheral.stop()
    }

    func restartConnection() {
        stop()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.start()
        }
    }

    func resetCounters() {
        generatedFrameSets = 0
        peripheral.resetCounters()
    }

    func binding(
        _ keyPath: WritableKeyPath<SimulatorTelemetry, Double>
    ) -> Binding<Double> {
        Binding(
            get: { self.telemetry[keyPath: keyPath] },
            set: { value in
                self.scenario = .manual
                self.telemetry[keyPath: keyPath] = value
            }
        )
    }

    private func tick() {
        guard isRunning else { return }
        let now = Date.now
        guard now.timeIntervalSince(lastSentAt) >= 1 / Double(sampleRate) else { return }
        if scenario != .manual {
            telemetry = scenario.telemetry(elapsed: now.timeIntervalSince(scenarioStartedAt))
        }
        peripheral.send(EMUFrameCodec.encode(telemetry))
        generatedFrameSets += 1
        lastSentAt = now
    }
}
