// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

package struct FanControlFanReading: Codable, Equatable, Identifiable, Sendable {
    package let index: Int
    package let actualRPM: Double
    package let minimumRPM: Double
    package let maximumRPM: Double
    package let targetRPM: Double
    package let isManuallyControlled: Bool

    package var id: Int { index }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(index: Int, actualRPM: Double, minimumRPM: Double, maximumRPM: Double, targetRPM: Double, isManuallyControlled: Bool) {
        self.index = index
        self.actualRPM = actualRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
        self.isManuallyControlled = isManuallyControlled
    }
}

package enum FanControlMode: String, Codable, Sendable {
    case system
    case manual
    case curve
}

package enum FanControlTemperatureSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case averageSoC
    case hottestSoC
    case averageCPU
    case hottestCPU
    case hottestGPU

    package var id: String { rawValue }
}

package struct FanControlTemperatureReading: Codable, Equatable, Sendable {
    package let source: FanControlTemperatureSource
    package let celsius: Double

    // Spelled out because a memberwise initializer never leaves its module.
    package init(source: FanControlTemperatureSource, celsius: Double) {
        self.source = source
        self.celsius = celsius
    }
}

package struct FanControlCurvePoint: Codable, Equatable, Sendable {
    package var temperature: Int
    package var coolingLevel: Int

    // Spelled out because a memberwise initializer never leaves its module.
    package init(temperature: Int, coolingLevel: Int) {
        self.temperature = temperature
        self.coolingLevel = coolingLevel
    }
}

package struct FanControlCurve: Codable, Equatable, Sendable {
    package var sensor: FanControlTemperatureSource
    package var points: [FanControlCurvePoint]

    // Spelled out because a memberwise initializer never leaves its module.
    package init(sensor: FanControlTemperatureSource, points: [FanControlCurvePoint]) {
        self.sensor = sensor
        self.points = points
    }
}

