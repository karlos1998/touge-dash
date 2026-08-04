import Foundation

struct CloudAccount: Codable, Equatable, Sendable {
    let id: UUID
    let email: String
    let displayName: String
}

struct CloudAuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let account: CloudAccount
}

struct CloudVehicle: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    let hardwareFingerprint: String
    let role: String
    let createdAt: Date
}

struct CloudDashboardTemplate: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let name: String
    let definition: DashboardDefinition
    let modifiedAt: Date
    let deletedAt: Date?
    let serverUpdatedAt: Date?

    init(record: DashboardTemplateRecord) {
        id = record.id
        schemaVersion = record.schemaVersion
        name = record.name
        definition = record.definition
        modifiedAt = record.modifiedAt
        deletedAt = record.deletedAt
        serverUpdatedAt = nil
    }

    var record: DashboardTemplateRecord {
        DashboardTemplateRecord(
            id: id,
            schemaVersion: schemaVersion,
            name: name,
            definition: definition,
            modifiedAt: modifiedAt,
            deletedAt: deletedAt
        )
    }
}

struct CloudDashboardTemplateSyncRequest: Encodable, Sendable {
    let templates: [CloudDashboardTemplate]
}

struct CloudDashboardTemplateSyncResponse: Decodable, Sendable {
    let templates: [CloudDashboardTemplate]
}

struct CloudSyncResult: Codable, Sendable {
    let sessionId: UUID
    let serverRevision: Int
    let acceptedSamples: Int
    let synchronizedAt: Date
}

struct CloudIncidentSyncResult: Codable, Sendable {
    let incidentId: UUID
    let serverRevision: Int
    let acceptedSamples: Int
    let synchronizedAt: Date
}

struct CloudIncidentUpload: Encodable, Sendable {
    let id: UUID
    let sessionId: UUID
    let type: String
    let severity: String
    let triggeredAt: Date
    let captureStartedAt: Date
    let captureEndedAt: Date
    let revision: Int
    let sampleCount: Int
    let sampleRateHz: Double
    let triggerValue: Double
    let thresholdValue: Double
    let triggerUnit: String
    let triggerRpm: Double
    let triggerBoostBar: Double
    let triggerAfr: Double
    let triggerSpeedKph: Double
    let latitude: Double?
    let longitude: Double?
    let samples: [CloudSampleUpload]
}

struct CloudTimelineAnnotationUpload: Encodable, Sendable {
    let id: UUID
    let incidentId: UUID?
    let recordedAt: Date
    let body: String
}

struct CloudTimelineAnnotationResponse: Decodable, Sendable {
    let id: UUID
    let sessionId: UUID
    let incidentId: UUID?
    let recordedAt: Date
    let body: String
    let updatedAt: Date
}

struct CloudIncidentShareRequest: Encodable, Sendable {
    let unit: String
    let amount: Int?
}

struct CloudIncidentShare: Decodable, Sendable {
    let id: UUID
    let token: String
    let createdAt: Date
    let expiresAt: Date?
}

struct CloudSessionUpload: Encodable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let revision: Int
    let sampleCount: Int
    let distanceMeters: Double
    let maxRpm: Double
    let maxSpeedKph: Double
    let maxBoostBar: Double
    let maxCoolantCelsius: Double
    let maxOilTemperatureCelsius: Double
    let minimumOilPressureBar: Double?
    let containsLocation: Bool
    let samples: [CloudSampleUpload]
}

struct CloudSampleUpload: Encodable, Sendable {
    let id: UUID
    let recordedAt: Date
    let revision: Int
    let rpm: Double
    let boostBar: Double
    let mapKpa: Double
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
    let speedKph: Double
    let checkEngineMask: Int
    let latitude: Double?
    let longitude: Double?
    let horizontalAccuracy: Double?
    let altitude: Double?
}

struct CloudLiveUpload: Encodable, Sendable {
    let recordedAt: Date
    let rpm: Double
    let boostBar: Double
    let mapKpa: Double
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
    let speedKph: Double
    let checkEngineMask: Int
    let latitude: Double?
    let longitude: Double?
}

struct CloudAPIErrorPayload: Decodable, Sendable {
    let code: String?
    let message: String?
}

enum CloudAPIError: LocalizedError {
    case invalidServerAddress
    case invalidResponse
    case localHistoryIncomplete
    case unauthorized
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress: localized("Nieprawidłowy adres serwera.")
        case .invalidResponse: localized("Serwer zwrócił nieprawidłową odpowiedź.")
        case .localHistoryIncomplete:
            localized("Nie udało się odczytać wszystkich lokalnych próbek. Synchronizacja spróbuje ponownie.")
        case .unauthorized: localized("Sesja wygasła. Zaloguj się ponownie.")
        case .server(let status, let message):
            Locale.current.language.languageCode?.identifier == "pl"
                ? message
                : String(format: localized("Błąd serwera (%d)."), status)
        }
    }
}

extension JSONEncoder {
    static func tougeDashCloud() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static func tougeDashCloud() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
