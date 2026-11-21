// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// A chat's right-click menu in the inbox (02 §3.4.1), as plain values: which items it has, in what order, and what
// each one does. The views draw it (a native NSMenu on a right-click, so the system's own "Ask Siri" item is left
// out; a SwiftUI menu under the hover button), and a test reads it without drawing anything. What the menu offers
// for a network comes from what that network can do, never from its name.

/// One thing the menu does. The view runs it; this only names it.
public enum ChatMenuCommand: Equatable, Sendable {
    case accept, decline
    case archive(Bool)
    case mute
    case markRead(Bool)
    case pin
    case searchInChat(roomID: String)
    case hide(Bool)
    case lowPriority(Bool)
    case toggleLabel(id: Int64, on: Bool)
    case newLabel
    case remind(presetTitle: String)
    case remindCustom
    case dismissReminder
    case openInNewWindow(roomID: String)
    case chatTheme(roomID: String, chatTitle: String)
    case copyChatName(String)
    case copyChatLink(String)
    case beginSelecting
    case mergeChat
    case editChat(roomID: String)
    case leaveGroup(roomID: String)
    case deleteChat(roomID: String)
    case reportSpam(roomID: String)
}

/// A key shown beside an item (the Chat menu's own).
public struct ChatMenuKey: Equatable, Sendable {
    public let key: String
    public let command: Bool
    public let shift: Bool

    public init(_ key: String, command: Bool = true, shift: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
    }
}

public struct ChatMenuItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public var help: String?
    /// What choosing it does; nil for a line that only says something (a greyed note).
    public var command: ChatMenuCommand?
    public var isEnabled = true
    /// Ticked, as a label the chats already have.
    public var isOn = false
    public var key: ChatMenuKey?
    public var isDestructive = false
    /// A submenu's items; empty for an item that does something.
    public var children: [ChatMenuItem] = []

    public init(_ id: String, _ title: String, help: String? = nil, command: ChatMenuCommand? = nil,
                isEnabled: Bool = true, isOn: Bool = false, key: ChatMenuKey? = nil, isDestructive: Bool = false,
                children: [ChatMenuItem] = []) {
        self.id = id
        self.title = title
        self.help = help
        self.command = command
        self.isEnabled = isEnabled
        self.isOn = isOn
        self.key = key
        self.isDestructive = isDestructive
        self.children = children
    }
}

/// What the menu is built from: the chats it was opened on, and what the app knows about them and their networks.
public struct ChatMenuContext {
    /// The chats the menu acts on, as loaded.
    public var rows: [InboxRow]
    public var accounts: [Account] = []
    public var isSelecting = false
    /// The menu shows its keys (a right-click menu does; the hover button's menu doesn't, since a key in a button's
    /// menu would take the Chat menu's while the pointer is on the row).
    public var showsKeys = true
    public var lowPriorityEntitled = true
    public var remindersEntitled = true
    /// The Remind Me suggestions, by title ("In an Hour", "Tomorrow").
    public var reminderPresets: [String] = []
    public var labels: [(id: Int64, title: String)] = []
    /// Search in this chat is on offer.
    public var canSearchInChat = false
    /// The chat a single row stands for is a merged chat.
    public var isMerged: (InboxRow) -> Bool = { _ in false }
    /// What the row's chat can do, as its network's room.features said; nil while that isn't known yet.
    public var features: (InboxRow) -> ChatFeatures? = { _ in nil }
    /// The name copied by Copy ▸ Chat Name: the title the row shows.
    public var chatName: (InboxRow) -> String = { $0.displayTitle }
    /// The network's own link to the chat, where the network has one (none of the engine's networks hands one over
    /// today, so Copy ▸ Link is left out until one does).
    public var chatLink: (InboxRow) -> String? = { _ in nil }
    /// The app can delete a chat from this menu (it has a place to ask first and a way to do it).
    public var canDeleteChats = true
    /// The app can leave a group from this menu.
    public var canLeaveGroups = false

    public init(rows: [InboxRow]) { self.rows = rows }
}

