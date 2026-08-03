import CoreLocation
import Foundation
import SwiftData

@MainActor
final class TelemetryHistoryRecorder: ObservableObject {
    static let sampleInterval: TimeInterval = 1
    static let newSessionGap: TimeInterval = 90

    let locationTracker: LocationTrackingService

    private let context: ModelContext
    private var vehicleID: UUID
    private var activeSession: DriveSession?
    private var lastRecordedAt = Date.distantPast
    private var lastSavedAt = Date.distantPast
    private var lastDistanceLocation: RecordedLocation?

    init(container: ModelContainer, locationTracker: LocationTrackingService) {
        context = ModelContext(container)
        context.autosaveEnabled = true
        vehicleID = LocalVehicleIdentity.resolve()
        self.locationTracker = locationTracker
        restoreRecentSession()
    }

    struct RecordingChange: Equatable, Sendable {
        let sessionBecamePending: Bool
    }

    @discardableResult
    func record(_ snapshot: TelemetrySnapshot, at timestamp: Date = .now) -> RecordingChange? {
        guard timestamp.timeIntervalSince(lastRecordedAt) >= Self.sampleInterval else { return nil }

        let previousSessionID = activeSession?.id
        let session = resolveSession(at: timestamp)
        let isNewSession = previousSessionID != session.id
        let wasPending = !isNewSession && session.syncState != .synced
        let location = freshLocation(at: timestamp)
        let sample = TelemetryHistorySample(
            snapshot: snapshot,
            timestamp: timestamp,
            location: location,
            session: session
        )
        context.insert(sample)

        update(session, with: sample, location: location)
        lastRecordedAt = timestamp

        if timestamp.timeIntervalSince(lastSavedAt) >= 5 {
            try? context.save()
            lastSavedAt = timestamp
        }
        return RecordingChange(sessionBecamePending: isNewSession || !wasPending)
    }

    func activateVehicle(_ id: UUID) {
        guard vehicleID != id else { return }
        saveNow()
        vehicleID = id
        activeSession = nil
        lastDistanceLocation = nil
        lastRecordedAt = .distantPast
        restoreRecentSession()
    }

    func saveNow() {
        try? context.save()
        lastSavedAt = .now
    }

    #if DEBUG
    func seedPreviewDataIfNeeded() {
        var descriptor = FetchDescriptor<DriveSession>()
        descriptor.fetchLimit = 1
        guard (try? context.fetchCount(descriptor)) == 0 else { return }

        let start = Calendar.current.date(byAdding: .hour, value: -19, to: .now) ?? .now.addingTimeInterval(-68_400)
        let session = DriveSession(vehicleID: vehicleID, startedAt: start)
        context.insert(session)

        var previousLocation: RecordedLocation?
        for index in 0..<300 {
            let elapsed = Double(index) * 4
            let phase = Double(index) / 18
            var snapshot = TelemetrySnapshot.preview
            snapshot.rpm = 2_200 + sin(phase) * 1_100 + max(0, sin(phase * 0.37)) * 2_700
            snapshot.speedKPH = max(0, 62 + sin(phase * 0.52) * 38)
            snapshot.boostBar = max(-0.25, -0.05 + sin(phase * 0.83) * 0.55 + max(0, sin(phase * 0.31)) * 0.65)
            snapshot.throttlePercent = max(5, min(100, 42 + sin(phase * 0.7) * 34))
            snapshot.coolantCelsius = 82 + min(14, elapsed / 100) + sin(phase * 0.18) * 1.2
            snapshot.oilTemperatureCelsius = 76 + min(31, elapsed / 70) + sin(phase * 0.22) * 1.8
            snapshot.oilPressureBar = max(1.2, 1.4 + snapshot.rpm / 2_100)
            snapshot.afr = 14.5 - max(0, snapshot.boostBar) * 1.8 + sin(phase) * 0.2
            snapshot.injectorDutyPercent = min(92, 18 + snapshot.rpm / 105 + max(0, snapshot.boostBar) * 20)
            snapshot.updatedAt = start.addingTimeInterval(elapsed)

            let location = RecordedLocation(
                latitude: 52.4032 + Double(index) * 0.000045 + sin(phase * 0.15) * 0.0012,
                longitude: 16.9145 + Double(index) * 0.000075 + cos(phase * 0.17) * 0.0014,
                horizontalAccuracy: 6,
                altitude: 82,
                timestamp: snapshot.updatedAt
            )
            let sample = TelemetryHistorySample(
                snapshot: snapshot,
                timestamp: snapshot.updatedAt,
                location: location,
                session: session
            )
            context.insert(sample)
            update(session, with: sample, location: location, previousLocation: previousLocation)
            previousLocation = location
        }
        try? context.save()
    }
    #endif

