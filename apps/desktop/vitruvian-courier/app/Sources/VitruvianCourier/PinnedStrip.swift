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

    @State private var draftOrder: [String]?
    @State private var draggingID: String?
    @State private var dragTracker = PinnedDragTracker()

    private var canDrag: Bool { !inbox.isSelecting && !inbox.isLocked && rows.count > 1 }
    private var displayedRows: [InboxRow] { PinnedOrder.ordered(rows, by: draftOrder) }
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
                    .opacity(draggingID == row.id ? 0.45 : 1)
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
                    .onHover { inside in if inside { inbox.prefetchFeatures(for: row) } }
                    .modifier(PinnedTileDragModifier(
                        enabled: canDrag,
                        makeProvider: { beginDrag(rowID: row.id) },
                        dropDelegate: makeDropDelegate(targetID: row.id)
                    ))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onDrop(of: [Self.dragType], delegate: makeDropDelegate(targetID: nil))
        .onChange(of: rowIDs) { _, newIDs in
            draftOrder = nil
            if let draggingID, !newIDs.contains(draggingID) {
                self.draggingID = nil
                dragTracker.cancelAll()
            }
        }
        .onChange(of: canDrag) { _, allowed in
            if !allowed {
                cancelDrag(animated: false)
            }
        }
        .onDisappear {
            cancelDrag(animated: false)
        }
    }

    @MainActor
    private func beginDrag(rowID: String) -> NSItemProvider {
        dragTracker.cancelAll()
        draggingID = rowID
        draftOrder = rowIDs
        dragTracker.startWatchingDragEnd {
            cancelDrag(animated: true)
        }
        let provider = NSItemProvider()
        // Private type conforming only to public.data so tiles cannot be dropped into other apps as text.
        provider.registerDataRepresentation(forTypeIdentifier: Self.dragType.identifier, visibility: .ownProcess) { completion in
            completion(Data(rowID.utf8), nil)
            return nil
        }
        return provider
    }

    @MainActor
    private func cancelDrag(animated: Bool) {
        dragTracker.cancelAll()
        draggingID = nil
        if animated {
            withAnimation(.easeInOut(duration: 0.15)) {
                draftOrder = nil
            }
        } else {
            draftOrder = nil
        }
    }

    private func makeDropDelegate(targetID: String?) -> PinnedStripDropDelegate {
        PinnedStripDropDelegate(
            targetID: targetID,
            isValid: { canDrag && draggingID != nil },
            onEnter: { target in
                dragTracker.markInsideStrip()
                guard let target, let draggingID else { return }
                let base = draftOrder ?? rowIDs
                let next = PinnedOrder.moving(draggingID, onto: target, in: base)
                if next != base {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        draftOrder = next
                    }
                }
            },
            onUpdate: {
                dragTracker.markInsideStrip()
            },
            onExit: {
                dragTracker.scheduleExitReset {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        draftOrder = nil
                    }
                }
            },
            onPerformDrop: {
                dragTracker.cancelAll()
                guard canDrag, draggingID != nil else {
                    draggingID = nil
                    draftOrder = nil
                    return false
                }
                let committed = draftOrder
                draggingID = nil
                guard let committed, committed != rowIDs else {
                    draftOrder = nil
                    return true
                }
                Task { @MainActor in
                    await inbox.reorderPinned(committed)
                    if draggingID == nil {
                        draftOrder = nil
                    }
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
    let dropDelegate: PinnedStripDropDelegate

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag { makeProvider() }
                .onDrop(of: [PinnedStrip.dragType], delegate: dropDelegate)
        } else {
            content
        }
    }
}

private struct PinnedStripDropDelegate: DropDelegate {
    let targetID: String?
    let isValid: @MainActor () -> Bool
    let onEnter: @MainActor (String?) -> Void
    let onUpdate: @MainActor () -> Void
    let onExit: @MainActor () -> Void
    let onPerformDrop: @MainActor () -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [PinnedStrip.dragType]) else { return false }
        return MainActor.assumeIsolated { isValid() }
    }

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated { onEnter(targetID) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated {
            onUpdate()
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

/// Coordinates exit-reset debouncing across the 6 pt grid gaps and cleanup when a drag ends outside or is cancelled.
@MainActor
private final class PinnedDragTracker {
    private var exitResetTask: Task<Void, Never>?
    private var endWatchTask: Task<Void, Never>?

    func markInsideStrip() {
        exitResetTask?.cancel()
        exitResetTask = nil
    }

    func scheduleExitReset(_ reset: @escaping @MainActor () -> Void) {
        exitResetTask?.cancel()
        exitResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self, !Task.isCancelled else { return }
            self.exitResetTask = nil
            reset()
        }
    }

    func startWatchingDragEnd(_ onEnded: @escaping @MainActor () -> Void) {
        endWatchTask?.cancel()
        endWatchTask = Task { @MainActor [weak self] in
            var sawPressed = (NSEvent.pressedMouseButtons & 1) != 0
            var releasedTicks = 0
            var idleTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard let self, !Task.isCancelled else { return }
                if (NSEvent.pressedMouseButtons & 1) != 0 {
                    sawPressed = true
                    releasedTicks = 0
                    idleTicks = 0
                } else if sawPressed {
                    releasedTicks += 1
                    if releasedTicks >= 2 {
                        self.endWatchTask = nil
                        onEnded()
                        return
                    }
                } else {
                    idleTicks += 1
                    if idleTicks >= 5 {
                        self.endWatchTask = nil
                        onEnded()
                        return
                    }
                }
            }
        }
    }

    func cancelAll() {
        exitResetTask?.cancel()
        exitResetTask = nil
        endWatchTask?.cancel()
        endWatchTask = nil
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