public enum ChatMenuPlan {
    /// The menu's sections, top to bottom; a divider goes between them.
    public static func sections(_ context: ChatMenuContext) -> [[ChatMenuItem]] {
        let rows = context.rows
        guard !rows.isEmpty else { return [] }
        let networks = Array(Set(rows.map(\.network)))
        let all = { (test: (InboxRow) -> Bool) in rows.allSatisfy(test) }
        let showsKeys = context.showsKeys
        func key(_ k: String, shift: Bool = false) -> ChatMenuKey? { showsKeys ? ChatMenuKey(k, shift: shift) : nil }
        var sections: [[ChatMenuItem]] = []

        // 1. Requests only.
        if rows.contains(where: \.request) {
            sections.append([
                ChatMenuItem("accept", String(localized: "Accept"), help: String(localized: "Moves the chat into your inbox."),
                             command: .accept),
                ChatMenuItem("decline", String(localized: "Decline"),
                             help: String(localized: "Hides the chat on this Mac. The person isn’t told."), command: .decline),
            ])
        }

        var main: [ChatMenuItem] = []
        // 2. Archive. A pinned chat can't be.
        if all(\.archived) {
            main.append(ChatMenuItem("archive", String(localized: "Unarchive"), command: .archive(false), key: key("e")))
        } else {
            let pinned = all(\.pinned)
            main.append(ChatMenuItem(
                "archive", String(localized: "Archive"),
                help: pinned ? String(localized: "Unpin a chat to archive it")
                    : String(localized: "Clears the chat from your inbox until someone writes again."),
                command: .archive(true), isEnabled: !pinned, key: key("e")))
        }

        // 3. Mute, and what else mutes it.
        let muting = !all(\.muted)
        main.append(ChatMenuItem(
            "mute", muting ? String(localized: "Mute") : String(localized: "Unmute"),
            help: SyncHelp.mute(muting, reach: SyncReach.of(.mute, networks: networks, accounts: context.accounts)),
            command: .mute, key: key("m", shift: true)))
        if let line = rows.lazy.compactMap(\.mutedLine).first {
            main.append(ChatMenuItem("mutedBy", line, isEnabled: false))
        }

        // 4. Read.
        if rows.contains(where: \.isUnread) {
            main.append(ChatMenuItem("read", String(localized: "Mark as Read"), command: .markRead(true), key: key("u", shift: true)))
        } else {
            main.append(ChatMenuItem("read", String(localized: "Mark as Unread"), help: SyncHelp.markUnread,
                                     command: .markRead(false), key: key("u", shift: true)))
        }

        // 5. Pin.
        let pinning = !all(\.pinned)
        main.append(ChatMenuItem(
            "pin", pinning ? String(localized: "Pin") : String(localized: "Unpin"),
            help: SyncHelp.pin(pinning, reach: SyncReach.of(.pin, networks: networks, accounts: context.accounts)),
            command: .pin, key: key("p")))

        // Search in this chat. One chat at a time.
        if rows.count == 1, context.canSearchInChat {
            main.append(ChatMenuItem("search", String(localized: "Search…"),
                                     help: String(localized: "Search the messages in this chat."),
                                     command: .searchInChat(roomID: rows[0].roomID), key: key("f")))
        }

        // 6. Hide.
        if all(\.hidden) {
            main.append(ChatMenuItem("hide", String(localized: "Unhide"), command: .hide(false)))
        } else {
            main.append(ChatMenuItem(
                "hide", String(localized: "Hide"),
                help: String(localized: "Takes the chat out of your inbox without leaving it. Filter ▸ Hidden shows it again."),
                command: .hide(true)))
        }

        // 7. Low priority (part of a plan; moving back never is).
        if all(\.lowPriority) {
            main.append(ChatMenuItem("lowPriority", String(localized: "Move to Inbox"), command: .lowPriority(false)))
        } else if context.lowPriorityEntitled {
            main.append(ChatMenuItem(
                "lowPriority", String(localized: "Move to Low Priority"),
                help: String(localized: "Keeps the chat out of your inbox, even when new messages arrive."),
                command: .lowPriority(true)))
        } else {
            main.append(ChatMenuItem("lowPriority", String(localized: "Available with a plan"), isEnabled: false))
        }

        // 8. Labels.
        var labelItems = context.labels.map { label in
            ChatMenuItem("label:\(label.id)", label.title,
                         command: .toggleLabel(id: label.id, on: !rows.allSatisfy { $0.labels.contains(label.id) }),
                         isOn: rows.allSatisfy { $0.labels.contains(label.id) })
        }
        labelItems.append(ChatMenuItem("newLabel", String(localized: "New Label…"), command: .newLabel))
        main.append(ChatMenuItem("label", String(localized: "Label"),
                                 help: String(localized: "A label puts the chat in a space of its own, on this Mac."),
                                 children: labelItems))

        // 9. Reminders.
        var remindItems: [ChatMenuItem] = []
        if context.remindersEntitled {
            remindItems += context.reminderPresets.map {
                ChatMenuItem("remind:\($0)", $0, command: .remind(presetTitle: $0))
            }
            remindItems.append(ChatMenuItem("remindCustom", String(localized: "Custom…"), command: .remindCustom))
        } else {
            remindItems.append(ChatMenuItem("remindPlan", String(localized: "Available with a plan"), isEnabled: false))
        }
        if rows.contains(where: { $0.reminder != nil }) {
            remindItems.append(ChatMenuItem("dismissReminder", String(localized: "Dismiss Reminder"), command: .dismissReminder))
        }
        main.append(ChatMenuItem("remind", String(localized: "Remind Me"),
                                 help: String(localized: "Brings the chat back to your inbox at the time you pick."),
                                 children: remindItems))

        // 18 of 02 §3.4.1, with Copy ▸: one chat at a time.
        if rows.count == 1 {
            let row = rows[0]
            main.append(ChatMenuItem("openInNewWindow", String(localized: "Open in New Window"),
                                     command: .openInNewWindow(roomID: row.roomID)))
            main.append(ChatMenuItem("chatTheme", String(localized: "Chat Theme…"),
                                     command: .chatTheme(roomID: row.roomID, chatTitle: row.name)))
            main.append(copyMenu(for: row, context))
        }
        sections.append(main)

        // 10. Begin Selecting.
        if !context.isSelecting {
            sections.append([ChatMenuItem("beginSelecting", String(localized: "Begin Selecting"), command: .beginSelecting)])
        }

        // 12. Single-chat Merge, Edit, Leave, Delete, and Report as Spam.
        if rows.count == 1 {
            let row = rows[0]
            var manage: [ChatMenuItem] = []
            if row.isDirect || !row.mergeID.isEmpty || row.roomID.hasPrefix("merge:") {
                manage.append(ChatMenuItem(
                    "merge",
                    context.isMerged(row) ? String(localized: "Edit Merged Chat…") : String(localized: "Merge with Another Chat…"),
                    command: .mergeChat))
            }
            manage.append(ChatMenuItem(
                "editChat", row.isDirect ? String(localized: "Edit Chat…") : String(localized: "Edit Group…"),
                command: .editChat(roomID: row.roomID)))
            let features = context.features(row)
            if context.canLeaveGroups, !row.isDirect, features?.canLeave == true {
                manage.append(ChatMenuItem("leaveGroup", String(localized: "Leave Group…"),
                                           command: .leaveGroup(roomID: row.roomID), isDestructive: true))
            }
            if offersDelete(row, features: features, context) {
                manage.append(ChatMenuItem("deleteChat", String(localized: "Delete Chat…"),
                                           command: .deleteChat(roomID: row.roomID), isDestructive: true))
            }
            manage.append(ChatMenuItem("reportSpam", String(localized: "Report as Spam…"),
                                       command: .reportSpam(roomID: row.roomID), isDestructive: true))
            sections.append(manage)
        }
        return sections
    }

