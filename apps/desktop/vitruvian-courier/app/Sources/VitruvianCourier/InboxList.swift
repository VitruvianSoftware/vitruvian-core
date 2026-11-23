// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// Tracks the row under the pointer without invalidating the entire `InboxList` body on every row transition,
/// and suppresses selection when a click targets the row's inline hover button.
@MainActor
private final class InboxHoverTracker {
    var roomID: String?
    private var suppressedSelectionRoomID: String?

    func suppressSelectionForCurrentClick(roomID: String) {
        suppressedSelectionRoomID = roomID
        DispatchQueue.main.async { [weak self] in
            if self?.suppressedSelectionRoomID == roomID {
                self?.suppressedSelectionRoomID = nil
            }
        }
    }

    func shouldSuppressSelection(for roomID: String) -> Bool {
        if suppressedSelectionRoomID == roomID {
            suppressedSelectionRoomID = nil
            return true
        }
        return false
    }
}

/// The chat list: the banners, a header (the space's name with Filter and Display Options, or while selecting, how
/// many are selected), pinned chats, the chats, and while selecting the actions for them. Toasts sit at its
/// bottom.
struct InboxList: View {
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var preferences: InboxPreferences
    @ObservedObject var composerPreferences: ComposerPreferences = ComposerPreferences()
    @ObservedObject var ui: InboxUI
    /// The conversation pane's model: its sheets are what Edit Chat… and Report as Spam… in a chat's menu open.
    var conversation: ConversationModel? = nil
    /// Opens ⌘K's search. When the window doesn't pass it, the header's button chooses the Search… item of the
    /// menu bar, which is the same thing ⌘K does.
    var openSearch: (@MainActor () -> Void)? = nil
    @Environment(\.openDetachedWindow) private var openDetachedWindow
    @Environment(\.appearancePreferences) private var appearanceEnv
    @Environment(\.drawsLiquidGlass) private var drawsLiquidGlass
    /// The chat the pointer is over: `x` selects it, and `InboxRowView` tracks its own hover state locally.
    @State private var hoverTracker = InboxHoverTracker()

    var rowStyle: RowStyle {
        RowStyle(
            preferences,
            composerPreferences: composerPreferences,
            redactNamesAndPictures: appearanceEnv?.redactNamesAndPictures ?? false,
            fontSizeScale: appearanceEnv?.fontSizeScale ?? .default
        )
    }

