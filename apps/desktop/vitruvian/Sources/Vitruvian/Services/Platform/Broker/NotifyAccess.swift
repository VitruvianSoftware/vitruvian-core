// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The `notify` capability: tell the person something happened.
@MainActor
package struct NotifyAccess {
    package struct Backing {
        package var beep: () -> Void

        package init(beep: @escaping () -> Void) {
            self.beep = beep
        }

        @MainActor package static let live = Backing(beep: { NSSound.beep() })
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing

    /// The system alert sound.
    @discardableResult
    package func beep() -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        backing.beep()
        return nil
    }
}
