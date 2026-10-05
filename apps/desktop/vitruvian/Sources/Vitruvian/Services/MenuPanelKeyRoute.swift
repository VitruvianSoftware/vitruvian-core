// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import VitruvianCore

/// A key as the menu bar panel's monitor reads it. `NSEvent` is one, with
/// the `targetWindow` the island's route also reads; tests pass their own.
@MainActor
package protocol MenuPanelKeyEvent {
    var targetWindow: AnyObject? { get }
    var keyCode: UInt16 { get }
    var modifierFlags: NSEvent.ModifierFlags { get }
}

extension NSEvent: MenuPanelKeyEvent {}

/// The menu bar panel's keys, as its local key monitor sees them: Escape
/// closes it, and while a view holds it open, Space and Return reach that
/// view. `AppDelegate` passes the panel; tests pass doubles.
@MainActor
package struct MenuPanelKeyRoute<Event: MenuPanelKeyEvent> {
    /// What the route reads from the panel and asks of it.
    @MainActor
    package struct Panel {
        package var isShown: () -> Bool
        /// The popover's own window, while it has one.
        package var window: () -> AnyObject?
        /// An input method is composing in the panel's first responder.
        package var isComposing: () -> Bool
        /// A view in the panel holds it open (`PanelInteractionState`).
        package var viewKeepsOpen: () -> Bool
        /// A text control in the panel has the keyboard.
        package var isEditingText: () -> Bool
        /// The panel's window is the app's key window.
        package var isKey: () -> Bool
        package var close: () -> Void
        /// Hands a key to the panel's first responder.
        package var deliver: (Event) -> Void

        package init(isShown: @escaping () -> Bool, window: @escaping () -> AnyObject?,
                     isComposing: @escaping () -> Bool, viewKeepsOpen: @escaping () -> Bool,
                     isEditingText: @escaping () -> Bool, isKey: @escaping () -> Bool,
                     close: @escaping () -> Void, deliver: @escaping (Event) -> Void) {
            self.isShown = isShown
            self.window = window
            self.isComposing = isComposing
            self.viewKeepsOpen = viewKeepsOpen
            self.isEditingText = isEditingText
            self.isKey = isKey
            self.close = close
            self.deliver = deliver
        }
    }

    package let panel: Panel

    package init(panel: Panel) {
        self.panel = panel
    }

    /// Whether the panel takes `event`, after acting on it. A key it does
    /// not take goes on to the app.
    package func handle(_ event: Event) -> Bool {
        if panel.isShown(), event.keyCode == UInt16(kVK_Escape) {
            // The monitor sees the whole app; Esc in another window, such as
            // Settings or a popover or dialog opened from the panel, stays there.
            guard let window = panel.window(), event.targetWindow === window else { return false }
            // While an input method is composing, Esc belongs to it and
            // drops the candidate; the panel closes on the next one.
            if panel.isComposing() { return false }
            panel.close()
            return true
        }

        guard panel.isShown(), panel.viewKeepsOpen(), Self.isPlainHoldKey(event),
              let window = panel.window() else { return false }

        // Text controls inside the popover, especially the Homebrew search
        // field, need Space/Return delivered through AppKit's normal field
        // editor path so delegates and target/actions can submit correctly.
        if panel.isEditingText() { return false }

        if panel.isKey() || event.targetWindow === window {
            panel.deliver(event)
            return true
        }
        return false
    }

    /// Space, Return or Enter, without Command, Control or Option.
    package static func isPlainHoldKey(_ event: Event) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
        return event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76
    }
}
