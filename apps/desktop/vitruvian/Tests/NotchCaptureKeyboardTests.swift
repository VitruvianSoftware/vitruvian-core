// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production routing of a capture preview's and a capture chooser's
/// keys, decided from plain values. No windows are shown, no native monitors
/// are installed and no keyboard input is generated.
enum NotchCaptureKeyboardTests {
    private typealias Preview = ScreenshotPreviewKeys
    private typealias Chooser = ScreenshotChooserKeys
    private typealias Flags = NSEvent.ModifierFlags

    static func run(_ suite: TestSuite) {
        preview(suite)
        chooser(suite)
    }

    /// The flags a test bit pattern names: command, control, option, shift
    /// and Caps Lock, in that order.
    private static func flags(_ bits: Int) -> Flags {
        var flags: Flags = []
        for (bit, flag) in [Flags.command, .control, .option, .shift, .capsLock].enumerated() where bits & (1 << bit) != 0 {
            flags.insert(flag)
        }
        return flags
    }

    private static func preview(_ suite: TestSuite) {
        let id = UUID()
        func focus(_ change: (inout NotchService.CaptureFocus) -> Void = { _ in }) -> NotchService.CaptureFocus {
            var focus = NotchService.CaptureFocus(acceptsSystemFeedback: true, expanded: true, selected: .captures,
                                                  showingAppPanel: false, showingSections: false, showingMetric: false,
                                                  choosing: false, captureID: id, hasContent: true)
            change(&focus)
            return focus
        }
        /// The preview's own gate, as its key monitor asks it.
        func owns(inIsland: Bool = true, _ island: NotchService.CaptureFocus = focus(), closed: Bool = false,
                  visible: Bool = true, inPanel: Bool = true, sheet: Bool = false, text: Bool = false,
                  recording: Bool = false) -> Bool {
            Preview.ownsKeys(closed: closed, panelVisible: visible, inPanel: inPanel,
                             shownByIsland: !inIsland || island.shows(id), hasSheet: sheet, editingText: text,
                             recordingShortcut: recording)
        }
        suite.expect(owns(), "a visible capture owns its keys")
        for module in NotchModule.allCases where module != .captures {
            suite.expect(!owns(focus { $0.selected = module }),
                         "a hidden capture never edits, copies, saves or discards while another section owns the window")
        }
        let elsewhere: [(NotchService.CaptureFocus, String)] = [
            (focus { $0.showingSections = true }, "section search keeps typing, deletion and clipboard shortcuts"),
            (focus { $0.showingAppPanel = true }, "the app panel never inherits hidden capture commands"),
            (focus { $0.showingMetric = true }, "a metric's detail never inherits hidden capture commands"),
            (focus { $0.expanded = false }, "a collapsed capture cannot consume keyboard input"),
            (focus { $0.choosing = true }, "an active chooser cannot trigger actions on the previous capture"),
            (focus { $0.captureID = UUID() }, "a replaced preview cannot act on its successor"),
            (focus { $0.hasContent = false }, "a capture whose content is gone owns no keys"),
            (focus { $0.acceptsSystemFeedback = false }, "an island that is away owns no capture keys"),
        ]
        for (island, label) in elsewhere {
            suite.expect(!owns(island), label)
        }
        suite.expect(!owns(text: true), "text editing retains every preview shortcut")
        suite.expect(!owns(sheet: true), "a sheet owns input over its parent preview")
        suite.expect(!owns(recording: true), "shortcut recording cannot execute preview actions")
        suite.expect(owns(inIsland: false, focus { $0.expanded = false }),
                     "floating previews retain shortcuts independently of notch state")
        suite.expect(!owns(closed: true), "a closed preview ignores late keyboard callbacks")
        suite.expect(!owns(visible: false), "a preview that is not on screen ignores keys")
        suite.expect(!owns(inPanel: false), "keys in unrelated windows are left alone")

        let commands: [(Int, Flags, ScreenshotQuickPreviewController.Action)] = [
            (kVK_ANSI_E, [], .edit), (kVK_Return, [], .edit), (kVK_ANSI_KeypadEnter, [], .edit),
            (kVK_Delete, [], .discard), (kVK_ForwardDelete, [], .discard), (kVK_ANSI_C, .command, .copy),
            (kVK_ANSI_S, .command, .save), (kVK_Delete, .command, .discard), (kVK_ForwardDelete, .command, .discard),
            (kVK_ANSI_E, .shift, .edit),
        ]
        for (key, flags, action) in commands {
            suite.expect(Preview.command(keyCode: key, flags: flags, characters: nil) == .perform(action),
                         "visible capture retains its existing keyboard actions")
        }
        let passed: [(Int, Flags)] = [(kVK_ANSI_E, .control), (kVK_Delete, .option), (kVK_ANSI_A, []),
                                      (kVK_ANSI_A, .command), (kVK_ANSI_E, .command)]
        for (key, flags) in passed {
            suite.expect(Preview.command(keyCode: key, flags: flags, characters: nil) == nil,
                         "other keys and modified ones are passed on")
        }
        suite.expect(Preview.command(keyCode: kVK_Escape, flags: [], characters: nil) == .close,
                     "Escape closes without dispatching a destructive action")
        for (character, key, closes) in [("w", kVK_ANSI_W, true), ("W", kVK_ANSI_W, true),
                                         ("w", kVK_ANSI_Z, true), ("z", kVK_ANSI_W, false),
                                         ("é", kVK_ANSI_W, false), ("ц", kVK_ANSI_W, true),
                                         ("ц", kVK_ANSI_Z, false)] {
            for bits in 0..<32 {
                let accepts = closes && bits & ~16 == 1
                suite.expect((Preview.command(keyCode: key, flags: flags(bits), characters: character) == .close) == accepts,
                             "Command W follows French and Latin letters, falls back for non-Latin input, and excludes extra modifiers")
            }
        }
    }