    func formattedRowTimestamp(
        _ row: InboxRow,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        RelativeTime.text(
            forMillis: row.lastTS,
            now: now,
            calendar: calendar,
            locale: locale,
            timeFormat: rowStyle.timeFormat
        )
    }

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
                Divider()
            } else if !drawsLiquidGlass {
                header
                Divider()
            }
            if !preferences.regularPinnedRows, !pinned.isEmpty {
                PinnedStrip(inbox: inbox, spaces: spaces, ui: ui, conversation: conversation, rows: pinned,
                            doubleClick: doubleClick)
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
        .modifier(InboxToolbarHeader(inbox: inbox, title: spaceTitle, openSearch: openSearch))
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
            InboxHeaderButtons(inbox: inbox, openSearch: openSearch)
            FilterMenu(inbox: inbox)
            DisplayOptionsMenu(inbox: inbox)
        }
        // The same strip as the chat's and the panes' headers, so the titles share a line across the window.
        .padding(.horizontal, PaneHeaderMetrics.inset)
        .frame(height: PaneHeaderMetrics.stripHeight)
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
        } else if inbox.rows.isEmpty && inbox.startNewChatDraft == nil {
            EmptyStateView(state: EmptyState.of(inbox.query), guidance: EmptyStateGuidance.of(inbox.query),
                           goToInbox: { spaces.select("inbox") })
        } else {
            list
        }
    }

    private var list: some View {
        let offset = preferences.regularPinnedRows ? 0 : pinned.count
        let rows = Array(inbox.rows.dropFirst(offset))
        let style = rowStyle
        return ScrollViewReader { scroll in
            // The times are read against "now", which moves on: draw again every minute.
            TimelineView(.everyMinute) { timeline in
                List(selection: selection(for: rows)) {
                    if let draft = inbox.startNewChatDraft {
                        NewChatPlaceholderRow(draft: draft, style: style)
                            .tag(InboxModel.newChatRowID)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        InboxRowView(
                            row: row,
                            displayTitleOverride: inbox.displayTitle(for: row),
                            requestHandle: inbox.requestHandle(for: row),
                            networkName: inbox.networkName(row.network),
                            mergedNetworks: inbox.mergedNetworks(for: row),
                            now: timeline.date, style: style,
                            isSelecting: inbox.isSelecting, isSelected: inbox.selection.contains(row.id),
                            onHoverChange: { inside in
                                if inside {
                                    hoverTracker.roomID = row.id
                                    // The menu offers Delete Chat… only where the network can: ask now, so it knows.
                                    inbox.prefetchFeatures(for: row)
                                } else if hoverTracker.roomID == row.id {
                                    hoverTracker.roomID = nil
                                }
                            },
                            onWillHoverAct: { hoverTracker.suppressSelectionForCurrentClick(roomID: row.id) },
                            hoverAct: { hoverAct(row, style.hoverAction) },
                            accept: { Task { await inbox.acceptRequest(ids: [row.id]) } },
                            decline: { Task { await inbox.declineRequest(ids: [row.id]) } }) {
                                ChatContextMenu(inbox: inbox, spaces: spaces, ui: ui, ids: menuIDs(row.id),
                                                showsKeys: false, conversation: conversation)
                            }
                            // A native menu, so the system's own "Ask Siri" item is left out.
                            .chatRowContextMenu(inbox: inbox, spaces: spaces, ui: ui, conversation: conversation) { menuIDs(row.id) }
                            .tag(row.id)
                            // Within the last 20 chats loaded: read the next page.
                            .onAppear { inbox.rowAppeared(at: index + offset) }
                    }
                }
                .listStyle(.inset)
                .courierSidebarList()
                .contextMenu(forSelectionType: String.self, menu: { _ in EmptyView() }, primaryAction: { ids in
                    if let id = ids.first, id != InboxModel.newChatRowID,
                       let row = inbox.rows.first(where: { $0.id == id || $0.roomID == id }) { doubleClick(row) }
                })
                .onKeyPress(phases: .down, action: key)
                .onExitCommand { _ = inbox.escape() }
            }
            .onChange(of: inbox.selectedRoomID) { _, id in
                // A key moved the selection, which may be off screen.
                if let id { scroll.scrollTo(id) }
            }
            .onChange(of: inbox.startNewChatDraft != nil) { _, isCreating in
                if isCreating { scroll.scrollTo(InboxModel.newChatRowID, anchor: .top) }
            }
        }
    }

    /// The open chat is the list's selection (or the inline "New Chat" row while starting a chat). While selecting, a
    /// click toggles a chat (⇧-click selects up to it) and the list shows checkmarks instead; outside it, ⌘-click and
    /// ⇧-click start selecting.
    private func selection(for listedRows: [InboxRow]) -> Binding<String?> {
        Binding(get: {
            if inbox.isSelecting { return nil }
            if inbox.startNewChatDraft != nil { return InboxModel.newChatRowID }
            return listedRows.first(where: { inbox.isOpen($0.id) || inbox.isOpen($0.roomID) })?.id
        }, set: { id in
            let flags = NSEvent.modifierFlags
            let click = [.leftMouseDown, .leftMouseUp].contains(NSApp.currentEvent?.type)
            if id == InboxModel.newChatRowID {
                return
            }
            if inbox.isSelecting {
                // Arrow keys don't change what is selected; clicks do.
                guard click, let id else { return }
                if flags.contains(.shift) { inbox.extendSelection(to: id) } else { inbox.toggleSelected(id) }
            } else if click, flags.contains(.command) {
                // ⌘-clicking the open chat starts selecting with it; another chat joins it.
                if let id { inbox.toggleSelected(id) } else { inbox.beginSelecting() }
            } else if click, flags.contains(.shift), let id {
                inbox.extendSelection(to: id)
            } else if let id {
                guard !hoverTracker.shouldSuppressSelection(for: id) else { return }
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
            let ids = inbox.plainKeyTargets(pointedAt: hoverTracker.roomID)
            guard !ids.isEmpty else { return .ignored }
            let unarchive = inbox.targetRows(ids).allSatisfy(\.archived)
            Task { await inbox.archive(!unarchive, ids: ids) }
            return .handled
        case ("x", []):
            guard let hovered = hoverTracker.roomID else { return .ignored }
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
        case .archive: Task { await inbox.archive(!row.archived, ids: [row.id]) }
        case .toggleRead: Task { await inbox.toggleRead(ids: [row.id]) }
        case .menu, .nothing: break
        }
    }

    /// Double-click does what Settings ▸ Inbox says.
    private func doubleClick(_ row: InboxRow) {
        let ids = [row.id]
        switch preferences.doubleClickAction {
        case .openInNewWindow: openDetachedWindow?(.chat(roomID: row.roomID))
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
    var guidance = EmptyStateGuidance(actions: [], howTo: nil)
    var goToInbox: () -> Void = {}

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
            if let howTo = guidance.howTo {
                Text(howTo)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            if guidance.actions.contains(.goToInbox) {
                Button(action: goToInbox) {
                    Text(String(localized: "Go to Inbox"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18)))
                        .contentShape(Capsule())
                }
                // Drawn here rather than with `.bordered`: in the sidebar `.bordered` came out as faint text, and the
                // empty list's one way out has to look clickable.
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Go to Inbox"))
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
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

/// With glass, the space's name and its menus in the sidebar's part of the window's toolbar, on the line of the
/// traffic lights and of every other column's header (PaneHeader.swift). Not while selecting, whose header stays in
/// the list; nothing without glass, where `InboxList.header` is a strip.
private struct InboxToolbarHeader: ViewModifier {
    @ObservedObject var inbox: InboxModel
    let title: String
    var openSearch: (@MainActor () -> Void)? = nil
    @Environment(\.drawsLiquidGlass) private var drawsLiquidGlass

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), drawsLiquidGlass {
            content.toolbar {
                if !inbox.isSelecting {
                    // `.navigation` would put the name in the chat's half of the toolbar: the sidebar's items are its
                    // automatic ones, the name first, then the menus pushed to the sidebar button.
                    ToolbarItem(placement: .automatic) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible)
                    ToolbarItemGroup(placement: .automatic) {
                        InboxHeaderButtons(inbox: inbox, openSearch: openSearch, inToolbar: true)
                        FilterMenu(inbox: inbox, inToolbar: true)
                        DisplayOptionsMenu(inbox: inbox, inToolbar: true)
                    }
                }
            }
        } else {
            content
        }
    }
}

/// Search (⌘K) and New Chat (⌘N), as icon buttons at the head of the sidebar, as Beeper has them.
struct InboxHeaderButtons: View {
    @ObservedObject var inbox: InboxModel
    var openSearch: (@MainActor () -> Void)? = nil
    /// In the window's toolbar: the toolbar's own button look.
    var inToolbar = false

    var body: some View {
        Group {
            button(String(localized: "Search"), symbol: "magnifyingglass", keys: "⌘K") {
                if let openSearch { openSearch() } else { _ = MainMenuAction.choose(String(localized: "Search…")) }
            }
            button(String(localized: "New Chat"), symbol: "square.and.pencil", keys: "⌘N") {
                inbox.openStartNewChat()
            }
        }
    }

    @ViewBuilder
    private func button(_ title: String, symbol: String, keys: String, action: @escaping () -> Void) -> some View {
        if inToolbar {
            Button(action: action) { Label(title, systemImage: symbol).labelStyle(.iconOnly) }
                .courierTooltip(title, shortcut: keys, edge: .bottom)
        } else {
            InboxHeaderIconButton(title: title, symbol: symbol, keys: keys, action: action)
        }
    }
}

private struct InboxHeaderIconButton: View {
    let title: String
    let symbol: String
    let keys: String
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.08) : .clear)
                        .animation(
                            reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                            value: isHovering
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .courierTooltip(title, shortcut: keys, edge: .bottom)
    }
}

