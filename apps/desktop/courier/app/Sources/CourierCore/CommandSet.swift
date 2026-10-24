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
    /// What to ask the person before running it, when it changes many chats at once; nil when it just runs. The
    /// command bar shows it with the command's title and runs the command only after a yes.
    public let confirmation: String?
    /// Whether it can do anything now. The bar greys out what can't.
    public let isEnabled: @MainActor () -> Bool
    /// Does it. What takes the engine is started and not waited for.
    public let run: @MainActor () -> Void
}

/// The inbox's and search's commands, registered here for the command bar, which part 4.7 builds.
public enum CommandSet {
    /// The 13 commands of the inventory ledger that act on the inbox, in its order.
    ///
    /// The four bulk commands ("Archive all …", "Mark all chats as read") carry a `confirmation` for the bar to ask
    /// first; `run` itself acts at once. The other nine have none.
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
                           confirmation: String(localized: "Archive every chat in this space? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAll(readOnly: false) }
            },
            CourierCommand(id: "Archive all chats older than a week",
                           title: String(localized: "Archive all chats older than a week"), keys: nil,
                           confirmation: String(localized: "Archive every chat in this space whose last message is over a week old? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAll(readOnly: false, olderThanDays: 7) }
            },
            CourierCommand(id: "Archive all read chats", title: String(localized: "Archive all read chats"),
                           keys: "⌘⇧E",
                           confirmation: String(localized: "Archive every chat in this space that has nothing unread? Pinned chats stay where they are. You can undo this."),
                           isEnabled: sweepable) {
                Task { _ = await inbox.archiveAllRead() }
            },
            CourierCommand(id: "Mark all chats as read", title: String(localized: "Mark all chats as read"),
                           keys: nil,
                           confirmation: String(localized: "Mark every unread chat in this space as read? Your networks are told too, so this can’t be undone."),
                           isEnabled: { hasUnread(inbox, spaces) }) {
                Task { await inbox.markAllRead() }
            },
            CourierCommand(id: "Next Chat", title: String(localized: "Next Chat"), keys: "⌘]", confirmation: nil,
                           isEnabled: { !inbox.rows.isEmpty }) {
                inbox.selectNext()
            },
            CourierCommand(id: "Show message requests", title: String(localized: "Show message requests"),
                           keys: nil, confirmation: nil, isEnabled: { true }) {
                spaces.select("requests")
            },
            CourierCommand(id: "Toggle space bar", title: String(localized: "Toggle space bar"), keys: "⌘S", confirmation: nil,
                           isEnabled: { true }) {
                inbox.preferences.showSpaceBar.toggle()
            },
            CourierCommand(id: "Edit spaces", title: String(localized: "Edit spaces"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                spaces.isEditing = true
            },
            CourierCommand(id: "Filter Chats", title: String(localized: "Filter Chats"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                inbox.cycleFilter()
            },
            CourierCommand(id: "Filter by folder type", title: String(localized: "Filter by folder type"),
                           keys: nil, confirmation: nil, isEnabled: { true }) {
                step(inbox, through: SpacesModel.placeFilters)
            },
            CourierCommand(id: "Filter by type", title: String(localized: "Filter by type"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                step(inbox, through: [.dms, .groups])
            },
            CourierCommand(id: "Filter by account", title: String(localized: "Filter by account"), keys: "⌘⌥A", confirmation: nil,
                           isEnabled: { nextAccount(inbox, spaces) != nil }) {
                if let next = nextAccount(inbox, spaces) { spaces.select(next.spaceID) }
            },
            CourierCommand(id: "Toggle chat selection mode", title: String(localized: "Toggle chat selection mode"),
                           keys: nil, confirmation: nil, isEnabled: { inbox.isSelecting || !inbox.rows.isEmpty }) {
                if inbox.isSelecting { inbox.endSelecting() } else { inbox.beginSelecting() }
            },
        ]
    }

    /// The three search commands, for the command bar: "Search chats" and "Search messages in all chats" open ⌘K's
    /// panel over every chat; "Search messages in current chat" opens it in the open chat (⌘F), and is off with no
    /// chat open. None asks first.
    @MainActor
    public static func search(_ search: SearchModel,
                              openRoomID: @escaping @MainActor () -> String?) -> [CourierCommand] {
        [
            CourierCommand(id: "Search chats", title: String(localized: "Search chats"), keys: "⌘K",
                           confirmation: nil, isEnabled: { true }) {
                search.show()
            },
            CourierCommand(id: "Search messages in all chats", title: String(localized: "Search messages in all chats"),
                           keys: "⌘K", confirmation: nil, isEnabled: { true }) {
                search.show()
            },
            CourierCommand(id: "Search messages in current chat",
                           title: String(localized: "Search messages in current chat"), keys: "⌘F",
                           confirmation: nil, isEnabled: { openRoomID() != nil }) {
                guard let roomID = openRoomID() else { return }
                search.show(in: roomID)
            },
        ]
    }

    /// The message commands of the ledger's command bar (02 §3.3, "Message" and "Navigation and global"; 02 §3.4.2
    /// items 5 and 8), for the command bar part 4.7 builds: Send later, Create quick reply from draft (it asks for a
    /// title), Edit, Forward, Unsend, Delete for me, Reply in thread, Reply privately and Mark as unread. Each acting on a message acts on the selected one, and is on only
    /// when `MessageActions.available` offers it for that message, as the message's menu does; running it does what
    /// the menu's item does (Unsend and Delete for Me still ask first, in their own words, so none carries a
    /// `confirmation`). Send later and the quick reply act on the composer's text.
    @MainActor
    public static func message(_ actions: MessageActionsModel, _ conversation: ConversationModel) -> [CourierCommand] {
        func offers(_ action: MessageAction) -> Bool {
            guard let selected = conversation.selectedMessage else { return false }
            return conversation.availableActions(for: selected).actions.contains(action)
        }
        func run(_ action: MessageAction) {
            guard let selected = conversation.selectedMessage else { return }
            Task { await actions.perform(action, on: selected.id) }
        }
        return [
            CourierCommand(id: "Send later", title: String(localized: "Send later"), keys: "⌘⇧L", confirmation: nil,
                           isEnabled: { conversation.composer.canSchedule }) {
                actions.requestSendLater()
            },
            CourierCommand(id: "Create quick reply from draft", title: String(localized: "Create quick reply from draft"),
                           keys: nil, confirmation: nil, isEnabled: { actions.canCreateQuickReply }) {
                actions.requestQuickReplyFromDraft()
            },
            CourierCommand(id: "Edit", title: String(localized: "Edit"), keys: "⌘T", confirmation: nil,
                           isEnabled: { offers(.edit) }) {
                guard let selected = conversation.selectedMessage, offers(.edit) else { return }
                conversation.composer.startEditing(selected)
            },
            CourierCommand(id: "Forward", title: String(localized: "Forward"), keys: "⌘⇧F", confirmation: nil,
                           isEnabled: { offers(.forward) }) {
                run(.forward)
            },
            CourierCommand(id: "Unsend", title: String(localized: "Unsend"), keys: nil, confirmation: nil,
                           isEnabled: { offers(.unsend) }) {
                run(.unsend)
            },
            CourierCommand(id: "Delete for me", title: String(localized: "Delete for me"), keys: nil,
                           confirmation: nil, isEnabled: { offers(.deleteForMe) }) {
                run(.deleteForMe)
            },
            CourierCommand(id: "Reply in thread", title: String(localized: "Reply in thread"), keys: "⌘↓",
                           confirmation: nil, isEnabled: { offers(.replyInThread) }) {
                run(.replyInThread)
            },
            CourierCommand(id: "Reply privately", title: String(localized: "Reply privately"), keys: nil,
                           confirmation: nil, isEnabled: { offers(.replyPrivately) }) {
                run(.replyPrivately)
            },
            CourierCommand(id: "Mark as unread", title: String(localized: "Mark as unread"), keys: nil,
                           confirmation: nil, isEnabled: { offers(.markUnread) }) {
                run(.markUnread)
            },
        ]
    }

    /// Incognito and the accounts (02 §2.6): "Turn on incognito mode" (and, while it is on, "Turn off incognito
    /// mode", the same ledger row's other state: only the one that applies is on), "Add Account" and "Accounts". Both
    /// account commands open Add a Network until the Accounts pane comes (4.6), where Add Another Account is offered
    /// for a linked network. The ledger's "Account" command (its pane is 4.6's) is not registered yet. Turning
    /// Incognito on asks about typing (`ConversationModel.setIncognito`), as Settings does. None asks first.
    @MainActor
    public static func accounts(_ login: LoginFlowModel, _ conversation: ConversationModel) -> [CourierCommand] {
        [
            CourierCommand(id: "Turn on incognito mode", title: String(localized: "Turn on incognito mode"), keys: nil,
                           confirmation: nil,
                           isEnabled: { !conversation.incognitoIsOn && conversation.isEntitled(.incognito) }) {
                conversation.setIncognito(true)
            },
            CourierCommand(id: "Turn off incognito mode", title: String(localized: "Turn off incognito mode"),
                           keys: nil, confirmation: nil, isEnabled: { conversation.incognitoIsOn }) {
                conversation.setIncognito(false)
            },
            CourierCommand(id: "Add Account", title: String(localized: "Add Account"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                login.showPicker()
            },
            CourierCommand(id: "Accounts", title: String(localized: "Accounts"), keys: nil, confirmation: nil,
                           isEnabled: { true }) {
                login.showPicker()
            },
        ]
    }

    /// Something in the space shown is unread. The bar's count says so for the whole space; the chats loaded say so
    /// only when the bar doesn't know the space yet.
    @MainActor
    private static func hasUnread(_ inbox: InboxModel, _ spaces: SpacesModel) -> Bool {
        if let space = spaces.spaces.first(where: { $0.spaceID == inbox.query.space }) { return space.unreadChats > 0 }
        return inbox.rows.contains { $0.isUnread }
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