package struct FanControlConfiguration: Codable, Equatable, Sendable {
    package var mode: FanControlMode
    package var manualLevel: Int
    package var curves: [FanControlCurve]

    package static let defaultCurve = FanControlCurve(
        sensor: .hottestSoC,
        points: [
            FanControlCurvePoint(temperature: 50, coolingLevel: 0),
            FanControlCurvePoint(temperature: 70, coolingLevel: 100),
        ]
    )

    package static func manual(level: Int) -> FanControlConfiguration {
        FanControlConfiguration(mode: .manual, manualLevel: level,
                                curves: [])
    }

    package static func curve(_ curves: [FanControlCurve]) -> FanControlConfiguration {
        FanControlConfiguration(mode: .curve,
                                manualLevel: FanControlPolicy.defaultCoolingLevel,
                                curves: curves)
    }

    package static func encodeCurves(_ curves: [FanControlCurve]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(curves) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    package static func decodeCurves(_ value: String) -> [FanControlCurve]? {
        guard let data = value.data(using: .utf8),
              let curves = try? JSONDecoder().decode([FanControlCurve].self, from: data),
              FanControlPolicy.validCurves(curves) else { return nil }
        return curves
    }

    package static var defaultCurvesStorage: String {
        encodeCurves([defaultCurve]) ?? "[]"
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(mode: FanControlMode, manualLevel: Int, curves: [FanControlCurve]) {
        self.mode = mode
        self.manualLevel = manualLevel
        self.curves = curves
    }
}

package struct FanControlSnapshot: Codable, Equatable, Sendable {
    package var fans: [FanControlFanReading]
    package var isCooling: Bool
    package var endsAt: Date?
    package var stopReason: FanControlStopReason?
    package var coolingLevel: Int?
    package var configuration: FanControlConfiguration?
    package var temperatures: [FanControlTemperatureReading]?

    package static let empty = FanControlSnapshot(fans: [], isCooling: false,
                                          endsAt: nil, stopReason: nil,
                                          coolingLevel: nil,
                                          configuration: nil,
                                          temperatures: nil)

    // Spelled out because a memberwise initializer never leaves its module.
    package init(fans: [FanControlFanReading], isCooling: Bool, endsAt: Date? = nil, stopReason: FanControlStopReason? = nil, coolingLevel: Int? = nil, configuration: FanControlConfiguration? = nil, temperatures: [FanControlTemperatureReading]? = nil) {
        self.fans = fans
        self.isCooling = isCooling
        self.endsAt = endsAt
        self.stopReason = stopReason
        self.coolingLevel = coolingLevel
        self.configuration = configuration
        self.temperatures = temperatures
    }
}

package enum FanControlStopReason: String, Codable, Equatable, Sendable {
    case timeLimit
    case appDisconnected
    case heartbeatLost
    case hardwareChanged
    case thermalPressure
    case temperatureUnavailable
    case recovery
}

package enum FanControlErrorCode: String, Codable, Equatable, Error, Sendable {
    case noFans
    case unsupportedHardware
    case alreadyControlled
    case authorizationRequired
    case helperUnavailable
    case controlFailed
}

package struct FanControlResponse: Codable, Equatable, Sendable {
    package let succeeded: Bool
    package let snapshot: FanControlSnapshot
    package let error: FanControlErrorCode?

    package static func success(_ snapshot: FanControlSnapshot) -> FanControlResponse {
        FanControlResponse(succeeded: true, snapshot: snapshot, error: nil)
    }

    package static func failure(_ error: FanControlErrorCode,
                        snapshot: FanControlSnapshot = .empty) -> FanControlResponse {
        FanControlResponse(succeeded: false, snapshot: snapshot, error: error)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(succeeded: Bool, snapshot: FanControlSnapshot, error: FanControlErrorCode?) {
        self.succeeded = succeeded
        self.snapshot = snapshot
        self.error = error
    }
}

package enum FanControlPolicy {
    /// Retained only for the legacy XPC entry point used by older app builds.
    package static let coolingDuration: TimeInterval = 15 * 60
    package static let heartbeatLimit: TimeInterval = 7
    package static let verificationFailureLimit = 3
    package static let temperatureFailureLimit = 3
    package static let maximumFanCount = 8
    package static let maximumSaneRPM = 20_000.0
    package static let minimumCoolingLevel = 0
    package static let maximumCoolingLevel = 100
    package static let coolingLevelStep = 5
    package static let defaultCoolingLevel = maximumCoolingLevel
    package static let minimumCurveTemperature = 20
    package static let maximumCurveTemperature = 110
    package static let minimumCurvePointCount = 2
    package static let maximumCurvePointCount = 8
    package static let maximumCurveCount = FanControlTemperatureSource.allCases.count
    package static let curveHysteresis = 2.0

    package static func isAutomaticMode(_ mode: UInt8) -> Bool {
        mode == 0 || mode == 3
    }

    package static func fanCount(from value: Double) -> Int? {
        guard value.isFinite else { return nil }
        let rounded = value.rounded()
        guard abs(value - rounded) < 0.001 else { return nil }
        let count = Int(rounded)
        return (1...maximumFanCount).contains(count) ? count : nil
    }

    package static func validBounds(minimum: Double, maximum: Double) -> Bool {
        minimum.isFinite && maximum.isFinite
            && minimum >= 0 && maximum > minimum && maximum <= maximumSaneRPM
    }

    package static func validReading(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximumSaneRPM
    }

    package static func validCoolingLevel(_ level: Int) -> Bool {
        (minimumCoolingLevel...maximumCoolingLevel).contains(level)
            && level.isMultiple(of: coolingLevelStep)
    }

    package static func targetRPMMatches(target: Double, expected: Double) -> Bool {
        target.isFinite && expected.isFinite
            && abs(target - expected) <= max(2, expected * 0.001)
    }

    /// Not every Mac exposes `Ftst`. Where it is present the unlock write has to
    /// succeed; where it is absent there is nothing to force and nothing to fail.
    package static func forceTestSatisfied(keyExists: Bool, writeSucceeded: Bool) -> Bool {
        !keyExists || writeSucceeded
    }

    package static func coolingTargetRPM(minimum: Double, maximum: Double,
                                 level: Int) -> Double? {
        guard validBounds(minimum: minimum, maximum: maximum),
              validCoolingLevel(level) else { return nil }
        return minimum + (maximum - minimum) * Double(level) / 100
    }

    package static func validConfiguration(_ configuration: FanControlConfiguration) -> Bool {
        switch configuration.mode {
        case .system:
            return true
        case .manual:
            return validCoolingLevel(configuration.manualLevel)
        case .curve:
            return validCurves(configuration.curves)
        }
    }

    package static func validCurves(_ curves: [FanControlCurve]) -> Bool {
        guard (1...maximumCurveCount).contains(curves.count),
              Set(curves.map(\.sensor)).count == curves.count else { return false }
        return curves.allSatisfy(validCurve)
    }

    package static func validCurve(_ curve: FanControlCurve) -> Bool {
        guard (minimumCurvePointCount...maximumCurvePointCount).contains(curve.points.count) else {
            return false
        }
        for (index, point) in curve.points.enumerated() {
            guard (minimumCurveTemperature...maximumCurveTemperature).contains(point.temperature),
                  validCoolingLevel(point.coolingLevel) else { return false }
            if index > 0 {
                let previous = curve.points[index - 1]
                guard point.temperature > previous.temperature,
                      point.coolingLevel >= previous.coolingLevel else { return false }
            }
        }
        return true
    }

    package static func nextCurvePoint(for points: [FanControlCurvePoint]) -> FanControlCurvePoint? {
        guard points.count < maximumCurvePointCount,
              let first = points.first,
              let last = points.last else { return nil }
        var best: (index: Int, gap: Int)?
        for index in 1..<points.count {
            let gap = points[index].temperature - points[index - 1].temperature
            if gap > 1, gap > (best?.gap ?? 0) { best = (index, gap) }
        }
        if let best {
            let lower = points[best.index - 1]
            let upper = points[best.index]
            let temperature = lower.temperature + best.gap / 2
            let rawLevel = Double(lower.coolingLevel + upper.coolingLevel) / 2
            let level = Int((rawLevel / Double(coolingLevelStep)).rounded())
                * coolingLevelStep
            return FanControlCurvePoint(temperature: temperature, coolingLevel: level)
        }
        if last.temperature < maximumCurveTemperature {
            return FanControlCurvePoint(
                temperature: min(maximumCurveTemperature, last.temperature + 10),
                coolingLevel: last.coolingLevel
            )
        }
        if first.temperature > minimumCurveTemperature {
            return FanControlCurvePoint(
                temperature: max(minimumCurveTemperature, first.temperature - 10),
                coolingLevel: first.coolingLevel
            )
        }
        return nil
    }

    package static func addingCurvePoint(to points: [FanControlCurvePoint]) -> [FanControlCurvePoint]? {
        guard let point = nextCurvePoint(for: points) else { return nil }
        var updated = points
        updated.append(point)
        updated.sort { $0.temperature < $1.temperature }
        guard validCurve(FanControlCurve(sensor: .hottestSoC, points: updated)) else { return nil }
        return updated
    }

    package static func curveCoolingLevel(curves: [FanControlCurve],
                                  temperatures: [FanControlTemperatureReading],
                                  previousLevel: Int? = nil) -> Int? {
        guard let requested = evaluatedCurveCoolingLevel(curves: curves,
                                                         temperatures: temperatures) else { return nil }
        guard let previousLevel, requested < previousLevel else { return requested }
        let warmerReadings = temperatures.map {
            FanControlTemperatureReading(source: $0.source,
                                         celsius: $0.celsius + curveHysteresis)
        }
        guard let held = evaluatedCurveCoolingLevel(curves: curves,
                                                    temperatures: warmerReadings) else { return nil }
        return min(previousLevel, max(requested, held))
    }

    private static func evaluatedCurveCoolingLevel(curves: [FanControlCurve],
                                                   temperatures: [FanControlTemperatureReading]) -> Int? {
        guard validCurves(curves) else { return nil }
        let values = Dictionary(temperatures.map { ($0.source, $0.celsius) },
                                uniquingKeysWith: { _, newest in newest })
        var levels: [Int] = []
        for curve in curves {
            guard let temperature = values[curve.sensor], validTemperature(temperature) else {
                return nil
            }
            levels.append(interpolatedCoolingLevel(points: curve.points,
                                                   temperature: temperature))
        }
        return levels.max()
    }

    package static func interpolatedCoolingLevel(points: [FanControlCurvePoint],
                                         temperature: Double) -> Int {
        guard let first = points.first, let last = points.last else {
            return minimumCoolingLevel
        }
        if temperature <= Double(first.temperature) { return first.coolingLevel }
        if temperature >= Double(last.temperature) { return last.coolingLevel }
        for index in 1..<points.count {
            let upper = points[index]
            guard temperature <= Double(upper.temperature) else { continue }
            let lower = points[index - 1]
            let progress = (temperature - Double(lower.temperature))
                / Double(upper.temperature - lower.temperature)
            let raw = Double(lower.coolingLevel)
                + Double(upper.coolingLevel - lower.coolingLevel) * progress
            let stepped = Int(ceil(raw / Double(coolingLevelStep) - 1e-9))
                * coolingLevelStep
            return min(maximumCoolingLevel, max(minimumCoolingLevel, stepped))
        }
        return last.coolingLevel
    }

    package static func validTemperature(_ value: Double) -> Bool {
        value.isFinite && value >= 1 && value < 125
    }

    package static func aggregatedTemperatures(
        cpuReadings: [(key: String, value: Double)],
        gpuReadings: [Double],
        platform: CPUTemperaturePlatform
    ) -> [FanControlTemperatureReading] {
        let validCPU = cpuReadings.filter {
            $0.value >= TemperatureSensorSelector.minimumChipTemperature
                && validTemperature($0.value)
        }
        let preferredCPU = validCPU.filter {
            TemperatureSensorSelector.isCPUCoreKey($0.key, platform: platform)
        }
        let cpu: [Double]
        if TemperatureSensorSelector.hasCPUCoreSet(platform: platform) {
            cpu = preferredCPU.map(\.value)
        } else if platform == .generic {
            cpu = validCPU.map(\.value)
        } else {
            cpu = []
        }
        let gpu = gpuReadings.filter {
            $0 >= TemperatureSensorSelector.minimumChipTemperature && validTemperature($0)
        }
        let soc = cpu + gpu

        var readings: [FanControlTemperatureReading] = []
        if !soc.isEmpty {
            readings.append(.init(source: .averageSoC,
                                  celsius: soc.reduce(0, +) / Double(soc.count)))
            if let hottest = soc.max() {
                readings.append(.init(source: .hottestSoC, celsius: hottest))
            }
        }
        if !cpu.isEmpty {
            readings.append(.init(source: .averageCPU,
                                  celsius: cpu.reduce(0, +) / Double(cpu.count)))
            if let hottest = cpu.max() {
                readings.append(.init(source: .hottestCPU, celsius: hottest))
            }
        }
        if let hottest = gpu.max() {
            readings.append(.init(source: .hottestGPU, celsius: hottest))
        }
        return readings
    }

    package static func telemetryReadings(expectedCount: Int,
                                  readings: [Double?]) -> [Double]? {
        guard (1...maximumFanCount).contains(expectedCount),
              readings.count == expectedCount else { return nil }
        let values = readings.compactMap { $0 }
        guard values.count == expectedCount,
              values.allSatisfy(validReading) else { return nil }
        return values
    }

    package static func menuBarValue(for speeds: [Double]) -> String? {
        guard !speeds.isEmpty, speeds.allSatisfy(validReading) else { return nil }
        return speeds.map { String(Int($0.rounded())) }.joined(separator: "/")
    }

    package static func menuBarWidthUnits(fanCount: Int) -> Int {
        guard (1...maximumFanCount).contains(fanCount) else { return 0 }
        return 7 + fanCount * 5 + (fanCount - 1)
    }

    package static func restoreReason(now: Date,
                              endsAt: Date?,
                              heartbeatAge: TimeInterval,
                              verificationFailures: Int,
                              temperatureFailures: Int = 0,
                              thermalState: ProcessInfo.ThermalState) -> FanControlStopReason? {
        if let endsAt, now >= endsAt { return .timeLimit }
        if heartbeatAge > heartbeatLimit { return .heartbeatLost }
        if verificationFailures >= verificationFailureLimit { return .hardwareChanged }
        if temperatureFailures >= temperatureFailureLimit { return .temperatureUnavailable }
        if thermalState == .serious || thermalState == .critical {
            return .thermalPressure
        }
        return nil
    }
}

package enum SMCValueCodec {
    package static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Double(Float32(bitPattern: bits))
            return value.isFinite ? value : nil
        case "fpe2" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "sp78" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(UInt32(bytes[0]) << 24
                          | UInt32(bytes[1]) << 16
                          | UInt32(bytes[2]) << 8
                          | UInt32(bytes[3]))
        case "ioft" where bytes.count == 8:
            var raw: UInt64 = 0
            for (offset, byte) in bytes.enumerated() {
                raw |= UInt64(byte) << UInt64(offset * 8)
            }
            return Double(raw) / 65_536.0
        default:
            return nil
        }
    }

    package static func encode(_ value: Double, type: String, size: Int) -> [UInt8]? {
        guard value.isFinite, value >= 0 else { return nil }
        switch type {
        case "flt " where size == 4:
            let float = Float32(value)
            guard float.isFinite else { return nil }
            let bits = float.bitPattern
            return [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff),
                    UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
        case "fpe2" where size == 2:
            let scaled = (value * 4).rounded()
            guard scaled <= Double(UInt16.max) else { return nil }
            let raw = UInt16(scaled)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui8 " where size == 1:
            guard value.rounded() == value, value <= Double(UInt8.max) else { return nil }
            return [UInt8(value)]
        case "ui16" where size == 2:
            guard value.rounded() == value, value <= Double(UInt16.max) else { return nil }
            let raw = UInt16(value)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui32" where size == 4:
            guard value.rounded() == value, value <= Double(UInt32.max) else { return nil }
            let raw = UInt32(value)
            return [UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff),
                    UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        default:
            return nil
        }
    }
}
