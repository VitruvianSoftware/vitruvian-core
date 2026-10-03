// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

package struct WindowActivationRetention {
    package private(set) var count = 0

    package mutating func retain() -> Bool {
        count += 1
        return count == 1
    }

    package mutating func release() -> Bool {
        guard count > 0 else { return false }
        count -= 1
        return count == 0
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(count: Int = 0) {
        self.count = count
    }
}

/// The app is normally accessory only, with no Dock icon and no place in
/// Command Tab. While a user-facing window needs to remain reachable it becomes
/// a regular app, then returns to its normal policy after the last one closes.
package enum WindowActivationPolicy {
    private static var retention = WindowActivationRetention()
    private static var promoted = false

    package static func retain() {
        _ = retention.retain()
        guard !promoted, NSApp.activationPolicy() != .regular else { return }
        promoted = NSApp.setActivationPolicy(.regular)
    }

    package static func release() {
        guard retention.release(), promoted else { return }
        if NSApp.setActivationPolicy(.accessory) {
            promoted = false
        }
    }
}
