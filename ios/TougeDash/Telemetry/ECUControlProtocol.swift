import Foundation

/// The only ECU-bound payload supported by Touge Dash. This deliberately does
/// not expose arbitrary GATT, serial or CAN writes.
struct ECUControlSnapshot: Equatable, Sendable {
    static let channelRange = 1...8
    static let rotaryValueRange = 0...15

    private(set) var switches: [Bool]
    private(set) var rotaryValues: [UInt8]

    init(switches: [Bool] = Array(repeating: false, count: 8), rotaryValues: [UInt8] = Array(repeating: 0, count: 8)) {
        precondition(switches.count == 8)
        precondition(rotaryValues.count == 8)
        precondition(rotaryValues.allSatisfy { Self.rotaryValueRange.contains(Int($0)) })
        self.switches = switches
        self.rotaryValues = rotaryValues
    }

    func switchValue(channel: Int) -> Bool? {
        guard Self.channelRange.contains(channel) else { return nil }
        return switches[channel - 1]
    }

    func rotaryValue(channel: Int) -> UInt8? {
        guard Self.channelRange.contains(channel) else { return nil }
        return rotaryValues[channel - 1]
    }

    func settingSwitch(channel: Int, to value: Bool) -> ECUControlSnapshot? {
        guard Self.channelRange.contains(channel) else { return nil }
        var copy = self
        copy.switches[channel - 1] = value
        return copy
    }

    func settingRotary(channel: Int, to value: Int) -> ECUControlSnapshot? {
        guard Self.channelRange.contains(channel), Self.rotaryValueRange.contains(value) else { return nil }
        var copy = self
        copy.rotaryValues[channel - 1] = UInt8(value)
        return copy
    }

    /// eDash 0.0.48 status frame: length, type, switch bitmap, four packed
    /// rotary bytes and an additive 8-bit checksum.
    func encodedStatusFrame() -> Data {
        var bytes: [UInt8] = [0x08, 0x55, switchBitmap]
        for index in stride(from: 0, to: rotaryValues.count, by: 2) {
            bytes.append((rotaryValues[index] << 4) | rotaryValues[index + 1])
        }
        bytes.append(UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 + Int($1) }))
        return Data(bytes)
    }

    static func isValidStatusFrame(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard bytes.count == 8, bytes[0] == 0x08, bytes[1] == 0x55 else { return false }
        let checksum = UInt8(truncatingIfNeeded: bytes.prefix(7).reduce(0) { $0 + Int($1) })
        return checksum == bytes[7]
    }

    private var switchBitmap: UInt8 {
        switches.enumerated().reduce(0) { result, entry in
            entry.element ? result | UInt8(1 << (7 - entry.offset)) : result
        }
    }
}

struct ECUControlLoopbackAccumulator: Sendable {
    private var switchByte: UInt8?
    private var rotary1234: UInt16?
    private var rotary5678: UInt16?
    private var switchReceivedAt: Date?
    private var rotary1234ReceivedAt: Date?
    private var rotary5678ReceivedAt: Date?
    private var revision: UInt64 = 0
    private var switchRevision: UInt64 = 0
    private var rotary1234Revision: UInt64 = 0
    private var rotary5678Revision: UInt64 = 0

    var currentRevision: UInt64 { revision }

    mutating func reset() {
        self = ECUControlLoopbackAccumulator()
    }

    @discardableResult
    mutating func apply(_ frame: EMUFrame, receivedAt: Date = .now) -> Bool {
        guard frame.channel == 254 || frame.channel == 253 || frame.channel == 252 else { return false }
        revision &+= 1
        switch frame.channel {
        case 254:
            switchByte = UInt8(truncatingIfNeeded: frame.rawValue)
            switchReceivedAt = receivedAt
            switchRevision = revision
        case 253:
            rotary1234 = frame.rawValue
            rotary1234ReceivedAt = receivedAt
            rotary1234Revision = revision
        case 252:
            rotary5678 = frame.rawValue
            rotary5678ReceivedAt = receivedAt
            rotary5678Revision = revision
        default: break
        }
        return true
    }

    func snapshotIfFresh(
        at now: Date = .now,
        maximumAge: TimeInterval = 2,
        receivedAfterRevision: UInt64? = nil
    ) -> ECUControlSnapshot? {
        guard let switchByte, let rotary1234, let rotary5678,
              let switchReceivedAt, let rotary1234ReceivedAt, let rotary5678ReceivedAt,
              now.timeIntervalSince(switchReceivedAt) <= maximumAge,
              now.timeIntervalSince(rotary1234ReceivedAt) <= maximumAge,
              now.timeIntervalSince(rotary5678ReceivedAt) <= maximumAge else {
            return nil
        }
        if let receivedAfterRevision,
           [switchRevision, rotary1234Revision, rotary5678Revision].contains(where: { $0 <= receivedAfterRevision }) {
            return nil
        }

        let switches = (0..<8).map { index in
            (switchByte & UInt8(1 << (7 - index))) != 0
        }
        let rotaryValues = unpack(rotary1234) + unpack(rotary5678)
        return ECUControlSnapshot(switches: switches, rotaryValues: rotaryValues)
    }

    private func unpack(_ value: UInt16) -> [UInt8] {
        [12, 8, 4, 0].map { shift in UInt8((value >> shift) & 0x0F) }
    }
}
