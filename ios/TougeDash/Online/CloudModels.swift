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

struct CloudSyncResult: Codable, Sendable {
    let sessionId: UUID
    let serverRevision: Int
    let acceptedSamples: Int
    let synchronizedAt: Date
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
    case unauthorized
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress: "Nieprawidłowy adres serwera."
        case .invalidResponse: "Serwer zwrócił nieprawidłową odpowiedź."
        case .unauthorized: "Sesja wygasła. Zaloguj się ponownie."
        case .server(_, let message): message
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
