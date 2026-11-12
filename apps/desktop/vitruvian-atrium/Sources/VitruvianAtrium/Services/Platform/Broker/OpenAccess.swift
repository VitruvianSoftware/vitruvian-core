// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The `open` capability: hand a link to the person's default app for it.
@MainActor
package struct OpenAccess {
    package struct Backing {
        package var open: (URL) -> Bool

        package init(open: @escaping (URL) -> Bool) {
            self.open = open
        }

        @MainActor package static let live = Backing(open: { NSWorkspace.shared.open($0) })
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing

    /// Whether the system opened `url`.
    package func url(_ url: URL) -> Result<Bool, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(backing.open(url))
    }
}
