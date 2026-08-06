import Foundation
import SwiftData
import Combine

enum HistoryPresentationPolicy {
    static let maximumVisibleSessions = 10
    static let maximumVisibleIncidents = 10
    static let maximumVisibleVideoRecords = 40
}

@MainActor
enum HistoryLocalStore {
    static func enforceRetention(in context: ModelContext, keepingActiveSessionID: UUID? = nil) throws {
        let sessions = try context.fetch(FetchDescriptor<DriveSession>(
            sortBy: [SortDescriptor(\DriveSession.startedAt, order: .reverse)]
        ))
        let retainedSessionIDs = Set(sessions.prefix(HistoryPresentationPolicy.maximumVisibleSessions).map(\.id))
        for session in sessions where !retainedSessionIDs.contains(session.id) && session.id != keepingActiveSessionID {
            delete(session: session, in: context)
        }

        let incidents = try context.fetch(FetchDescriptor<DriveIncident>(
            sortBy: [SortDescriptor(\DriveIncident.triggeredAt, order: .reverse)]
        ))
        for incident in incidents.dropFirst(HistoryPresentationPolicy.maximumVisibleIncidents) {
            delete(incident: incident, in: context)
        }
        try context.save()
    }

    static func delete(session: DriveSession, in context: ModelContext) {
        let sessionID = session.id
        let videos = (try? context.fetch(FetchDescriptor<DriveVideoRecording>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))) ?? []
        for video in videos {
            try? DriveVideoFileStore.delete(video)
            context.delete(video)
        }
        let incidents = (try? context.fetch(FetchDescriptor<DriveIncident>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))) ?? []
        incidents.forEach(context.delete)
        let attempts = (try? context.fetch(FetchDescriptor<AccelerationAttempt>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))) ?? []
        attempts.forEach(context.delete)
        let annotations = (try? context.fetch(FetchDescriptor<TimelineAnnotation>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))) ?? []
        annotations.forEach(context.delete)
        context.delete(session)
    }

    static func delete(incident: DriveIncident, in context: ModelContext) {
        let incidentID = incident.id
        let annotations = (try? context.fetch(FetchDescriptor<TimelineAnnotation>(
            predicate: #Predicate { $0.incidentID == incidentID }
        ))) ?? []
        annotations.forEach(context.delete)
        context.delete(incident)
    }
}

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

enum AccelerationType: String, Codable, CaseIterable, Identifiable, Sendable {
    case zeroTo100 = "ZERO_TO_100"
    case hundredTo200 = "HUNDRED_TO_200"
    case twoHundredTo250 = "TWO_HUNDRED_TO_250"

    var id: String { rawValue }
    var startKPH: Double { self == .zeroTo100 ? 0 : self == .hundredTo200 ? 100 : 200 }
    var endKPH: Double { self == .zeroTo100 ? 100 : self == .hundredTo200 ? 200 : 250 }
    var label: String { self == .zeroTo100 ? "0–100" : self == .hundredTo200 ? "100–200" : "200–250" }
}

struct ActiveAcceleration: Equatable, Sendable {
    let type: AccelerationType
    let startedAt: Date
    let elapsed: TimeInterval
    let currentSpeedKPH: Double
    let progress: Double
}

@Model
final class AccelerationAttempt {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var typeRaw: String
    var startedAt: Date
    var endedAt: Date
    var durationMillis: Int64
    var startSpeedKPH: Double
    var endSpeedKPH: Double
    var sourceRaw: String
    var qualityRaw: String
    var sampleRateHz: Double
    var shiftCount: Int
    var revision: Int

    init(
        id: UUID = UUID(), sessionID: UUID, type: AccelerationType,
        startedAt: Date, endedAt: Date, durationMillis: Int64,
        sampleRateHz: Double, shiftCount: Int, quality: String
    ) {
        self.id = id
        self.sessionID = sessionID
        typeRaw = type.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMillis = durationMillis
        startSpeedKPH = type.startKPH
        endSpeedKPH = type.endKPH
        sourceRaw = "ECU"
        qualityRaw = quality
        self.sampleRateHz = sampleRateHz
        self.shiftCount = shiftCount
        revision = 1
    }

    var type: AccelerationType { AccelerationType(rawValue: typeRaw) ?? .zeroTo100 }
}

@MainActor
final class AccelerationEngine: ObservableObject {
    private struct Point { let at: Date; let speed: Double; let rpm: Double; let throttle: Double }
    private struct Running {
        let type: AccelerationType
        let startedAt: Date
        var peakSpeed: Double
        var lastProgressAt: Date
        var previousRPM: Double
        var previousThrottle: Double
        var shiftDropActive = false
        var shiftCount = 0
        var sampleCount = 1
    }

    @Published private(set) var active: ActiveAcceleration?
    @Published private(set) var recentResults: [AccelerationAttempt] = []
    private var history: [Point] = []
    private var previous: Point?
    private var running: Running?
    private var stationarySince: Date?
    private var zeroArmed = false

    func reset() {
        history.removeAll(keepingCapacity: true)
        previous = nil; running = nil; stationarySince = nil; zeroArmed = false; active = nil
        recentResults = []
    }

    func sample(_ snapshot: TelemetrySnapshot, at: Date, sessionID: UUID?) -> AccelerationAttempt? {
        let point = Point(at: at, speed: max(0, snapshot.speedKPH), rpm: snapshot.rpm, throttle: snapshot.throttlePercent)
        let candidate = previous
        let prior = candidate.flatMap { at.timeIntervalSince($0.at) <= 0.75 ? $0 : nil }
        if candidate != nil, prior == nil {
            abort()
            history.removeAll(keepingCapacity: true)
            stationarySince = nil
            zeroArmed = false
        }
        previous = point
        history.append(point)
        history.removeAll { at.timeIntervalSince($0.at) > 2.5 }
        updateStationary(point)
        let completed = updateRunning(point, prior: prior, sessionID: sessionID)
        if running == nil, let prior { tryStart(point, prior: prior) }
        publish(point)
        return completed
    }

