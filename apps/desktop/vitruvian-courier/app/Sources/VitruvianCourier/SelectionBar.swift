// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The list's header while selecting: how many chats are selected, and Cancel (Esc does the same).
struct SelectionHeader: View {
    @ObservedObject var inbox: InboxModel

    var body: some View {
        HStack {
            Text(count == 1 ? String(localized: "1 chat selected") : String(localized: "\(count) chats selected"))
                .font(.headline)
            Spacer()
            Button(String(localized: "Select All")) { inbox.selectAll() }
                .buttonStyle(.borderless)
                .disabled(inbox.rows.isEmpty)
            Button(String(localized: "Cancel")) { inbox.endSelecting() }
                .buttonStyle(.borderless)
                .help(String(localized: "Stop selecting (Esc)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var count: Int { inbox.selection.count }
}

/// What can be done to every chat selected at once, under the list.
struct SelectionBar: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    let ui: InboxUI

    var body: some View {
        let rows = inbox.targetRows()
        let all = { (test: (InboxRow) -> Bool) in !rows.isEmpty && rows.allSatisfy(test) }
        let empty = inbox.selection.isEmpty
        HStack(spacing: 4) {
            icon("envelope.open", String(localized: "Mark as Read")) { await inbox.setRead(true) }
            icon("envelope.badge", String(localized: "Mark as Unread"), help: SyncHelp.markUnread) {
                await inbox.setRead(false)
            }
            if all(\.lowPriority) {
                icon("tray.and.arrow.up", String(localized: "Move to Inbox")) { await inbox.setLowPriority(false) }
            } else {
                icon("arrow.down.to.line", String(localized: "Move to Low Priority"),
                     help: inbox.isEntitled(.lowPriority)
                         ? String(localized: "Keeps the chat out of your inbox, even when new messages arrive.")
                         : String(localized: "Available with a plan")) {
                    await inbox.setLowPriority(true)
                }
                .disabled(!inbox.isEntitled(.lowPriority))
            }
            Menu {
                RemindMeItems(inbox: inbox, ui: ui, ids: nil)
            } label: {
                Image(systemName: "alarm")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "Remind Me"))
            .accessibilityLabel(String(localized: "Remind Me"))
            icon("alarm.waves.left.and.right", String(localized: "Dismiss Reminder")) { await inbox.dismissReminder() }
                .disabled(!rows.contains { $0.reminder != nil })
            if all(\.archived) {
                icon("tray.and.arrow.up.fill", String(localized: "Unarchive")) { await inbox.archive(false) }
            } else {
                icon("archivebox", String(localized: "Archive"),
                     help: all(\.pinned) ? String(localized: "Unpin a chat to archive it")
                         : String(localized: "Clears the chat from your inbox until someone writes again.")) {
                    await inbox.archive(true)
                }
                .disabled(all(\.pinned))
            }
            Spacer(minLength: 0)
            Menu {
                let muting = !all(\.muted)
                Button(muting ? String(localized: "Mute") : String(localized: "Unmute")) {
                    Task { await inbox.toggleMute() }
                }
                .help(SyncHelp.mute(muting, reach: SyncReach.of(.mute, networks: Array(Set(rows.map(\.network))),
                                                                 accounts: inbox.accounts)))
                if all(\.hidden) {
                    Button(String(localized: "Unhide")) { Task { await inbox.setHidden(false) } }
                } else {
                    Button(String(localized: "Hide")) { Task { await inbox.setHidden(true) } }
                        .help(String(localized: "Takes the chat out of your inbox without leaving it. Filter ▸ Hidden shows it again."))
                }
                LabelMenu(inbox: inbox, spaces: spaces, ids: nil, rows: rows)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "More"))
            .accessibilityLabel(String(localized: "More"))
        }
        .disabled(empty)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func icon(_ symbol: String, _ title: String, help: String? = nil,
                      _ action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help.map { "\(title): \($0)" } ?? title)
        .accessibilityLabel(title)
    }
}
