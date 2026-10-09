// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import VitruvianCore
import VitruvianDesign

/// Everything the quick launcher can hold. Raw values are storage ids for
/// the user's order and hidden set.
package enum QuickLauncherItem: String, PanelOrderItem, CaseIterable, Identifiable {
    // Case order is the default grid order; the cleaner comes second, right
    // after Keep awake, by the owner's decision. Saved orders are untouched
    // (a case added later joins a saved order at the end).
    case keepAwake, cleaner, toggles, micMute, screenOCR, colorPicker, clipboard, windowLayout,
         cleaning, homebrew, media, urlCleaner, uninstaller, screenshot, screenRecorder,
         cameraPreview, scratchpad

    package var id: String { rawValue }

    /// The hub feature behind the tile; off in the hub removes it from the
    /// grid, the hidden list and edit mode until it returns.
    package var feature: AppFeature {
        switch self {
        case .keepAwake: return .keepAwake
        case .cleaner: return .cleaner
        case .toggles: return .quickToggles
        case .micMute: return .micMute
        case .screenOCR: return .screenOCR
        case .colorPicker: return .colorPicker
        case .clipboard: return .clipboardHistory
        case .windowLayout: return .windowLayout
        case .cleaning: return .cleaningMode
        case .homebrew: return .homebrew
        case .media: return .mediaTools
        case .urlCleaner: return .urlCleaner
        case .uninstaller: return .uninstaller
        case .screenshot: return .screenshot
        case .screenRecorder: return .screenRecorder
        case .cameraPreview: return .cameraPreview
        case .scratchpad: return .scratchpad
        }
    }
}

extension QuickLauncherItem {
    /// The registry command a tile runs. Nil for the utilities the panel
    /// hosts inside itself, which run nothing outside it.
    package var command: BuiltinCommand? {
        switch self {
        case .keepAwake: return .keepAwakeToggle
        case .micMute: return .micMuteToggle
        case .screenOCR: return .screenOCRCapture
        case .screenshot: return .screenshotCapture
        case .screenRecorder: return .screenRecorderToggle
        case .colorPicker: return .colorPickerPick
        case .cameraPreview: return .cameraPreviewShow
        case .scratchpad: return .scratchpadShow
        case .clipboard: return .clipboardHistoryShow
        case .cleaning: return .cleaningModeActivate
        case .windowLayout, .homebrew, .media, .urlCleaner, .uninstaller, .cleaner, .toggles: return nil
        }
    }
}

