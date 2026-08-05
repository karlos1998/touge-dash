import XCTest
@testable import EMULoggerSimulator

final class EMUFrameCodecTests: XCTestCase {
    func testFrameUsesProtocolMarkerAndChecksum() {
        let frame = Array(EMUFrameCodec.encode(channel: 1, rawValue: 6_400))

        XCTAssertEqual(frame.count, 5)
        XCTAssertEqual(frame[0], 1)
        XCTAssertEqual(frame[1], 0xA3)
        XCTAssertEqual(frame[2], 0x19)
        XCTAssertEqual(frame[3], 0x00)
        XCTAssertEqual(frame[4], UInt8(truncatingIfNeeded: frame.prefix(4).reduce(0) { $0 + Int($1) }))
    }

    func testPayloadContainsEveryTougeDashTelemetryChannel() {
        let payload = EMUFrameCodec.encode(SimulatorTelemetry())
        let channels = stride(from: 0, to: payload.count, by: 5).map { payload[$0] }

        XCTAssertEqual(payload.count, 16 * 5)
        XCTAssertEqual(channels, [1, 2, 3, 4, 5, 6, 12, 14, 19, 21, 22, 23, 24, 27, 28, 255])
    }

    func testControlStatusRoundTripsThroughLoopbackChannels() throws {
        let command = Data([0x08, 0x55, 0xA0, 0x27, 0x00, 0x00, 0x00, 0x24])
        let state = try XCTUnwrap(EMUFrameCodec.decodeControlStatus(command))

        XCTAssertEqual(state.switches, [true, false, true, false, false, false, false, false])
        XCTAssertEqual(state.rotaryValues, [2, 7, 0, 0, 0, 0, 0, 0])

        let loopback = EMUFrameCodec.encodeControlLoopback(state)
        XCTAssertEqual(loopback.count, 15)
        XCTAssertEqual(stride(from: 0, to: loopback.count, by: 5).map { loopback[$0] }, [254, 253, 252])
    }

    func testWarningScenariosCrossExpectedLimits() {
        XCTAssertGreaterThan(SimulationScenario.overboost.telemetry(elapsed: 2).boostBar, 1.5)
        XCTAssertGreaterThan(SimulationScenario.highTemperature.telemetry(elapsed: 2).coolantCelsius, 110)
        let lowOil = SimulationScenario.lowOilPressure.telemetry(elapsed: 2)
        XCTAssertGreaterThan(lowOil.rpm, 3_000)
        XCTAssertLessThan(lowOil.oilPressureBar, 1.5)
        XCTAssertLessThan(SimulationScenario.lowVoltage.telemetry(elapsed: 2).batteryVoltage, 11.5)
    }
}
