// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Something the person can ask for by name, from the command bar (⌘J, part 4.7).
public struct CourierCommand: Identifiable {
    /// The inventory ledger's name for it, in English, which never changes with the language.
    public let id: String
    /// What the person reads.
    public let title: String
    /// The shortcut as the menu shows it, when it has one.
    public let keys: String?
    /// Whether it can do anything now. The bar greys out what can't.
    public let isEnabled: @MainActor () -> Bool
    /// Does it. What takes the engine is started and not waited for.
    public let run: @MainActor () -> Void
}

/// The inbox's commands, registered here for the command bar, which part 4.7 builds.
public enum CommandSet {
    /// The 13 commands of the inventory ledger that act on the inbox, in its order.
    ///
    /// The bulk commands ("Archive all …", "Mark all chats as read") ask for a confirmation in the bar, which is
    /// the bar's to ask: here they act at once, and archiving can be undone.
    ///
    /// The filter commands step through their choices one at a time until the bar has the pickers that list them:
    /// Filter Chats is Cycle Filters (⌥Tab), Filter by folder type steps through Archived, Low priority, Hidden,
    /// Requests, Reminders and Send later and back to none, Filter by type through DMs, Groups and back to none, and
    /// Filter by account through the accounts.
    @MainActor
    public static func inbox(_ inbox: InboxModel, _ spaces: SpacesModel) -> [CourierCommand] {
        let sweepable: @MainActor () -> Bool = { inbox.isLoaded && inbox.canArchiveAll }
        return [
            CourierCommand(id: "Archive all chats", title: String(localized: "Archive all chats"), keys: nil,
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAll(readOnly: false) }
            },
            CourierCommand(id: "Archive all chats older than a week",
                           title: String(localized: "Archive all chats older than a week"), keys: nil,
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAll(readOnly: false, olderThanDays: 7) }
            },
            CourierCommand(id: "Archive all read chats", title: String(localized: "Archive all read chats"),
                           keys: "⌘⇧E", isEnabled: sweepable) {
                Task { _ = await inbox.archiveAllRead() }
            },
            CourierCommand(id: "Mark all chats as read", title: String(localized: "Mark all chats as read"),
                           keys: nil, isEnabled: { inbox.rows.contains { $0.isUnread } }) {
                Task { await inbox.markAllRead() }
            },
            CourierCommand(id: "Next Chat", title: String(localized: "Next Chat"), keys: "⌘]",
                           isEnabled: { !inbox.rows.isEmpty }) {
                inbox.selectNext()
            },
            CourierCommand(id: "Show message requests", title: String(localized: "Show message requests"),
                           keys: nil, isEnabled: { true }) {
                spaces.select("requests")
            },
            CourierCommand(id: "Toggle space bar", title: String(localized: "Toggle space bar"), keys: "⌘S",
                           isEnabled: { true }) {
                inbox.preferences.showSpaceBar.toggle()
            },
            CourierCommand(id: "Edit spaces", title: String(localized: "Edit spaces"), keys: nil,
                           isEnabled: { true }) {
                spaces.isEditing = true
            },
            CourierCommand(id: "Filter Chats", title: String(localized: "Filter Chats"), keys: nil,
                           isEnabled: { true }) {
                inbox.cycleFilter()
            },
            CourierCommand(id: "Filter by folder type", title: String(localized: "Filter by folder type"),
                           keys: nil, isEnabled: { true }) {
                step(inbox, through: SpacesModel.placeFilters)
            },
            CourierCommand(id: "Filter by type", title: String(localized: "Filter by type"), keys: nil,
                           isEnabled: { true }) {
                step(inbox, through: [.dms, .groups])
            },
            CourierCommand(id: "Filter by account", title: String(localized: "Filter by account"), keys: "⌘⌥A",
                           isEnabled: { nextAccount(inbox, spaces) != nil }) {
                if let next = nextAccount(inbox, spaces) { spaces.select(next.spaceID) }
            },
            CourierCommand(id: "Toggle chat selection mode", title: String(localized: "Toggle chat selection mode"),
                           keys: nil, isEnabled: { inbox.isSelecting || !inbox.rows.isEmpty }) {
                if inbox.isSelecting { inbox.endSelecting() } else { inbox.beginSelecting() }
            },
        ]
    }

    /// Replaces the one of `choices` that the query has with the next, and after the last with none. The query's
    /// other filters stay.
    @MainActor
    private static func step(_ inbox: InboxModel, through choices: [InboxFilter]) {
        var filters = inbox.query.filters
        let current = choices.firstIndex { filters.contains($0) }
        filters.subtract(choices)
        let next = current.map { $0 + 1 } ?? 0
        if next < choices.count { filters.insert(choices[next]) }
        inbox.query.filters = filters
    }

    /// The first account on the bar after the space shown, and after the last the first; nil with no account on the
    /// bar.
    @MainActor
    private static func nextAccount(_ inbox: InboxModel, _ spaces: SpacesModel) -> Space? {
        let bar = spaces.visible
        let accounts = bar.filter { $0.kind == .account }
        guard !accounts.isEmpty else { return nil }
        guard let here = bar.firstIndex(where: { $0.spaceID == inbox.query.space }) else { return accounts[0] }
        return bar[(here + 1)...].first { $0.kind == .account } ?? accounts[0]
    }
}
