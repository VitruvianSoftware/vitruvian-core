// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The features that have become tools. The host starts, stops and runs
/// only what is listed here; a migration adds one line.
@MainActor
package enum BundledTools {
    package static let all: [any BundledTool.Type] = [PortManagerService.self, URLCleanerService.self]
}
