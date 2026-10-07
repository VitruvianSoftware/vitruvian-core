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

import CompXHID
import CompXProtocol

/// What `restore()` did.
public enum RestoreResult: Equatable, Sendable {
    /// The baseline was written back to the device.
    case restored(LightingConfig)
    /// No baseline has ever been saved, so there was nothing to put back.
    case noBaseline
    /// Something else changed the light since this signal; it was left alone.
    case skipped(current: LightingConfig)
}

/// Anything that can show a status and then put things back.
public protocol StatusIndicator {
    func signal(_ signal: StatusSignal) throws
    @discardableResult func restore() throws -> RestoreResult
}

/// Turns a GravaStar mouse into a status light.
///
/// Before showing a signal it reads the current lighting. If that is not one
/// of the presets, it is the user's own look and is saved as the baseline.
/// `restore()` writes the baseline back and keeps the file, so a second
/// restore is harmless.
public final class MouseStatusIndicator: StatusIndicator {
    public let mouse: GravaStarMouse
    public let store: BaselineStore

    public init(mouse: GravaStarMouse, store: BaselineStore = BaselineStore()) {
        self.mouse = mouse
        self.store = store
    }

    /// Whether a mouse is attached. Not having one is normal (laptop
    /// undocked); notification sources should treat it as a quiet no-op.
    public static var isAvailable: Bool { GravaStarMouse.isConnected() }

    public func signal(_ signal: StatusSignal) throws {
        let current = try mouse.readLighting()
        if !StatusPresets.isPreset(current) {
            try store.save(current)
        }
        try mouse.writeLighting(StatusPresets.lighting(for: signal))
    }

    @discardableResult
    public func restore() throws -> RestoreResult {
        guard let baseline = try store.load() else { return .noBaseline }
        try mouse.writeLighting(baseline)
        return .restored(baseline)
    }

    /// Restores only if the light still shows `signal`. Used by
    /// `--restore-after`, so a timer from an older signal never wipes out a
    /// newer one (or a change the user made by hand).
    @discardableResult
    public func restore(ifShowing signal: StatusSignal) throws -> RestoreResult {
        let current = try mouse.readLighting()
        guard current == StatusPresets.lighting(for: signal) else { return .skipped(current: current) }
        return try restore()
    }
}
