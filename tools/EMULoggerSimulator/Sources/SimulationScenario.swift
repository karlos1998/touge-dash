import Foundation

enum SimulationScenario: String, CaseIterable, Identifiable, Sendable {
    case idle
    case cruise
    case pull
    case performanceRun
    case warmup
    case overboost
    case highTemperature
    case lowOilPressure
    case lowVoltage
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: "Wolne obroty"
        case .cruise: "Spokojna jazda"
        case .pull: "Przyspieszenie"
        case .performanceRun: "Pomiar 0–100 / 100–200 / 200–250"
        case .warmup: "Rozgrzewanie"
        case .overboost: "Overboost"
        case .highTemperature: "Przegrzanie"
        case .lowOilPressure: "Niskie ciśnienie oleju"
        case .lowVoltage: "Niskie napięcie"
        case .manual: "Ręczne wartości"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "gauge.with.dots.needle.0percent"
        case .cruise: "car.fill"
        case .pull: "bolt.fill"
        case .performanceRun: "stopwatch.fill"
        case .warmup: "thermometer.medium"
        case .overboost: "gauge.with.dots.needle.100percent"
        case .highTemperature: "thermometer.high"
        case .lowOilPressure: "oilcan.fill"
        case .lowVoltage: "battery.25percent"
        case .manual: "slider.horizontal.3"
        }
    }

    var isWarning: Bool {
        [.overboost, .highTemperature, .lowOilPressure, .lowVoltage].contains(self)
    }

    func telemetry(elapsed: TimeInterval) -> SimulatorTelemetry {
        switch self {
        case .idle:
            var value = SimulatorTelemetry()
            value.rpm = 920 + sin(elapsed * 2.1) * 25
            value.boostBar = -0.55 + sin(elapsed * 0.7) * 0.02
            value.oilPressureBar = 2.15 + sin(elapsed) * 0.06
            return value

        case .cruise:
            var value = SimulatorTelemetry()
            value.rpm = 2_750 + sin(elapsed * 0.8) * 180
            value.speedKPH = 88 + sin(elapsed * 0.35) * 7
            value.boostBar = -0.2 + sin(elapsed * 0.9) * 0.08
            value.throttlePercent = 24 + sin(elapsed * 0.6) * 5
            value.oilPressureBar = 3.7 + sin(elapsed * 0.8) * 0.2
            value.injectorDutyPercent = 23
            return value

        case .pull:
            let phase = elapsed.truncatingRemainder(dividingBy: 12)
            let acceleration = min(1, max(0, phase / 8))
            let release = phase > 8 ? min(1, (phase - 8) / 4) : 0
            var value = SimulatorTelemetry()
            value.rpm = mix(2_400, 7_200, acceleration) - release * 4_200
            value.speedKPH = mix(48, 172, acceleration) - release * 42
            value.boostBar = mix(-0.15, 1.32, min(1, acceleration * 1.7)) - release * 1.65
            value.throttlePercent = phase < 8 ? 96 : mix(96, 3, release)
            value.afr = phase < 8 ? 11.7 : 14.7
            value.lambda = value.afr / 14.7
            value.oilPressureBar = 2.0 + value.rpm / 1_650
            value.injectorDutyPercent = min(92, 18 + acceleration * 70)
            value.ignitionDegrees = 16 - max(0, value.boostBar) * 6
            return value

        case .performanceRun:
            let phase = elapsed.truncatingRemainder(dividingBy: 19)
            let run = max(0, phase - 1.2)
            let speed: Double
            let shifting: Bool
            if run <= 4.0 {
                speed = mix(0, 100, run / 4.0); shifting = false
            } else if run <= 4.7 {
                speed = 100; shifting = true
            } else if run <= 9.7 {
                speed = mix(100, 200, (run - 4.7) / 5.0); shifting = false
            } else if run <= 10.4 {
                speed = 200; shifting = true
            } else if run <= 14.4 {
                speed = mix(200, 255, (run - 10.4) / 4.0); shifting = false
            } else {
                speed = max(0, 255 - (run - 14.4) * 85); shifting = false
            }
            var value = SimulatorTelemetry()
            value.speedKPH = speed
            value.throttlePercent = shifting || run > 14.4 ? 4 : run > 0 ? 96 : 0
            value.rpm = shifting ? 4_400 : 2_200 + speed * 24
            value.boostBar = value.throttlePercent > 50 ? min(1.35, speed / 120) : -0.45
            value.afr = value.throttlePercent > 50 ? 11.8 : 14.7
            value.lambda = value.afr / 14.7
            value.oilPressureBar = 1.7 + value.rpm / 1_800
            value.injectorDutyPercent = min(92, 14 + speed * 0.29)
            return value

        case .warmup:
            let progress = min(1, elapsed / 45)
            var value = SimulatorTelemetry()
            value.rpm = mix(1_350, 900, progress) + sin(elapsed) * 20
            value.coolantCelsius = mix(36, 91, progress)
            value.oilTemperatureCelsius = mix(28, 94, progress)
            value.oilPressureBar = mix(4.8, 2.1, progress)
            value.boostBar = -0.52
            return value

        case .overboost:
            var value = SimulationScenario.pull.telemetry(elapsed: min(7.5, elapsed.truncatingRemainder(dividingBy: 8)))
            value.rpm = 5_800 + sin(elapsed * 0.8) * 700
            value.boostBar = 1.82 + sin(elapsed * 1.6) * 0.08
            value.throttlePercent = 100
            value.afr = 11.8
            value.lambda = 0.8
            return value

        case .highTemperature:
            var value = SimulationScenario.cruise.telemetry(elapsed: elapsed)
            value.coolantCelsius = 114 + sin(elapsed * 0.4) * 2
            value.oilTemperatureCelsius = 126 + sin(elapsed * 0.25) * 2
            return value

        case .lowOilPressure:
            var value = SimulationScenario.cruise.telemetry(elapsed: elapsed)
            value.rpm = 4_600
            value.speedKPH = 110
            value.oilPressureBar = 0.75 + sin(elapsed) * 0.08
            return value

        case .lowVoltage:
            var value = SimulationScenario.idle.telemetry(elapsed: elapsed)
            value.rpm = 1_150
            value.batteryVoltage = 10.7 + sin(elapsed * 0.6) * 0.15
            return value

        case .manual:
            return SimulatorTelemetry()
        }
    }

    private func mix(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + (end - start) * progress
    }
}
