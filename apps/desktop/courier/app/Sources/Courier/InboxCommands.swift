// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// The Chat menu: the inbox's keys, where the menu bar shows them; the View menu's space bar and labels; Undo,
/// which undoes the toast's action while it shows; and search: Search… (⌘K) in the Courier menu, Search in Chat…
/// (⌘F) in the Chat menu. (⌘⌥↓ and ⌘⌥↑ also move between chats; they are in MainWindow,
/// since a menu item has one key. E, x, ⇧J, ⇧K and ⌘A work on the list itself: see InboxList.)
struct InboxCommands: Commands {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var login: LoginFlowModel
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var preferences: InboxPreferences
    let ui: InboxUI
    @ObservedObject var search: SearchModel
    /// The open chat: ⌘Z and ⌘⇧Z act on its held (undo send) messages while it has some. (⌘C on a selected message
    /// is MainWindow's.)
    let conversation: ConversationModel
    @ObservedObject var lifecycle: SystemLifecycleModel
    @ObservedObject var menuCoordinator: AppMenuCoordinator
    let minimizeToMenuBar: @MainActor () -> Void
    @ObservedObject var hotkeys: HotkeyRegistry = HotkeyRegistry()
    @ObservedObject var hotkeyDispatcher: HotkeyDispatcher
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Courier")) {
                menuCoordinator.openSettings(.about)
            }
            .disabled(lifecycle.isLocked)
        }
        CommandGroup(replacing: .appSettings) {
            Button(String(localized: "Settings…")) {
                dispatch("Settings")
            }
            .registryShortcut("Settings", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Settings"))
        }
        // 02 §3.1's Accounts…, Search…, and Lock App, after Settings.
        CommandGroup(after: .appSettings) {
            Button(String(localized: "Accounts…")) {
                menuCoordinator.openSettings(.accounts)
            }
            .disabled(lifecycle.isLocked)

            Button(String(localized: "Search…")) {
                dispatch("Search")
            }
            .registryShortcut("Search", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Search"))

            Button(String(localized: "Focus Courier")) {
                dispatch("Focus App")
            }
            .registryShortcut("Focus App", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Focus App"))

            Button(String(localized: "Focus Courier and Command Bar")) {
                dispatch("Focus App and Command Bar")
            }
            .registryShortcut("Focus App and Command Bar", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Focus App and Command Bar"))

            Divider()

            Button(lifecycle.isLocked ? String(localized: "Unlock Courier…") : String(localized: "Lock App")) {
                if lifecycle.isLocked {
                    _ = bringMainWindowForward()
                }
                Task { await menuCoordinator.lockOrUnlockApp() }
            }
        }
        CommandGroup(before: .appTermination) {
            Button(String(localized: "Minimize to Menu Bar")) {
                dispatch("Minimize To Menu Bar")
            }
            .registryShortcut("Minimize To Menu Bar", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Minimize To Menu Bar"))
        }
        CommandGroup(replacing: .appTermination) {
            Button(String(localized: "Quit Courier")) {
                dispatch("Quit App")
            }
            .registryShortcut("Quit App", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Quit App"))
        }
        // The first-run window has its own button; once a network is linked, this is the way to add another.
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Chat")) {
                dispatch("Chat: Start New")
            }
            .registryShortcut("Chat: Start New", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Chat: Start New"))

            Button(String(localized: "New Group or Blast…")) {
                dispatch("Chat: Create New Group")
            }
            .registryShortcut("Chat: Create New Group", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Chat: Create New Group"))

            Button(String(localized: "Open Chat in New Window"), action: menuCoordinator.openChatInNewWindow)
                .disabled(conversation.roomID == nil || lifecycle.isLocked)

            Divider()

            Button(String(localized: "Add a Network…"), action: inbox.addNetwork)
                .disabled(inbox.accounts.isEmpty || login.screen != .closed || lifecycle.isLocked)
        }
        CommandGroup(after: .importExport) {
            Divider()
            Button(String(localized: "Close Window"), action: menuCoordinator.closeWindow)
                .keyboardShortcut("w", modifiers: .command)
                .disabled(lifecycle.isLocked)
            Button(String(localized: "Close All"), action: menuCoordinator.closeAllWindows)
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(lifecycle.isLocked)
        }
        // ⌘Z takes back my newest held message while the open chat has one (undo send); otherwise it undoes what
        // the toast says was just done, and otherwise it is the text's own undo. ⌘⇧Z sends the held messages now,
        // or else is the text's redo.
        CommandGroup(replacing: .undoRedo) {
            Button(String(localized: "Undo")) {
                dispatch("Undo Pending Send")
            }
            .registryShortcut("Undo Pending Send", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Undo Pending Send"))
            Button(String(localized: "Redo")) {
                if let composer = hotkeyDispatcher.heldComposer {
                    Task { await composer.sendHeldNow() }
                } else {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(lifecycle.isLocked)
        }
        CommandGroup(before: .sidebar) {
            Button(preferences.showSpaceBar ? String(localized: "Hide Space Bar") : String(localized: "Show Space Bar")) {
                dispatch("Toggle Space Bar")
            }
            .registryShortcut("Toggle Space Bar", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Toggle Space Bar"))
            Button(menuCoordinator.isSidebarVisible ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar")) {
                dispatch("Toggle Sidebar")
            }
            .registryShortcut("Toggle Sidebar", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Toggle Sidebar"))
            Button(conversation.incognitoIsOn ? String(localized: "Turn Off Incognito Mode") : String(localized: "Turn On Incognito Mode")) {
                dispatch("Toggle Incognito Mode")
            }
            .registryShortcut("Toggle Incognito Mode", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Toggle Incognito Mode"))
            Button(String(localized: "Edit Spaces…")) {
                spaces.isEditing = true
                openWindow(id: WindowID.editSpaces)
            }
            .disabled(lifecycle.isLocked)
            Button(String(localized: "Edit Labels…")) { openWindow(id: WindowID.editLabels) }
                .disabled(lifecycle.isLocked)
            Button(String(localized: "New Label…")) {
                openWindow(id: WindowID.label, value: LabelWindowTarget.new(applyTo: []))
            }
            .disabled(lifecycle.isLocked)
            Divider()
        }
        CommandMenu(String(localized: "Chat")) {
            Button(String(localized: "Next Chat")) { dispatch("Select Next Chat") }
                .registryShortcut("Select Next Chat", in: hotkeys)
                .disabled(!hotkeyDispatcher.canPerform("Select Next Chat"))
            Button(String(localized: "Previous Chat")) { dispatch("Select Previous Chat") }
                .registryShortcut("Select Previous Chat", in: hotkeys)
                .disabled(!hotkeyDispatcher.canPerform("Select Previous Chat"))
            Button(String(localized: "Next Unread Chat")) { dispatch("Select Next Unread Chat") }
                .registryShortcut("Select Next Unread Chat", in: hotkeys)
                .disabled(!hotkeyDispatcher.canPerform("Select Next Unread Chat"))
            Button(String(localized: "Previous Viewed Chat")) { dispatch("History: Previous Chat") }
                .registryShortcut("History: Previous Chat", in: hotkeys)
                .disabled(!hotkeyDispatcher.canPerform("History: Previous Chat"))
            Button(String(localized: "Next Viewed Chat")) { dispatch("History: Next Chat") }
                .registryShortcut("History: Next Chat", in: hotkeys)
                .disabled(!hotkeyDispatcher.canPerform("History: Next Chat"))
            Menu(String(localized: "Go to Chat")) {
                if hotkeyDispatcher.canPerform("Switch First 9 Chats Modifier") {
                    let chatMod = modifierFlags(for: "Switch First 9 Chats Modifier", fallback: .control)
                    ForEach(Array(inbox.rows.prefix(9).enumerated()), id: \.element.id) { index, row in
                        Button(row.name.isEmpty ? String(localized: "Unnamed chat") : row.name) {
                            _ = hotkeyDispatcher.performSwitchChat(number: index + 1)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: chatMod)
                    }
                }
            }
            .disabled(!hotkeyDispatcher.canPerform("Switch First 9 Chats Modifier"))
            // The open chat's messages; with none open, every chat (as ⌘K). MainWindow also takes ⌘F, so that it
            // wins over the Edit menu's Find while typing.
            Button(String(localized: "Search in Chat…")) {
                dispatch("Search: Room")
            }
            .registryShortcut("Search: Room", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Search: Room"))
            Divider()
            actions
                .disabled(lifecycle.isLocked)
            Divider()
            selecting
                .disabled(lifecycle.isLocked)
            Divider()
            sweeps
                .disabled(lifecycle.isLocked)
            Divider()
            filters
                .disabled(lifecycle.isLocked)
            Divider()
            spaceKeys
                .disabled(lifecycle.isLocked)
        }
        CommandGroup(after: .help) {
            Button(String(localized: "Report a Problem…")) {
                dispatch("Report a Problem")
            }
            .registryShortcut("Report a Problem", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Report a Problem"))

            Button(String(localized: "Keyboard Shortcuts")) {
                dispatch("Keyboard Shortcuts")
            }
            .registryShortcut("Keyboard Shortcuts", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Keyboard Shortcuts"))

            Button(String(localized: "Privacy & Security")) {
                menuCoordinator.openSettings(.privacy)
            }
            .disabled(lifecycle.isLocked)

            Button(String(localized: "Changelog")) {
                menuCoordinator.openSettings(.changelog)
            }
            .disabled(lifecycle.isLocked)
        }
    }

    private func dispatch(_ id: String) {
        hotkeyDispatcher.bringMainWindowForward = { [ui, openWindow] in
            guard !ui.isMainWindowKey else { return true }
            NSApp.activate()
            openWindow(id: "main")
            return false
        }
        _ = hotkeyDispatcher.perform(id)
    }

    private func modifierFlags(for id: String, fallback: EventModifiers) -> EventModifiers {
        guard let chord = hotkeys.primaryChord(for: id) else { return fallback }
        var mods: EventModifiers = []
        if chord.command { mods.insert(.command) }
        if chord.shift { mods.insert(.shift) }
        if chord.option { mods.insert(.option) }
        if chord.control { mods.insert(.control) }
        return mods.isEmpty ? fallback : mods
    }

    /// The panel is drawn over the main window, so search first brings it forward (making it again if it was
    /// closed). True when it already was in front.
    private func bringMainWindowForward() -> Bool {
        guard !ui.isMainWindowKey else { return true }
        NSApp.activate()
        openWindow(id: "main")
        return false
    }

    // MARK: The open chat (or the chats selected)

    @ViewBuilder
    private var actions: some View {
        let rows = inbox.targetRows()
        let all = { (test: (InboxRow) -> Bool) in !rows.isEmpty && rows.allSatisfy(test) }
        Button(all(\.archived) ? String(localized: "Unarchive") : String(localized: "Archive")) {
            dispatch("Chat: Toggle Archive")
        }
        .registryShortcut("Chat: Toggle Archive", in: hotkeys)
        .disabled(!hotkeyDispatcher.canPerform("Chat: Toggle Archive"))
        Button(inbox.toggleReadMarksRead ? String(localized: "Mark as Read") : String(localized: "Mark as Unread")) {
            dispatch("Chat: Toggle Mark As Read")
        }
        .registryShortcut("Chat: Toggle Mark As Read", in: hotkeys)
        .disabled(!hotkeyDispatcher.canPerform("Chat: Toggle Mark As Read"))
        Button(all(\.muted) ? String(localized: "Unmute Chat") : String(localized: "Mute Chat")) {
            dispatch("Chat: Toggle Mute")
        }
        .registryShortcut("Chat: Toggle Mute", in: hotkeys)
        .disabled(!hotkeyDispatcher.canPerform("Chat: Toggle Mute"))
        Button(all(\.pinned) ? String(localized: "Unpin") : String(localized: "Pin")) {
            dispatch("Chat: Toggle Pin")
        }
        .registryShortcut("Chat: Toggle Pin", in: hotkeys)
        .disabled(!hotkeyDispatcher.canPerform("Chat: Toggle Pin"))
        Button(String(localized: "Remind Me…")) {
            dispatch("Remind Later")
        }
        .registryShortcut("Remind Later", in: hotkeys)
        .disabled(!hotkeyDispatcher.canPerform("Remind Later"))
    }

    @ViewBuilder
    private var selecting: some View {
        Button(inbox.isSelecting ? String(localized: "End Selecting") : String(localized: "Begin Selecting")) {
            if inbox.isSelecting { inbox.endSelecting() } else { inbox.beginSelecting() }
        }
        .disabled(!inbox.isSelecting && inbox.rows.isEmpty)
        Button(String(localized: "Select All Chats"), action: inbox.selectAll)
            .disabled(inbox.rows.isEmpty)
    }

    /// The four bulk commands, each asking first (Ruling 26). ⌘⇧E counts what it would archive.
    @ViewBuilder
    private var sweeps: some View {
        let commands = CommandSet.inbox(inbox, spaces)
        let byID = Dictionary(commands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        Button(String(localized: "Archive All Read Chats…")) {
            dispatch("Chat: Archive All Read")
        }
        .registryShortcut("Chat: Archive All Read", in: hotkeys)
        .disabled(!hotkeyDispatcher.canPerform("Chat: Archive All Read"))
        ForEach(["Archive all chats", "Archive all chats older than a week", "Mark all chats as read"], id: \.self) { id in
            if let command = byID[id] {
                Button(command.title + "…") { Confirm.run(command) }
                    .disabled(!command.isEnabled() || lifecycle.isLocked)
            }
        }
    }

    @ViewBuilder
    private var filters: some View {
        Button(String(localized: "Cycle Filters")) { dispatch("Cycle Filters") }
            .registryShortcut("Cycle Filters", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Cycle Filters"))
        Button(String(localized: "Filter: All")) { dispatch("Filter: All") }
            .registryShortcut("Filter: All", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Filter: All"))
        Button(inbox.query.filters.contains(.unread) ? String(localized: "Show All Chats")
            : String(localized: "Show Only Unread Chats")) { dispatch("Filter: Unread") }
            .registryShortcut("Filter: Unread", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Filter: Unread"))
        Button(String(localized: "Filter: Drafts")) { dispatch("Filter: Drafts") }
            .registryShortcut("Filter: Drafts", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Filter: Drafts"))
        Button(String(localized: "Filter: Unanswered")) { dispatch("Filter: Unanswered") }
            .registryShortcut("Filter: Unanswered", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Filter: Unanswered"))
        Button(String(localized: "Filter: DMs")) { dispatch("Filter: DMs") }
            .registryShortcut("Filter: DMs", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Filter: DMs"))
        Button(String(localized: "Filter: Groups")) { dispatch("Filter: Groups") }
            .registryShortcut("Filter: Groups", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Filter: Groups"))
        Button(String(localized: "Filter by Account…")) { dispatch("Filter By Account") }
            .registryShortcut("Filter By Account", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Filter By Account"))
    }

    @ViewBuilder
    private var spaceKeys: some View {
        Button(String(localized: "Next Account")) { dispatch("Select Next Account") }
            .registryShortcut("Select Next Account", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Select Next Account"))
        Button(String(localized: "Previous Account")) { dispatch("Select Previous Account") }
            .registryShortcut("Select Previous Account", in: hotkeys)
            .disabled(!hotkeyDispatcher.canPerform("Select Previous Account"))
        Menu(String(localized: "Go to Space")) {
            if hotkeyDispatcher.canPerform("Switch First 9 Spaces Modifier") {
                let spaceMod = modifierFlags(for: "Switch First 9 Spaces Modifier", fallback: .command)
                ForEach(Array(spaces.visible.prefix(9).enumerated()), id: \.element.spaceID) { index, space in
                    Button(SpaceLook.title(space)) {
                        _ = hotkeyDispatcher.performSwitchSpace(number: index + 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: spaceMod)
                }
            }
        }
        .disabled(!hotkeyDispatcher.canPerform("Switch First 9 Spaces Modifier"))
    }
}
