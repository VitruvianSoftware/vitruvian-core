// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore

/// AppKit owns first-responder timing inside a menu-bar popover. SwiftUI can
/// request focus before its backing field has joined the popover window; this
/// hook waits for that attachment and lets the representable retry then.
package final class MixerPercentNativeTextField: NSTextField {
    package var didAttachToWindow: (() -> Void)?

    package override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { didAttachToWindow?() }
    }

    @discardableResult
    package func focusAndSelectAll() -> Bool {
        guard let window else { return false }
        window.makeKey()
        guard window.makeFirstResponder(self) else { return false }
        selectText(nil)
        return true
    }
}
