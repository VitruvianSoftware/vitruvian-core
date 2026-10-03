// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Detection and settings gate for Liquid Glass visuals on macOS 26 and later.
package enum LiquidGlassSupport {
    /// Whether the host operating system supports native Liquid Glass.
    package static var isSupported: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    /// Select the preference for the surface that owns the mixer.
    package static func isEnabled(inNotch: Bool, windows: Bool, island: Bool) -> Bool {
        guard isSupported else { return false }
        return inNotch ? island : windows
    }
}
