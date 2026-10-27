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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Courier")) {
                menuCoordinator.openSettings(.about)
            }
            .disabled(lifecycle.isLocked)
        }
        // 02 §3.1's Accounts…, Search…, and Lock App, after Settings.
        CommandGroup(after: .appSettings) {
            Button(String(localized: "Accounts…")) {
                menuCoordinator.openSettings(.accounts)
            }
            .disabled(lifecycle.isLocked)

            Button(String(localized: "Search…")) {
                let visible = bringMainWindowForward()
                search.toggle(visible: visible)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(lifecycle.isLocked)

            Divider()

            Button(lifecycle.isLocked ? String(localized: "Unlock Courier…") : String(localized: "Lock App")) {
                if lifecycle.isLocked {
                    _ = bringMainWindowForward()
                }
                Task { await menuCoordinator.lockOrUnlockApp() }
            }
        }
        CommandGroup(before: .appTermination) {
            Button(String(localized: "Minimize to Menu Bar"), action: menuCoordinator.minimizeToMenuBar)
                .keyboardShortcut("q", modifiers: [.command, .option])
        }
        // The first-run window has its own button; once a network is linked, this is the way to add another.
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Chat")) {
                _ = bringMainWindowForward()
                menuCoordinator.newChat()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(inbox.accounts.isEmpty || lifecycle.isLocked)

            Button(String(localized: "New Group or Blast…")) {
                _ = bringMainWindowForward()
                inbox.openStartNewChat(multiSelect: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(inbox.accounts.isEmpty || lifecycle.isLocked)

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
            Button(String(localized: "Close All"), action: menuCoordinator.closeAllWindows)
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
        // ⌘Z takes back my newest held message while the open chat has one (undo send); otherwise it undoes what
        // the toast says was just done, and otherwise it is the text's own undo. ⌘⇧Z sends the held messages now,
        // or else is the text's redo.
        CommandGroup(replacing: .undoRedo) {
            Button(String(localized: "Undo")) {
                if let composer = heldComposer {
                    Task { await composer.undoNewestHeld() }
                } else if inbox.toast?.canUndo == true {
                    Task { await inbox.undo() }
                } else {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(lifecycle.isLocked)
            Button(String(localized: "Redo")) {
                if let composer = heldComposer {
                    Task { await composer.sendHeldNow() }
                } else {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(lifecycle.isLocked)
        }
        CommandGroup(before: .sidebar) {
            Button(preferences.showSpaceBar ? String(localized: "Hide Space Bar") : String(localized: "Show Space Bar"),
                   action: menuCoordinator.toggleSpaceBar)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(lifecycle.isLocked)
            Button(menuCoordinator.isSidebarVisible ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar"),
                   action: menuCoordinator.toggleSidebar)
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(lifecycle.isLocked)
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
            Button(String(localized: "Next Chat"), action: inbox.selectNext)
                .keyboardShortcut("]", modifiers: .command)
                .disabled(lifecycle.isLocked)
            Button(String(localized: "Previous Chat"), action: inbox.selectPrevious)
                .keyboardShortcut("[", modifiers: .command)
                .disabled(lifecycle.isLocked)
            Button(String(localized: "Next Unread Chat"), action: inbox.selectNextUnread)
                .keyboardShortcut("u", modifiers: .command)
                .disabled(lifecycle.isLocked)
            Menu(String(localized: "Go to Chat")) {
                if !lifecycle.isLocked {
                    ForEach(Array(inbox.rows.prefix(9).enumerated()), id: \.element.id) { index, row in
                        Button(row.name.isEmpty ? String(localized: "Unnamed chat") : row.name) {
                            inbox.selectChat(number: index + 1)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                    }
                }
            }
            .disabled(lifecycle.isLocked)
            // The open chat's messages; with none open, every chat (as ⌘K). MainWindow also takes ⌘F, so that it
            // wins over the Edit menu's Find while typing.
            Button(String(localized: "Search in Chat…")) {
                _ = bringMainWindowForward()
                search.show(in: inbox.selectedRoomID)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(lifecycle.isLocked)
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
                menuCoordinator.openSettings(.reportProblem)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(lifecycle.isLocked)

            Button(String(localized: "Keyboard Shortcuts")) {
                menuCoordinator.openSettings(.shortcuts)
            }
            .keyboardShortcut("/", modifiers: .command)
            .disabled(lifecycle.isLocked)

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

    /// The composer with held messages in the open chat: the chat's, else the thread pane's; nil when none.
    private var heldComposer: ComposerModel? {
        [conversation.composer, conversation.thread.composer].first {
            !$0.heldIDs.isEmpty && $0.roomID != nil && $0.roomID == conversation.roomID
        }
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
            Task { await inbox.archive(!all(\.archived)) }
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(inbox.targets.isEmpty || (!all(\.archived) && all(\.pinned)))
        Button(inbox.toggleReadMarksRead ? String(localized: "Mark as Read") : String(localized: "Mark as Unread")) {
            Task { await inbox.toggleRead() }
        }
        .keyboardShortcut("u", modifiers: [.command, .shift])
        .disabled(!inbox.canToggleRead)
        Button(all(\.muted) ? String(localized: "Unmute Chat") : String(localized: "Mute Chat")) {
            Task { await inbox.toggleMute() }
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .disabled(inbox.targets.isEmpty)
        Button(all(\.pinned) ? String(localized: "Unpin") : String(localized: "Pin")) {
            Task { await inbox.togglePin() }
        }
        .keyboardShortcut("p", modifiers: .command)
        .disabled(inbox.targets.isEmpty)
        Button(String(localized: "Remind Me…")) { ui.remindPopover = true }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(inbox.targets.isEmpty)
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
            Task { await Confirm.archiveAllRead(inbox) }
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(!(byID["Archive all read chats"]?.isEnabled() ?? false))
        ForEach(["Archive all chats", "Archive all chats older than a week", "Mark all chats as read"], id: \.self) { id in
            if let command = byID[id] {
                Button(command.title + "…") { Confirm.run(command) }
                    .disabled(!command.isEnabled())
            }
        }
    }

    @ViewBuilder
    private var filters: some View {
        Button(String(localized: "Cycle Filters"), action: inbox.cycleFilter)
            .keyboardShortcut(.tab, modifiers: .option)
        Button(inbox.query.filters.contains(.unread) ? String(localized: "Show All Chats")
            : String(localized: "Show Only Unread Chats"), action: inbox.toggleUnreadFilter)
            .keyboardShortcut("y", modifiers: [.command, .shift])
        Button(String(localized: "Filter by Account…")) { ui.accountPopover = true }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(!spaces.spaces.contains { $0.kind == .account })
    }

    @ViewBuilder
    private var spaceKeys: some View {
        Button(String(localized: "Next Account"), action: spaces.selectNextAccount)
            .keyboardShortcut("]", modifiers: [.command, .shift])
        Button(String(localized: "Previous Account"), action: spaces.selectPreviousAccount)
            .keyboardShortcut("[", modifiers: [.command, .shift])
        Menu(String(localized: "Go to Space")) {
            ForEach(Array(spaces.visible.prefix(9).enumerated()), id: \.element.spaceID) { index, space in
                Button(SpaceLook.title(space)) { spaces.selectNumber(index + 1) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
    }
}
