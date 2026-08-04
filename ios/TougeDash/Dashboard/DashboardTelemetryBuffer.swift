import Combine
import Foundation

struct DashboardTelemetryPoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let recordedAt: Date
    let snapshot: TelemetrySnapshot

    init(id: UUID = UUID(), recordedAt: Date, snapshot: TelemetrySnapshot) {
        self.id = id
        self.recordedAt = recordedAt
        self.snapshot = snapshot
    }
}

@MainActor
final class DashboardTelemetryBuffer: ObservableObject {
    @Published private(set) var points: [DashboardTelemetryPoint] = []

    private let retention: TimeInterval
    private let minimumInterval: TimeInterval
    private var lastRecordedAt = Date.distantPast

    init(retention: TimeInterval = 600, samplesPerSecond: Double = 5) {
        self.retention = retention
        minimumInterval = 1 / samplesPerSecond
    }

    func record(_ snapshot: TelemetrySnapshot, now: Date = .now) {
        guard now.timeIntervalSince(lastRecordedAt) >= minimumInterval else { return }
        lastRecordedAt = now
        points.append(DashboardTelemetryPoint(recordedAt: now, snapshot: snapshot))

        let cutoff = now.addingTimeInterval(-retention)
        if let firstValid = points.firstIndex(where: { $0.recordedAt >= cutoff }), firstValid > 0 {
            points.removeFirst(firstValid)
        } else if points.count > Int(retention / minimumInterval) + 10 {
            points.removeFirst(points.count - Int(retention / minimumInterval))
        }
    }

    func points(for duration: DashboardChartDuration, now: Date = .now) -> [DashboardTelemetryPoint] {
        let cutoff = now.addingTimeInterval(-TimeInterval(duration.rawValue))
        return points.filter { $0.recordedAt >= cutoff }
    }

    func reset() {
        points.removeAll(keepingCapacity: true)
        lastRecordedAt = .distantPast
    }
}
