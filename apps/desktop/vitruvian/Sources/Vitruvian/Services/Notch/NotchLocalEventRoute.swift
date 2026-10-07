// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// A key or click as the island's local monitor reads it. `NSEvent` is one;
/// tests pass their own.
@MainActor
package protocol NotchMonitoredEvent {
    var type: NSEvent.EventType { get }
    /// The window the event is addressed to, if any.
    var targetWindow: AnyObject? { get }
    /// Only read from key events, like `NSEvent`'s own.
    var keyCode: UInt16 { get }
    var modifierFlags: NSEvent.ModifierFlags { get }
    /// Only read from key events, like `NSEvent`'s own.
    var charactersIgnoringModifiers: String? { get }
}

extension NSEvent: NotchMonitoredEvent {
    package var targetWindow: AnyObject? { window }
}

/// The island's own keys and the clicks that close it, as its local event
/// monitor sees them. `NotchService` passes the island; tests pass doubles.
@MainActor
package struct NotchLocalEventRoute<Event: NotchMonitoredEvent> {
    /// What the route reads from the island and asks of it.
    @MainActor
    package struct Island {
        package var panel: () -> AnyObject?
        /// An input method is composing in the panel's first responder.
        package var isComposing: () -> Bool
        /// A level being typed in the mixer, or the scratchpad's find bar,
        /// has the keyboard and takes Escape itself.
        package var fieldTakesEscape: () -> Bool
        /// Capture controls own the keyboard while they are up.
        package var isCapturing: () -> Bool
        package var modules: () -> [NotchModule]
        package var selected: () -> NotchModule
        package var showingSections: () -> Bool
        package var showingAppPanel: () -> Bool
        /// The open island's layout, which places the Tools rail.
        package var geometry: () -> NotchGeometry
        /// Whether the Tools grid is being edited, and how many tools it shows.
        package var tools: () -> (editing: Bool, count: Int)
        /// The panel, or a window hanging from it such as a popover.
        package var ownsWindow: (AnyObject?) -> Bool
        /// A click lands away from the island: not on it, its status item
        /// or the Accessibility Keyboard, while nothing keeps it open.
        package var clickIsAway: () -> Bool
        package var toggleSections: () -> Void
        package var select: (NotchModule) -> Void
        /// Each answers whether it took the key.
        package var sectionKey: (Event) -> Bool
        package var scratchpadKey: (Event) -> Bool
        package var clipboardPasteKey: (Event) -> Bool
        package var toolsKey: (Event, QuickToolsSupport.GridFlow) -> Bool
        package var stepBack: () -> Void
        package var collapse: () -> Void
        package var clickedInside: () -> Void
        /// The Command Bar inside the island reads its own keys, Escape included.
        package var showingCommandBar: () -> Bool

        package init(panel: @escaping () -> AnyObject?, isComposing: @escaping () -> Bool,
                     fieldTakesEscape: @escaping () -> Bool, isCapturing: @escaping () -> Bool,
                     modules: @escaping () -> [NotchModule], selected: @escaping () -> NotchModule,
                     showingSections: @escaping () -> Bool, showingAppPanel: @escaping () -> Bool,
                     geometry: @escaping () -> NotchGeometry, tools: @escaping () -> (editing: Bool, count: Int),
                     ownsWindow: @escaping (AnyObject?) -> Bool, clickIsAway: @escaping () -> Bool,
                     toggleSections: @escaping () -> Void, select: @escaping (NotchModule) -> Void,
                     sectionKey: @escaping (Event) -> Bool, scratchpadKey: @escaping (Event) -> Bool,
                     clipboardPasteKey: @escaping (Event) -> Bool,
                     toolsKey: @escaping (Event, QuickToolsSupport.GridFlow) -> Bool,
                     stepBack: @escaping () -> Void, collapse: @escaping () -> Void,
                     clickedInside: @escaping () -> Void,
                     showingCommandBar: @escaping () -> Bool = { false }) {
            self.panel = panel
            self.isComposing = isComposing
            self.fieldTakesEscape = fieldTakesEscape
            self.isCapturing = isCapturing
            self.modules = modules
            self.selected = selected
            self.showingSections = showingSections
            self.showingAppPanel = showingAppPanel
            self.geometry = geometry
            self.tools = tools
            self.ownsWindow = ownsWindow
            self.clickIsAway = clickIsAway
            self.toggleSections = toggleSections
            self.select = select
            self.sectionKey = sectionKey
            self.scratchpadKey = scratchpadKey
            self.clipboardPasteKey = clipboardPasteKey
            self.toolsKey = toolsKey
            self.stepBack = stepBack
            self.collapse = collapse
            self.clickedInside = clickedInside
            self.showingCommandBar = showingCommandBar
        }
    }

    package let island: Island

    package init(island: Island) {
        self.island = island
    }

    /// Whether the island takes `event`, after acting on it. An event it
    /// does not take goes on to the app.
    package func handle(_ event: Event) -> Bool {
        let key = event.type == .keyDown && event.targetWindow === island.panel()
        // While an input method is composing, Esc belongs to it and drops
        // the candidate; the island takes the next one.
        if key, event.keyCode == 53, island.isComposing() { return false }
        if key, island.showingCommandBar() { return false }
        if key, !island.isCapturing() {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
                island.toggleSections()
                return true
            }
            if modifiers == [.command, .option],
               let module = NotchSupport.moduleShortcut(event.charactersIgnoringModifiers ?? "",
                                                         modules: island.modules()) {
                island.select(module)
                return true
            }
            if event.keyCode == 48, modifiers == .control || modifiers == [.control, .shift],
               let module = NotchSupport.adjacentModule(to: island.selected(), modules: island.modules(),
                                                       backwards: modifiers.contains(.shift)) {
                island.select(module)
                return true
            }
            if event.keyCode == 53, island.showingSections() {
                island.toggleSections()
                return true
            }
            if island.sectionKey(event) { return true }
            if island.scratchpadKey(event) { return true }
            if island.clipboardPasteKey(event) { return true }
        }
        if key, island.selected() == .tools, !island.showingAppPanel(), !island.showingSections() {
            // The rail reads across its rows until it scrolls, in the rows
            // the open page leaves it below its header; the editing grid
            // keeps its own rows.
            let tools = island.tools()
            let flow: QuickToolsSupport.GridFlow = tools.editing
                ? .rows(columns: NotchSupport.toolColumns)
                : island.geometry().toolFlow(count: tools.count)
            return island.toolsKey(event, flow)
        }
        if key, event.keyCode == 53 {
            // A level being typed in the mixer cancels on Escape by itself,
            // and the scratchpad's find bar closes on it; the next one steps
            // back.
            if island.fieldTakesEscape() { return false }
            island.stepBack()
            return true
        }
        let clicks: [NSEvent.EventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let click = clicks.contains(event.type)
        let islandWindow = island.ownsWindow(event.targetWindow)
        if click, islandWindow { island.clickedInside() }
        if click, !islandWindow, island.clickIsAway() { island.collapse() }
        return false
    }
}
