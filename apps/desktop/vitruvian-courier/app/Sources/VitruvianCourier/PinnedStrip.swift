// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import UniformTypeIdentifiers

/// Pinned chats above the list, as Beeper-like tiles (a 48 pt avatar, the name on one line under it) (Settings ▸ Inbox ▸ "Show pinned chats as full rows" puts them
/// in the list instead). A click opens the chat, or while selecting, selects it.
struct PinnedStrip: View {
    static let dragType: UTType = UTType("com.vitruviansoftware.courier.pinned-chat")
        ?? UTType(mimeType: "application/x-vitruvian-courier-pinned-chat", conformingTo: .data)
        ?? .data

    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    let ui: InboxUI
    var conversation: ConversationModel? = nil
    let rows: [InboxRow]
    let doubleClick: (InboxRow) -> Void

    @State private var drag = PinnedDragState()
    @State private var tileFrames: [String: CGRect] = [:]
    private static let space = "pinnedStrip"

    private var canDrag: Bool { !inbox.isSelecting && !inbox.isLocked && rows.count > 1 }
    private var displayedRows: [InboxRow] { PinnedOrder.ordered(rows, by: drag.draft) }
    private var rowIDs: [String] { rows.map(\.id) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 112), spacing: 6)], spacing: 6) {
            ForEach(displayedRows, id: \.id) { row in
                PinnedChat(row: row, displayTitleOverride: inbox.displayTitle(for: row),
                           networkName: inbox.networkName(row.network),
                           isOpen: !inbox.isSelecting && inbox.isOpen(row.id),
                           isSelected: inbox.isSelecting && inbox.selection.contains(row.id),
                           showsBadge: inbox.preferences.showNetworkIcons,
                           tinted: inbox.preferences.colorNetworkIcons)
                    .opacity(drag.fadedID == row.id ? 0.45 : 1)
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
                    // A native menu, so the system's own "Ask Siri" item is left out.
                    .chatRowContextMenu(inbox: inbox, spaces: spaces, ui: ui, conversation: conversation) { menuIDs(row) }
                    .onHover { inside in
                        conversation?.hoverPrefetch(row.id, inside: inside)
                        if inside { inbox.prefetchFeatures(for: row) }
                    }
                    .modifier(PinnedTileDragModifier(enabled: canDrag, makeProvider: { beginDrag(rowID: row.id) }))
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: PinnedTileFramesKey.self,
                                               value: [row.id: proxy.frame(in: .named(Self.space))])
                    })
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // One drop target for the whole strip: a drop target on each tile never hears the drag under this one, so
        // the tile under the pointer is found from the tiles' frames, in the same space as the drop's location.
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(PinnedTileFramesKey.self) { tileFrames = $0 }
        .onDrop(of: [Self.dragType], delegate: dropDelegate)
        .onChange(of: rowIDs) { _, newIDs in drag.rowsChanged(newIDs) }
        .onChange(of: canDrag) { _, allowed in
            if !allowed { drag.cancel() }
        }
        .onDisappear { drag.cancel() }
    }

    @MainActor
    private func beginDrag(rowID: String) -> NSItemProvider {
        drag.begin(rowID, order: rowIDs)
        let provider = NSItemProvider()
        // A private type conforming only to public.data, so no other app takes the tile (as text or otherwise). Visible
        // to all: a drag goes through the system's drag pasteboard, and an own-process item never reaches it, so no
        // drop target, Courier's included, would ever see it.
        provider.registerDataRepresentation(forTypeIdentifier: Self.dragType.identifier, visibility: .all) { completion in
            completion(Data(rowID.utf8), nil)
            return nil
        }
        return provider
    }

    private var dropDelegate: PinnedStripDropDelegate {
        PinnedStripDropDelegate(
            isValid: { canDrag && drag.canDrop },
            onMove: { location in
                var next = drag
                if next.move(over: PinnedOrder.tile(at: location, in: tileFrames), order: rowIDs) {
                    withAnimation(.easeInOut(duration: 0.15)) { drag = next }
                } else if next != drag {
                    drag = next
                }
            },
            onExit: {
                withAnimation(.easeInOut(duration: 0.15)) { drag.exit() }
            },
            onPerformDrop: {
                guard canDrag else {
                    drag.cancel()
                    return false
                }
                guard let order = drag.drop(order: rowIDs) else { return true }
                Task { @MainActor in
                    await inbox.reorderPinned(order)
                    drag.committed()
                }
                return true
            }
        )
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

private struct PinnedTileDragModifier: ViewModifier {
    let enabled: Bool
    let makeProvider: @MainActor () -> NSItemProvider

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag { makeProvider() }
        } else {
            content
        }
    }
}

private struct PinnedTileFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct PinnedStripDropDelegate: DropDelegate {
    let isValid: @MainActor () -> Bool
    let onMove: @MainActor (CGPoint) -> Void
    let onExit: @MainActor () -> Void
    let onPerformDrop: @MainActor () -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [PinnedStrip.dragType]) else { return false }
        return MainActor.assumeIsolated { isValid() }
    }

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated { onMove(info.location) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated {
            onMove(info.location)
            return isValid() ? DropProposal(operation: .move) : DropProposal(operation: .cancel)
        }
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { onExit() }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { onPerformDrop() }
    }
}

struct PinnedChat: View {
    let row: InboxRow
    var displayTitleOverride: String? = nil
    let networkName: String
    let isOpen: Bool
    let isSelected: Bool
    let showsBadge: Bool
    let tinted: Bool
    @Environment(\.redactNamesAndPictures) private var isRedacted
    @Environment(\.themeAccentColor) private var themeAccent

    /// The chat's name, or with "Redact names and pictures" on, its stand-in, as the chat list shows it.
    private var displayName: String {
        let formatted = PhoneNumberFormat.display(displayTitleOverride ?? row.displayTitle)
        let raw = formatted.isEmpty ? String(localized: "Unnamed chat") : formatted
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
                // One line, cut in the middle, so every tile is the same height; the tooltip has the whole name.
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
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
