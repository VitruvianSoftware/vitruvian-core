// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// The `keystrokes` capability: paste text into the app in front, and press
/// one of its menu commands. It rides on Accessibility, so every operation
/// is refused until the person grants it.
@MainActor
package struct KeystrokesAccess {
    package struct Backing {
        /// Puts `text` on the clipboard, types Command-V and puts back what
        /// was there. `willPost` is called just before the key goes down
        /// and `didPost` once it is up; neither when the paste cannot start.
        package var paste: (_ text: String, _ willPost: @escaping () -> Void, _ didPost: @escaping () -> Void) -> Void
        /// Asks the person for Accessibility: the system prompt, and the
        /// app's guide to System Settings.
        package var requestGrant: () -> Void
        /// The front app and its menus.
        package var menu: FrontAppMenu.Environment

        package init(paste: @escaping (String, @escaping () -> Void, @escaping () -> Void) -> Void,
                     requestGrant: @escaping () -> Void, menu: FrontAppMenu.Environment) {
            self.paste = paste
            self.requestGrant = requestGrant
            self.menu = menu
        }

        /// The paste is `TransientPaste`, as it is: its delays are tuned by
        /// hand against real apps.
        @MainActor package static let live = Backing(
            paste: { text, willPost, didPost in
                _ = TransientPaste.shared.paste(text, willPostShortcut: willPost, didPostShortcut: didPost)
            },
            requestGrant: { Permissions.shared.requestAccessibility() },
            menu: .live)

        /// Types nothing and asks nobody. For tests of other capabilities.
        package static var inert: Backing {
            Backing(paste: { _, _, _ in }, requestGrant: {}, menu: .inert)
        }
    }

    let gate: () -> BrokerRefusal?
    let backing: Backing
    let menu: FrontAppMenu
    let hotkeys: HotkeyBindings
    let tool: ToolID

    /// Why the tool may not send keystrokes now, or nil when it may. A tool
    /// asks before it reads what it means to paste, so that without the
    /// grant nothing is read at all.
    package var refusal: BrokerRefusal? { gate() }

    /// Has the person asked for the grant this capability rides on: the
    /// system prompt, which macOS shows once, and the app's guide. Does
    /// nothing when the grant is held. Refused for a tool that did not
    /// declare the capability or is not installed.
    @discardableResult
    package func requestGrant() -> BrokerRefusal? {
        let refusal = gate()
        guard case .notGranted? = refusal else { return refusal }
        backing.requestGrant()
        return nil
    }

    /// Presses the first enabled item in the front app's menus that has one
    /// of these key equivalents. True when an item was pressed.
    package func pressFrontAppMenuItem(matching equivalents: [MenuKeyEquivalent]) -> Result<Bool, BrokerRefusal> {
        if let refusal = gate() { return .failure(refusal) }
        return .success(menu.pressItem(matching: equivalents))
    }

    /// Pastes `text` into the app in front and leaves the clipboard as it
    /// was. The paste types Command-V, so a key of the tool's own that is
    /// Command-V is let go just before it and taken again once it is
    /// typed: the paste never presses the tool's own shortcut.
    @discardableResult
    package func paste(_ text: String) -> BrokerRefusal? {
        if let refusal = gate() { return refusal }
        let hotkeys = self.hotkeys
        let tool = self.tool
        var released: [GlobalShortcutRole] = []
        backing.paste(text,
                      { released = hotkeys.release(of: tool, where: { $0.isStandardPasteCommand }) },
                      { hotkeys.retake(released, for: tool) })
        return nil
    }
}
