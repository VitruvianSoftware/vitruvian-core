// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// Every yield goes through here. `yieldActivation(to:)` only hands over
/// activation this app holds, and Vitruvian (`LSUIElement`, non-activating
/// panels) usually holds none when a switch commits, so the yield gave away
/// nothing and the cooperative `activate(from:)` after it was refused.
/// Self-activating first gives the yield something to hand over.
package enum ActivationHandoff {
    /// Our own activation notification arrives within a turn of the request.
    /// Past that, an activation of Vitruvian is the user opening one of its
    /// windows, which is a real use and stays in the switcher's history.
    private static let selfActivationWindow: CFTimeInterval = 1

    // Main thread only, like the NSApp calls below.
    nonisolated(unsafe) private static var lastSelfActivation: CFAbsoluteTime = 0

    /// Whether the activation of Vitruvian being reported right now is the one
    /// `yield(to:)` asked for on its way out. Main thread, like every `NSApp`
    /// call here and like the activation notifications that read it.
    package static var isHandingOff: Bool {
        CFAbsoluteTimeGetCurrent() - lastSelfActivation < selfActivationWindow
    }

    /// Whether an activation of `pid` reported now is this app's own
    /// self-activation on its way out of a hand-off. Only that one is no use
    /// of the app: the Dock icon, Settings and Vitruvian's own windows are.
    package static func isHandoffActivation(of pid: pid_t) -> Bool {
        pid == ProcessInfo.processInfo.processIdentifier && isHandingOff
    }

    package static func yield(to app: NSRunningApplication) {
        // Every caller hands off from the main thread.
        MainActor.assumeIsolated {
            handOff(to: app,
                    activateSelf: { NSApp.activate(ignoringOtherApps: true) },
                    yieldTo: { NSApp.yieldActivation(to: $0) })
        }
    }

    /// The hand-off with its two system calls passed in. The stamp comes
    /// first, so the activation notification the self-activation sends is
    /// already known as this app's own; then the self-activation, which gives
    /// the yield after it something to hand over.
    @MainActor
    package static func handOff(to app: NSRunningApplication,
                                activateSelf: () -> Void,
                                yieldTo: (NSRunningApplication) -> Void) {
        lastSelfActivation = CFAbsoluteTimeGetCurrent()
        activateSelf()
        yieldTo(app)
    }
}
