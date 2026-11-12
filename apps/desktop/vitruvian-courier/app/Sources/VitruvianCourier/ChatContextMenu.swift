// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// A chat's right-click menu (02 §3.4.1, the 4.1 part), in its order. It acts on `ids`, the chats it was opened
/// on; nil is the chats selected. Each state says in its help what it does and, for pin and mute, whether the
/// phone hears it too.
struct ChatContextMenu: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    let ui: InboxUI
    let ids: [String]?
    /// Whether the items show their keys. A right-click menu does; the hover button's menu doesn't, since a menu
    /// in a button would take those keys from the Chat menu while the pointer is on the row.
    var showsKeys = true
    var features: ChatFeatures? = nil
    var onEditChat: ((String) -> Void)? = nil
    var onLeaveGroup: ((String) -> Void)? = nil
    var onDeleteChat: ((String) -> Void)? = nil
    var onReportSpam: ((String) -> Void)? = nil
    var onOpenInNewWindow: ((String) -> Void)? = nil
    var onCustomizeChatTheme: ((String) -> Void)? = nil
    @Environment(\.searchInChat) private var searchInChat
    @Environment(\.openDetachedWindow) private var openDetachedWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let rows = inbox.targetRows(ids)
        let networks = Array(Set(rows.map(\.network)))
        let all = { (test: (InboxRow) -> Bool) in !rows.isEmpty && rows.allSatisfy(test) }

        // 1. Requests only.
        if rows.contains(where: \.request) {
            Button(String(localized: "Accept")) { Task { await inbox.acceptRequest(ids: ids) } }
                .help(String(localized: "Moves the chat into your inbox."))
            Button(String(localized: "Decline")) { Task { await inbox.declineRequest(ids: ids) } }
                .help(String(localized: "Hides the chat on this Mac. The person isn’t told."))
            Divider()
        }

        // 2. Archive. A pinned chat can't be.
        if all(\.archived) {
            Button(String(localized: "Unarchive")) { Task { await inbox.archive(false, ids: ids) } }
                .shortcut("e", .command, if: showsKeys)
        } else {
            Button(String(localized: "Archive")) { Task { await inbox.archive(true, ids: ids) } }
                .shortcut("e", .command, if: showsKeys)
                .disabled(all(\.pinned))
                .help(all(\.pinned) ? String(localized: "Unpin a chat to archive it")
                    : String(localized: "Clears the chat from your inbox until someone writes again."))
        }

        // 3. Mute, and what else mutes it.
        let muting = !all(\.muted)
        Button(muting ? String(localized: "Mute") : String(localized: "Unmute")) {
            Task { await inbox.toggleMute(ids: ids) }
        }
        .shortcut("m", [.command, .shift], if: showsKeys)
        .help(SyncHelp.mute(muting, reach: SyncReach.of(.mute, networks: networks, accounts: inbox.accounts)))
        if let line = rows.lazy.compactMap(\.mutedLine).first {
            Text(line)
        }

        // 4. Read.
        if rows.contains(where: \.isUnread) {
            Button(String(localized: "Mark as Read")) { Task { await inbox.setRead(true, ids: ids) } }
                .shortcut("u", [.command, .shift], if: showsKeys)
        } else {
            Button(String(localized: "Mark as Unread")) { Task { await inbox.setRead(false, ids: ids) } }
                .shortcut("u", [.command, .shift], if: showsKeys)
                .help(SyncHelp.markUnread)
        }

        // 5. Pin.
        let pinning = !all(\.pinned)
        Button(pinning ? String(localized: "Pin") : String(localized: "Unpin")) {
            Task { await inbox.togglePin(ids: ids) }
        }
        .shortcut("p", .command, if: showsKeys)
        .help(SyncHelp.pin(pinning, reach: SyncReach.of(.pin, networks: networks, accounts: inbox.accounts)))

        // 11 of 02 §3.4.1, which sits here: search in this chat. One chat at a time.
        if rows.count == 1, let searchInChat {
            let roomID = rows[0].roomID
            Button(String(localized: "Search…")) { searchInChat(roomID) }
                .shortcut("f", .command, if: showsKeys)
                .help(String(localized: "Search the messages in this chat."))
        }

        // 6. Hide.
        if all(\.hidden) {
            Button(String(localized: "Unhide")) { Task { await inbox.setHidden(false, ids: ids) } }
        } else {
            Button(String(localized: "Hide")) { Task { await inbox.setHidden(true, ids: ids) } }
                .help(String(localized: "Takes the chat out of your inbox without leaving it. Filter ▸ Hidden shows it again."))
        }

        // 7. Low priority (part of a plan; moving back never is).
        if all(\.lowPriority) {
            Button(String(localized: "Move to Inbox")) { Task { await inbox.setLowPriority(false, ids: ids) } }
        } else if inbox.isEntitled(.lowPriority) {
            Button(String(localized: "Move to Low Priority")) { Task { await inbox.setLowPriority(true, ids: ids) } }
                .help(String(localized: "Keeps the chat out of your inbox, even when new messages arrive."))
        } else {
            Button(String(localized: "Available with a plan")) {}
                .disabled(true)
        }

        // 8. Labels.
        LabelMenu(inbox: inbox, spaces: spaces, ids: ids, rows: rows)

        // 9. Reminders.
        RemindMeMenu(inbox: inbox, ui: ui, ids: ids)

        // 18 of 02 §3.4.1: Open in New Window (single chat) and Chat Theme…
        if rows.count == 1 {
            let roomID = rows[0].roomID
            let chatTitle = rows[0].name
            Button(String(localized: "Open in New Window")) {
                if let onOpenInNewWindow {
                    onOpenInNewWindow(roomID)
                } else {
                    openDetachedWindow?(.chat(roomID: roomID))
                }
            }
            Button(String(localized: "Chat Theme…")) {
                if let onCustomizeChatTheme {
                    onCustomizeChatTheme(roomID)
                } else {
                    openWindow(id: WindowID.chatTheme, value: ChatThemeWindowTarget(roomID: roomID, chatTitle: chatTitle))
                }
            }
        }

        // 10.
        if !inbox.isSelecting {
            Divider()
            Button(String(localized: "Begin Selecting")) {
                // Selecting starts with the chats right-clicked, not the open one.
                inbox.beginSelecting()
                if let ids {
                    for id in inbox.selection where !ids.contains(id) { inbox.toggleSelected(id) }
                    for id in ids where !inbox.selection.contains(id) { inbox.toggleSelected(id) }
                }
            }
        }

        // 12. Single-chat Edit, Merge, Leave, Delete, and Report as Spam (Tasks 10 & 11).
        if rows.count == 1 {
            Divider()
            if rows[0].isDirect || !rows[0].mergeID.isEmpty || rows[0].roomID.hasPrefix("merge:") {
                Button(
                    inbox.mergedChat(for: rows[0]) == nil
                        ? String(localized: "Merge with Another Chat…")
                        : String(localized: "Edit Merged Chat…")
                ) {
                    inbox.openMergeEditor(for: rows[0])
                }
            }
            ChatRoomManagementMenuSection(
                row: rows[0],
                features: features,
                onEditChat: onEditChat,
                onLeaveGroup: onLeaveGroup,
                onDeleteChat: onDeleteChat,
                onReportSpam: onReportSpam
            )
        }
    }
}

