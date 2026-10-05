// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// Quitting while the command bar has borrowed a keyboard layout puts the
/// person's own layout back first. `AppDelegate` asks it what to answer
/// AppKit; tests pass a borrowing over doubles.
@MainActor
package final class CommandBarTermination {
    private let hasBorrowed: @MainActor () -> Bool
    private let restore: @MainActor () -> Void
    /// A restoration is queued and its reply not yet sent.
    package private(set) var restorationPending = false

    package init(hasBorrowed: @escaping @MainActor () -> Bool, restore: @escaping @MainActor () -> Void) {
        self.hasBorrowed = hasBorrowed
        self.restore = restore
    }

    /// The answer to AppKit's quit request. On `.terminateLater`, `reply`
    /// runs once, on a later turn of the main run loop, after the
    /// restoration; a repeated request waits for that same reply.
    package func shouldTerminate(reply: @escaping @MainActor (Bool) -> Void) -> NSApplication.TerminateReply {
        if restorationPending { return .terminateLater }
        guard hasBorrowed() else { return .terminateNow }
        restorationPending = true
        let restore = restore
        // Terminate-later runs a modal loop, which may be nested inside a
        // main-queue callback. Schedule in both modes before approving quit.
        RunLoop.main.perform(inModes: [.default, .modalPanel]) { [weak self] in
            // Performed on the main run loop.
            MainActor.assumeIsolated {
                restore()
                self?.restorationPending = false
                reply(true)
            }
        }
        return .terminateLater
    }
}