    private static func chooser(_ suite: TestSuite) {
        func context(island: Bool = true, focused: Bool = false, sheet: Bool = false, text: Bool = false,
                     recording: Bool = false, spaceIsDown: Bool = false, dragging: Bool = false,
                     acceptsWindowClick: Bool = true, tools: [ScreenCaptureTool] = [],
                     loupe: Bool = false) -> Chooser.Context {
            Chooser.Context(inOverlay: !island, inIsland: island, hasSheet: sheet, editingText: text,
                            recordingShortcut: recording, focusedControl: focused, spaceIsDown: spaceIsDown,
                            dragging: dragging, acceptsWindowClick: acceptsWindowClick, availableTools: tools,
                            loupeAcceptsKeys: loupe)
        }
        func press(_ key: Int, up: Bool = false, _ flags: Flags = [], _ characters: String? = nil,
                   in context: Chooser.Context) -> Chooser.Command? {
            Chooser.command(keyCode: key, keyUp: up, flags: flags, characters: characters, context: context)
        }
        for focused in [false, true] {
            for key in [kVK_Tab, kVK_Space, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow] {
                for up in [false, true] {
                    suite.expect(press(key, up: up, in: context(focused: focused)) == nil,
                                 "unhandled navigation and activation keys reach native controls")
                }
            }
        }
        suite.expect(press(kVK_Return, in: context(focused: true)) == nil,
                     "Return activates the focused control instead of taking an unexpected full-screen capture")
        suite.expect(press(kVK_Return, in: context()) == .captureDisplay
                     && press(kVK_ANSI_KeypadEnter, in: context()) == .captureDisplay,
                     "Return still captures the display when no control owns it")
        suite.expect(press(kVK_Return, in: context(acceptsWindowClick: false)) == .consume,
                     "Return is kept from the app even when no display can be taken")
        for focused in [false, true] {
            suite.expect(press(kVK_Space, in: context(focused: focused, dragging: true)) == .startMovingSelection,
                         "Space still moves a selection even while a chooser control has focus")
            suite.expect(press(kVK_Space, up: true, in: context(focused: focused, spaceIsDown: true)) == .stopMovingSelection,
                         "releasing Space clears movement after the drag has ended")
        }
        suite.expect(press(kVK_Space, up: true, in: context()) == nil && press(kVK_ANSI_A, up: true, in: context()) == nil
                     && press(kVK_ANSI_A, up: true, in: context(spaceIsDown: true)) == nil,
                     "only releasing a held Space ends the move; other releases are passed on")
        suite.expect(press(kVK_Escape, in: context(focused: true)) == .cancel,
                     "Escape retains chooser cancellation while controls are focused")
        suite.expect(press(kVK_Return, in: context(text: true)) == nil, "a chooser text editor retains Return")
        suite.expect(press(kVK_Escape, in: context(sheet: true)) == nil && press(kVK_Escape, in: context(recording: true)) == nil,
                     "a sheet or a shortcut being recorded keeps the island's keys")
        let unrelated = Chooser.Context(inOverlay: false, inIsland: false, hasSheet: false, editingText: false,
                                        recordingShortcut: false, focusedControl: false, spaceIsDown: false,
                                        dragging: false, acceptsWindowClick: true, availableTools: [], loupeAcceptsKeys: true)
        suite.expect(press(kVK_Return, in: unrelated) == nil && press(kVK_Escape, in: unrelated) == nil,
                     "capture selection leaves unrelated windows alone")
        for island in [true, false] {
            for bits in 0..<16 {
                for (character, key, matches) in [("r", kVK_ANSI_X, true), ("R", kVK_ANSI_X, true),
                                                  ("x", kVK_ANSI_R, true), ("x", kVK_ANSI_X, false)] {
                    let accepts = matches && bits & 7 == 0
                    suite.expect((press(key, flags(bits), character, in: context(island: island)) == .repeatRegion) == accepts,
                                 "repeat follows the typed letter or physical key, but never command, control or option")
                }
            }
        }
        suite.expect(press(kVK_Return, in: context(island: false)) == .captureDisplay
                     && press(kVK_Return, in: context(island: false, focused: true, text: true)) == .captureDisplay,
                     "the original floating chooser keeps full-display capture, whatever the island holds")
        let tools: [ScreenCaptureTool] = [.screenshot, .color]
        suite.expect(press(kVK_ANSI_1, [], ScreenCaptureTool.screenshot.shortcutKey, in: context(tools: tools)) == .selectTool(.screenshot)
                     && press(kVK_ANSI_4, [], ScreenCaptureTool.color.shortcutKey, in: context(tools: tools)) == .selectTool(.color)
                     && press(kVK_ANSI_2, [], ScreenCaptureTool.recording.shortcutKey, in: context(tools: tools)) == nil
                     && press(kVK_ANSI_1, .command, ScreenCaptureTool.screenshot.shortcutKey, in: context(tools: tools)) == nil,
                     "a tool's number switches to it only when it is offered and no command key is held")
        suite.expect(press(kVK_ANSI_S, [], "s", in: context()) == .toggleScrolling
                     && press(kVK_ANSI_Z, [], "z", in: context()) == .toggleLoupe
                     && press(kVK_ANSI_X, [], "z", in: context()) == .toggleLoupe
                     && press(kVK_ANSI_Z, .command, "z", in: context()) == nil,
                     "scrolling capture and the loupe follow their letters without a command key")
        suite.expect(press(kVK_ANSI_C, [], "c", in: context()) == nil
                     && press(kVK_ANSI_C, [], "c", in: context(loupe: true)) == .copyColor
                     && press(kVK_ANSI_C, .command, "c", in: context(loupe: true)) == nil,
                     "C copies a color only while the loupe takes keys")
        suite.expect(press(kVK_LeftArrow, in: context(loupe: true)) == .nudge(keyCode: kVK_LeftArrow, fast: false)
                     && press(kVK_UpArrow, .shift, in: context(loupe: true)) == .nudge(keyCode: kVK_UpArrow, fast: true)
                     && press(kVK_DownArrow, .option, in: context(loupe: true)) == nil,
                     "arrows nudge the pointer while the loupe takes keys, ten pixels with Shift")
    }
}
