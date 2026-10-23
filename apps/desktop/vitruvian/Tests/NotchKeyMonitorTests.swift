// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The island's local event route runs against plain doubles. No window is
/// shown, no native monitor is installed and no key is posted.
enum NotchKeyMonitorTests {
    final class Window {}

    struct Event: NotchMonitoredEvent {
        /// Reads of key-only fields from a click, which `NSEvent` refuses.
        static var nonKeyReads = 0
        var type: NSEvent.EventType = .keyDown
        var targetWindow: AnyObject?
        var code: UInt16 = 0
        var modifierFlags: NSEvent.ModifierFlags = []
        var characters: String?
        var keyCode: UInt16 {
            if type != .keyDown { Self.nonKeyReads += 1 }
            return code
        }
        var charactersIgnoringModifiers: String? {
            if type != .keyDown { Self.nonKeyReads += 1 }
            return characters
        }
    }

    /// The island as the route sees it, recording what it was asked to do.
    final class Island {
        let panel = Window()
        let popover = Window()
        var composing = false
        var fieldTakesEscape = false
        var capturing = false
        var modules = NotchModule.allCases
        var selected = NotchModule.controls
        var showingSections = false
        var showingAppPanel = false
        var showingCommandBar = false
        var editingSections = false
        var showingToolPage = false
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     safeAreaTop: 32, cameraWidth: 180)
        var tools = (editing: false, count: 3)
        var clickIsAway = true
        /// The keys the section, Scratchpad and clipboard handlers take.
        var taken: Set<String> = []
        var actions: [String] = []
        var keyboardInputs = 0
        var flows: [QuickToolsSupport.GridFlow] = []

        var route: NotchLocalEventRoute<Event> {
            NotchLocalEventRoute(island: .init(
                panel: { [unowned self] in self.panel },
                isComposing: { [unowned self] in self.composing },
                fieldTakesEscape: { [unowned self] in self.fieldTakesEscape },
                isCapturing: { [unowned self] in self.capturing },
                modules: { [unowned self] in self.modules },
                selected: { [unowned self] in self.selected },
                showingSections: { [unowned self] in self.showingSections },
                showingAppPanel: { [unowned self] in self.showingAppPanel },
                geometry: { [unowned self] in self.geometry },
                tools: { [unowned self] in self.tools },
                ownsWindow: { [unowned self] in $0 === self.panel || $0 === self.popover },
                clickIsAway: { [unowned self] in self.clickIsAway },
                toggleSections: { [unowned self] in self.actions.append("sections") },
                select: { [unowned self] in self.actions.append("select \($0.rawValue)") },
                sectionKey: { [unowned self] _ in self.takes("section") },
                scratchpadKey: { [unowned self] _ in self.takes("scratchpad") },
                clipboardPasteKey: { [unowned self] _ in self.takes("clipboard") },
                toolsKey: { [unowned self] _, flow in
                    self.actions.append("tools")
                    self.flows.append(flow)
                    return true
                },
                stepBack: { [unowned self] in self.actions.append("stepBack") },
                collapse: { [unowned self] in self.actions.append("collapse") },
                clickedInside: { [unowned self] in self.actions.append("clicked") },
                keyboardInput: { [unowned self] in self.keyboardInputs += 1 },
                showingCommandBar: { [unowned self] in self.showingCommandBar },
                editingSections: { [unowned self] in self.editingSections },
                stopEditingSections: { [unowned self] in self.actions.append("stopEditing") },
                showingToolPage: { [unowned self] in self.showingToolPage }))
        }

        private func takes(_ handler: String) -> Bool {
            guard taken.contains(handler) else { return false }
            actions.append(handler)
            return true
        }