/// Single-chat room management actions in `ChatContextMenu` (Task 10):
/// **Edit Chat…** / **Edit Group…**, **Leave Group…** (when `!row.isDirect && features.canLeave`),
/// **Delete Chat…** (when `features.canDelete`), and **Report as Spam…**.
public struct ChatRoomManagementMenuSection: View {
    public let row: InboxRow
    public var features: ChatFeatures?
    public var onEditChat: ((String) -> Void)?
    public var onLeaveGroup: ((String) -> Void)?
    public var onDeleteChat: ((String) -> Void)?
    public var onReportSpam: ((String) -> Void)?

    public init(
        row: InboxRow,
        features: ChatFeatures? = nil,
        onEditChat: ((String) -> Void)? = nil,
        onLeaveGroup: ((String) -> Void)? = nil,
        onDeleteChat: ((String) -> Void)? = nil,
        onReportSpam: ((String) -> Void)? = nil
    ) {
        self.row = row
        self.features = features
        self.onEditChat = onEditChat
        self.onLeaveGroup = onLeaveGroup
        self.onDeleteChat = onDeleteChat
        self.onReportSpam = onReportSpam
    }

    public var body: some View {
        Button(row.isDirect ? String(localized: "Edit Chat…") : String(localized: "Edit Group…")) {
            onEditChat?(row.roomID)
        }
        if let features, !row.isDirect, features.canLeave {
            Button(String(localized: "Leave Group…"), role: .destructive) {
                onLeaveGroup?(row.roomID)
            }
        }
        if let features, features.canDelete {
            Button(String(localized: "Delete Chat…"), role: .destructive) {
                onDeleteChat?(row.roomID)
            }
        }
        Button(String(localized: "Report as Spam…"), role: .destructive) {
            onReportSpam?(row.roomID)
        }
    }
}