    private func updateStationary(_ point: Point) {
        if point.speed <= 2 {
            if stationarySince == nil { stationarySince = point.at }
            if point.at.timeIntervalSince(stationarySince ?? point.at) >= 0.8 { zeroArmed = true }
        } else if point.speed > 5 { stationarySince = nil }
    }

    private func tryStart(_ point: Point, prior: Point) {
        if zeroArmed, prior.speed <= 1, point.speed > 1 {
            running = Running(type: .zeroTo100, startedAt: crossingTime(prior, point, threshold: 1), peakSpeed: point.speed, lastProgressAt: point.at, previousRPM: point.rpm, previousThrottle: point.throttle)
            zeroArmed = false; stationarySince = nil
            return
        }
        for type in [AccelerationType.hundredTo200, .twoHundredTo250] where prior.speed < type.startKPH && point.speed >= type.startKPH {
            guard let approach = history.first(where: { $0.speed <= type.startKPH - 6 }) else { continue }
            let seconds = max(0.001, point.at.timeIntervalSince(approach.at))
            guard (point.speed - approach.speed) / seconds >= 3 else { continue }
            running = Running(type: type, startedAt: crossingTime(prior, point, threshold: type.startKPH), peakSpeed: point.speed, lastProgressAt: point.at, previousRPM: point.rpm, previousThrottle: point.throttle)
            return
        }
    }

    private func updateRunning(_ point: Point, prior: Point?, sessionID: UUID?) -> AccelerationAttempt? {
        guard var current = running else { return nil }
        current.sampleCount += 1
        if point.speed > current.peakSpeed + 0.25 { current.peakSpeed = point.speed; current.lastProgressAt = point.at }
        else { current.peakSpeed = max(current.peakSpeed, point.speed) }
        if !current.shiftDropActive, current.previousThrottle >= 35, point.throttle <= 15, current.previousRPM - point.rpm >= 250 {
            current.shiftDropActive = true; current.shiftCount += 1
        }
        if point.throttle >= 25 { current.shiftDropActive = false }
        current.previousRPM = point.rpm; current.previousThrottle = point.throttle
        running = current

        if let prior, prior.speed < current.type.endKPH, point.speed >= current.type.endKPH {
            let endedAt = crossingTime(prior, point, threshold: current.type.endKPH)
            let duration = max(0.001, endedAt.timeIntervalSince(current.startedAt))
            let rate = Double(current.sampleCount) / duration
            running = nil
            guard let sessionID else { return nil }
            let attempt = AccelerationAttempt(
                sessionID: sessionID, type: current.type, startedAt: current.startedAt, endedAt: endedAt,
                durationMillis: Int64((duration * 1_000).rounded()), sampleRateHz: rate,
                shiftCount: current.shiftCount, quality: rate >= 20 && duration >= 1 ? "HIGH" : rate >= 8 ? "MEDIUM" : "ESTIMATED"
            )
            recentResults = Array(([attempt] + recentResults).prefix(12))
            return attempt
        }
        if point.speed < current.type.startKPH - 8 || current.peakSpeed - point.speed > 8 || point.at.timeIntervalSince(current.lastProgressAt) > 3.2 { abort() }
        return nil
    }

    private func publish(_ point: Point) {
        active = running.map {
            ActiveAcceleration(type: $0.type, startedAt: $0.startedAt, elapsed: max(0, point.at.timeIntervalSince($0.startedAt)), currentSpeedKPH: point.speed, progress: min(1, max(0, (point.speed - $0.type.startKPH) / ($0.type.endKPH - $0.type.startKPH))))
        }
    }

    private func abort() { running = nil; active = nil }
    private func crossingTime(_ before: Point, _ after: Point, threshold: Double) -> Date {
        let delta = after.speed - before.speed
        guard delta > 0.0001 else { return after.at }
        let fraction = min(1, max(0, (threshold - before.speed) / delta))
        return before.at.addingTimeInterval(after.at.timeIntervalSince(before.at) * fraction)
    }
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
    // Optional fields keep the SwiftData migration lightweight for recordings
    // created before imported videos and timeline alignment were introduced.
    var sourceKindRaw: String?
    var sourceDisplayName: String?
    var videoTrimStartSeconds: Double?
    var telemetryTrimStartSeconds: Double?
    var exportDurationSeconds: Double?
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
        sourceKind: DriveVideoSourceKind = .camera,
        sourceDisplayName: String? = nil,
        videoTrimStartSeconds: Double? = nil,
        telemetryTrimStartSeconds: Double? = nil,
        exportDurationSeconds: Double? = nil,
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
        sourceKindRaw = sourceKind.rawValue
        self.sourceDisplayName = sourceDisplayName
        self.videoTrimStartSeconds = videoTrimStartSeconds
        self.telemetryTrimStartSeconds = telemetryTrimStartSeconds
        self.exportDurationSeconds = exportDurationSeconds
        self.createdAt = createdAt
    }

    var sourceKind: DriveVideoSourceKind {
        get { sourceKindRaw.flatMap(DriveVideoSourceKind.init(rawValue:)) ?? .camera }
        set { sourceKindRaw = newValue.rawValue }
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
    static let simulatorID = UUID(uuidString: "0E0F7D29-8A5C-4A69-A8A7-51E519100001")!

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
