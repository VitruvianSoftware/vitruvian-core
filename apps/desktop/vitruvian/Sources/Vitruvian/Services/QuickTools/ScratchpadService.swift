// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers
import VitruvianCore
import VitruvianDesign

/// A floating pad for short-lived text: meeting notes, numbers, fragments on
/// their way somewhere else. Summoned from the panel, the quick panel or a
/// global shortcut, it saves every edit by itself in a small tabbed document, so
/// nothing runs at rest and edits remain available between openings. It steps
/// aside on a click outside, and an option keeps it floating over other apps
/// instead.
@MainActor
package final class ScratchpadService: NSObject, ObservableObject, NSWindowDelegate {
    package static let shared = ScratchpadService(environment: .live)

    /// A save dialog for one export, as the pad drives it.
    @MainActor
    package struct ExportDialog {
        /// Opens on its own at `level`, staying up while another app is
        /// active. Used over the island.
        package var beginAbove: (_ level: NSWindow.Level,
                                 _ completion: @escaping (NSApplication.ModalResponse, URL?) -> Void) -> Void
        package var makeKeyAndOrderFront: () -> Void
        /// Runs as an app-modal dialog, as for the floating pad.
        package var runModal: () -> (NSApplication.ModalResponse, URL?)

        package init(beginAbove: @escaping (NSWindow.Level,
                                            @escaping (NSApplication.ModalResponse, URL?) -> Void) -> Void,
                     makeKeyAndOrderFront: @escaping () -> Void,
                     runModal: @escaping () -> (NSApplication.ModalResponse, URL?)) {
            self.beginAbove = beginAbove
            self.makeKeyAndOrderFront = makeKeyAndOrderFront
            self.runModal = runModal
        }

        init(_ panel: NSSavePanel, suggestedName: String) {
            panel.allowedContentTypes = [.plainText]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.nameFieldStringValue = suggestedName
            self.init(beginAbove: { level, completion in
                panel.level = level
                // Like the sheet it replaces, it stays up while another app is active.
                panel.hidesOnDeactivate = false
                panel.begin { response in completion(response, panel.url) }
            }, makeKeyAndOrderFront: { panel.makeKeyAndOrderFront(nil) },
            runModal: { (panel.runModal(), panel.url) })
        }
    }

    /// What the pad reads and drives outside itself. `live` is the app's:
    /// its private container, the HUD, the main queue, a save panel, the
    /// island and the application. Tests pass a store over a directory of
    /// their own and doubles for the rest.
    @MainActor
    package struct Environment {
        package var makeStore: () -> ScratchpadStore
        /// Shows a warning in the HUD, for when the pad is not there to show it.
        package var showWarning: (_ message: String) -> Void
        /// Runs an autosave after `delay` unless it is cancelled first.
        package var schedule: (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void
        package var makeExportDialog: (_ suggestedName: String) -> ExportDialog
        package var islandWindow: () -> (any IslandWindowing)?
        package var activate: () -> Void
        package var main: (@escaping @MainActor () -> Void) -> Void

        package init(makeStore: @escaping () -> ScratchpadStore,
                     showWarning: @escaping (String) -> Void,
                     schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void,
                     makeExportDialog: @escaping (String) -> ExportDialog,
                     islandWindow: @escaping () -> (any IslandWindowing)?,
                     activate: @escaping () -> Void,
                     main: @escaping (@escaping @MainActor () -> Void) -> Void) {
            self.makeStore = makeStore
            self.showWarning = showWarning
            self.schedule = schedule
            self.makeExportDialog = makeExportDialog
            self.islandWindow = islandWindow
            self.activate = activate
            self.main = main
        }

        package static var live: Environment {
            Environment(
                makeStore: { ScratchpadStore(directoryURL: PrivateFileStore.containerURL, defaults: .standard) },
                showWarning: { QuickToolHUD.show(icon: "exclamationmark.triangle", message: $0) },
                schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) },
                makeExportDialog: { ExportDialog(NSSavePanel(), suggestedName: $0) },
                islandWindow: { NotchService.shared.presentationWindow },
                activate: { NSApp.activate(ignoringOtherApps: true) },
                main: { work in DispatchQueue.main.async { work() } })
        }
    }

    @Published package private(set) var shortcutRegistrationFailed = false
    @Published package private(set) var isPinned = false
    @Published package private(set) var isPreviewing = false
    /// Not a preference: the row is a thing you reach for while writing, not a
    /// choice about the pad, so every opening starts without it and one click
    /// brings it back. Held here rather than in either view so both pads agree
    /// while the pad is up.
    @Published package private(set) var marksExpanded = false
    @Published package private(set) var pads: [ScratchpadPad] = []
    @Published package private(set) var selectedPadID: UUID?
    /// Both pads show this in place until a write succeeds again.
    @Published package private(set) var saveFailed = false
    /// Bumped when Command-W asks the view to close the selected tab
    /// (so confirmation stays in SwiftUI).
    @Published package private(set) var keyboardCloseSelectedPadSerial = 0
    @Published package var text = "" {
        didSet {
            guard hasLoaded, !isReplacingText, var document else { return }
            document.updateSelectedText(text, modifiedAt: Date())
            self.document = document
            pads = document.pads
            scheduleSave()
        }
    }

    private let hotkey = QuickToolHotkey(id: 18)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private weak var textView: NSTextView?
    private var pendingSave: DispatchWorkItem?
    private var document: ScratchpadDocument?
    private let environment: Environment
    private var store: ScratchpadStore
    private var hasLoaded = false
    private var isReplacingText = false
    package private(set) var modalInteractionActive = false

    package init(environment: Environment) {
        self.environment = environment
        store = environment.makeStore()
        super.init()
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    package func syncWithPreferences() {
        let available = AppFeature.scratchpad.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.scratchpadShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.scratchpadShortcut,
                                            fallback: .scratchpadDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.scratchpadShortcut)
        if !available {
            hide()
            // Uninstalled in the hub: nothing stays resident.
            panel = nil
        }
    }

    package func suspend() {
        hotkey.unregister()
        hide()
    }

    package var isVisible: Bool {
        panel?.isVisible == true
    }

    /// The shortcut is a strict toggle only while the pad has the keyboard:
    /// visible but unfocused, it grabs focus instead of closing, so one press
    /// always lands the caret in the text.
    package func toggle() {
        guard !modalInteractionActive else { return }
        if NotchService.shared.showScratchpad(toggle: true) {
            if isVisible { hide() }
            return
        }
        if isVisible, panel?.isKeyWindow == true {
            hide()
        } else {
            show()
        }
    }

    /// The island's own open action passes false: it moves the document out
    /// to the floating pad instead of routing it back into the island.
    package func show(allowsIsland: Bool = true) {
        guard AppFeature.scratchpad.isAvailable, !modalInteractionActive else { return }
        if allowsIsland, NotchService.shared.showScratchpad() {
            if isVisible { hide() }
            return
        }
        if isVisible {
            focusText(requiresKeyWindow: false)
            return
        }
        isPreviewing = false
        marksExpanded = false
        isPinned = !closesOnClickOutside
        guard loadApplyingRetention() else {
            environment.showWarning(FeatureStrings.scratchpad(L10n.shared.language).loadFailed)
            return
        }
        let panel = ensurePanel()
        installMonitors(for: panel)
        // The pad keeps the spot and size the user gave it while the app
        // runs; it only re-centers when that spot is no longer on any screen.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        focusText(requiresKeyWindow: false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
    }

    /// The island edits the same document in place: load it (or the current
    /// copy) without showing the floating pad, and commit when it leaves.
    package func loadForEmbedding() -> Bool {
        guard AppFeature.scratchpad.isAvailable else { return false }
        marksExpanded = false
        return loadApplyingRetention()
    }

    /// The inline warning leaves with the pad or the island, so a final
    /// write that fails on the way out falls back to the HUD.
    package func commitEdits() {
        flushSave()
        if saveFailed {
            environment.showWarning(FeatureStrings.scratchpad(L10n.shared.language).saveFailed)
        }
    }

    package func hide() {
        guard panel != nil else { return }
        commitEdits()
        removeMonitors()
        panel?.orderOut(nil)
        isPinned = false
        isPreviewing = false
        modalInteractionActive = false
    }

    // MARK: - Document

    @discardableResult
    private func loadApplyingRetention() -> Bool {
        if hasLoaded, let document, document != store.lastSavedDocument {
            flushSave()
            return true
        }
        let defaults = UserDefaults.standard
        let defaultName = FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        let retention = ScratchpadRetention.sanitized(
            defaults.string(forKey: DefaultsKey.scratchpadRetention))
        do {
            let loaded = try store.load(defaultName: defaultName, retention: retention, now: Date())
            apply(loaded)
            hasLoaded = true
            return true
        } catch {
            hasLoaded = false
            return false
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSave() }
        pendingSave = work
        environment.schedule(0.8, work)
    }

    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasLoaded, let document else { return }
        _ = save(document)
    }

    /// A failed write keeps the edits in memory and retries on the next change.
    private func save(_ next: ScratchpadDocument) -> Bool {
        saveFailed = !store.save(next)
        return !saveFailed
    }

    private func apply(_ document: ScratchpadDocument, focus: Bool = false) {
        self.document = document
        pads = document.pads
        selectedPadID = document.selectedID
        let selectedText = document.pads.first(where: { $0.id == document.selectedID })?.text ?? ""
        isReplacingText = true
        text = selectedText
        isReplacingText = false
        if text.isEmpty { isPreviewing = false }
        if focus { focusText() }
    }

    package var canCreatePad: Bool { pads.count < ScratchpadDocument.maximumPadCount }
    package var canClosePad: Bool { pads.count > 1 }
    package var selectedPadName: String {
        pads.first(where: { $0.id == selectedPadID })?.name
            ?? FeatureStrings.scratchpad(L10n.shared.language).pageTitle
    }

    package func createPad(defaultName: String) {
        guard let document, let next = document.addingPad(defaultName: defaultName), save(next) else { return }
        apply(next, focus: true)
    }

    package func selectPad(_ id: UUID) {
        guard id != selectedPadID, let document, let next = document.selecting(id), save(next) else { return }
        apply(next, focus: true)
    }

    package func renamePad(_ id: UUID, to name: String) {
        guard let document, let next = document.renaming(id, to: name), save(next) else { return }
        apply(next, focus: id == selectedPadID)
    }

    @discardableResult
    package func closePad(_ id: UUID) -> Bool {
        guard let document, let next = document.removing(id), save(next) else { return false }
        apply(next, focus: true)
        return true
    }

    package func setModalInteractionActive(_ active: Bool) {
        modalInteractionActive = active
    }

    /// Settings export asks for a current document only when the user invokes
    /// it; normal app launch still performs no scratchpad content read.
    package func prepareForSettingsBackup() {
        if hasLoaded { flushSave() } else { loadApplyingRetention() }
    }

    /// Import intentionally replaces settings. Drop the in-memory document so
    /// the termination flush cannot overwrite the restored backup on the way out.
    package func prepareForSettingsRestore() {
        pendingSave?.cancel()
        pendingSave = nil
        hasLoaded = false
        document = nil
        store = environment.makeStore()
    }

    // MARK: - Actions

    package func copyAll() {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Clearing goes through the text view when it is up, so one Cmd+Z brings
    /// everything back while the pad stays open. The island passes its own
    /// editor for the same undo there.
    package func clear(through editor: NSTextView? = nil) {
        guard !text.isEmpty else { return }
        if let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) {
            // A live input-method composition holds a marked range into the
            // storage; replacing the whole text underneath it leaves that
            // range pointing at nothing. Commit it first.
            if textView.hasMarkedText() { textView.unmarkText() }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: full, replacementString: "") {
                textView.replaceCharacters(in: full, with: "")
                textView.didChangeText()
            }
        } else {
            text = ""
        }
        if isPreviewing {
            isPreviewing = false
            focusText()
        }
        flushSave()
    }

    /// The toolbar types the Markdown the user would have typed, through the
    /// text view so one Cmd+Z takes the whole mark back. The island passes its
    /// own editor for the same undo there.
    package func apply(_ mark: ScratchpadMark, through editor: NSTextView? = nil) {
        guard !isPreviewing else { return }
        guard let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) else { return }
        // A live input-method composition holds a marked range into the
        // storage; editing around it leaves that range pointing at nothing.
        if textView.hasMarkedText() { textView.unmarkText() }
        // Clicking a button takes first responder away from the editor, and a
        // selection set on a view that is not first responder does not show.
        textView.window?.makeFirstResponder(textView)
        let edit = ScratchpadSupport.edit(applying: mark,
                                          to: textView.string,
                                          selection: textView.selectedRange())
        guard (textView.string as NSString).substring(with: edit.range) != edit.replacement else { return }
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        flushSave()
    }

    package func toggleMarks() {
        marksExpanded.toggle()
    }

    package func togglePreview() {
        guard !text.isEmpty else { return }
        isPreviewing.toggle()
        if isPreviewing { marksExpanded = false }
        if isPreviewing {
            if let textView = textView, textView.window === panel { hideFindBar(in: textView) }
            panel?.makeFirstResponder(nil)
        } else {
            focusText()
        }
    }

    package func togglePin() {
        guard isVisible else { return }
        isPinned.toggle()
    }

    package func outsideClickPreferenceDidChange() {
        guard isVisible else { return }
        isPinned = !closesOnClickOutside
    }

    /// Activate for dialog input and return focus to the originating host.
    /// The island's dialog floats just above it: a sheet would move and
    /// reskin the borderless surface.
    package func exportText(suggestedName: String, from window: (any IslandWindowing)? = nil) {
        guard !text.isEmpty, !modalInteractionActive, let padID = selectedPadID,
              let sourceWindow = window ?? (panel as (any IslandWindowing)?), sourceWindow.isVisible else { return }
        modalInteractionActive = true
        flushSave()
        let dialog = environment.makeExportDialog(suggestedName)
        let environment = self.environment
        let complete: (NSApplication.ModalResponse, URL?) -> Void = { [weak self] response, url in
            self?.modalInteractionActive = false
            if response == .OK, let url {
                do {
                    // The island's dialog leaves the pad editable, so the file
                    // gets the pad as it is when the save is confirmed. A pad
                    // closed meanwhile is reported like any failed write.
                    guard let content = self?.document?.pads.first(where: { $0.id == padID })?.text else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    // A read-only volume or a full disk used to end here in
                    // silence, with the save panel closed and nothing written.
                    environment.showWarning(FeatureStrings.scratchpad(L10n.shared.language).exportFailed)
                }
            }
            // Dismissal restores the previous key window after completion.
            environment.main {
                if sourceWindow.isVisible { sourceWindow.makeKey() }
            }
        }
        if sourceWindow === environment.islandWindow() {
            // modalInteractionActive keeps the island's working surface
            // while its independent dialog is up.
            dialog.beginAbove(NSWindow.Level(rawValue: sourceWindow.level.rawValue + 1), complete)
            environment.activate()
            // Activation alone can leave the nonactivating island holding focus.
            dialog.makeKeyAndOrderFront()
        } else {
            environment.activate()
            environment.main {
                let (response, url) = dialog.runModal()
                complete(response, url)
            }
        }
    }

    // MARK: - Focus

    /// The editor registers itself while the pad's view is alive; the service
    /// only ever aims focus and the undoable clear at it.
    package func registerTextView(_ view: NSTextView) {
        textView = view
    }

    /// Document actions keep focus in their host. Only an explicit show may
    /// bring the floating pad forward while the island or another app is key.
    private func focusText(requiresKeyWindow: Bool = true) {
        guard let panel, panel.isVisible, !requiresKeyWindow || panel.isKeyWindow else { return }
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, panel.isKeyWindow,
                  let textView = self.textView else { return }
            panel.makeFirstResponder(textView)
            let end = NSRange(location: (textView.string as NSString).length, length: 0)
            textView.setSelectedRange(end)
            textView.scrollRangeToVisible(end)
        }
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default; the pad needs it so
    /// typing and Esc work without activating the app.
    private final class KeyableScratchpadPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableScratchpadPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                                           styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                           backing: .buffered,
                                           defer: false)
        panel.title = "Vitruvian"
        panel.isReleasedWhenClosed = false
        // Dragging inside the pad must select text, never move the window;
        // the header strip is the handle.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: 280, height: 220)
        panel.minSize = NSSize(width: 280, height: 220)
        panel.delegate = self
        let host = NSHostingController(rootView: ServiceViews.factory.scratchpad())
        // No preferred-size tracking: the pad is user-resizable and the view
        // fills whatever frame the panel has.
        host.sizingOptions = []
        panel.contentViewController = host
        // Assigning the content controller shrinks the window to the view's
        // minimum; restore the pad's starting size.
        panel.setContentSize(NSSize(width: 380, height: 300))
        center(panel)
        self.panel = panel
        return panel
    }

    package func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(280, frameSize.width), height: max(220, frameSize.height))
    }

    private func center(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.minY + (screen.height - size.height) * 0.58
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, min(y, screen.maxY - size.height - 16)),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    // MARK: - Monitors

    /// Esc always closes the pad, and so does a click anywhere outside it
    /// unless the user asked for a pad that stays put while working in other
    /// apps. The choice is read at click time, so flipping it in Settings
    /// takes effect on an open pad.
    private var closesOnClickOutside: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.scratchpadCloseOnClickOutside)
    }

    /// The export dialog is a click outside the pad by geometry, so saving to
    /// a file must never be what closes it.
    private var dismissesOnOutsideClick: Bool {
        ScratchpadSupport.dismissesOnOutsideClick(isPinned: isPinned,
                                                  exportModalActive: modalInteractionActive)
    }

    private func performFocusedTabShortcut(_ action: ScratchpadFocusedShortcut.Action) {
        switch action {
        case .createPad:
            createPad(defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle)
        case .closeSelectedPad:
            keyboardCloseSelectedPadSerial += 1
        case .hidePad:
            hide()
        case .find:
            performFind(.showFindInterface)
        case .findNext:
            performFind(.nextMatch)
        case .findPrevious:
            performFind(.previousMatch)
        }
    }

    /// The text view runs the find itself; it only has to be told which of the
    /// finder's actions was asked for, and that arrives as a sender's tag.
    package func performFind(_ action: NSTextFinder.Action, in editor: NSTextView? = nil) {
        guard let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) else { return }
        // Both hosts keep the editor at zero opacity while previewing. Finding
        // there would open a bar or select a match nobody can see, over a
        // source nobody is reading, so the pad comes back to the text first.
        let leftPreview = isPreviewing
        if isPreviewing {
            isPreviewing = false
        }
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        // Stepping through matches leaves the keyboard where it is, so
        // Command-G from the search field keeps typing in the field. Preview
        // took the keyboard from the text, so a step out of it gives it back.
        if action == .showFindInterface || leftPreview {
            textView.window?.makeFirstResponder(textView)
        }
        textView.performTextFinderAction(sender)
    }

    /// Both hosts draw the editor at zero opacity in preview, and its find bar
    /// with it, so the bar closes rather than keep a search nobody can see.
    package func hideFindBar(in editor: NSTextView) {
        guard editor.enclosingScrollView?.isFindBarVisible == true else { return }
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editor.performTextFinderAction(sender)
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                // Mid-composition Esc belongs to the input method, not the pad.
                if let textView = self.textView, textView.hasMarkedText() {
                    return event
                }
                // The find bar puts itself away on Esc and hands the keyboard
                // back to the text; the pad hides on the next one.
                if PlainTextEditor.findBarHasKeyboard(in: panel) { return event }
                self.hide()
                return nil
            }
            guard !self.modalInteractionActive else { return event }
            let commandOnly = event.modifierFlags
                .intersection([.command, .option, .control]) == .command
            let shift = event.modifierFlags.contains(.shift)
            if let action = ScratchpadFocusedShortcut.action(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                commandOnly: commandOnly,
                shift: shift,
                canCreatePad: self.canCreatePad,
                canClosePad: self.canClosePad
            ) {
                self.performFocusedTabShortcut(action)
                return nil
            }
            // At the tab limit Command-T still belongs to the pad, not the text.
            if commandOnly, !shift, event.charactersIgnoringModifiers?.lowercased() == "t" {
                return nil
            }
            return event
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               // Every key on the Accessibility Keyboard is a click outside this
               // panel. Dismissing on those makes the panel impossible to type into.
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hide()
            }
        }
    }

    /// A click on the pad's own edge (its resize border) still belongs to it.
    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
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
    }
}
