// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// The LED animation. Raw values are the device's mode byte.
public enum LightingMode: UInt8, CaseIterable, Sendable, CustomStringConvertible {
    case off = 0
    case rainbow = 1
    case breathe = 2
    case fixed = 3
    case neon = 4
    case rainbowBreathe = 5
    case fixedRainbow = 6

    /// Accepts the canonical names plus the prototype's aliases
    /// (`breath`, `single-breath`, `static`, `rainbow-breath`, ...).
    public init?(name: String) {
        switch name.lowercased() {
        case "off": self = .off
        case "rainbow": self = .rainbow
        case "breathe", "breath", "single-breath", "single-breathe": self = .breathe
        case "fixed", "static": self = .fixed
        case "neon": self = .neon
        case "rainbow-breathe", "rainbow-breath", "rainbowbreathe": self = .rainbowBreathe
        case "fixed-rainbow", "fixedrainbow": self = .fixedRainbow
        default: return nil
        }
    }

    /// The machine name used on the command line and in JSON.
    public var name: String {
        switch self {
        case .off: return "off"
        case .rainbow: return "rainbow"
        case .breathe: return "breathe"
        case .fixed: return "fixed"
        case .neon: return "neon"
        case .rainbowBreathe: return "rainbow-breathe"
        case .fixedRainbow: return "fixed-rainbow"
        }
    }

    /// The human name the vendor tool shows.
    public var description: String {
        switch self {
        case .off: return "Off"
        case .rainbow: return "Rainbow"
        case .breathe: return "Single Color Breath"
        case .fixed: return "Fixed Color"
        case .neon: return "Neon"
        case .rainbowBreathe: return "Rainbow Breath"
        case .fixedRainbow: return "Fixed Rainbow"
        }
    }
}

/// An LED colour.
public struct RGB: Equatable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// The ten names the prototype knows.
    public static let named: [String: RGB] = [
        "red": RGB(r: 255, g: 0, b: 0),
        "green": RGB(r: 0, g: 255, b: 0),
        "blue": RGB(r: 0, g: 0, b: 255),
        "cyan": RGB(r: 0, g: 255, b: 255),
        "magenta": RGB(r: 255, g: 0, b: 255),
        "purple": RGB(r: 128, g: 0, b: 128),
        "yellow": RGB(r: 255, g: 255, b: 0),
        "orange": RGB(r: 255, g: 128, b: 0),
        "white": RGB(r: 255, g: 255, b: 255),
        "pink": RGB(r: 255, g: 105, b: 180),
    ]

    public static let black = RGB(r: 0, g: 0, b: 0)

    /// `#00ffcc` or `00FFCC`. Exactly six hex digits.
    public init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespaces))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else { return nil }
        self.init(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF))
    }

    public init?(name: String) {
        guard let rgb = RGB.named[name.lowercased().trimmingCharacters(in: .whitespaces)] else { return nil }
        self = rgb
    }

    /// A named colour or a hex string.
    public init?(_ text: String) {
        if let named = RGB(name: text) {
            self = named
        } else if let hex = RGB(hex: text) {
            self = hex
        } else {
            return nil
        }
    }

    /// Lower-case `#rrggbb`.
    public var hexString: String {
        String(format: "#%02x%02x%02x", r, g, b)
    }
}

/// A speed or brightness step. The device accepts 0 through 9.
public struct Level: Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public static let range: ClosedRange<UInt8> = 0...9

    public let value: UInt8

    public init?(_ value: Int) {
        guard value >= 0, value <= Int(Level.range.upperBound) else { return nil }
        self.value = UInt8(value)
    }

    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.value < rhs.value }
    public var description: String { String(value) }

    // Literal shorthands for presets and defaults, so call sites need no `!`.
    public static let zero = Level(0)!
    public static let five = Level(5)!
    public static let seven = Level(7)!
    public static let nine = Level(9)!
}

/// The mouse's whole lighting state: the 7-byte record at flash `0x00A0`.
public struct LightingConfig: Equatable, Hashable, Sendable {
    public static let recordLength = 7

    public var mode: LightingMode
    public var color: RGB
    public var speed: Level
    public var brightness: Level

    public init(mode: LightingMode, color: RGB, speed: Level, brightness: Level) {
        self.mode = mode
        self.color = color
        self.speed = speed
        self.brightness = brightness
    }

    /// `[mode, r, g, b, speed, brightness, crc]`, `crc = (0x55 - Σ first 6) mod 256`.
    public func encodeRecord() -> [UInt8] {
        let body = [mode.rawValue, color.r, color.g, color.b, speed.value, brightness.value]
        return body + [Checksum.inner(body)]
    }

    /// Decodes the record. With 7+ bytes the record checksum is verified;
    /// with exactly 6 it is not (there is nothing to check).
    public static func decode<C: Collection>(record: C) throws -> LightingConfig where C.Element == UInt8 {
        let bytes = Array(record)
        guard bytes.count >= 6 else {
            throw CompXError.malformedResponse("lighting record is \(bytes.count) bytes, need 6")
        }
        if bytes.count >= recordLength, Checksum.inner(bytes[0..<6]) != bytes[6] {
            throw CompXError.badCRC
        }
        guard let mode = LightingMode(rawValue: bytes[0]) else {
            throw CompXError.malformedResponse("unknown lighting mode \(bytes[0])")
        }
        guard let speed = Level(Int(bytes[4])), let brightness = Level(Int(bytes[5])) else {
            throw CompXError.malformedResponse("speed \(bytes[4]) / brightness \(bytes[5]) outside 0-9")
        }
        return LightingConfig(
            mode: mode, color: RGB(r: bytes[1], g: bytes[2], b: bytes[3]),
            speed: speed, brightness: brightness
        )
    }
}

extension LightingConfig: Codable {
    private enum CodingKeys: String, CodingKey { case mode, color, speed, brightness }

    /// `{"mode":"fixed","color":"#00ffff","speed":5,"brightness":7}`.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode.name, forKey: .mode)
        try c.encode(color.hexString, forKey: .color)
        try c.encode(Int(speed.value), forKey: .speed)
        try c.encode(Int(brightness.value), forKey: .brightness)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let modeName = try c.decode(String.self, forKey: .mode)
        let hex = try c.decode(String.self, forKey: .color)
        guard let mode = LightingMode(name: modeName) else {
            throw DecodingError.dataCorruptedError(forKey: .mode, in: c, debugDescription: "unknown mode \(modeName)")
        }
        guard let color = RGB(hex: hex) else {
            throw DecodingError.dataCorruptedError(forKey: .color, in: c, debugDescription: "bad colour \(hex)")
        }
        guard let speed = Level(try c.decode(Int.self, forKey: .speed)),
              let brightness = Level(try c.decode(Int.self, forKey: .brightness))
        else {
            throw DecodingError.dataCorruptedError(forKey: .speed, in: c, debugDescription: "level outside 0-9")
        }
        self.init(mode: mode, color: color, speed: speed, brightness: brightness)
    }
}
