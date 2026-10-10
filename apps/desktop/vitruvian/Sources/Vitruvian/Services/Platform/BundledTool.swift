// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// A tool compiled into the app. It says what it is in `manifest`, is built
/// with the services that manifest allows, and reaches nothing else: no
/// singleton, no system service.
@MainActor
package protocol BundledTool: AnyObject {
    static var manifest: ToolManifest { get }
    init(services: ToolServices)
    /// Undo whatever the tool has running. Safe to call twice.
    func stop()
}