/// The floating quick panel: a small, pretty launcher with the user's
/// favorite tools, summoned from anywhere with a global shortcut (⌃⌘V by
/// default; V for Vitruvian). Fully customizable in place: items can be
/// hidden, brought back and reordered by dragging.
@MainActor
package final class QuickLauncherService: ObservableObject {
    package static let shared = QuickLauncherService(environment: .live)

    /// What the launcher reaches outside its grid. `live` is the app's: the
    /// feature switches, the saved order, the island, the main queue and each
    /// tool's own service. Tests pass doubles, so no tool runs.
    @MainActor
    package struct Environment {
        package var isAvailable: (AppFeature) -> Bool
        /// Every tool in the person's saved order.
        package var itemOrder: () -> [QuickLauncherItem]
        /// The open island shows the Tools page, which hiding closes.
        package var islandShowsTools: () -> Bool
        package var collapseIsland: () -> Void
        /// Shows the camera in the island when it is set up to; false leaves
        /// it to its own window.
        package var showCameraInIsland: () -> Bool
        /// Runs a tool that works outside the launcher.
        package var perform: (QuickLauncherItem) -> Void
        package var after: (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
        /// Tile ids in the person's saved order, as written: tiles of either kind.
        package var savedTileOrder: () -> [String]
        package var saveTileOrder: ([String]) -> Void
        /// Registry commands that ask for the panel and that no built-in tile runs.
        package var commands: () -> [CommandDescriptor]
        package var canRunCommand: (CommandID) -> Bool
        package var runCommand: (CommandID) -> Void

        package init(isAvailable: @escaping (AppFeature) -> Bool,
                     itemOrder: @escaping () -> [QuickLauncherItem],
                     islandShowsTools: @escaping () -> Bool, collapseIsland: @escaping () -> Void,
                     showCameraInIsland: @escaping () -> Bool, perform: @escaping (QuickLauncherItem) -> Void,
                     after: @escaping (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void,
                     savedTileOrder: @escaping () -> [String] = { [] },
                     saveTileOrder: @escaping ([String]) -> Void = { _ in },
                     commands: @escaping () -> [CommandDescriptor] = { [] },
                     canRunCommand: @escaping (CommandID) -> Bool = { _ in true },
                     runCommand: @escaping (CommandID) -> Void = { _ in }) {
            self.isAvailable = isAvailable
            self.itemOrder = itemOrder
            self.islandShowsTools = islandShowsTools
            self.collapseIsland = collapseIsland
            self.showCameraInIsland = showCameraInIsland
            self.perform = perform
            self.after = after
            self.savedTileOrder = savedTileOrder
            self.saveTileOrder = saveTileOrder
            self.commands = commands
            self.canRunCommand = canRunCommand
            self.runCommand = runCommand
        }

        package static var live: Environment {
            Environment(
                isAvailable: { $0.isAvailable },
                itemOrder: { PanelLayout.itemOrder(QuickLauncherItem.self, key: DefaultsKey.quickLauncherItemOrder) },
                islandShowsTools: { NotchService.shared.expanded && NotchService.shared.selected == .tools },
                collapseIsland: { NotchService.shared.collapse() },
                showCameraInIsland: { CameraPreviewService.shared.showInNotchIfEnabled() },
                perform: { item in
                    if let command = item.command { ToolRegistry.shared.run(command.id) }
                },
                after: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() } },
                savedTileOrder: { PanelLayout.rawItemOrder(key: DefaultsKey.quickLauncherItemOrder) },
                saveTileOrder: { PanelLayout.setRawItemOrder($0, key: DefaultsKey.quickLauncherItemOrder) },
                commands: { ToolRegistry.shared.extraCommands(on: .quickPanel) },
                canRunCommand: { ToolRegistry.shared.canRun($0) },
                runCommand: { ToolRegistry.shared.run($0) })
        }
    }

    private let environment: Environment

    nonisolated package static let columns = 3

    @Published package private(set) var shortcutRegistrationFailed = false
    @Published package var isEditing = false
    /// The tile whose inline options card is open in edit mode. Lives here
    /// (not in the view) so the Esc key monitor can close the card first,
    /// before leaving edit mode and before hiding the panel.
    @Published package var editingOptionsItem: QuickLauncherItem?
    /// A utility view (Homebrew, Uninstaller…) currently hosted INSIDE the
    /// launcher, replacing the grid. Everything happens in this panel; the
    /// menu bar popover is never involved.
    @Published package private(set) var activeUtility: QuickLauncherItem?
    @Published package private(set) var selectedIndex: Int?
    /// Where the keyboard moved the selection, which the island's rail
    /// scrolls to. Hover clears it: centering a hovered tile slid the next
    /// one under the pointer, and the rail kept scrolling by itself.
    @Published package private(set) var keyboardIndex: Int?
    @Published package private(set) var presentationID = UUID()
    @Published package private(set) var hiddenItemsRaw: String = UserDefaults.standard[Preferences.quickLauncherHiddenItems]

    private let hotkey = QuickToolHotkey(id: 14)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    package init(environment: Environment) {
        self.environment = environment
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    package func syncWithPreferences() {
        let enabled = AppFeature.quickLauncher.isAvailable
            && UserDefaults.standard[Preferences.quickLauncherShortcutEnabled]
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.quickLauncherShortcut,
                                            fallback: .quickLauncherDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.quickLauncherShortcut)
    }

    package func suspend() {
        hotkey.unregister()
        hide()
    }

    package var isVisible: Bool {
        panel?.isVisible == true
    }

    // MARK: - Items

    /// Every tile in the grid, in the person's order.
    package var visibleTiles: [QuickLauncherTile] {
        let hidden = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        return orderedTiles.filter { !hidden.contains($0.rawValue) }
    }

    package var hiddenTiles: [QuickLauncherTile] {
        let hidden = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        return orderedTiles.filter { hidden.contains($0.rawValue) }
    }

    /// The app's own tiles among them, in the same order.
    package var visibleItems: [QuickLauncherItem] { visibleTiles.compactMap(\.builtin) }
    package var hiddenItems: [QuickLauncherItem] { hiddenTiles.compactMap(\.builtin) }

    /// The app's own tiles that are switched on, then the commands on offer,
    /// placed by the saved order.
    private var orderedTiles: [QuickLauncherTile] {
        let builtins = environment.itemOrder().filter { environment.isAvailable($0.feature) }
            .map(QuickLauncherTile.builtin)
        let commands = environment.commands().map { QuickLauncherTile.command($0.id) }
        let live = builtins + commands
        let byID = Dictionary(live.map { ($0.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        return QuickToolsSupport.tileOrder(live: live.map(\.rawValue), saved: environment.savedTileOrder())
            .compactMap { byID[$0] }
    }

    package var tileOrderBinding: Binding<[QuickLauncherTile]> {
        Binding {
            self.orderedTiles
        } set: { newValue in
            self.environment.saveTileOrder(
                QuickToolsSupport.savedTileOrder(afterMoving: newValue.map(\.rawValue),
                                                 previous: self.environment.savedTileOrder(),
                                                 isWellFormed: { QuickLauncherTile(rawValue: $0) != nil }))
            self.objectWillChange.send()
        }
    }

    package func setHidden(_ tile: QuickLauncherTile, _ hidden: Bool) {
        var ids = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        if hidden {
            ids.insert(tile.rawValue)
            // Hiding the tile whose options card is open would orphan the
            // card below a grid that no longer shows its owner.
            if let item = tile.builtin, editingOptionsItem == item { editingOptionsItem = nil }
        } else {
            ids.remove(tile.rawValue)
        }
        hiddenItemsRaw = QuickToolsSupport.serializeHiddenIDs(ids)
        UserDefaults.standard[Preferences.quickLauncherHiddenItems] = hiddenItemsRaw
        clampSelection()
    }

    package func setHidden(_ item: QuickLauncherItem, _ hidden: Bool) {
        setHidden(.builtin(item), hidden)
    }

    // MARK: - Presentation

    package func toggle() {
        if NotchService.shared.openQuickPanel(toggle: true) { return }
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    package func show() {
        if NotchService.shared.openQuickPanel() { return }
        let panel = ensurePanel()
        prepareForPresentation()
        position(panel)
        installMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
    }

    /// Both destinations start with usable keyboard navigation. A utility that
    /// is still installed keeps its working state when the island is reopened.
    package func prepareForPresentation() {
        refreshAvailability()
        presentationID = UUID()
        isEditing = false
        editingOptionsItem = nil
        selectedIndex = visibleTiles.isEmpty ? nil : 0
        keyboardIndex = selectedIndex
    }

    package func refreshAvailability() {
        if let activeUtility, !environment.isAvailable(activeUtility.feature) { self.activeUtility = nil }
        if let editingOptionsItem, !environment.isAvailable(editingOptionsItem.feature) { self.editingOptionsItem = nil }
        clampSelection()
    }

    package func hide() {
        if environment.islandShowsTools() { environment.collapseIsland() }
        removeMonitors()
        isEditing = false
        editingOptionsItem = nil
        activeUtility = nil
        panel?.orderOut(nil)
    }

    package func closeUtility() {
        activeUtility = nil
    }

    /// Hands key focus back after a modal dialog ran on top of the launcher
    /// (choosing a file in Media, for example), so Esc and the keyboard
    /// shortcuts keep working without an extra click.
    package func refocusAfterModal() {
        if NotchService.shared.expanded, NotchService.shared.selected == .tools {
            NotchService.shared.presentationWindow?.makeKey(); return
        }
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
    }

    /// The single owner of the dismissal policy: the bare grid behaves like a
    /// transient HUD, but with a utility hosted inside the launcher is a
    /// working window that must survive its own dialogs, admin prompts and
    /// clicks in other apps (dragging a file into Media). Every dismissal
    /// trigger consults this, so a future one cannot forget the rule.
    private var dismissesOnOutsideInteraction: Bool {
        // Edit mode counts as a working window too: the clamshell toggle in
        // the Keep awake options card can raise an admin password prompt,
        // and that prompt's activation must not tear the launcher down.
        activeUtility == nil && !isEditing
    }

    /// Re-fits the panel to its content when the grid gives way to a hosted
    /// utility (and back), keeping the top edge and horizontal center still.
    package func refreshPanelLayout() {
        guard let panel, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
            let screen = NSScreen.pointerVisibleFrame
            var frame = panel.frame
            frame.origin.x = frame.midX - size.width / 2
            frame.origin.y = frame.maxY - size.height
            frame.size = size
            frame.origin.x = max(screen.minX + 16, min(frame.origin.x, screen.maxX - size.width - 16))
            frame.origin.y = max(screen.minY + 16, frame.origin.y)
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - Actions

    package func activateSelection() {
        guard let selectedIndex, visibleTiles.indices.contains(selectedIndex) else { return }
        run(visibleTiles[selectedIndex])
    }

    package func activate(at index: Int) {
        guard visibleTiles.indices.contains(index) else { return }
        run(visibleTiles[index])
    }

    package func moveSelection(_ direction: QuickToolsSupport.GridDirection,
                       flow: QuickToolsSupport.GridFlow = .rows(columns: QuickLauncherService.columns)) {
        let count = visibleTiles.count
        guard count > 0 else { return }
        selectedIndex = QuickToolsSupport.gridIndex(after: selectedIndex ?? 0,
                                                    count: count,
                                                    flow: flow,
                                                    direction: direction)
        keyboardIndex = selectedIndex
    }

    /// The pointer's selection. The hovered tile is already in view, so the
    /// rail stays where it is.
    package func select(_ tile: QuickLauncherTile) {
        selectedIndex = visibleTiles.firstIndex(of: tile)
        keyboardIndex = nil
    }

    package func select(_ item: QuickLauncherItem) {
        select(.builtin(item))
    }

    package func run(_ tile: QuickLauncherTile) {
        switch tile {
        case .builtin(let item):
            run(item)
        case .command(let id):
            guard !isEditing, environment.canRunCommand(id) else { return }
            // The same beat the app's own screen-touching tiles get, so the
            // panel is really gone before the command shows anything.
            hide()
            environment.after(0.15) { [weak self] in self?.environment.runCommand(id) }
        }
    }

    package func run(_ item: QuickLauncherItem) {
        guard !isEditing, environment.isAvailable(item.feature) else { return }
        switch item {
        case .keepAwake, .micMute:
            environment.perform(item)
        case .screenOCR, .screenshot, .screenRecorder, .colorPicker, .scratchpad:
            hide()
            environment.after(0.15) { [weak self] in self?.environment.perform(item) }
        case .cameraPreview:
            let embedded = environment.showCameraInIsland()
            hide()
            if !embedded {
                environment.after(0.15) { [weak self] in self?.environment.perform(item) }
            }
        case .clipboard, .cleaning:
            hide()
            environment.after(0.1) { [weak self] in self?.environment.perform(item) }
        case .windowLayout, .homebrew, .media, .urlCleaner, .uninstaller, .cleaner, .toggles:
            activeUtility = item
        }
    }

    private func clampSelection() {
        let count = visibleTiles.count
        guard count > 0 else {
            selectedIndex = nil
            return
        }
        selectedIndex = min(selectedIndex ?? 0, count - 1)
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default, and the launcher needs
    /// it for arrows, digits and Esc. Borderless also removes the invisible
    /// title-bar strip that would swallow clicks on the header controls.
    private final class KeyableLauncherPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    /// The launcher's panel, before its content: a floating overlay, which
    /// window managers do not list.
    package static func makePanel() -> NSPanel {
        KeyableLauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = Self.makePanel()
        panel.title = "Vitruvian"
        panel.isReleasedWhenClosed = false
        // Item drag-to-reorder needs the mouse drag for itself; a background-
        // movable window would win the gesture and drag the whole panel.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ServiceViews.factory.quickLauncher())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    /// Spotlight-style placement: centered on the screen with the mouse,
    /// a bit above the middle so the eyes land on it naturally.
    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 420, height: 380)
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.minY + (screen.height - size.height) * 0.62
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, y),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    // MARK: - Monitors

    package func handlePanelKey(_ event: NSEvent,
                        flow: QuickToolsSupport.GridFlow = .rows(columns: QuickLauncherService.columns)) -> NSEvent? {
        takesPanelKey(event, flow: flow) ? nil : event
    }

    /// Whether the launcher takes `key`, after acting on it.
    package func takesPanelKey(_ key: some QuickLauncherKey,
                               flow: QuickToolsSupport.GridFlow = .rows(columns: QuickLauncherService.columns)) -> Bool {
        if key.keyCode == UInt16(kVK_Escape) {
            // While an input method is composing in a utility's field, Esc
            // belongs to it and drops the candidate; the launcher takes the
            // next one.
            if key.inputIsComposing { return false }
            if activeUtility != nil {
                activeUtility = nil
            } else if editingOptionsItem != nil {
                // An open options card closes first; a second Esc then
                // leaves edit mode, and a third hides the panel.
                editingOptionsItem = nil
            } else if isEditing {
                isEditing = false
            } else {
                hide()
            }
            return true
        }
        guard !isEditing, activeUtility == nil,
              key.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch Int(key.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateSelection()
            return true
        case kVK_LeftArrow:
            moveSelection(.left, flow: flow)
            return true
        case kVK_RightArrow:
            moveSelection(.right, flow: flow)
            return true
        case kVK_UpArrow:
            moveSelection(.up, flow: flow)
            return true
        case kVK_DownArrow:
            moveSelection(.down, flow: flow)
            return true
        default:
            if let index = Self.digitIndex(for: key.keyCode) {
                activate(at: index)
                return true
            }
            return false
        }
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            return self.handlePanelKey(event)
        }
        // With a utility hosted inside (Media, Homebrew, Uninstaller…) the
        // launcher is a small working window, not a transient HUD: it must
        // survive its own file dialogs and admin prompts, and clicks in other
        // apps to drag a file onto its drop zones. Only the bare grid keeps
        // the Spotlight-like dismiss-on-outside-click behavior.
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideInteraction else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideInteraction else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               // Every key on the Accessibility Keyboard is a click outside this
               // panel. Dismissing on those makes the panel impossible to type into.
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hide()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Read here: the notification itself never crosses to the main actor.
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                guard let self,
                      self.dismissesOnOutsideInteraction,
                      let app,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      app.bundleIdentifier != AssistiveKeyboard.bundleID
                else { return }
                self.hide()
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private static func digitIndex(for keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }
}

/// A key as the launcher reads it. `NSEvent` is one; tests pass their own.
@MainActor
package protocol QuickLauncherKey {
    var keyCode: UInt16 { get }
    var modifierFlags: NSEvent.ModifierFlags { get }
    /// An input method is composing in the key's window.
    var inputIsComposing: Bool { get }
}

extension NSEvent: QuickLauncherKey {
    package var inputIsComposing: Bool {
        (window?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }
}
