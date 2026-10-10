// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The `notify` capability: tell the person something happened.
@MainActor
package struct NotifyAccess {
    package struct Backing {
        package var beep: () -> Void
        package var hud: (_ icon: String, _ message: String) -> Void

        package init(beep: @escaping () -> Void, hud: @escaping (String, String) -> Void = { _, _ in }) {
            self.beep = beep
            self.hud = hud
        }

        @MainActor package static let live = Backing(beep: { NSSound.beep() },
                                                    hud: { QuickToolHUD.show(icon: $0, message: $1) })
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

    /// A short message with a symbol beside it, in the app's own heads-up
    /// panel.
    @discardableResult
    package func hud(icon: String, message: String) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        backing.hud(icon, message)
        return nil
    }
}
