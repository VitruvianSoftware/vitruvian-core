// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The filters as the Filter menu names them, in its order, with what the less obvious ones mean.
enum FilterText {
    /// The Filter menu's order (inventory 01 §3).
    static let menuOrder: [InboxFilter] = [
        .unread, .dms, .groups, .drafts, .unanswered, .noReply, .unknown, .muted, .hidden, .archived, .lowPriority,
        .requests, .reminders, .sendLater,
    ]

    static func title(_ filter: InboxFilter) -> String {
        switch filter {
        case .unread: String(localized: "Unread")
        case .dms: String(localized: "DMs")
        case .groups: String(localized: "Groups")
        case .drafts: String(localized: "Drafts")
        case .unanswered: String(localized: "Unanswered")
        case .noReply: String(localized: "No reply")
        case .unknown: String(localized: "From unknown numbers")
        case .muted: String(localized: "Muted")
        case .hidden: String(localized: "Hidden")
        case .archived: String(localized: "Archived")
        case .lowPriority: String(localized: "Low Priority")
        case .requests: String(localized: "Requests")
        case .reminders: String(localized: "Reminders")
        case .sendLater: String(localized: "Send Later")
        }
    }

    /// Inferred (inventory 01 §3): what Unanswered, No reply and From unknown numbers mean, as the engine has it.
    static func help(_ filter: InboxFilter) -> String? {
        switch filter {
        case .dms: String(localized: "One-to-one chats.")
        case .unanswered: String(localized: "Chats where someone else sent the newest message.")
        case .noReply: String(localized: "Chats where you sent the newest message and no one has answered.")
        case .unknown: String(localized: "One-to-one chats with no name, or a phone number for a name.")
        case .hidden: String(localized: "Chats you hid. They stay out of your inbox.")
        case .lowPriority: String(localized: "Chats that stay out of your inbox, even when new messages arrive.")
        case .requests: String(localized: "Messages from people you haven’t chatted with before.")
        default: nil
        }
    }

    static func sort(_ sort: InboxSort) -> String {
        switch sort {
        case .newest: String(localized: "Newest message first")
        case .oldest: String(localized: "Oldest message first")
        case .leastTimeRemaining: String(localized: "Reminder soonest")
        case .mostTimeRemaining: String(localized: "Reminder latest")
        }
    }
}

/// Filter (N): the 14 filters as checkmarks, All, and Clear all filters.
struct FilterMenu: View {
    @ObservedObject var inbox: InboxModel

    var body: some View {
        Menu {
            Toggle(String(localized: "All"), isOn: Binding(
                get: { inbox.query.filters.isEmpty },
                set: { if $0 { inbox.query.filters = [] } }))
            Divider()
            ForEach(FilterText.menuOrder, id: \.self) { filter in
                Toggle(FilterText.title(filter), isOn: Binding(
                    get: { inbox.query.filters.contains(filter) },
                    set: { on in
                        if on { inbox.query.filters.insert(filter) } else { inbox.query.filters.remove(filter) }
                    }))
                    .help(optional: FilterText.help(filter))
            }
            Divider()
            Button(String(localized: "Clear all filters")) { inbox.query.filters = [] }
                .disabled(inbox.query.filters.isEmpty)
        } label: {
            Label(title, systemImage: inbox.query.filters.isEmpty ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(String(localized: "Narrow the list (⌥Tab steps through the common filters)"))
    }

    private var title: String {
        let count = inbox.query.filters.count
        return count == 0 ? String(localized: "Filter") : String(localized: "Filter (\(count))")
    }
}

/// Display Options: the four orders.
struct DisplayOptionsMenu: View {
    @ObservedObject var inbox: InboxModel

    var body: some View {
        Menu {
            Picker(String(localized: "Order"), selection: Binding(get: { inbox.query.sort },
                                                                 set: { inbox.query.sort = $0 })) {
                ForEach(InboxSort.allCases, id: \.self) { Text(FilterText.sort($0)).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .accessibilityLabel(String(localized: "Display Options"))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Display Options"))
    }
}

/// ⌘⌥A: the accounts; picking one shows its space.
struct AccountPicker: View {
    @ObservedObject var spaces: SpacesModel
    let done: () -> Void

    private var accounts: [Space] { spaces.spaces.filter { $0.kind == .account } }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Filter by Account"))
                .font(.headline)
                .padding(.bottom, 6)
            if accounts.isEmpty {
                Text(String(localized: "No accounts yet"))
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts) { space in
                Button {
                    spaces.select(space.spaceID)
                    done()
                } label: {
                    HStack(spacing: 8) {
                        NetworkBadge(network: space.network, name: space.title, size: 16)
                        Text(space.title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(minWidth: 220)
    }
}

extension View {
    /// A tooltip when there is something to say.
    @ViewBuilder
    func help(optional text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}
