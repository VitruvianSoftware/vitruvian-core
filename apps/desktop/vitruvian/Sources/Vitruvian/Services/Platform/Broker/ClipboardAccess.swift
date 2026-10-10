// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The clipboard capabilities. Stage A offers writing text; reading and
/// rewriting arrive with the first tool that needs them.
@MainActor
package struct ClipboardAccess {
    package struct Backing {
        /// Replace the clipboard with `text`, then say on the main thread
        /// whether it took.
        package var write: (_ text: String, _ completion: @escaping @MainActor (Bool) -> Void) -> Void

        package init(write: @escaping (String, @escaping @MainActor (Bool) -> Void) -> Void) {
            self.write = write
        }

        @MainActor package static let live = Backing(write: { text, completion in
            GeneralPasteboardAccess.shared.async({
                NSPasteboard.general.clearContents()
                NSPasteboard.general.declareVitruvianSource()
                return NSPasteboard.general.setString(text, forType: .string)
            }, then: { copied in
                completion(copied)
            })
        })
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing

    /// Replaces the clipboard with `text`. `completion` hears whether it
    /// took; it is not called when the call is refused.
    @discardableResult
    package func write(_ text: String, completion: @escaping @MainActor (Bool) -> Void = { _ in }) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        backing.write(text, completion)
        return nil
    }
}
