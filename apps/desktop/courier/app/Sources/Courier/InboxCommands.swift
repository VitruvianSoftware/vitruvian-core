// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// The Chat menu: the inbox's keys, where the menu bar shows them; the View menu's space bar and labels; and Undo,
/// which undoes the toast's action while it shows. (⌘⌥↓ and ⌘⌥↑ also move between chats; they are in MainWindow,
/// since a menu item has one key. E, x, ⇧J, ⇧K and ⌘A work on the list itself: see InboxList.)
struct InboxCommands: Commands {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var login: LoginFlowModel
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var preferences: InboxPreferences
    let ui: InboxUI
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // The first-run window has its own button; once a network is linked, this is the way to add another.
        CommandGroup(after: .newItem) {
            Button(String(localized: "Add a Network…"), action: inbox.addNetwork)
                .disabled(inbox.accounts.isEmpty || login.screen != .closed)
        }
        // ⌘Z undoes what the toast says was just done; otherwise it is the text's own undo.
        CommandGroup(replacing: .undoRedo) {
            Button(String(localized: "Undo")) {
                if inbox.toast?.canUndo == true {
                    Task { await inbox.undo() }
                } else {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            Button(String(localized: "Redo")) { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(before: .sidebar) {
            Button(preferences.showSpaceBar ? String(localized: "Hide Space Bar") : String(localized: "Show Space Bar")) {
                preferences.showSpaceBar.toggle()
            }
            .keyboardShortcut("s", modifiers: .command)
            Button(String(localized: "Edit Spaces…")) {
                spaces.isEditing = true
                openWindow(id: WindowID.editSpaces)
            }
            Button(String(localized: "Edit Labels…")) { openWindow(id: WindowID.editLabels) }
            Button(String(localized: "New Label…")) {
                openWindow(id: WindowID.label, value: LabelWindowTarget.new(applyTo: []))
            }
            Divider()
        }
        CommandMenu(String(localized: "Chat")) {
            Button(String(localized: "Next Chat"), action: inbox.selectNext)
                .keyboardShortcut("]", modifiers: .command)
            Button(String(localized: "Previous Chat"), action: inbox.selectPrevious)
                .keyboardShortcut("[", modifiers: .command)
            Button(String(localized: "Next Unread Chat"), action: inbox.selectNextUnread)
                .keyboardShortcut("u", modifiers: .command)
            Menu(String(localized: "Go to Chat")) {
                ForEach(Array(inbox.rows.prefix(9).enumerated()), id: \.element.roomID) { index, row in
                    Button(row.name.isEmpty ? String(localized: "Unnamed chat") : row.name) {
                        inbox.selectChat(number: index + 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
                }
            }
            Divider()
            actions
            Divider()
            selecting
            Divider()
            sweeps
            Divider()
            filters
            Divider()
            spaceKeys
        }
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
        .disabled(rows.isEmpty || (!all(\.archived) && all(\.pinned)))
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
            Task { await Confirm.archiveAllRead(inbox, command: byID["Archive all read chats"]) }
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