/// Chooses an item of the menu bar by its title: the way a header button does what a menu item with a key does,
/// without the list holding the models behind it.
@MainActor
enum MainMenuAction {
    @discardableResult
    static func choose(_ title: String, in menu: NSMenu? = NSApp.mainMenu) -> Bool {
        guard let menu else { return false }
        for (index, item) in menu.items.enumerated() {
            if item.title == title, item.isEnabled, !item.isSeparatorItem {
                menu.performActionForItem(at: index)
                return true
            }
            if let submenu = item.submenu, choose(title, in: submenu) { return true }
        }
        return false
    }
}

/// Placeholder row selected at the top of the inbox while composing a new chat in the detail pane.
private struct NewChatPlaceholderRow: View {
    let draft: StartNewChatDraft
    let style: RowStyle
    @Environment(\.appearancePreferences) private var appearanceEnv
    @Environment(\.themeAccentColor) private var themeAccent
    @Environment(\.courierZoomMultiplier) private var zoom

    private var pointSizes: (title: CGFloat, preview: CGFloat, time: CGFloat) {
        FontSizeScale.inboxRowPointSizes(
            scale: appearanceEnv?.fontSizeScale ?? style.fontSizeScale,
            zoom: zoom
        )
    }

    private var titleText: String {
        if draft.selectedRecipients.count >= 2 {
            switch draft.mode {
            case .newGroup: return String(localized: "New Group Chat")
            case .blast: return String(localized: "New Blast Message")
            case .directChat: return String(localized: "New Chat")
            }
        }
        if draft.startsInMultiSelect || !draft.selectedRecipients.isEmpty {
            return String(localized: "New Group or Blast")
        }
        return String(localized: "New Chat")
    }

    private var subtitleText: String {
        if !draft.selectedRecipients.isEmpty {
            return draft.selectedRecipients
                .map { $0.name.isEmpty ? $0.userID : $0.name }
                .joined(separator: ", ")
        }
        let trimmed = draft.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return String(localized: "Choose a person to message")
    }

    var body: some View {
        let avatarSize: CGFloat = style.compact ? 28 : 40
        HStack(spacing: style.compact ? 8 : 10) {
            ZStack {
                Circle()
                    .fill(themeAccent.opacity(0.16))
                Image(systemName: "square.and.pencil")
                    .font(.system(size: round(avatarSize * 0.42), weight: .semibold))
                    .foregroundStyle(themeAccent)
            }
            .frame(width: avatarSize, height: avatarSize)

            VStack(alignment: .leading, spacing: style.compact ? 1 : 3) {
                Text(titleText)
                    .font(.system(size: pointSizes.title, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitleText)
                    .font(.system(size: pointSizes.preview))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, style.compact ? 1 : 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox.newChatPlaceholderRow")
    }
}
