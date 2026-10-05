// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The menu bar panel's key route runs against plain doubles. No popover is
/// shown, no monitor is installed and no key is posted.
enum MenuPanelKeyTests {
    final class Window {}

    struct Event: MenuPanelKeyEvent {
        var keyCode: UInt16
        var targetWindow: AnyObject?
        var modifierFlags: NSEvent.ModifierFlags = []
    }

    /// The panel as the route sees it, recording what it was asked to do.
    final class Panel {
        let window = Window()
        var isShown = true
        var composing = false
        var viewKeepsOpen = false
        var editingText = false
        var isKey = false
        var closes = 0
        var delivered: [UInt16] = []

        var route: MenuPanelKeyRoute<Event> {
            MenuPanelKeyRoute(panel: .init(
                isShown: { [unowned self] in self.isShown },
                window: { [unowned self] in self.window },
                isComposing: { [unowned self] in self.composing },
                viewKeepsOpen: { [unowned self] in self.viewKeepsOpen },
                isEditingText: { [unowned self] in self.editingText },
                isKey: { [unowned self] in self.isKey },
                close: { [unowned self] in
                    self.closes += 1
                    self.isShown = false
                },
                deliver: { [unowned self] in self.delivered.append($0.keyCode) }))
        }
    }

    static func run(_ suite: TestSuite) {
        escape(suite)
        holdKeys(suite)
    }

    private static func escape(_ suite: TestSuite) {
        let escape = UInt16(kVK_Escape)
        func panelKeepsEscape(from window: AnyObject?) -> Bool {
            let panel = Panel()
            return !panel.route.handle(Event(keyCode: escape, targetWindow: window))
                && panel.isShown && panel.closes == 0
        }
        suite.expect(panelKeepsEscape(from: Window()),
                     "Esc in Settings beside the open panel stays there, for its search field or sheet")
        suite.expect(panelKeepsEscape(from: nil), "Esc with no key window leaves the panel open")

        let panel = Panel()
        panel.composing = true
        suite.expect(!panel.route.handle(Event(keyCode: escape, targetWindow: panel.window))
                     && panel.isShown && panel.closes == 0,
                     "a composing input method keeps Esc in a panel field such as the Homebrew search")
        panel.composing = false
        suite.expect(panel.route.handle(Event(keyCode: escape, targetWindow: panel.window))
                     && !panel.isShown && panel.closes == 1,
                     "Esc closes the panel once composition ends")
        suite.expect(!panel.route.handle(Event(keyCode: escape, targetWindow: panel.window)) && panel.closes == 1,
                     "Esc with the panel already closed goes on to the app")
    }

    /// While a view holds the panel open, Space and Return reach it even
    /// when the panel is not key.
    private static func holdKeys(_ suite: TestSuite) {
        let space: UInt16 = 49, returnKey: UInt16 = 36, enter: UInt16 = 76
        let panel = Panel()
        suite.expect(!panel.route.handle(Event(keyCode: space, targetWindow: panel.window))
                     && panel.delivered.isEmpty,
                     "Space goes its usual way while no view holds the panel open")
        panel.viewKeepsOpen = true
        for key in [space, returnKey, enter] {
            panel.delivered = []
            suite.expect(panel.route.handle(Event(keyCode: key, targetWindow: panel.window))
                         && panel.delivered == [key],
                         "a view holding the panel open gets Space, Return and Enter (\(key))")
        }
        panel.delivered = []
        suite.expect(!panel.route.handle(Event(keyCode: 0, targetWindow: panel.window)) && panel.delivered.isEmpty,
                     "other keys go their usual way")
        for modifier in [NSEvent.ModifierFlags.command, .control, .option] {
            suite.expect(!panel.route.handle(Event(keyCode: space, targetWindow: panel.window,
                                                   modifierFlags: modifier))
                         && panel.delivered.isEmpty,
                         "a held key with Command, Control or Option is a shortcut, not the view's")
        }
        suite.expect(panel.route.handle(Event(keyCode: space, targetWindow: panel.window, modifierFlags: .shift))
                     && panel.delivered == [space],
                     "Shift-Space still reaches the view")
        panel.delivered = []
        suite.expect(!panel.route.handle(Event(keyCode: space, targetWindow: Window())) && panel.delivered.isEmpty,
                     "a held key for another window stays there while the panel is not key")
        panel.isKey = true
        suite.expect(panel.route.handle(Event(keyCode: space, targetWindow: nil)) && panel.delivered == [space],
                     "a key panel gets the held key whatever window AppKit names")
        panel.delivered = []
        panel.editingText = true
        suite.expect(!panel.route.handle(Event(keyCode: returnKey, targetWindow: panel.window))
                     && panel.delivered.isEmpty,
                     "a text field in the panel submits through AppKit's own field editor")
        panel.editingText = false
        panel.isShown = false
        suite.expect(!panel.route.handle(Event(keyCode: space, targetWindow: panel.window)) && panel.delivered.isEmpty,
                     "a closed panel takes no held key")
    }
}
