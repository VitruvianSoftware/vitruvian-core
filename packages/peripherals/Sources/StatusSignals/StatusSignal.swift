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

import CompXProtocol

/// What a notification source wants to say. Deliberately small: a new state
/// is one case here plus one row in `StatusPresets`.
public enum StatusSignal: String, CaseIterable, Sendable {
    /// Turn the light off.
    case off
    /// Something is in flight. Blue, breathing.
    case working
    /// It passed. Solid green.
    case success
    /// It failed. Red, breathing faster and brighter.
    case failure
    /// Waiting / degraded. Solid amber.
    case warning
    /// A human is needed. Magenta, breathing.
    case attention
}

/// The look of each signal. Same colour code as the diagrams: green passed,
/// red failed, blue in flight, amber waiting.
public enum StatusPresets {
    public static func lighting(for signal: StatusSignal) -> LightingConfig {
        switch signal {
        case .off:
            return LightingConfig(mode: .off, color: .black, speed: .zero, brightness: .zero)
        case .working:
            return LightingConfig(mode: .breathe, color: RGB(r: 0x00, g: 0x00, b: 0xFF), speed: .five, brightness: .seven)
        case .success:
            return LightingConfig(mode: .fixed, color: RGB(r: 0x00, g: 0xFF, b: 0x00), speed: .five, brightness: .seven)
        case .failure:
            return LightingConfig(mode: .breathe, color: RGB(r: 0xFF, g: 0x00, b: 0x00), speed: .seven, brightness: .nine)
        case .warning:
            return LightingConfig(mode: .fixed, color: RGB(r: 0xFF, g: 0x80, b: 0x00), speed: .five, brightness: .seven)
        case .attention:
            return LightingConfig(mode: .breathe, color: RGB(r: 0xFF, g: 0x00, b: 0xFF), speed: .five, brightness: .seven)
        }
    }

    /// The signal whose preset this config is, if any.
    public static func signal(showing config: LightingConfig) -> StatusSignal? {
        StatusSignal.allCases.first { lighting(for: $0) == config }
    }

    public static func isPreset(_ config: LightingConfig) -> Bool {
        signal(showing: config) != nil
    }
}
