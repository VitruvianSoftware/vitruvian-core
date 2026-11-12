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

/// One window's hold on the shared activation lifetime. Showing the window
/// takes the hold once, however often it is shown again while it is open,
/// and closing it gives the hold back once, so a window keeps the app in
/// Command Tab exactly while it is visible and never past its close.
@MainActor
package struct WindowActivationClaim {
    package private(set) var isHeld = false
    private let retain: @MainActor () -> Void
    private let release: @MainActor () -> Void

    /// Takes and gives back the shared policy's hold; a test counts instead.
    package init(retain: @escaping @MainActor () -> Void = { WindowActivationPolicy.retain() },
                 release: @escaping @MainActor () -> Void = { WindowActivationPolicy.release() }) {
        self.retain = retain
        self.release = release
    }

    /// The window was shown: the first showing takes the hold.
    package mutating func windowShown() {
        guard !isHeld else { return }
        isHeld = true
        retain()
    }

    /// The window closed: gives back a hold it took, and nothing otherwise.
    package mutating func windowClosed() {
        guard isHeld else { return }
        isHeld = false
        release()
    }
}

/// The app is normally accessory only, with no Dock icon and no place in
/// Command Tab. While a user-facing window needs to remain reachable it becomes
/// a regular app, then returns to its normal policy after the last one closes.
@MainActor
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