        func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = [], _ characters: String? = nil) -> Event {
            Event(targetWindow: panel, code: code, modifierFlags: modifiers, characters: characters)
        }

        /// Whether the island took the event, and what it did with it.
        func send(_ event: Event) -> (taken: Bool, actions: [String]) {
            actions = []
            let taken = route.handle(event)
            return (taken, actions)
        }
    }

    static func run(_ suite: TestSuite) {
        Event.nonKeyReads = 0
        escape(suite)
        editing(suite)
        tools(suite)
        shortcuts(suite)
        clicks(suite)
        keyboardFocus(suite)
        keyboardHandoff(suite)
        suite.expect(Event.nonKeyReads == 0, "the route never reads a key code or characters from a click")
    }

    /// Where the keyboard goes when the island closes, over windows that say
    /// whether they can take it.
    private static func keyboardHandoff(_ suite: TestSuite) {
        final class Window {
            let takes: Bool
            init(takes: Bool) { self.takes = takes }
        }
        let panel = Window(takes: true)
        let hidden = Window(takes: false)
        let settings = Window(takes: true)
        let behind = Window(takes: true)
        let ordered = [panel, hidden, settings, behind]
        func next(keyWindow: Window?, frontmost: Bool, in windows: [Window] = ordered) -> Window? {
            NotchKeyboardHandoff.successor(of: panel, keyWindow: keyWindow, appIsFrontmost: frontmost,
                                           ordered: windows, takesKeyboard: { $0.takes })
        }
        suite.expect(next(keyWindow: panel, frontmost: true) === settings,
                     "closing the island hands the keyboard to the frontmost window that can take it")
        suite.expect(next(keyWindow: panel, frontmost: false) == nil,
                     "closing the island leaves the keyboard alone while another app takes over")
        suite.expect(next(keyWindow: settings, frontmost: true) == nil,
                     "an island that no longer holds the keyboard hands nothing over")
        suite.expect(next(keyWindow: panel, frontmost: true, in: [panel, hidden]) == nil,
                     "with no window to take it, the keyboard stays where AppKit keeps it")
    }

    /// Opening by pointer may give a control focus without showing it. Keys
    /// for the island show it again; clicks and other windows' keys do not.
    private static func keyboardFocus(_ suite: TestSuite) {
        let island = Island()
        _ = island.send(Event(type: .leftMouseDown, targetWindow: island.panel))
        var elsewhere = island.key(48)
        elsewhere.targetWindow = Window()
        _ = island.send(elsewhere)
        suite.expect(island.keyboardInputs == 0,
                     "pointer input and keys in another window do not expose the island's automatic focus")
        let tab = island.send(island.key(48))
        let backTab = island.send(island.key(48, .shift))
        suite.expect(island.keyboardInputs == 2 && !tab.taken && !backTab.taken,
                     "Tab and Shift-Tab show the focus again and still reach the controls for navigation")
        let shortcut = island.send(island.key(40, .command, "k"))
        suite.expect(island.keyboardInputs == 3 && shortcut.taken,
                     "a key the island takes itself still shows where the focus went")
    }

    /// Each Escape branch, reached from a field that can hold a composing
    /// input method: the gallery search, a field in a Tools utility, one in
    /// the app panel and the Scratchpad editor.
    private static func escape(_ suite: TestSuite) {
        let destinations: [(name: String, module: NotchModule, sections: Bool, appPanel: Bool, action: String)] = [
            ("the gallery search", .controls, true, false, "sections"),
            ("a Tools utility", .tools, false, false, "tools"),
            ("the app panel", .tools, false, true, "stepBack"),
            ("the Scratchpad editor", .scratchpad, false, false, "stepBack"),
        ]
        for destination in destinations {
            let island = Island()
            island.selected = destination.module
            island.showingSections = destination.sections
            island.showingAppPanel = destination.appPanel
            island.composing = true
            let composing = island.send(island.key(53))
            suite.expect(!composing.taken && composing.actions.isEmpty,
                         "a composing input method keeps Esc in \(destination.name)")
            island.composing = false
            let escaped = island.send(island.key(53))
            suite.expect(escaped.taken && escaped.actions == [destination.action],
                         "Esc reaches the island from \(destination.name) once composition ends")
        }
        let island = Island()
        island.selected = .mixer
        island.fieldTakesEscape = true
        let field = island.send(island.key(53))
        suite.expect(!field.taken && field.actions.isEmpty,
                     "a mixer level being typed, or the find bar, takes Esc before the island steps back")
        var elsewhere = island.key(53)
        elsewhere.targetWindow = Window()
        island.fieldTakesEscape = false
        let other = island.send(elsewhere)
        suite.expect(!other.taken && other.actions.isEmpty, "a key for another window is not the island's")

        // The Command Bar inside the island reads its own keys: Escape steps
        // back through its search, and Command-K is its actions, not the gallery.
        let bar = Island()
        bar.showingCommandBar = true
        let barEscape = bar.send(bar.key(53))
        let barCommandK = bar.send(bar.key(40, .command, "k"))
        suite.expect(!barEscape.taken && barEscape.actions.isEmpty && !barCommandK.taken && barCommandK.actions.isEmpty,
                     "the island hands Escape and its shortcuts to the Command Bar open inside it")
        bar.showingCommandBar = false
        let islandEscape = bar.send(bar.key(53))
        suite.expect(islandEscape.taken && islandEscape.actions == ["stepBack"],
                     "without the bar, Escape steps back through the island again")
    }

    /// Customizing Explore: Escape ends it before it leaves Explore, and the
    /// keys that pick and move sections reach nothing.
    private static func editing(_ suite: TestSuite) {
        let island = Island()
        island.showingSections = true
        island.editingSections = true
        island.taken = ["section"]
        let escaped = island.send(island.key(53))
        suite.expect(escaped.taken && escaped.actions == ["stopEditing"],
                     "Escape ends customizing Explore before it leaves Explore")
        for code: UInt16 in [36, 76, 48, 123, 124, 125, 126] {
            let held = island.send(island.key(code))
            suite.expect(held.taken && held.actions.isEmpty, "while customizing, key \(code) picks and moves no section")
        }
        let shiftTab = island.send(island.key(48, .shift))
        suite.expect(shiftTab.taken && shiftTab.actions.isEmpty, "while customizing, Shift-Tab moves no highlight")
        island.editingSections = false
        let leaves = island.send(island.key(53))
        suite.expect(leaves.taken && leaves.actions == ["sections"], "out of customizing, Escape leaves Explore")
        let picks = island.send(island.key(36))
        suite.expect(picks.taken && picks.actions == ["section"], "out of customizing, Return reaches the gallery")
        let page = Island()
        page.selected = .tools
        page.showingToolPage = true
        let down = page.send(page.key(125))
        suite.expect(!down.taken && page.flows.isEmpty, "a tool's page over the Tools page keeps the arrows from the rail")
    }

    /// A title too long to sit beside the camera takes a row below it, so a
    /// custom island leaves the Tools rail fewer rows than the island without
    /// its page would. The arrows walk the rail the page draws.
    private static func tools(_ suite: TestSuite) {
        let island = Island()
        island.selected = .tools
        let plain = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1710, height: 1112), safeAreaTop: 37.5,
                                  cameraWidth: 208, layout: .custom, customWidth: 480, customHeight: 330)
        var titled = plain
        titled.headerTitleWidth = 200
        island.geometry = titled
        island.tools = (false, 12)
        let down = island.send(island.key(125))
        suite.expect(down.taken && island.flows == [titled.toolFlow(count: 12)]
                     && titled.toolFlow(count: 12) != plain.toolFlow(count: 12),
                     "the Tools arrows follow the rail below a title that takes the row under the camera")
        island.flows = []
        island.tools = (true, 12)
        _ = island.send(island.key(125))
        suite.expect(island.flows == [.rows(columns: NotchSupport.toolColumns)],
                     "the Tools grid being edited keeps its own rows")
        island.showingSections = true
        island.flows = []
        _ = island.send(island.key(125))
        suite.expect(island.flows.isEmpty, "the gallery open over Tools keeps the arrows from the rail")
    }

    private static func shortcuts(_ suite: TestSuite) {
        let island = Island()
        let gallery = island.send(island.key(40, .command, "k"))
        suite.expect(gallery.taken && gallery.actions == ["sections"], "Command-K opens the gallery")
        let capsLock = island.send(island.key(40, .command, "K"))
        suite.expect(capsLock.taken && capsLock.actions == ["sections"], "Command-K opens the gallery with Caps Lock on")
        let shifted = island.send(island.key(40, [.command, .shift], "k"))
        suite.expect(!shifted.taken && shifted.actions.isEmpty, "Command-Shift-K is not the gallery's shortcut")
        let music = island.send(island.key(46, [.command, .option], "M"))
        suite.expect(music.taken && music.actions == ["select music"],
                     "Command-Option and a page's letter opens that page")
        let missing = island.send(island.key(46, [.command, .option, .shift], "m"))
        suite.expect(!missing.taken && missing.actions.isEmpty, "another modifier makes it not that shortcut")
        island.modules = [.controls, .mixer, .music]
        island.selected = .music
        let next = island.send(island.key(48, .control))
        suite.expect(next.taken && next.actions == ["select controls"], "Control-Tab wraps to the first page")
        island.selected = .controls
        let previous = island.send(island.key(48, [.control, .shift]))
        suite.expect(previous.taken && previous.actions == ["select music"],
                     "Control-Shift-Tab goes back, wrapping to the last page")
        island.capturing = true
        let capturing = island.send(island.key(40, .command, "k"))
        suite.expect(!capturing.taken && capturing.actions.isEmpty,
                     "capture controls keep the island's shortcuts while they are up")
        island.capturing = false
        island.taken = ["scratchpad", "clipboard"]
        let scratchpad = island.send(island.key(1, .command, "s"))
        suite.expect(scratchpad.taken && scratchpad.actions == ["scratchpad"],
                     "the gallery, then the Scratchpad, then clipboard paste each get a key in turn")
        island.taken = ["section", "scratchpad"]
        let section = island.send(island.key(36))
        suite.expect(section.taken && section.actions == ["section"], "the gallery's keys come first")
        island.taken = ["clipboard"]
        let paste = island.send(island.key(9, .command, "v"))
        suite.expect(paste.taken && paste.actions == ["clipboard"], "clipboard paste gets the keys the others leave")
        island.taken = []
        let plain = island.send(island.key(0, [], "a"))
        suite.expect(!plain.taken && plain.actions.isEmpty, "a key no part of the island wants goes on to the app")
    }

    private static func clicks(_ suite: TestSuite) {
        let island = Island()
        for (window, name) in [(island.panel, "the island"), (island.popover, "a popover hanging from it")] {
            let inside = island.send(Event(type: .leftMouseDown, targetWindow: window))
            suite.expect(!inside.taken && inside.actions == ["clicked"],
                         "a click in \(name) counts as a click inside and goes on to it")
        }
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            let away = island.send(Event(type: type, targetWindow: Window()))
            suite.expect(!away.taken && away.actions == ["collapse"], "a click away closes the island and still lands")
        }
        island.clickIsAway = false
        let kept = island.send(Event(type: .leftMouseDown, targetWindow: nil))
        suite.expect(!kept.taken && kept.actions.isEmpty,
                     "a click on the island's status item, or while it keeps its surface, leaves it open")
    }
}