    private func resolveSession(at timestamp: Date) -> DriveSession {
        if let activeSession,
           timestamp.timeIntervalSince(activeSession.endedAt) <= Self.newSessionGap {
            return activeSession
        }

        let session = DriveSession(vehicleID: vehicleID, startedAt: timestamp)
        context.insert(session)
        activeSession = session
        lastDistanceLocation = nil
        return session
    }

    private func restoreRecentSession() {
        var descriptor = FetchDescriptor<DriveSession>(
            sortBy: [SortDescriptor(\DriveSession.endedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let session = try? context.fetch(descriptor).first,
              Date.now.timeIntervalSince(session.endedAt) <= Self.newSessionGap else { return }
        activeSession = session
        lastRecordedAt = session.endedAt

        if let lastSample = session.samples.max(by: { $0.timestamp < $1.timestamp }),
           let latitude = lastSample.latitude,
           let longitude = lastSample.longitude {
            lastDistanceLocation = RecordedLocation(
                latitude: latitude,
                longitude: longitude,
                horizontalAccuracy: lastSample.horizontalAccuracy ?? 0,
                altitude: lastSample.altitude ?? 0,
                timestamp: lastSample.timestamp
            )
        }
    }

    private func freshLocation(at timestamp: Date) -> RecordedLocation? {
        guard locationTracker.isEnabled,
              let location = locationTracker.latestLocation,
              abs(timestamp.timeIntervalSince(location.timestamp)) <= 30 else { return nil }
        return location
    }

    private func update(
        _ session: DriveSession,
        with sample: TelemetryHistorySample,
        location: RecordedLocation?,
        previousLocation explicitPreviousLocation: RecordedLocation? = nil
    ) {
        session.endedAt = sample.timestamp
        session.modifiedAt = sample.timestamp
        session.sampleCount += 1
        session.maxRPM = max(session.maxRPM, sample.rpm)
        session.maxSpeedKPH = max(session.maxSpeedKPH, sample.speedKPH)
        session.maxBoostBar = max(session.maxBoostBar, sample.boostBar)
        session.maxCoolantCelsius = max(session.maxCoolantCelsius, sample.coolantCelsius)
        session.maxOilTemperatureCelsius = max(session.maxOilTemperatureCelsius, sample.oilTemperatureCelsius)
        if sample.oilPressureBar > 0 {
            session.minimumOilPressureBar = min(session.minimumOilPressureBar ?? sample.oilPressureBar, sample.oilPressureBar)
        }
        session.syncState = session.remoteID == nil ? .local : .changedAfterSync
        session.revision += 1

        if let location {
            session.containsLocation = true
            let previousLocation = explicitPreviousLocation ?? lastDistanceLocation
            if let previousLocation, previousLocation.timestamp != location.timestamp {
                let previous = CLLocation(latitude: previousLocation.latitude, longitude: previousLocation.longitude)
                let current = CLLocation(latitude: location.latitude, longitude: location.longitude)
                let distance = current.distance(from: previous)
                let interval = location.timestamp.timeIntervalSince(previousLocation.timestamp)
                if distance.isFinite, distance >= 0, interval > 0, distance / interval < 90 {
                    session.distanceMeters += distance
                }
            }
            lastDistanceLocation = location
        }
    }
}
