// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The Chat menu: the inbox's keys, where the menu bar shows them. (⌘⌥↓ and ⌘⌥↑ also move between chats; they
/// are in MainWindow, since a menu item has one key.)
struct InboxCommands: Commands {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var login: LoginFlowModel

    var body: some Commands {
        // The first-run window has its own button; once a network is linked, this is the way to add another.
        CommandGroup(after: .newItem) {
            Button(String(localized: "Add a Network…"), action: inbox.addNetwork)
                .disabled(inbox.accounts.isEmpty || login.screen != .closed)
        }
        CommandMenu(String(localized: "Chat")) {
            Button(String(localized: "Next Chat"), action: inbox.selectNext)
                .keyboardShortcut("]", modifiers: .command)
            Button(String(localized: "Previous Chat"), action: inbox.selectPrevious)
                .keyboardShortcut("[", modifiers: .command)
            Button(String(localized: "Next Unread Chat"), action: inbox.selectNextUnread)
                .keyboardShortcut("u", modifiers: .command)
            Divider()
            Button(String(localized: "Mark as Read")) {
                Task { await inbox.toggleRead() }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!inbox.canToggleRead)
            Button(inbox.selectedRowIsMuted ? String(localized: "Unmute Chat") : String(localized: "Mute Chat")) {
                Task { await inbox.toggleMute() }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(inbox.selectedRow == nil)
        }
    }
}