    /// Copy ▸: the chat's name, and its link where the network gives one.
    static func copyMenu(for row: InboxRow, _ context: ChatMenuContext) -> ChatMenuItem {
        var items = [ChatMenuItem("copyName", String(localized: "Chat Name"), command: .copyChatName(context.chatName(row)))]
        if let link = context.chatLink(row), !link.isEmpty {
            items.append(ChatMenuItem("copyLink", String(localized: "Link"), command: .copyChatLink(link)))
        }
        return ChatMenuItem("copy", String(localized: "Copy"), children: items)
    }

    /// Delete Chat… is offered unless the chat's network has said it can't delete: a network that can (its features
    /// say so) shows it, and so does a network that hasn't answered yet, where choosing it finds out first and
    /// explains if the answer is no. Never a dead item for a network known to refuse. A merged chat is several chats,
    /// so it is deleted from its own chats, not here.
    static func offersDelete(_ row: InboxRow, features: ChatFeatures?, _ context: ChatMenuContext) -> Bool {
        guard context.canDeleteChats, features?.canDelete != false else { return false }
        return row.mergeID.isEmpty && !row.roomID.hasPrefix("merge:")
    }
}

/// Asking before a chat is deleted from the inbox's menu, and saying so when it can't be.
public enum ChatDeleteConfirmation {
    /// The question and what Delete does, as the engine does it: the chat is hidden on this Mac and deleted for the
    /// person on the network, and the others in the chat keep theirs. A network where deleting a group also leaves it
    /// (WhatsApp) says that too.
    public static func text(chatName: String, networkName: String?, features: ChatFeatures)
        -> (title: String, detail: String) {
        let trimmed = chatName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? String(localized: "this chat") : trimmed
        let place = networkName ?? String(localized: "its network")
        var detail = String(localized: "It’s hidden here and deleted for you on \(place). Others in the chat keep their copy.")
        if features.deleteLeavesGroup {
            detail += " " + String(localized: "You’ll also leave the group.")
        }
        return (String(localized: "Delete “\(name)”?"), detail)
    }

    /// What Delete Chat… says when the chat's network can't delete it, or the engine couldn't say.
    public static func unavailable(_ resolution: InboxModel.DeleteResolution, networkName: String?) -> String {
        let place = networkName ?? String(localized: "This network")
        switch resolution {
        case .unsupported:
            return String(localized: "\(place) doesn’t let Vitruvian Courier delete this chat.")
        case .unknown:
            return String(localized: "Couldn’t check whether \(place) can delete this chat. Try again in a moment.")
        case .ask:
            return ""
        }
    }
}

/// Edit Chat… and Report as Spam… from the inbox's menu: what Chat Info's buttons do for the open chat, for the chat
/// that was right-clicked. Their sheets are hosted by the window (`ChatRoomSheets`), so neither opens the chat: opening
/// it would mark it read, and that sends the people in it a read receipt, which Report as Spam on a stranger's chat
/// must never do.
@MainActor
public enum ChatRoomActions {
    public static func editChat(roomID: String, conversation: ConversationModel) async {
        await conversation.beginEditChat(roomID: roomID)
    }

    public static func reportSpam(roomID: String, conversation: ConversationModel) async {
        await conversation.beginReportSpam(roomID: roomID)
    }
}
