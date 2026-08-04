import Foundation
import SwiftData

enum HistorySyncState: String, Codable, Sendable {
    case local
    case pendingUpload
    case synced
    case changedAfterSync
}

enum IncidentKind: String, Codable, CaseIterable, Sendable {
    case lowOilPressure = "LOW_OIL_PRESSURE"
    case leanUnderBoost = "LEAN_UNDER_BOOST"
    case overboost = "OVERBOOST"
    case engineOverheat = "ENGINE_OVERHEAT"
    case highCoolantTemperature = "HIGH_COOLANT_TEMPERATURE"
    case highOilTemperature = "HIGH_OIL_TEMPERATURE"
    case lowFuelPressure = "LOW_FUEL_PRESSURE"
    case lowBatteryVoltage = "LOW_BATTERY_VOLTAGE"

    var title: String {
        switch self {
        case .lowOilPressure: localized("Niskie ciśnienie oleju")
        case .leanUnderBoost: localized("Uboga mieszanka pod boostem")
        case .overboost: localized("Przekroczone doładowanie")
        case .engineOverheat: localized("Przegrzanie silnika")
        case .highCoolantTemperature: localized("Wysoka temperatura płynu")
        case .highOilTemperature: localized("Wysoka temperatura oleju")
        case .lowFuelPressure: localized("Niskie ciśnienie paliwa")
        case .lowBatteryVoltage: localized("Niskie napięcie")
        }
    }

    var symbol: String {
        switch self {
        case .lowOilPressure: "oilcan.fill"
        case .leanUnderBoost: "aqi.medium"
        case .overboost: "gauge.with.dots.needle.100percent"
        case .engineOverheat: "thermometer.high"
        case .highCoolantTemperature: "thermometer.and.liquid.waves"
        case .highOilTemperature: "oilcan.fill"
        case .lowFuelPressure: "fuelpump.fill"
        case .lowBatteryVoltage: "battery.25percent"
        }
    }
}

enum IncidentSeverity: String, Codable, Sendable {
    case warning = "WARNING"
    case critical = "CRITICAL"
}

struct CapturedTelemetryPoint: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let rpm: Double
    let boostBar: Double
    let mapKPa: Double
    let throttlePercent: Double
    let coolantCelsius: Double
    let intakeCelsius: Double
    let oilTemperatureCelsius: Double
    let oilPressureBar: Double
    let fuelPressureBar: Double
    let afr: Double
    let lambda: Double
    let batteryVoltage: Double
    let ignitionDegrees: Double
    let injectorDutyPercent: Double
    let speedKPH: Double
    let checkEngineMask: Int
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let altitude: Double?

    init(
        id: UUID = UUID(),
        snapshot: TelemetrySnapshot,
        timestamp: Date,
        location: RecordedLocation? = nil
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
    }
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
    var chartEligible: Bool?
    var syncStateRaw: String
    var remoteID: String?
    var session: DriveSession?

    init(
        id: UUID = UUID(),
        snapshot: TelemetrySnapshot,
        timestamp: Date,
        location: RecordedLocation? = nil,
        chartEligible: Bool = true,
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
        self.chartEligible = chartEligible
        syncStateRaw = HistorySyncState.local.rawValue
        remoteID = nil
        self.session = session
    }

    var syncState: HistorySyncState {
        get { HistorySyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }
}

@Model
final class DriveVideoRecording {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var fileName: String
    var startedAt: Date
    var endedAt: Date
    var duration: Double
    var fileSizeBytes: Int64
    var pixelWidth: Int
    var pixelHeight: Int
    var framesPerSecond: Double
    var cameraName: String
    var hasAudio: Bool
    var preferredOverlayTemplateID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        fileName: String,
        startedAt: Date,
        endedAt: Date,
        duration: Double,
        fileSizeBytes: Int64,
        pixelWidth: Int,
        pixelHeight: Int,
        framesPerSecond: Double,
        cameraName: String,
        hasAudio: Bool,
        preferredOverlayTemplateID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.fileName = fileName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.fileSizeBytes = fileSizeBytes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.framesPerSecond = framesPerSecond
        self.cameraName = cameraName
        self.hasAudio = hasAudio
        self.preferredOverlayTemplateID = preferredOverlayTemplateID
        self.createdAt = createdAt
    }
}

