// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Pinned chats above the list, as compact avatars (Settings ▸ Inbox ▸ "Show pinned chats as full rows" puts them
/// in the list instead). A click opens the chat, or while selecting, selects it.
struct PinnedStrip: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    let ui: InboxUI
    let rows: [InboxRow]
    let doubleClick: (InboxRow) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 54, maximum: 64), spacing: 4)], spacing: 8) {
            ForEach(rows, id: \.id) { row in
                PinnedChat(row: row, networkName: inbox.networkName(row.network),
                           isOpen: !inbox.isSelecting && inbox.isOpen(row.id),
                           isSelected: inbox.isSelecting && inbox.selection.contains(row.id),
                           showsBadge: inbox.preferences.showNetworkIcons,
                           tinted: inbox.preferences.colorNetworkIcons)
                    .onTapGesture(count: 2) { doubleClick(row) }
                    .onTapGesture { click(row) }
                    .contextMenu {
                        ChatContextMenu(inbox: inbox, spaces: spaces, ui: ui, ids: menuIDs(row))
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func click(_ row: InboxRow) {
        let flags = NSEvent.modifierFlags
        if inbox.isSelecting || flags.contains(.command) {
            inbox.toggleSelected(row.id)
        } else if flags.contains(.shift) {
            inbox.extendSelection(to: row.id)
        } else {
            inbox.select(row.id)
        }
    }

    /// Right-clicking a chat that is part of the selection acts on the selection.
    private func menuIDs(_ row: InboxRow) -> [String]? {
        inbox.isSelecting && inbox.selection.contains(row.id) ? nil : [row.id]
    }
}

private struct PinnedChat: View {
    let row: InboxRow
    let networkName: String
    let isOpen: Bool
    let isSelected: Bool
    let showsBadge: Bool
    let tinted: Bool
    @Environment(\.redactNamesAndPictures) private var isRedacted

    /// The chat's name, or with "Redact names and pictures" on, its stand-in, as the chat list shows it.
    private var displayName: String {
        let raw = row.name.isEmpty ? String(localized: "Unnamed chat") : row.name
        return isRedacted ? AppearancePreferences.redactedText(raw, kind: .chatTitle) : raw
    }

    var body: some View {
        VStack(spacing: 3) {
            ChatAvatar(row: row)
                .blur(radius: isRedacted ? 6 : 0)
                .clipShape(Circle())
                .frame(width: 40, height: 40)
                .overlay(alignment: .bottomTrailing) {
                    if showsBadge {
                        NetworkBadge(network: row.network, name: networkName, size: 13, tinted: tinted)
                            .background(Circle().fill(.background))
                            .offset(x: 2, y: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if row.isUnread {
                        Circle()
                            // Grey when the chat is muted itself or by its label or account, as in the chat list.
                            .fill(row.muted || row.mutedBy != .none ? Color.gray : Color.accentColor)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                            .accessibilityLabel(String(localized: "Unread"))
                    }
                }
                .padding(3)
                .background {
                    if isOpen || isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
            Text(displayName)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .help(displayName)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