/// Label ▸: each label, ticked when every chat has it, and New Label….
struct LabelMenu: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    let ids: [String]?
    let rows: [InboxRow]
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu(String(localized: "Label")) {
            ForEach(spaces.spaces.filter { $0.kind == .label }) { label in
                let has = !rows.isEmpty && rows.allSatisfy { $0.labels.contains(label.labelID) }
                Toggle(label.title, isOn: Binding(get: { has }, set: { on in
                    Task { await inbox.setLabel(label.labelID, on: on, ids: ids) }
                }))
            }
            Divider()
            Button(String(localized: "New Label…")) {
                openWindow(id: WindowID.label, value: LabelWindowTarget.new(applyTo: ids ?? inbox.targets))
            }
        }
        .help(String(localized: "A label puts the chat in a space of its own, on this Mac."))
    }
}

/// Asking before doing something to many chats, and saying what went wrong.
@MainActor
enum Confirm {
    /// A yes-or-no question: true for `action`, false for Cancel.
    static func ask(_ message: String, detail: String? = nil, action: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail ?? ""
        let button = alert.addButton(withTitle: action)
        button.hasDestructiveAction = destructive
        alert.addButton(withTitle: String(localized: "Cancel"))
        return AppLockGate.shared.runAlertModal(alert) == .alertFirstButtonReturn
    }

    static func tell(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: String(localized: "OK"))
        _ = AppLockGate.shared.runAlertModal(alert)
    }

    /// Runs a command, after its confirmation when it has one (a bulk command): only an OK runs it.
    static func run(_ command: CourierCommand) {
        guard command.isEnabled() else { return }
        if let question = command.confirmation {
            guard ask(question, action: command.title) else { return }
        }
        command.run()
    }

    /// ⌘⇧E: "Archive N read chats?" for the space shown, counted as below.
    static func archiveAllRead(_ inbox: InboxModel) async {
        guard inbox.canArchiveAll else { return }
        await sweep(inbox, readOnly: true)
    }

    /// An archive-all: counts it with a dry run of the same sweep, asks "Archive N chats?" ("Archive N read
    /// chats?"), and archives only on OK, with Undo in the toast. With none to archive it beeps; when the count
    /// can't be had it asks without one. `space` nil is the space shown.
    static func sweep(_ inbox: InboxModel, readOnly: Bool, olderThanDays days: Int = 0, space: String? = nil) async {
        let question: String
        var detail: String? = String(localized: "Pinned chats stay where they are. You can undo this.")
        switch await inbox.archiveAllCount(readOnly: readOnly, olderThanDays: days, space: space) {
        case 0?:
            NSSound.beep()
            return
        case let count?:
            switch (readOnly, count) {
            case (true, 1): question = String(localized: "Archive 1 read chat?")
            case (true, _): question = String(localized: "Archive \(count) read chats?")
            case (false, 1): question = String(localized: "Archive 1 chat?")
            case (false, _): question = String(localized: "Archive \(count) chats?")
            }
        case nil:
            question = String(localized: "Archive these chats? Pinned chats stay where they are. You can undo this.")
            detail = nil
        }
        guard ask(question, detail: detail, action: String(localized: "Archive")) else { return }
        _ = await inbox.archiveAll(readOnly: readOnly, olderThanDays: days, space: space)
    }
}

extension View {
    /// A key shown on a menu item, when `shown`.
    @ViewBuilder
    func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers, if shown: Bool) -> some View {
        if shown { keyboardShortcut(key, modifiers: modifiers) } else { self }
    }
}
