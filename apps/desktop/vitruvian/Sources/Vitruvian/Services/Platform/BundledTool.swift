// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// A tool compiled into the app. It says what it is in `manifest`, is built
/// with the services that manifest allows, and reaches nothing else: no
/// singleton, no system service. It never asks whether it is installed or
/// switched on: the tool host does, and calls `start` and `stop`.
@MainActor
package protocol BundledTool: AnyObject {
    static var manifest: ToolManifest { get }
    init(services: ToolServices)
    /// Begin whatever the tool does in the background. The host calls it
    /// every time it finds the tool installed, switched on and holding its
    /// grants, so it must be safe to call twice.
    func start()
    /// Undo everything `start` did. Safe to call twice.
    func stop()
    /// Run one of the manifest's commands.
    func run(_ command: CommandID)
    /// Whether a command can run right now.
    func canRun(_ command: CommandID) -> Bool
}