@Model
final class DriveIncident {
    @Attribute(.unique) var id: UUID
    var vehicleID: UUID
    var sessionID: UUID
    var kindRaw: String
    var severityRaw: String
    var triggeredAt: Date
    var captureStartedAt: Date
    var captureEndedAt: Date
    var sampleCount: Int
    var sampleRateHz: Double
    var triggerValue: Double
    var thresholdValue: Double
    var triggerUnit: String
    var triggerRPM: Double
    var triggerBoostBar: Double
    var triggerAFR: Double
    var triggerSpeedKPH: Double
    var latitude: Double?
    var longitude: Double?
    var encodedSamples: Data
    var syncStateRaw: String
    var revision: Int
    var remoteID: String?

    init(
        id: UUID = UUID(),
        vehicleID: UUID,
        sessionID: UUID,
        kind: IncidentKind,
        severity: IncidentSeverity,
        triggeredAt: Date,
        thresholdValue: Double,
        triggerValue: Double,
        triggerUnit: String,
        samples: [CapturedTelemetryPoint]
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.sessionID = sessionID
        kindRaw = kind.rawValue
        severityRaw = severity.rawValue
        self.triggeredAt = triggeredAt
        let firstTimestamp = samples.first?.timestamp ?? triggeredAt
        let lastTimestamp = samples.last?.timestamp ?? triggeredAt
        captureStartedAt = firstTimestamp
        captureEndedAt = lastTimestamp
        sampleCount = samples.count
        let duration = lastTimestamp.timeIntervalSince(firstTimestamp)
        sampleRateHz = duration > 0 ? Double(max(1, samples.count - 1)) / duration : 25
        self.triggerValue = triggerValue
        self.thresholdValue = thresholdValue
        self.triggerUnit = triggerUnit
        let trigger = samples.min {
            abs($0.timestamp.timeIntervalSince(triggeredAt)) < abs($1.timestamp.timeIntervalSince(triggeredAt))
        }
        triggerRPM = trigger?.rpm ?? 0
        triggerBoostBar = trigger?.boostBar ?? 0
        triggerAFR = trigger?.afr ?? 0
        triggerSpeedKPH = trigger?.speedKPH ?? 0
        latitude = trigger?.latitude
        longitude = trigger?.longitude
        encodedSamples = (try? JSONEncoder().encode(samples)) ?? Data()
        syncStateRaw = HistorySyncState.local.rawValue
        revision = 1
        remoteID = nil
    }

    var kind: IncidentKind {
        IncidentKind(rawValue: kindRaw) ?? .engineOverheat
    }

    var severity: IncidentSeverity {
        IncidentSeverity(rawValue: severityRaw) ?? .warning
    }

    var samples: [CapturedTelemetryPoint] {
        (try? JSONDecoder().decode([CapturedTelemetryPoint].self, from: encodedSamples)) ?? []
    }

    var syncState: HistorySyncState {
        get { HistorySyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }
}

@Model
final class TimelineAnnotation {
    @Attribute(.unique) var id: UUID
    var vehicleID: UUID
    var sessionID: UUID
    var incidentID: UUID?
    var timestamp: Date
    var body: String
    var createdAt: Date
    var modifiedAt: Date
    var syncStateRaw: String

    init(
        id: UUID = UUID(),
        vehicleID: UUID,
        sessionID: UUID,
        incidentID: UUID? = nil,
        timestamp: Date,
        body: String
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.sessionID = sessionID
        self.incidentID = incidentID
        self.timestamp = timestamp
        self.body = body
        createdAt = .now
        modifiedAt = .now
        syncStateRaw = HistorySyncState.local.rawValue
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

    static func resolve(defaults: UserDefaults = .standard) -> UUID {
        if let rawValue = defaults.string(forKey: defaultsKey),
           let id = UUID(uuidString: rawValue) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: defaultsKey)
        return id
    }
}
