// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore
import VitruvianDesign

/// What a screenshot surface does with a shared link outside itself: list
/// the live ones, copy one, revoke one, and say how it went. `live` is
/// `ScreenshotShareService`, the HUD and the system beep; tests pass doubles.
@MainActor
package struct ScreenshotLinkActions {
    package var records: () -> [ScreenshotShareRecord]
    package var copy: (URL) -> Bool
    /// Revokes the link on the sharing server.
    package var delete: @MainActor (ScreenshotShareRecord) async throws -> Void
    package var announce: (_ icon: String, _ message: String) -> Void
    package var beep: () -> Void

    // Spelled out because a memberwise initializer never leaves its module.
    package init(records: @escaping () -> [ScreenshotShareRecord], copy: @escaping (URL) -> Bool,
                 delete: @escaping @MainActor (ScreenshotShareRecord) async throws -> Void,
                 announce: @escaping (_ icon: String, _ message: String) -> Void,
                 beep: @escaping () -> Void) {
        self.records = records
        self.copy = copy
        self.delete = delete
        self.announce = announce
        self.beep = beep
    }

    package static var live: ScreenshotLinkActions {
        ScreenshotLinkActions(records: { ScreenshotShareService.shared.records },
                              copy: { ScreenshotShareService.shared.copy($0) },
                              delete: { try await ScreenshotShareService.shared.delete($0) },
                              announce: { QuickToolHUD.show(icon: $0, message: $1) },
                              beep: { NSSound.beep() })
    }

    /// Revokes, in the background, a link nobody is going to receive.
    package func revoke(_ record: ScreenshotShareRecord) {
        let delete = delete
        Task { @MainActor in try? await delete(record) }
    }
}
