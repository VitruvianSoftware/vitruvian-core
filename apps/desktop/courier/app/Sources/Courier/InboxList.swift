// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// The chat list: the banners, a header (the space's name with Filter and Display Options, or while selecting, how
/// many are selected), pinned chats, the chats, and while selecting the actions for them. Toasts sit at its
/// bottom.
struct InboxList: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var preferences: InboxPreferences
    @ObservedObject var ui: InboxUI
    /// The chat the pointer is over: `x` selects it, and it shows the hover button.
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            // The space bar marks an account that is reconnecting; without the bar, this strip does.
            if !preferences.showSpaceBar {
                AccountStatusStrip(items: inbox.statusItems)
            }
            ForEach(inbox.banners) { banner in
                AccountBannerView(banner: banner) { inbox.perform(banner) }
            }
            if inbox.isSelecting {
                SelectionHeader(inbox: inbox)
            } else {
                header
            }
            Divider()
            if !preferences.regularPinnedRows, !pinned.isEmpty {
                PinnedStrip(inbox: inbox, spaces: spaces, ui: ui, rows: pinned, doubleClick: doubleClick)
                Divider()
            }
            chats
            if inbox.isSelecting {
                Divider()
                SelectionBar(inbox: inbox, spaces: spaces, ui: ui)
            }
        }
        .overlay(alignment: .bottom) { ToastView(inbox: inbox) }
        .overlay(alignment: .top) { popoverAnchors }
    }

    /// Where ⌘⌥A's accounts and ⌘L's Remind Me open: the top of the list, whatever its header shows.
    private var popoverAnchors: some View {
        HStack {
            Color.clear
                .frame(width: 1, height: 36)
                .popover(isPresented: $ui.remindPopover, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Remind Me"))
                            .font(.headline)
                            .padding(.bottom, 4)
                        RemindMeItems(inbox: inbox, ui: ui, ids: nil) { ui.remindPopover = false }
                            .buttonStyle(.borderless)
                    }
                    .padding(14)
                    .frame(minWidth: 220, alignment: .leading)
                }
            Spacer()
            Color.clear
                .frame(width: 1, height: 36)
                .popover(isPresented: $ui.accountPopover, arrowEdge: .bottom) {
                    AccountPicker(spaces: spaces) { ui.accountPopover = false }
                }
                .padding(.trailing, 60)
        }
        .allowsHitTesting(false)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(spaceTitle)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            FilterMenu(inbox: inbox)
            DisplayOptionsMenu(inbox: inbox)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var spaceTitle: String {
        spaces.spaces.first { $0.spaceID == inbox.query.space }.map(SpaceLook.title) ?? String(localized: "Inbox")
    }

    // MARK: Chats

    /// Pinned chats come first in every sort. With compact pinned chats, they are the strip, not rows.
    private var pinned: [InboxRow] { inbox.rows.prefix { $0.pinned }.map { $0 } }

    @ViewBuilder
    private var chats: some View {
        if !inbox.isLoaded {
            SkeletonRows(compact: preferences.compactList)
        } else if inbox.rows.isEmpty {
            EmptyStateView(state: EmptyState.of(inbox.query))
        } else {
            list
        }
    }

    private var list: some View {
        let offset = preferences.regularPinnedRows ? 0 : pinned.count
        let rows = Array(inbox.rows.dropFirst(offset))
        let style = RowStyle(preferences)
        return ScrollViewReader { scroll in
            // The times are read against "now", which moves on: draw again every minute.
            TimelineView(.everyMinute) { timeline in
                List(selection: selection) {
                    ForEach(Array(rows.enumerated()), id: \.element.roomID) { index, row in
                        InboxRowView(
                            row: row, networkName: inbox.networkName(row.network),
                            mergedNetworks: inbox.mergedNetworks(for: row),
                            now: timeline.date, style: style,
                            isSelecting: inbox.isSelecting, isSelected: inbox.selection.contains(row.roomID),
                            isHovered: hovered == row.roomID,
                            hoverAct: { hoverAct(row, style.hoverAction) },
                            accept: { Task { await inbox.acceptRequest(ids: [row.roomID]) } },
                            decline: { Task { await inbox.declineRequest(ids: [row.roomID]) } }) {
                                ChatContextMenu(inbox: inbox, spaces: spaces, ui: ui, ids: menuIDs(row.roomID),
                                                showsKeys: false)
                            }
                            .tag(row.roomID)
                            .onHover { inside in
                                if inside { hovered = row.roomID } else if hovered == row.roomID { hovered = nil }
                            }
                            // Within the last 20 chats loaded: read the next page.
                            .onAppear { inbox.rowAppeared(at: index + offset) }
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first {
                        ChatContextMenu(inbox: inbox, spaces: spaces, ui: ui, ids: menuIDs(id))
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let row = inbox.rows.first(where: { $0.roomID == id }) { doubleClick(row) }
                }
                .onKeyPress(phases: .down, action: key)
                .onExitCommand { _ = inbox.escape() }
            }
            .onChange(of: inbox.selectedRoomID) { _, id in
                // A key moved the selection, which may be off screen.
                if let id { scroll.scrollTo(id) }
            }
        }
    }

    /// The open chat is the list's selection. While selecting, a click toggles a chat (⇧-click selects up to it)
    /// and the list shows checkmarks instead; outside it, ⌘-click and ⇧-click start selecting.
    private var selection: Binding<String?> {
        Binding(get: { inbox.isSelecting ? nil : inbox.selectedRoomID }, set: { id in
            let flags = NSEvent.modifierFlags
            let click = [.leftMouseDown, .leftMouseUp].contains(NSApp.currentEvent?.type)
            if inbox.isSelecting {
                // Arrow keys don't change what is selected; clicks do.
                guard click, let id else { return }
                if flags.contains(.shift) { inbox.extendSelection(to: id) } else { inbox.toggleSelected(id) }
            } else if click, flags.contains(.command) {
                // ⌘-clicking the open chat starts selecting with it; another chat joins it.
                if let id { inbox.toggleSelected(id) } else { inbox.beginSelecting() }
            } else if click, flags.contains(.shift), let id {
                inbox.extendSelection(to: id)
            } else {
                inbox.select(id)
            }
        })
    }

    /// Right-clicking a chat that is part of the selection acts on the selection; any other, on that chat.
    private func menuIDs(_ id: String) -> [String]? {
        inbox.isSelecting && inbox.selection.contains(id) ? nil : [id]
    }

    /// Keys on the list: E archives (the selection, or with no chat open the chat pointed at), x selects the chat pointed at, ⇧J and ⇧K extend the
    /// selection, ⌘A selects every chat.
    private func key(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers.subtracting([.capsLock, .numericPad])
        switch (press.characters.lowercased(), modifiers) {
        case ("e", []):
            // Selecting: the selection. No chat open: the chat the pointer is on (Ruling 32).
            let ids = inbox.plainKeyTargets(pointedAt: hovered)
            guard !ids.isEmpty else { return .ignored }
            let unarchive = inbox.targetRows(ids).allSatisfy(\.archived)
            Task { await inbox.archive(!unarchive, ids: ids) }
            return .handled
        case ("x", []):
            guard let hovered else { return .ignored }
            inbox.toggleSelected(hovered)
            return .handled
        case ("j", [.shift]):
            inbox.extendSelection(by: 1)
            return .handled
        case ("k", [.shift]):
            inbox.extendSelection(by: -1)
            return .handled
        case ("a", [.command]):
            inbox.selectAll()
            return .handled
        default:
            return .ignored
        }
    }

    private func hoverAct(_ row: InboxRow, _ action: HoverAction) {
        switch action {
        case .archive: Task { await inbox.archive(!row.archived, ids: [row.roomID]) }
        case .toggleRead: Task { await inbox.toggleRead(ids: [row.roomID]) }
        case .menu, .nothing: break
        }
    }

    /// Double-click does what Settings ▸ Inbox says.
    private func doubleClick(_ row: InboxRow) {
        let ids = [row.roomID]
        switch preferences.doubleClickAction {
        case .archive: Task { await inbox.archive(!row.archived, ids: ids) }
        case .toggleRead: Task { await inbox.toggleRead(ids: ids) }
        case .toggleMute: Task { await inbox.toggleMute(ids: ids) }
        case .toggleLowPriority: Task { await inbox.setLowPriority(!row.lowPriority, ids: ids) }
        case .nothing: break
        }
    }
}

/// An empty list: what this place is and how chats get here.
struct EmptyStateView: View {
    let state: EmptyState

    var body: some View {
        VStack(spacing: 8) {
            Text(state.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let line = state.line {
                Text(line)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Grey rows while the first page is read.
private struct SkeletonRows: View {
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            ForEach(0 ..< 8, id: \.self) { index in
                HStack(spacing: 10) {
                    Circle()
                        .frame(width: compact ? 28 : 40, height: compact ? 28 : 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .frame(width: CGFloat(110 + (index * 37) % 70), height: 10)
                        if !compact {
                            RoundedRectangle(cornerRadius: 3)
                                .frame(width: CGFloat(150 + (index * 53) % 90), height: 8)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.primary.opacity(0.08))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(String(localized: "Loading chats"))
    }
}
