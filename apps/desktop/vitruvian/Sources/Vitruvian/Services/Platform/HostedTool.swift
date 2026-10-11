// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// What the tool host holds: something it can start, stop, run a command on
/// and ask which commands can run. There are two kinds. A tool compiled
/// into the app is a `BundledTool`. A tool that runs as its own program is
/// an `ExternalTool`. The host treats them alike.
@MainActor
package protocol HostedTool: AnyObject {
    /// Begin whatever the tool does in the background. The host calls it
    /// every time it finds the tool installed, switched on and holding its
    /// grants, so it must be safe to call twice.
    func start()
    /// Undo everything `start` did. Safe to call twice.
    func stop()
    /// Run one of the manifest's commands.
    func run(_ command: CommandID)
    /// Whether a command can run right now. Asked while a list is drawn,
    /// so it answers from what the tool already knows and never waits.
    func canRun(_ command: CommandID) -> Bool
    /// At quit, after `stop`: true once nothing of the tool is left
    /// running. A tool compiled into the app has nothing to leave.
    var hasEnded: Bool { get }
    /// At quit, for a tool that has not ended: end it, a step harder each
    /// time this is called.
    func escalate()
}

extension HostedTool {
    package var hasEnded: Bool { true }

    package func escalate() {}
}
