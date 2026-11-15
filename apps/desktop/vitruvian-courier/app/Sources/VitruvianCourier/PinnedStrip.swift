// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// Pinned chats above the list, as Beeper-like tiles (a 48 pt avatar, the name under it) (Settings ▸ Inbox ▸ "Show pinned chats as full rows" puts them
/// in the list instead). A click opens the chat, or while selecting, selects it.
struct PinnedStrip: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    let ui: InboxUI
    let rows: [InboxRow]
    let doubleClick: (InboxRow) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 112), spacing: 6)], spacing: 6) {
            ForEach(rows, id: \.id) { row in
                PinnedChat(row: row, networkName: inbox.networkName(row.network),
                           isOpen: !inbox.isSelecting && inbox.isOpen(row.id),
                           isSelected: inbox.isSelecting && inbox.selection.contains(row.id),
                           showsBadge: inbox.preferences.showNetworkIcons,
                           tinted: inbox.preferences.colorNetworkIcons)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let flags = NSEvent.modifierFlags
                        let isSelectingOrModified = inbox.isSelecting
                            || flags.contains(.command)
                            || flags.contains(.shift)
                        if !isSelectingOrModified, (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                            doubleClick(row)
                        } else {
                            click(row)
                        }
                    }
                    // VoiceOver (and any accessibility client) presses the tile as it would a button.
                    .accessibilityAction { click(row) }
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

struct PinnedChat: View {
    let row: InboxRow
    let networkName: String
    let isOpen: Bool
    let isSelected: Bool
    let showsBadge: Bool
    let tinted: Bool
    @Environment(\.redactNamesAndPictures) private var isRedacted
    @Environment(\.themeAccentColor) private var themeAccent

    /// The chat's name, or with "Redact names and pictures" on, its stand-in, as the chat list shows it.
    private var displayName: String {
        let raw = row.name.isEmpty ? String(localized: "Unnamed chat") : row.name
        return isRedacted ? AppearancePreferences.redactedText(raw, kind: .chatTitle) : raw
    }

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ChatAvatar(row: row, size: 48)
                .blur(radius: isRedacted ? 6 : 0)
                .clipShape(Rectangle())
                .frame(width: 48, height: 48)
                .overlay(alignment: .bottomTrailing) {
                    if showsBadge {
                        NetworkBadge(network: row.network, name: networkName, size: 16, tinted: tinted, ringed: true)
                            .offset(x: 4, y: 4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if row.isUnread {
                        Circle()
                            // Grey when the chat is muted itself or by its label or account, as in the chat list.
                            .fill(row.muted || row.mutedBy != .none ? Color.gray : themeAccent)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                            .accessibilityLabel(String(localized: "Unread"))
                    }
                }
            Text(displayName)
                .font(.caption)
                .fontWeight(row.isUnread ? .semibold : .regular)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isOpen || isSelected ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOpen || isSelected ? themeAccent.opacity(0.22)
                    : hovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(displayName)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOpen || isSelected ? .isSelected : [])
    }
}
