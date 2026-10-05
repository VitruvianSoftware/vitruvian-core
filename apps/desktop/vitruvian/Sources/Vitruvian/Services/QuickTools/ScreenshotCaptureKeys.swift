// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import Carbon.HIToolbox
import VitruvianCore

/// What a key press does to a capture preview, decided from the press and
/// the preview's place. The preview's key monitor reads the event and acts.
package enum ScreenshotPreviewKeys {
    package enum Command: Equatable {
        case close
        case perform(ScreenshotQuickPreviewController.Action)
    }

    /// Whether the preview owns the keyboard at all: it is open and showing,
    /// the press is in its own window, nothing in front of it takes the keys
    /// (a sheet, a text field, a shortcut being recorded) and, inside the
    /// island, the island is showing this capture.
    package static func ownsKeys(closed: Bool, panelVisible: Bool, inPanel: Bool, shownByIsland: Bool,
                                 hasSheet: Bool, editingText: Bool, recordingShortcut: Bool) -> Bool {
        !closed && panelVisible && inPanel && shownByIsland && !hasSheet && !editingText && !recordingShortcut
    }

    /// Nil passes the press on.
    package static func command(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String?) -> Command? {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        if flags.intersection([.command, .option, .shift, .control]) == .command {
            let text = characters?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            let letter = text?.count == 1 ? text?.first : nil
            let isLatinLetter = letter.map { $0.isASCII && $0.isLetter } ?? false
            if isLatinLetter ? letter == "w" : keyCode == kVK_ANSI_W { return .close }
        }
        if flags.contains(.command) {
            switch keyCode {
            case kVK_ANSI_C: return .perform(.copy)
            case kVK_ANSI_S: return .perform(.save)
            case kVK_Delete, kVK_ForwardDelete: return .perform(.discard)
            default: return nil
            }
        }
        guard flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        switch keyCode {
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_ANSI_E: return .perform(.edit)
        case kVK_Delete, kVK_ForwardDelete: return .perform(.discard)
        // Escape only dismisses. Before the after-capture actions it was
        // equivalent to discard; now a discard can delete a file the HUD just
        // announced as saved, and "make this popup go away" must never do
        // that. Deleting stays on Trash and ⌫.
        case kVK_Escape: return .close
        default: return nil
        }
    }
}

/// What a key press does while a capture's area or window is being chosen,
/// over the overlays or the island's controls.
package enum ScreenshotChooserKeys {
    package enum Command: Equatable {
        /// Swallowed with nothing to do.
        case consume
        case cancel
        case captureDisplay
        case startMovingSelection
        case stopMovingSelection
        case repeatRegion
        case selectTool(ScreenCaptureTool)
        case toggleScrolling
        case toggleLoupe
        case copyColor
        case nudge(keyCode: Int, fast: Bool)
    }

    package struct Context {
        /// The press is in one of the overlays.
        package var inOverlay: Bool
        /// The press is in the island, which shows the chooser's controls.
        package var inIsland: Bool
        package var hasSheet: Bool
        package var editingText: Bool
        package var recordingShortcut: Bool
        /// One of the island's chooser controls has the keyboard.
        package var focusedControl: Bool
        package var spaceIsDown: Bool
        /// A selection is being dragged under the pointer.
        package var dragging: Bool
        package var acceptsWindowClick: Bool
        /// The tools a typed letter can switch to.
        package var availableTools: [ScreenCaptureTool]
        package var loupeAcceptsKeys: Bool

        package init(inOverlay: Bool, inIsland: Bool, hasSheet: Bool, editingText: Bool, recordingShortcut: Bool,
                     focusedControl: Bool, spaceIsDown: Bool, dragging: Bool, acceptsWindowClick: Bool,
                     availableTools: [ScreenCaptureTool], loupeAcceptsKeys: Bool) {
            self.inOverlay = inOverlay
            self.inIsland = inIsland
            self.hasSheet = hasSheet
            self.editingText = editingText
            self.recordingShortcut = recordingShortcut
            self.focusedControl = focusedControl
            self.spaceIsDown = spaceIsDown
            self.dragging = dragging
            self.acceptsWindowClick = acceptsWindowClick
            self.availableTools = availableTools
            self.loupeAcceptsKeys = loupeAcceptsKeys
        }
    }

    /// Nil passes the press on.
    package static func command(keyCode: Int, keyUp: Bool, flags: NSEvent.ModifierFlags, characters: String?,
                                context: Context) -> Command? {
        guard context.inOverlay || context.inIsland else { return nil }
        if context.inIsland {
            guard !context.hasSheet, !context.editingText, !context.recordingShortcut else { return nil }
            let movesSelection = keyCode == kVK_Space && (context.spaceIsDown || context.dragging)
            if context.focusedControl, keyCode != kVK_Escape, !movesSelection { return nil }
        }
        if keyUp {
            guard keyCode == kVK_Space, context.spaceIsDown else { return nil }
            return .stopMovingSelection
        }
        let plain = flags.intersection([.command, .control, .option]).isEmpty
        /// The typed character the hint promises, or its physical ANSI key,
        /// which keeps the shortcut on layouts whose letters are not Latin.
        func matches(_ character: String, _ physicalKeyCode: Int) -> Bool {
            plain && (characters?.lowercased() == character || keyCode == physicalKeyCode)
        }
        switch keyCode {
        case kVK_Escape:
            return .cancel
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return context.acceptsWindowClick ? .captureDisplay : .consume
        case kVK_Space:
            // Holding Space moves the in-progress selection.
            return context.dragging ? .startMovingSelection : nil
        default:
            break
        }
        if matches("r", kVK_ANSI_R) { return .repeatRegion }
        if plain, let tool = ScreenCaptureTool.matchingShortcut(characters), context.availableTools.contains(tool) {
            return .selectTool(tool)
        }
        if matches("s", kVK_ANSI_S) { return .toggleScrolling }
        // The loupe toggle follows the typed character, with the physical
        // slot as a fallback: the Z key sits elsewhere on some layouts and
        // the localized hints promise the letter itself.
        if matches("z", kVK_ANSI_Z) { return .toggleLoupe }
        // C copies the color under the pointer without ending the session,
        // so a whole palette can be read off one frozen screen. Only while
        // the loupe shows which pixel.
        if matches("c", kVK_ANSI_C) { return context.loupeAcceptsKeys ? .copyColor : nil }
        if plain, [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(keyCode) {
            return context.loupeAcceptsKeys ? .nudge(keyCode: keyCode, fast: flags.contains(.shift)) : nil
        }
        return nil
    }
}
