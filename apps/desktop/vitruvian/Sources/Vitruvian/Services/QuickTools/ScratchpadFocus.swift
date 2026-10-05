// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit

/// A window as the scratchpad's focus sees it. `NSWindow` is one.
@MainActor
package protocol ScratchpadFocusWindow: AnyObject {
    var isVisible: Bool { get }
    var isKeyWindow: Bool { get }
    func makeKey()
    func makeFirstResponder(_ responder: NSResponder?) -> Bool
}

extension NSWindow: ScratchpadFocusWindow {}

/// Where the scratchpad puts the keyboard. Document actions keep focus in
/// their host, so neither the floating pad nor the island's takes it from a
/// window that is not key.
@MainActor
package enum ScratchpadFocus {
    /// Gives `editor` the keyboard in `window`, with the caret at the end of
    /// its text, when `window` is key.
    package static func placeCaret(in editor: NSTextView, window: (any ScratchpadFocusWindow)?) {
        guard let window, window.isKeyWindow else { return }
        _ = window.makeFirstResponder(editor)
        let end = NSRange(location: (editor.string as NSString).length, length: 0)
        editor.setSelectedRange(end)
        editor.scrollRangeToVisible(end)
    }

    /// Brings the floating pad's visible `window` forward. Unless
    /// `requiresKeyWindow` is false, as for an explicit show, it does nothing
    /// while another window is key. The editor gets the caret `later`, read
    /// from `current` then, and only if the pad is still visible and key: a
    /// request queued before the person moved to another host is dropped.
    package static func bringForward(_ window: (any ScratchpadFocusWindow)?, requiresKeyWindow: Bool,
                                     later: (@escaping @MainActor () -> Void) -> Void,
                                     current: @escaping @MainActor ()
                                         -> (window: (any ScratchpadFocusWindow)?, editor: NSTextView?)) {
        guard let window, window.isVisible, !requiresKeyWindow || window.isKeyWindow else { return }
        window.makeKey()
        later {
            let (window, editor) = current()
            guard let window, window.isVisible, let editor else { return }
            placeCaret(in: editor, window: window)
        }
    }
}
