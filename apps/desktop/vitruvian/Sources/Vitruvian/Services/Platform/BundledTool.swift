// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// A tool compiled into the app. It says what it is in `manifest`, is built
/// with the services that manifest allows, and reaches nothing else: no
/// singleton, no system service. It never asks whether it is installed or
/// switched on: the tool host does, and calls `start` and `stop`.
///
/// What the host calls on it once it is built is `HostedTool`.
@MainActor
package protocol BundledTool: HostedTool {
    static var manifest: ToolManifest { get }
    init(services: ToolServices)
}
