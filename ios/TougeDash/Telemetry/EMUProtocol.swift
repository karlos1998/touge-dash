import Foundation

struct EMUFrame: Equatable, Sendable {
    let channel: UInt8
    let rawValue: UInt16
}

struct EMUParserStats: Equatable, Sendable {
    var validFrames = 0
    var badChecksums = 0
    var droppedBytes = 0
}

struct EMUFrameParser: Sendable {
    private(set) var buffer: [UInt8] = []
    private(set) var stats = EMUParserStats()

    mutating func feed(_ data: Data) -> [EMUFrame] {
        buffer.append(contentsOf: data)
        var frames: [EMUFrame] = []

        while buffer.count >= 5 {
            guard buffer[1] == 0xA3 else {
                buffer.removeFirst()
                stats.droppedBytes += 1
                continue
            }

            let expected = UInt8(truncatingIfNeeded: buffer[0...3].reduce(0) { $0 + Int($1) })
            guard expected == buffer[4] else {
                buffer.removeFirst()
                stats.badChecksums += 1
                stats.droppedBytes += 1
                continue
            }

            let rawValue = UInt16(buffer[2]) << 8 | UInt16(buffer[3])
            frames.append(EMUFrame(channel: buffer[0], rawValue: rawValue))
            buffer.removeFirst(5)
            stats.validFrames += 1
        }
        return frames
    }

    static func encode(channel: UInt8, rawValue: UInt16) -> Data {
        let payload = [channel, 0xA3, UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)]
        let checksum = UInt8(truncatingIfNeeded: payload.reduce(0) { $0 + Int($1) })
        return Data(payload + [checksum])
    }
}

struct EMUTelemetryAccumulator: Sendable {
    private(set) var snapshot = TelemetrySnapshot()
    var fallbackBarometricKPa = 101.325

    mutating func apply(_ frame: EMUFrame) {
        let raw = frame.rawValue
        switch frame.channel {
        case 1: snapshot.rpm = Double(raw)
        case 2:
            snapshot.mapKPa = Double(raw)
            snapshot.boostBar = (snapshot.mapKPa - fallbackBarometricKPa) / 100
        case 3: snapshot.throttlePercent = unsigned8(raw)
        case 4: snapshot.intakeCelsius = signed8(raw)
        case 5: snapshot.batteryVoltage = Double(raw) / 37
        case 6: snapshot.ignitionDegrees = signed8(raw) / 2
        case 12: snapshot.afr = unsigned8(raw) / 10
        case 14:
            fallbackBarometricKPa = unsigned8(raw)
            if snapshot.mapKPa > 0 {
                snapshot.boostBar = (snapshot.mapKPa - fallbackBarometricKPa) / 100
            }
        case 19: snapshot.injectorDutyPercent = unsigned8(raw) / 2
        case 21: snapshot.oilPressureBar = unsigned8(raw) / 16
        case 22: snapshot.oilTemperatureCelsius = unsigned8(raw)
        case 23: snapshot.fuelPressureBar = unsigned8(raw) / 16
        case 24: snapshot.coolantCelsius = signed16(raw)
        case 27: snapshot.lambda = unsigned8(raw) / 128
        case 28: snapshot.speedKPH = Double(raw) / 4
        case 255: snapshot.checkEngineMask = raw
        default: return
        }
        snapshot.updatedAt = .now
    }

    private func unsigned8(_ raw: UInt16) -> Double {
        Double(UInt8(truncatingIfNeeded: raw))
    }

    private func signed8(_ raw: UInt16) -> Double {
        Double(Int8(bitPattern: UInt8(truncatingIfNeeded: raw)))
    }

    private func signed16(_ raw: UInt16) -> Double {
        Double(Int16(bitPattern: raw))
    }
}
