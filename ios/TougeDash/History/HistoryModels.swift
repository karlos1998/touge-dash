import Foundation
import SwiftData

enum HistorySyncState: String, Codable, Sendable {
    case local
    case pendingUpload
    case synced
    case changedAfterSync
}

@Model
final class DriveSession {
    @Attribute(.unique) var id: UUID
    var vehicleID: UUID
    var remoteID: String?
    var startedAt: Date
    var endedAt: Date
    var modifiedAt: Date
    var sampleCount: Int
    var distanceMeters: Double
    var maxRPM: Double
    var maxSpeedKPH: Double
    var maxBoostBar: Double
    var maxCoolantCelsius: Double
    var maxOilTemperatureCelsius: Double
    var minimumOilPressureBar: Double?
    var containsLocation: Bool
    var syncStateRaw: String
    var revision: Int

    @Relationship(deleteRule: .cascade, inverse: \TelemetryHistorySample.session)
    var samples: [TelemetryHistorySample]

    init(
        id: UUID = UUID(),
        vehicleID: UUID,
        startedAt: Date,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.startedAt = startedAt
        self.endedAt = endedAt ?? startedAt
        modifiedAt = startedAt
        sampleCount = 0
        distanceMeters = 0
        maxRPM = 0
        maxSpeedKPH = 0
        maxBoostBar = 0
        maxCoolantCelsius = 0
        maxOilTemperatureCelsius = 0
        minimumOilPressureBar = nil
        containsLocation = false
        syncStateRaw = HistorySyncState.local.rawValue
        revision = 1
        samples = []
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    var syncState: HistorySyncState {
        get { HistorySyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }
}

@Model
final class TelemetryHistorySample {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var rpm: Double
    var boostBar: Double
    var mapKPa: Double
    var throttlePercent: Double
    var coolantCelsius: Double
    var intakeCelsius: Double
    var oilTemperatureCelsius: Double
    var oilPressureBar: Double
    var fuelPressureBar: Double
    var afr: Double
    var lambda: Double
    var batteryVoltage: Double
    var ignitionDegrees: Double
    var injectorDutyPercent: Double
    var speedKPH: Double
    var checkEngineMask: Int
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    var altitude: Double?
    var syncStateRaw: String
    var remoteID: String?
    var session: DriveSession?

    init(
        id: UUID = UUID(),
        snapshot: TelemetrySnapshot,
        timestamp: Date,
        location: RecordedLocation? = nil,
        session: DriveSession? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        rpm = snapshot.rpm
        boostBar = snapshot.boostBar
        mapKPa = snapshot.mapKPa
        throttlePercent = snapshot.throttlePercent
        coolantCelsius = snapshot.coolantCelsius
        intakeCelsius = snapshot.intakeCelsius
        oilTemperatureCelsius = snapshot.oilTemperatureCelsius
        oilPressureBar = snapshot.oilPressureBar
        fuelPressureBar = snapshot.fuelPressureBar
        afr = snapshot.afr
        lambda = snapshot.lambda
        batteryVoltage = snapshot.batteryVoltage
        ignitionDegrees = snapshot.ignitionDegrees
        injectorDutyPercent = snapshot.injectorDutyPercent
        speedKPH = snapshot.speedKPH
        checkEngineMask = Int(snapshot.checkEngineMask)
        latitude = location?.latitude
        longitude = location?.longitude
        horizontalAccuracy = location?.horizontalAccuracy
        altitude = location?.altitude
        syncStateRaw = HistorySyncState.local.rawValue
        remoteID = nil
        self.session = session
    }

    var syncState: HistorySyncState {
        get { HistorySyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }
}

struct RecordedLocation: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double
    let timestamp: Date
}

enum LocalVehicleIdentity {
    private static let defaultsKey = "tougeDash.localVehicleID"

    static func resolve() -> UUID {
        if let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
           let id = UUID(uuidString: rawValue) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: defaultsKey)
        return id
    }
}
