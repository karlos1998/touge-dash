import Foundation

struct SimulatorTelemetry: Equatable, Sendable {
    var rpm = 920.0
    var boostBar = -0.55
    var throttlePercent = 2.0
    var coolantCelsius = 88.0
    var intakeCelsius = 24.0
    var oilTemperatureCelsius = 92.0
    var oilPressureBar = 2.2
    var fuelPressureBar = 3.5
    var afr = 14.7
    var lambda = 1.0
    var batteryVoltage = 13.9
    var ignitionDegrees = 10.0
    var injectorDutyPercent = 6.0
    var speedKPH = 0.0
    var checkEngineMask: UInt16 = 0
    var barometricKPa = 101.0

    var mapKPa: Double { max(0, barometricKPa + boostBar * 100) }
}

enum EMUFrameCodec {
    static func encode(channel: UInt8, rawValue: UInt16) -> Data {
        let payload = [channel, 0xA3, UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)]
        let checksum = UInt8(truncatingIfNeeded: payload.reduce(0) { $0 + Int($1) })
        return Data(payload + [checksum])
    }

    static func encode(_ telemetry: SimulatorTelemetry) -> Data {
        let frames: [(UInt8, UInt16)] = [
            (1, unsigned16(telemetry.rpm)),
            (2, unsigned16(telemetry.mapKPa)),
            (3, unsigned8(telemetry.throttlePercent)),
            (4, signed8(telemetry.intakeCelsius)),
            (5, unsigned16(telemetry.batteryVoltage * 37)),
            (6, signed8(telemetry.ignitionDegrees * 2)),
            (12, unsigned8(telemetry.afr * 10)),
            (14, unsigned8(telemetry.barometricKPa)),
            (19, unsigned8(telemetry.injectorDutyPercent * 2)),
            (21, unsigned8(telemetry.oilPressureBar * 16)),
            (22, unsigned8(telemetry.oilTemperatureCelsius)),
            (23, unsigned8(telemetry.fuelPressureBar * 16)),
            (24, signed16(telemetry.coolantCelsius)),
            (27, unsigned8(telemetry.lambda * 128)),
            (28, unsigned16(telemetry.speedKPH * 4)),
            (255, telemetry.checkEngineMask)
        ]
        return frames.reduce(into: Data()) { data, frame in
            data.append(encode(channel: frame.0, rawValue: frame.1))
        }
    }

    private static func unsigned8(_ value: Double) -> UInt16 {
        UInt16(UInt8(clamping: Int(value.rounded())))
    }

    private static func unsigned16(_ value: Double) -> UInt16 {
        UInt16(clamping: Int(value.rounded()))
    }

    private static func signed8(_ value: Double) -> UInt16 {
        let clamped = max(Int(Int8.min), min(Int(Int8.max), Int(value.rounded())))
        return UInt16(UInt8(bitPattern: Int8(clamped)))
    }

    private static func signed16(_ value: Double) -> UInt16 {
        let clamped = max(Int(Int16.min), min(Int(Int16.max), Int(value.rounded())))
        return UInt16(bitPattern: Int16(clamped))
    }
}
