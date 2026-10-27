// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// A banner above the inbox: an account that needs the person.
public struct AccountBanner: Equatable, Identifiable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// The network ended the session.
        case loggedOut
        /// The network refused the saved sign-in.
        case badCredentials
        /// The bridge hit an error it could not get past; `detail` is its message.
        case unknownError
        /// The engine could not start the network; `detail` says why.
        case notStarted
    }

    /// The button on the banner.
    public enum Action: Equatable, Sendable {
        /// Starts that network's login again.
        case reconnect
    }

    public let network: String
    public let displayName: String
    public let reason: Reason
    /// The engine's own words: the bridge's message, or why the network did not start. May be empty. Help only,
    /// never the banner's title (no bridge English reaches a person as Courier's copy).
    public let detail: String
    public let action: Action?
    /// The account that needs the person (a `Login.accountID`): what Reconnect signs in again. Nil for a banner about
    /// the network as a whole (it did not start, or the engine lists no account for it).
    public let accountID: String?
    /// What the network calls that account, set only when the network has more than one: the banner names it.
    public let accountName: String?

    public init(network: String, displayName: String, reason: Reason, detail: String, action: Action?,
                accountID: String? = nil, accountName: String? = nil) {
        self.network = network
        self.displayName = displayName
        self.reason = reason
        self.detail = detail
        self.action = action
        self.accountID = accountID
        self.accountName = accountName
    }

    /// Network and account (C17): two accounts of one network are two banners.
    public var id: String { accountID.map { network + "\t" + $0 } ?? network }

    /// The network as the banner's title names it: "WhatsApp", or with more than one account "WhatsApp (+1 555 0101)".
    public var titleName: String {
        guard let accountName else { return displayName }
        return String(localized: "\(displayName) (\(accountName))")
    }
}

/// One linked account in the strip at the top of the inbox.
public struct AccountStatusItem: Equatable, Identifiable, Sendable {
    public let network: String
    public let displayName: String
    /// The bridge is connecting, or has lost its connection and is trying again.
    public let isReconnecting: Bool
    /// The engine hasn't started the network yet this session (STARTING): "Starting…".
    public let isStarting: Bool
    /// The account (a `Login.accountID`); nil when the engine lists none for a linked network.
    public let accountID: String?
    /// What the network calls the account, set only when the network has more than one.
    public let accountName: String?

    public init(network: String, displayName: String, isReconnecting: Bool, isStarting: Bool = false,
                accountID: String? = nil, accountName: String? = nil) {
        self.network = network
        self.displayName = displayName
        self.isReconnecting = isReconnecting
        self.isStarting = isStarting
        self.accountID = accountID
        self.accountName = accountName
    }

    /// Network and account (C17): two accounts of one network are two items.
    public var id: String { accountID.map { network + "\t" + $0 } ?? network }

    /// What the strip says beside the item's mark: "Starting…" while the engine hasn't started the network,
    /// "Reconnecting…" while the bridge is trying again; nil for a connected account, which says nothing.
    public var statusLabel: String? {
        if isStarting { return NetworkChoice.startingLabel }
        if isReconnecting { return String(localized: "Reconnecting…") }
        return nil
    }

    /// The item's tooltip: the network, named with its account when it has more than one ("WhatsApp (+1 555
    /// 0101)"), then the status, if any ("WhatsApp: Starting…").
    public var tooltip: String {
        let name = accountName.map { String(localized: "\(displayName) (\($0))") } ?? displayName
        guard let statusLabel else { return name }
        return String(localized: "account-status-tooltip", defaultValue: "\(name): \(statusLabel)",
                      comment: "The status strip's tooltip: the account, then its status.")
    }
}

/// The inbox: the chats a query lists, a page at a time, the open chat, the chats selected, and what the accounts
/// need.
///
/// **Pages.** The engine sorts and filters; the list is in its order. The first page is `pageSize` chats, and
/// `loadMore` reads the next with the last page's cursor. Only a null cursor is the last page: a page may hold
/// fewer chats than asked for (it ends early before 1 MiB) and still have more after it. A chat that moved between
/// two pages can come twice; the first copy is kept. Changing `query` reads its first page; no old cursor is
/// reused.
///
/// **Keeping the list right.** The model reads when the engine is greeted, on a resync, and when a change says a
/// row may have changed. A read starts at the top and reads as many chats as are shown (at least a page), in pages
/// of `refreshPageSize`, so a chat further down that changed is read again too. A burst of changes is read once:
/// the first change opens a short window, changes inside it add nothing, and the read follows. A change that comes
/// while a read is in flight asks for one more read after it, however many come.
///
/// An answer is written only if it came from the client that is up now, for the query that is shown now. A read
/// that was in flight when the engine restarted is dropped, and the new engine's greeting reads again.
///
/// **Actions** act on `targets`: the chats selected while selecting, else the open chat. A bulk action is one call
/// per 500 chats (the most the engine takes). What can be undone shows a toast with Undo, which reverses exactly the
/// chats the engine said it changed. Every state here is Courier's own, on this Mac; which of them a network also
/// hears is the engine's business (Account.syncs), and an unread mark never reaches one.
@MainActor
public final class InboxModel: ObservableObject {
    /// The chats in a page that `loadMore` reads, and the least a refresh reads.
    public static let pageSize = 200
    /// The chats in each page of a refresh.
    public static let refreshPageSize = 500
    /// The most chats one call may name (protocol.json's "1 to 500 chats").
    static let batchSize = 500
    /// Maximum number of recently viewed chat room IDs retained for the Dock menu.
    public static let maxRecentlyViewed = 20

    /// The chats shown, in the engine's order for `query`.
    @Published public private(set) var rows: [InboxRow] = []
    /// Most-recently-viewed chat room IDs (newest first), used by `DockMenuModel` for "Recent Chats".
    @Published public private(set) var recentlyViewedRoomIDs: [String] = []
    /// Whether the inbox has been read at least once from the engine that is up or was.
    @Published public private(set) var isLoaded = false
    /// What the inbox lists. A change reads the first page again.
    @Published public var query = InboxQuery() {
        didSet { if query != oldValue { queryChanged() } }
    }
    /// There are more chats after `rows`: `loadMore` reads them.
    @Published public private(set) var hasMore = false
    /// The chats selected, while selecting.
    @Published public private(set) var selection: Set<String> = []
    @Published public private(set) var isSelecting = false
    /// What was just done, with Undo when it can be. It goes after `toastDuration` or on the next action.
    @Published public private(set) var toast: Toast?
    /// Active Start New Chat / New Group / Blast modal draft (`⌘N` / `⌘⇧N`).
    @Published public var startNewChatDraft: StartNewChatDraft?
    /// Active Merge / Edit Merged Chat modal draft.
    @Published public var mergedChatEditorDraft: MergedChatEditorDraft?
    /// Known merged chats keyed by `mergeID` (`merge:xyz`), owned by `AppModel.mergedChats`.
    public var mergedChats: [String: MergedChat] {
        get { appModel.mergedChats }
        set { appModel.mergedChats = newValue }
    }

    /// The open chat's row was looked up because the list doesn't have it: its unread count is known only now,
    /// after the chat opened, for the conversation's "New" divider. The app sets it.
    public var onSelectedRowLookedUp: @MainActor (InboxRow) -> Void = { _ in }
    /// "Reconnect" on a banner: sign that account in again (`accountID`), or with nil the network's own sign-in. The
    /// app points it at the sign-in flow.
    public var onReconnect: @MainActor (_ network: String, _ accountID: String?) -> Void = { _, _ in }
    /// Incognito is on (`ConversationModel.incognitoIsOn`): "Mark chats read when I archive them" marks nothing read
    /// then. The app points it at the conversation.
    public var isIncognito: @MainActor () -> Bool = { false }
    /// "Add a network". The app points it at the sign-in flow's picker.
    public var onAddNetwork: @MainActor () -> Void = {}
    /// Opens a merged chat in the conversation view when a merged inbox row is selected.
    public var onOpenMergedChat: @MainActor (MergedChat) -> Void = { _ in }

    public let preferences: InboxPreferences
    private let entitlement: any EntitlementProvider
    private let appModel: AppModel
    private let hasTelegramCredentials: @MainActor () -> Bool
    /// What `hasTelegramCredentials` said, and for which accounts and which engine: reading the app bundle and the
    /// Keychain on every redraw of a view that shows `banners` would be wasteful, so it is asked once per change.
    private var telegramKeysAnswer: (accounts: [Account], connectedAt: Date?, has: Bool)?
    private let window: TimeInterval
    private let retryDelay: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let toastDuration: TimeInterval
    private let toastSleep: @Sendable (TimeInterval) async -> Void
    private var subscription: AnyCancellable?

    /// The task that reads, from the first change until the last read is done. Nil when idle.
    private var reading: Task<Void, Never>?
    /// A read is in flight (or about to be, once the window is over): changes now ask for one more read.
    private var readInFlight = false
    private var readAgain = false

    /// The cursor of the page after `rows`; nil when `rows` ends the list.
    private var nextCursor: String?
    /// Goes up with each new query: an answer for an older one is dropped.
    private var queryGeneration = 0
    /// Goes up each time a read replaces `rows`: a page read for the rows before it is dropped.
    private var listVersion = 0
    /// The next read is a new query's: its first page, not as many chats as the old query showed.
    private var firstPageOnly = false
    private var loadingMore: Task<Void, Never>?

    /// The chat a shift-click extends the selection from: the last one selected.
    private var anchor: String?
    /// The chat ⇧J and ⇧K last reached, where the next one moves from.
    private var cursor: String?
    private var undoAction: (@MainActor () async -> Void)?
    private var toastTimer: Task<Void, Never>?
    private var startNewChatSearchTask: Task<Void, Never>?

    /// The open chat's row when the list doesn't have it (a search opened an archived, hidden, low priority or
    /// request chat, or one past the pages read): looked up once by id when it opened, and kept until another chat
    /// opens. The list's own row wins whenever it has the chat.
    @Published private var lookedUpRow: InboxRow?
    /// The lookup in flight for the open chat, which a draft asked for meanwhile shares. `serial` tells a lookup
    /// from an older one for the same chat.
    private var rowLookup: (roomID: String, serial: Int, task: Task<InboxRow?, Never>)?
    private var lookupSerial = 0
    private var selectionSubscription: AnyCancellable?

    /// - Parameters:
    ///   - hasTelegramCredentials: whether the app has an app ID to start Telegram with (its own, or one the person
    ///     saved). Without one Telegram is "not started" by design, and Add a network asks for the keys, so that
    ///     is no banner; with one, a Telegram that did not start is a fault and says so. The default says it has.
    ///   - preferences: the inbox's settings. Required: the Settings screen, the notifications and this model must
    ///     share one object, because it reads the defaults once and a second copy would not see a change.
    ///   - entitlement: what the person's plan includes. A feature it doesn't is never asked of the engine.
    ///   - window: how long changes are gathered before one read, in seconds.
    ///   - retryDelay: how long after a failed read the next one waits, in seconds.
    ///   - sleep: waits `window` and `retryDelay`; tests give one they can open.
    ///   - toastDuration: how long a toast shows, in seconds.
    ///   - toastSleep: waits `toastDuration`; tests give one they can open.
    public init(appModel: AppModel, hasTelegramCredentials: @escaping @MainActor () -> Bool = { true },
                preferences: InboxPreferences, entitlement: any EntitlementProvider = AlwaysEntitled(),
                window: TimeInterval = 0.1, retryDelay: TimeInterval = 2,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) },
                toastDuration: TimeInterval = 6,
                toastSleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) }) {
        self.appModel = appModel
        self.hasTelegramCredentials = hasTelegramCredentials
        self.preferences = preferences
        self.entitlement = entitlement
        self.window = window
        self.retryDelay = retryDelay
        self.sleep = sleep
        self.toastDuration = toastDuration
        self.toastSleep = toastSleep
        // The views watch this model; the open chat and the accounts are the app model's.
        subscription = appModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        appModel.onConnect { [weak self] _ in self?.requestRead(waiting: false) }
        appModel.onChange { [weak self] change in self?.handle(change) }
        selectionSubscription = appModel.$selectedRoomID.removeDuplicates().sink { [weak self] roomID in
            self?.selectionChanged(to: roomID)
        }
    }

    // MARK: - What the views show

    public var accounts: [Account] { appModel.accounts }

    /// The open chat's id. It is the app model's; a refresh never changes it.
    public var selectedRoomID: String? { appModel.selectedRoomID }

    /// Whether `roomID` is currently open in the conversation pane (directly or as a member of the open merged chat).
    public func isOpen(_ roomID: String) -> Bool {
        appModel.isOpen(roomID: roomID)
    }

    /// The open chat's row: the list's, or for a chat the list doesn't have, the one looked up when it opened. Nil
    /// when nothing is open, or the open chat is neither in the list nor looked up (yet).
    public var selectedRow: InboxRow? {
        guard let id = appModel.selectedRoomID else { return nil }
        return knownRow(id)
    }

    /// A chat's unread count as the inbox knows it (its row's), for the "New" divider; 0 when it doesn't know.
    public func unreadCount(of roomID: String) -> Int {
        knownRow(roomID)?.unread ?? 0
    }

    /// A chat's draft as the engine keeps it, from the row the inbox has; nil when it has none (then
    /// `lookUpDraft`).
    public func savedDraft(of roomID: String) -> String? {
        knownRow(roomID)?.draft
    }

    /// A chat's row as the inbox knows it: the list's, else the open chat's looked-up row; nil when it has neither.
    public func row(of roomID: String) -> InboxRow? {
        knownRow(roomID)
    }

    /// The list's row of a chat, else the open chat's looked-up row.
    private func knownRow(_ roomID: String) -> InboxRow? {
        rows.first { $0.id == roomID || $0.roomID == roomID }
            ?? lookedUpRow.flatMap { ($0.id == roomID || $0.roomID == roomID) ? $0 : nil }
    }

    /// Records `roomID` at the front of `recentlyViewedRoomIDs` (deduplicated, capped at `maxRecentlyViewed`).
    public func recordRecentlyViewed(_ roomID: String) {
        guard !roomID.isEmpty, !roomID.hasPrefix("merge:") else { return }
        var updated = recentlyViewedRoomIDs.filter { $0 != roomID }
        updated.insert(roomID, at: 0)
        if updated.count > Self.maxRecentlyViewed {
            updated = Array(updated.prefix(Self.maxRecentlyViewed))
        }
        recentlyViewedRoomIDs = updated
    }

    /// Another chat opened: the row looked up for the last is let go, and one the list doesn't have is looked up,
    /// once, by id (as SearchModel reads the chat it searches in).
    private func selectionChanged(to roomID: String?) {
        if let roomID {
            recordRecentlyViewed(roomID)
        }
        // A lookup still out for the chat left behind isn't cancelled: a draft may be waiting on its answer.
        lookedUpRow = nil
        rowLookup = nil
        guard let roomID, !roomID.hasPrefix("merge:"),
              !rows.contains(where: { $0.id == roomID || $0.roomID == roomID }),
              let client = appModel.client else { return }
        lookupSerial += 1
        let serial = lookupSerial
        let task = Task<InboxRow?, Never> {
            let result: InboxResult? = try? await client.call("inbox.list", InboxListParams(roomIDs: [roomID]))
            return result?.rooms.first { $0.roomID == roomID }
        }
        rowLookup = (roomID, serial, task)
        Task { [weak self] in
            let row = await task.value
            guard let self, self.rowLookup?.serial == serial, client === self.appModel.client, let row else { return }
            self.lookedUpRow = row
            self.onSelectedRowLookedUp(row)
        }
    }

    public func select(_ roomID: String?) {
        if let roomID, !query.space.hasPrefix("account:") {
            if let merged = mergedChats[roomID] {
                onOpenMergedChat(merged)
                appModel.selectedRoomID = merged.mergeID
                return
            }
            if let row = rows.first(where: { $0.id == roomID }), !row.mergeID.isEmpty,
               let merged = mergedChats[row.mergeID] {
                onOpenMergedChat(merged)
                appModel.selectedRoomID = merged.mergeID
                return
            }
        }
        appModel.selectedRoomID = roomID
    }

    /// A network's name for people, for its badge's tooltip: the engine's, or the network's own id before the
    /// accounts are read.
    public func networkName(_ network: String) -> String {
        accounts.first { $0.network == network }?.displayName ?? network
    }

    /// Whether Telegram has an app ID, asked again only when the accounts or the engine that is up change.
    private var telegramHasKeys: Bool {
        let accounts = self.accounts
        let connectedAt = appModel.connectedAt
        if let answer = telegramKeysAnswer, answer.accounts == accounts, answer.connectedAt == connectedAt {
            return answer.has
        }
        let has = hasTelegramCredentials()
        telegramKeysAnswer = (accounts, connectedAt, has)
        return has
    }

    /// What needs the person, in the engine's order: one banner per account (login) that the network signed out,
    /// refused or stuck on an error, naming the account when the network has more than one; or one for a network
    /// that did not start. A network still starting (STARTING) has none, whatever its accounts last were. A network
    /// whose engine lists no account is read from its summary state, as before accounts had logins.
    public var banners: [AccountBanner] {
        accounts.flatMap { account -> [AccountBanner] in
            switch account.state {
            case .starting:
                return []
            case .notStarted:
                // Telegram without an app ID is not a fault: Add a network asks for the keys when it is picked.
                // Nor is the "not started" of a list that is not the connected engine's word: the engine is not up,
                // or it is up and has not yet answered accounts.list, so the list is still the previous engine's (as
                // when the engine restarts to start Telegram with keys just saved).
                if account.network == "telegram",
                   appModel.engineState != .connected || appModel.accountsReadAt == nil || !telegramHasKeys {
                    return []
                }
                return [AccountBanner(network: account.network, displayName: account.displayName,
                                      reason: .notStarted, detail: account.notStarted, action: nil)]
            default:
                break
            }
            guard !account.logins.isEmpty else {
                return Self.reason(of: account.state).map {
                    [AccountBanner(network: account.network, displayName: account.displayName, reason: $0,
                                   detail: account.error, action: .reconnect)]
                } ?? []
            }
            let named = account.logins.count > 1
            return account.logins.compactMap { login in
                Self.reason(of: login.state).map {
                    AccountBanner(network: account.network, displayName: account.displayName, reason: $0,
                                  detail: login.error, action: .reconnect, accountID: login.accountID,
                                  accountName: named ? Self.name(of: login) : nil)
                }
            }
        }
    }

    /// Why an account in `state` needs the person; nil when it doesn't.
    private static func reason(of state: AccountState) -> AccountBanner.Reason? {
        switch state {
        case .loggedOut: .loggedOut
        case .badCredentials: .badCredentials
        case .unknownError: .unknownError
        default: nil
        }
    }

    /// An account's name for a banner or the strip; nil when the network hasn't said.
    private static func name(of login: Login) -> String? {
        login.remoteName.isEmpty ? nil : login.remoteName
    }

    /// One item per linked account (each login, named when the network has more than one), in the engine's order.
    /// A network still starting shows its accounts as starting.
    public var statusItems: [AccountStatusItem] {
        accounts.filter(Self.isLinked).flatMap { account -> [AccountStatusItem] in
            let starting = account.state == .starting
            guard !account.logins.isEmpty else {
                return [AccountStatusItem(network: account.network, displayName: account.displayName,
                                          isReconnecting: !starting && Self.reconnectingStates.contains(account.state),
                                          isStarting: starting)]
            }
            let named = account.logins.count > 1
            return account.logins.map { login in
                AccountStatusItem(network: account.network, displayName: account.displayName,
                                  isReconnecting: !starting && Self.reconnectingStates.contains(login.state),
                                  isStarting: starting, accountID: login.accountID,
                                  accountName: named ? Self.name(of: login) : nil)
            }
        }
    }

    /// Each network with an account linked, once, in the engine's order: what filters by network (search's account
    /// chip) lists, however many accounts a network has.
    public var linkedNetworks: [AccountStatusItem] {
        var seen = Set<String>()
        return statusItems.filter { seen.insert($0.network).inserted }
    }

    /// No network is linked yet, so the window offers to add one. False until the engine has listed its accounts,
    /// and while any network is still starting (its account may be about to come back).
    public var showsAddNetwork: Bool {
        !accounts.isEmpty && !accounts.contains(where: Self.isLinked)
            && !accounts.contains { $0.state == .starting }
    }

    /// The states in which the bridge is trying to get (back) online (spec §5, "Network drops").
    static let reconnectingStates: Set<AccountState> = [.connecting, .transientDisconnect, .bridgeUnreachable]

    /// States only an account that has been logged in reaches. The others (not started, unconfigured, starting,
    /// running) say nothing about a login, so a network is linked there only if the engine names its account.
    private static let linkedStates: Set<AccountState> = [
        .connecting, .backfilling, .connected, .transientDisconnect, .badCredentials, .unknownError, .loggedOut,
        .bridgeUnreachable,
    ]

    static func isLinked(_ account: Account) -> Bool {
        linkedStates.contains(account.state) || !account.remoteName.isEmpty || !account.logins.isEmpty
    }

    public func perform(_ banner: AccountBanner) {
        switch banner.action {
        case .reconnect: onReconnect(banner.network, banner.accountID)
        case nil: break
        }
    }

    public func addNetwork() {
        onAddNetwork()
    }

    /// A chat's draft as the engine keeps it, wherever the chat is: its row when loaded, else looked up by id.
    /// Nil when the engine doesn't answer or doesn't have the chat: the draft is unknown, not empty.
    public func lookUpDraft(_ roomID: String) async -> String? {
        if let row = knownRow(roomID) { return row.draft }
        if let lookup = rowLookup, lookup.roomID == roomID {
            // The open chat's row is being looked up already: its answer has the draft.
            let client = appModel.client
            let row = await lookup.task.value
            guard client === appModel.client else { return nil }
            return row?.draft
        }
        guard let client = appModel.client else { return nil }
        let result: InboxResult? = try? await client.call("inbox.list", InboxListParams(roomIDs: [roomID]))
        guard client === appModel.client else { return nil }
        return result?.rooms.first { $0.roomID == roomID }?.draft
    }

    // MARK: - Moving through the list

    public func selectNext() { move(by: 1) }
    public func selectPrevious() { move(by: -1) }

    /// With nothing open, next opens the first chat and previous the last. The list does not wrap.
    private func move(by step: Int) {
        guard !rows.isEmpty else { return }
        let target: Int
        if let current = selectedIndex {
            target = min(max(current + step, 0), rows.count - 1)
        } else {
            target = step > 0 ? 0 : rows.count - 1
        }
        select(rows[target].id)
    }

    /// The next unread chat after the open one (unread messages, or marked unread, which a fired reminder also
    /// does: `InboxRow.isUnread`), and after the last, the first. Nothing moves when no other chat is unread.
    public func selectNextUnread() {
        guard !rows.isEmpty else { return }
        let start = selectedIndex ?? -1
        for step in 1 ... rows.count {
            let index = (start + step) % rows.count
            guard index != start else { continue }
            if rows[index].isUnread {
                select(rows[index].id)
                return
            }
        }
    }

    private var selectedIndex: Int? {
        guard let id = appModel.selectedRoomID else { return nil }
        return rows.firstIndex { $0.id == id || $0.roomID == id }
    }

    // MARK: - Filters

    /// Cycle Filters (⌥Tab): Unread, Drafts, Unanswered, DMs, Groups, then All, one at a time. From any other
    /// filters it starts at Unread.
    public func cycleFilter() {
        let cycle = InboxFilter.cycle
        if query.filters.count == 1, let current = query.filters.first, let index = cycle.firstIndex(of: current) {
            query.filters = index + 1 < cycle.count ? [cycle[index + 1]] : []
        } else {
            query.filters = [cycle[0]]
        }
    }

    /// ⌘⇧Y: the Unread filter on or off, the other filters as they are.
    public func toggleUnreadFilter() {
        if query.filters.contains(.unread) {
            query.filters.remove(.unread)
        } else {
            query.filters.insert(.unread)
        }
    }

    // MARK: - Pages

    /// Reads the page after the chats shown. It does nothing on the last page, and waits for a refresh that is in
    /// flight so the two never write over each other.
    public func loadMore() async {
        if let running = loadingMore {
            await running.value
            return
        }
        if let reading { await reading.value }
        if let running = loadingMore { // another loadMore started while this one waited
            await running.value
            return
        }
        guard let cursor = nextCursor, let client = appModel.client else { return }
        let generation = queryGeneration
        let version = listVersion
        let params = query.params(cursor: cursor, limit: Self.pageSize)
        let task = Task { [weak self] in
            let result: InboxResult? = try? await client.call("inbox.list", params)
            guard let self, let result, client === self.appModel.client, generation == self.queryGeneration,
                  version == self.listVersion else { return }
            // A chat that moved up between the pages is in both: the first copy stays.
            var seenRooms = Set(self.rows.map(\.roomID))
            var seenIDs = Set(self.rows.map(\.id))
            let isAccountSpace = self.query.space.hasPrefix("account:")
            let pageRows: [InboxRow] = isAccountSpace
                ? result.rooms.map { var r = $0; r.mergeID = ""; return r }
                : result.rooms
            let combined = self.rows + pageRows.filter {
                seenRooms.insert($0.roomID).inserted && seenIDs.insert($0.id).inserted
            }
            self.rows = isAccountSpace
                ? combined
                : Self.collapseMergedRows(combined, mergedChats: self.mergedChats)
            self.nextCursor = result.nextCursor
            self.hasMore = result.nextCursor != nil
        }
        loadingMore = task
        await task.value
        loadingMore = nil
    }

    private func queryChanged() {
        queryGeneration += 1
        nextCursor = nil
        hasMore = false
        firstPageOnly = true
        requestRead(waiting: false)
    }

    // MARK: - Selecting

    /// The chats an action acts on: the selection while selecting (in the list's order), else the open chat.
    public var targets: [String] {
        guard isSelecting else { return selectedRoomID.map { [$0] } ?? [] }
        let shown = rows.map(\.id).filter(selection.contains)
        return shown + selection.subtracting(shown).sorted()
    }

    /// The rows of the chats an action would act on (`ids`, else `targets`) that are loaded, in that order. A menu
    /// reads them to say Archive or Unarchive, Pin or Unpin.
    public func targetRows(_ ids: [String]? = nil) -> [InboxRow] {
        let shown = rowsByID
        return (ids ?? targets).compactMap { shown[$0] }
    }

    /// Whether the person's plan includes a feature. A menu shows "Available with a plan" in place of an action
    /// it doesn't.
    public func isEntitled(_ feature: Feature) -> Bool { entitlement.isEntitled(feature) }

    /// Starts selecting, with the open chat selected.
    public func beginSelecting() {
        guard !isSelecting else { return }
        isSelecting = true
        selection = selectedRoomID.map { [$0] } ?? []
        anchor = selectedRoomID
        cursor = selectedRoomID
    }

    /// ⇧J (`step` 1) and ⇧K (-1): the chat below (above) the last one reached joins the selection. It starts
    /// selecting; from nothing open and nothing selected, ⇧J takes the first chat and ⇧K the last.
    public func extendSelection(by step: Int) {
        guard !rows.isEmpty else { return }
        beginSelecting()
        let start = (cursor ?? anchor).flatMap { id in rows.firstIndex { $0.id == id || $0.roomID == id } }
        let index: Int
        if let start {
            index = min(max(start + step, 0), rows.count - 1)
        } else {
            index = step > 0 ? 0 : rows.count - 1
        }
        let id = rows[index].id
        selection.insert(id)
        if anchor == nil { anchor = id }
        cursor = id
    }

    /// What plain E acts on: the chats selected while selecting; else, with no chat open, the chat the pointer or
    /// keyboard is on (`pointedAt`); else nothing (with a chat open, E is a letter, not a key).
    public func plainKeyTargets(pointedAt pointed: String?) -> [String] {
        if isSelecting { return targets }
        guard appModel.openRoomIDs.isEmpty, let pointed else { return [] }
        return [pointed]
    }

    /// ⌃1–⌃9: opens the nth chat of the list. Past the last one, nothing happens.
    public func selectChat(number n: Int) {
        guard n >= 1, n <= rows.count else { return }
        select(rows[n - 1].id)
    }

    /// A row came into view. Within the last `loadMoreMargin` rows, the next page is read.
    public func rowAppeared(at index: Int) {
        guard hasMore, index >= rows.count - Self.loadMoreMargin else { return }
        Task { await loadMore() }
    }

    /// How close to the end of the list a row that appears reads the next page.
    public static let loadMoreMargin = 20

    /// ⌘-click: a chat in or out of the selection. It starts selecting.
    public func toggleSelected(_ roomID: String) {
        beginSelecting()
        if selection.remove(roomID) == nil {
            selection.insert(roomID)
            anchor = roomID
        }
        cursor = roomID
    }

    /// ⇧-click: every chat from the last one selected to this one, in the list's order.
    public func extendSelection(to roomID: String) {
        beginSelecting()
        guard let from = anchor.flatMap({ id in rows.firstIndex { $0.id == id || $0.roomID == id } }),
              let to = rows.firstIndex(where: { $0.id == roomID || $0.roomID == roomID }) else {
            selection.insert(roomID)
            anchor = roomID
            return
        }
        for row in rows[min(from, to) ... max(from, to)] { selection.insert(row.id) }
        cursor = roomID
    }

    /// ⌘A: every chat shown.
    public func selectAll() {
        beginSelecting()
        selection = Set(rows.map(\.id))
    }

    public func endSelecting() {
        isSelecting = false
        selection = []
        anchor = nil
        cursor = nil
    }

    /// Escape: it ends selecting first. False when there was nothing to end, so the key can do something else.
    public func escape() -> Bool {
        guard isSelecting else { return false }
        endSelecting()
        return true
    }

    // MARK: - Reading and muting

    /// Toggle read (⌘⇧U) has something to act on.
    public var canToggleRead: Bool { !targets.isEmpty }

    /// Toggle read would mark the targets read (one of them is unread or marked unread), not unread.
    public var toggleReadMarksRead: Bool {
        let shown = rowsByID
        return targets.contains { shown[$0]?.isUnread ?? false }
    }

    public var selectedRowIsMuted: Bool { selectedRow?.muted ?? false }

    /// An unread or marked-unread chat is marked read; a read one is marked unread. The mark stays on this Mac:
    /// no network is told. Then `afterToggleRead` says which chat opens.
    ///
    /// Every action that takes `ids` acts on those chats (a context menu's), and with none on `targets`.
    public func toggleRead(ids: [String]? = nil) async {
        let chosen = ids ?? targets
        let shown = rowsByID
        await setRead(chosen.contains { shown[$0]?.isUnread ?? false }, ids: chosen)
    }

    /// Mark as Read (`read`) or Mark as Unread, whatever the chats are now. Marking read reaches the networks, as
    /// opening the chat does; an unread mark stays on this Mac. Then `afterToggleRead` says which chat opens.
    public func setRead(_ read: Bool, ids: [String]? = nil) async {
        let rawIDs = beginAction(ids)
        let expandedIDs = expandRoomIDs(rawIDs)
        guard !expandedIDs.isEmpty, let client = appModel.client else { return }
        let shown = rowsByID
        let mergedMemberSet = mergedMemberRoomSet(for: rawIDs)
        let after = planAfterToggleRead()
        if read {
            // room.markRead also clears an unread mark and a reminder that fired. A failure is shown by the read
            // below, which has the chat as the engine has it. A chat that isn't loaded is marked too.
            for id in expandedIDs where mergedMemberSet.contains(id) || (shown[id]?.isUnread ?? true) {
                let _: Empty? = try? await client.call("room.markRead", RoomParams(roomID: id))
            }
        } else {
            _ = try? await changeEach("room.setMarkedUnread", expandedIDs) { RoomsFlagParams(roomIDs: $0, on: true) }
        }
        finishBulk()
        if rawIDs.contains(where: { appModel.isOpen(roomID: $0) })
            || expandedIDs.contains(where: { appModel.isOpen(roomID: $0) }) {
            after()
        }
        requestRead(waiting: false)
    }

    /// What "After marking the open chat read or unread" (`afterToggleRead`) does, worked out from the list as it is
    /// now; call what it returns once the mark is made. The one rule for Mark as Read and Unread here and for Mark as
    /// Unread from a message (`ConversationModel.markUnread`), which the app points at this.
    public func planAfterToggleRead() -> @MainActor () -> Void {
        let next = neighbor(for: preferences.afterToggleRead, leaving: [], fallBack: false)
        return { [weak self] in self?.apply(next) }
    }

    /// Mutes the chats, or unmutes them when every one is muted already. A network that takes mutes hears it.
    public func toggleMute(ids: [String]? = nil) async {
        let rawIDs = beginAction(ids)
        let expandedIDs = expandRoomIDs(rawIDs)
        guard !expandedIDs.isEmpty, let client = appModel.client else { return }
        let shown = rowsByID
        let mergedMemberSet = mergedMemberRoomSet(for: rawIDs)
        let mute = !rawIDs.allSatisfy { shown[$0]?.muted ?? false }
        for id in expandedIDs where mergedMemberSet.contains(id) || shown[id]?.muted != mute {
            // Ignored on failure: the read below shows the truth.
            let _: Empty? = try? await client.call("room.setMuted", SetMutedParams(roomID: id, muted: mute))
        }
        finishBulk()
        requestRead(waiting: false)
    }

    // MARK: - Archive, pin, low priority, hide, labels

    /// Archives the targets, or brings them back. A pinned chat is never archived: when every one is, the toast
    /// says to unpin. Archiving says how many with Undo, and then `afterArchive` says which chat opens.
    public func archive(_ on: Bool, ids: [String]? = nil) async {
        let rawIDs = beginAction(ids)
        let expandedIDs = expandRoomIDs(rawIDs)
        guard !expandedIDs.isEmpty else { return }
        let beforeRows = await rowsBeforeAction(expandedIDs, mergedMemberSet: mergedMemberRoomSet(for: rawIDs))
        let leavingSet = Set(rawIDs).union(expandedIDs)
        let next = neighbor(for: preferences.afterArchive, leaving: leavingSet, fallBack: true)
        // Incognito's promise wins: in it, the chat archives unread.
        let markRead: Bool? = on && preferences.markReadOnArchive && !isIncognito() ? true : nil
        do {
            let rawChanged = try await changeEach("room.setArchived", expandedIDs) {
                ArchiveParams(roomIDs: $0, archived: on, markRead: markRead)
            }
            let changed = rawChanged.filter { id in
                beforeRows[id].map { $0.archived != on && (!on || !$0.pinned) } ?? true
            }
            finishBulk()
            if on {
                if changed.contains(where: { appModel.isOpen(roomID: $0) })
                    || (!changed.isEmpty && leavingSet.contains(where: { appModel.isOpen(roomID: $0) })) {
                    apply(next)
                }
                showArchived(changed)
            }
        } catch {
            fail(error)
        }
        requestRead(waiting: false)
    }

    /// Pins the targets, or unpins them when every one is pinned already. A network that takes pins hears it.
    public func togglePin(ids: [String]? = nil) async {
        let rawIDs = beginAction(ids)
        let expandedIDs = expandRoomIDs(rawIDs)
        guard !expandedIDs.isEmpty, let client = appModel.client else { return }
        let shown = rowsByID
        let pin = !rawIDs.allSatisfy { shown[$0]?.pinned ?? false }
        for id in expandedIDs {
            // Ignored on failure, as toggleMute: the read below shows the truth.
            let _: Empty? = try? await client.call("room.setPinned", SetPinnedParams(roomID: id, pinned: pin))
        }
        finishBulk()
        requestRead(waiting: false)
    }

    /// Moves the targets to Low priority (part of a plan), or back (always).
    public func setLowPriority(_ on: Bool, ids: [String]? = nil) async {
        if on, !entitlement.isEntitled(.lowPriority) {
            denied()
            return
        }
        await setFlag("room.setLowPriority", on, ids: ids, toast: String(localized: "Moved to Low Priority"))
    }

    /// Hides the targets on this Mac, or shows them again.
    public func setHidden(_ on: Bool, ids: [String]? = nil) async {
        await setFlag("room.setHidden", on, ids: ids, toast: String(localized: "Hidden"))
    }

    /// Puts a label on the targets, or takes it off.
    public func setLabel(_ id: Int64, on: Bool, ids: [String]? = nil) async {
        let expandedIDs = expandRoomIDs(beginAction(ids))
        guard !expandedIDs.isEmpty else { return }
        do {
            _ = try await changeEach("room.setLabel", expandedIDs) { SetLabelParams(roomIDs: $0, labelID: id, on: on) }
            finishBulk()
        } catch {
            fail(error)
        }
        requestRead(waiting: false)
    }

    /// Low priority and hidden: a toast with Undo when turned on, which turns it off for exactly the chats changed.
    private func setFlag(_ method: String, _ on: Bool, ids: [String]?, toast message: String) async {
        let expandedIDs = expandRoomIDs(beginAction(ids))
        guard !expandedIDs.isEmpty else { return }
        do {
            let changed = try await changeEach(method, expandedIDs) { RoomsFlagParams(roomIDs: $0, on: on) }
            finishBulk()
            if on, !changed.isEmpty {
                showToast(message) { [weak self] in
                    _ = try? await self?.changeEach(method, changed) { RoomsFlagParams(roomIDs: $0, on: false) }
                }
            }
        } catch {
            fail(error)
        }
        requestRead(waiting: false)
    }

    // MARK: - Reminders and requests

    /// Sets a reminder on the targets (part of a plan). With "Archive after setting a reminder" on, they are
    /// archived until it brings them back. Undo puts back the reminders they had and unarchives what it archived.
    public func remind(at due: Date, condition: RemindCondition, ids: [String]? = nil) async {
        guard entitlement.isEntitled(.reminders) else {
            denied()
            return
        }
        let rawIDs = beginAction(ids)
        let expandedIDs = expandRoomIDs(rawIDs)
        guard !expandedIDs.isEmpty, let client = appModel.client else { return }
        let beforeRows = await rowsBeforeAction(expandedIDs, mergedMemberSet: mergedMemberRoomSet(for: rawIDs))
        let archive = preferences.archiveAfterReminder
        let leavingSet = Set(rawIDs).union(expandedIDs)
        let next = neighbor(for: preferences.afterArchive, leaving: leavingSet, fallBack: true)
        let dueAt = Self.millis(due)
        do {
            for chunk in expandedIDs.chunked(Self.batchSize) {
                let _: Empty = try await client.call("reminder.set", ReminderParams(
                    roomIDs: chunk, dueAt: dueAt, condition: condition.wire, archive: archive ? true : nil))
            }
        } catch {
            fail(error)
            requestRead(waiting: false)
            return
        }
        finishBulk()
        preferences.lastUsedReminder = due
        // What to put back: the reminders the chats had, and which of them this archived (not ones archived
        // already, and never a pinned one, which the engine leaves where it is).
        let before = expandedIDs.map { (id: $0, reminder: beforeRows[$0]?.reminder) }
        let archived = archive ? expandedIDs.filter { beforeRows[$0].map { !$0.archived && !$0.pinned } ?? false } : []
        if archived.contains(where: { appModel.isOpen(roomID: $0) })
            || (archive && leavingSet.contains(where: { appModel.isOpen(roomID: $0) })) {
            apply(next)
        }
        let time = due.formatted(date: .abbreviated, time: .shortened)
        showToast(String(localized: "Reminder set for \(time)")) { [weak self] in
            await self?.restoreReminders(before, unarchiving: archived)
        }
        requestRead(waiting: false)
    }

    /// Undo of a reminder: a chat that had one still to come gets it back, the others lose theirs.
    private func restoreReminders(_ before: [(id: String, reminder: Reminder?)], unarchiving archived: [String]) async {
        guard let client = appModel.client else { return }
        let now = Self.millis(Date())
        var restore: [Reminder: [String]] = [:]
        var clear: [String] = []
        for item in before {
            if let reminder = item.reminder, !reminder.fired, reminder.dueAt > now {
                restore[reminder, default: []].append(item.id)
            } else {
                clear.append(item.id)
            }
        }
        for chunk in clear.chunked(Self.batchSize) {
            let _: Empty? = try? await client.call("reminder.clear", RoomsParams(roomIDs: chunk))
        }
        for (reminder, ids) in restore {
            for chunk in ids.chunked(Self.batchSize) {
                let _: Empty? = try? await client.call("reminder.set", ReminderParams(
                    roomIDs: chunk, dueAt: reminder.dueAt, condition: reminder.condition))
            }
        }
        _ = try? await changeEach("room.setArchived", archived) { ArchiveParams(roomIDs: $0, archived: false) }
    }

    /// Ends the targets' reminders, set or fired.
    public func dismissReminder(ids: [String]? = nil) async {
        let expandedIDs = expandRoomIDs(beginAction(ids))
        guard !expandedIDs.isEmpty, let client = appModel.client else { return }
        for chunk in expandedIDs.chunked(Self.batchSize) {
            let _: Empty? = try? await client.call("reminder.clear", RoomsParams(roomIDs: chunk))
        }
        finishBulk()
        requestRead(waiting: false)
    }

    /// Accepts the targets' message requests: they move to the inbox, and a network that takes accepts hears it.
    public func acceptRequest(ids: [String]? = nil) async {
        let ids = beginAction(ids)
        guard !ids.isEmpty, let client = appModel.client else { return }
        var failure: Error?
        for id in ids {
            do {
                let _: Empty = try await client.call("room.acceptRequest", RoomParams(roomID: id))
            } catch {
                failure = failure ?? error
            }
        }
        finishBulk()
        if let failure { fail(failure) }
        requestRead(waiting: false)
    }

    /// Declining a request hides the chat, on this Mac: the network is not told, and the chat is in Hidden.
    public func declineRequest(ids: [String]? = nil) async {
        await setHidden(true, ids: ids)
    }

    // MARK: - All at once

    /// The space shown can be swept: only the inbox, an account's or a label's can.
    public var canArchiveAll: Bool { Self.canSweep(query.space) }

    /// Only the inbox, an account's space or a label's can be swept.
    public static func canSweep(_ space: String) -> Bool {
        space == "inbox" || space.hasPrefix("account:") || space.hasPrefix("label:")
    }

    /// How many chats `archiveAll` would archive now, from the engine's dry run of the same sweep; nil when it
    /// couldn't say (no engine, a refusal): "couldn't check", never 0. `space` nil is the space shown.
    public func archiveAllCount(readOnly: Bool, olderThanDays days: Int = 0, space: String? = nil) async -> Int? {
        let space = space ?? query.space
        guard let client = appModel.client, Self.canSweep(space) else { return nil }
        let result: RoomsChanged? = try? await client.call("inbox.archiveMatching", ArchiveMatchingParams(
            space: space == "inbox" ? nil : space, readOnly: readOnly, olderThanMS: Int64(days) * 86_400_000,
            dryRun: true))
        return result?.roomIDs.count
    }

    /// "Archive all read": every chat the space lists with nothing unread, but pinned ones. Undo unarchives exactly
    /// those, and leaves alone the chats that were archived before. Returns how many it archived.
    public func archiveAllRead() async -> Int {
        await archiveAll(readOnly: true)
    }

    /// "Archive all" of the space shown: every chat it lists but pinned ones, or only the read ones, or only those
    /// whose newest message is older than `days` (0, or one of 3, 7, 14, 28, 90 or 365: the ages the engine
    /// offers). Undo unarchives exactly the chats this archived. Returns how many it archived.
    /// `space` nil is the space shown; an auto-archive section names its own.
    public func archiveAll(readOnly: Bool, olderThanDays days: Int = 0, space: String? = nil) async -> Int {
        dismissToast()
        let space = space ?? query.space
        guard let client = appModel.client, Self.canSweep(space) else { return 0 }
        let result: RoomsChanged
        do {
            result = try await client.call("inbox.archiveMatching", ArchiveMatchingParams(
                space: space == "inbox" ? nil : space, readOnly: readOnly, olderThanMS: Int64(days) * 86_400_000,
                dryRun: false))
        } catch {
            fail(error)
            return 0
        }
        showArchived(result.roomIDs)
        requestRead(waiting: false)
        return result.roomIDs.count
    }

    /// "Mark all chats as read": every unread chat the space shown lists. Each network is told, as when one chat is
    /// read. There is no Undo: a network has heard it. Returns how many it marked.
    @discardableResult
    public func markAllRead() async -> Int {
        dismissToast()
        guard let client = appModel.client else { return 0 }
        let space = query.space
        let result: RoomsChanged
        do {
            result = try await client.call("inbox.markAllRead", SpaceParams(space: space == "inbox" ? nil : space))
        } catch {
            fail(error)
            return 0
        }
        requestRead(waiting: false)
        return result.roomIDs.count
    }

    // MARK: - Toasts and undo

    /// ⌘Z while a toast with Undo shows: reverses what it did, for exactly the chats it changed.
    public func undo() async {
        guard toast?.canUndo == true, let action = undoAction else { return }
        dismissToast()
        await action()
        requestRead(waiting: false)
    }

    /// Counts `roomIDs` in rows the person saw: outside account spaces, member rooms of the same merged chat count as 1.
    private func visibleChatCount(for roomIDs: [String]) -> Int {
        guard !query.space.hasPrefix("account:") else { return roomIDs.count }
        var roomToMerge: [String: String] = [:]
        for (mergeID, merge) in mergedChats {
            for roomID in merge.roomIDs {
                roomToMerge[roomID] = mergeID
            }
        }
        for row in rows where !row.mergeID.isEmpty {
            roomToMerge[row.roomID] = row.mergeID
        }
        var seen = Set<String>()
        for id in roomIDs {
            seen.insert(roomToMerge[id] ?? id)
        }
        return seen.count
    }

    /// Pre-action rows keyed by `roomID` for `roomIDs`, fetching any member rooms of a merged chat that are not
    /// currently in `rows` so their pre-action `archived`, `pinned`, and `reminder` states are known accurately.
    private func rowsBeforeAction(_ roomIDs: [String], mergedMemberSet: Set<String>) async -> [String: InboxRow] {
        var map = Dictionary(rows.map { ($0.roomID, $0) }, uniquingKeysWith: { first, _ in first })
        if let lookedUp = selectedRow {
            if map[lookedUp.roomID] == nil { map[lookedUp.roomID] = lookedUp }
        }
        let missing = roomIDs.filter { map[$0] == nil && mergedMemberSet.contains($0) }
        if !missing.isEmpty, let client = appModel.client {
            for chunk in missing.chunked(Self.batchSize) {
                if let result: InboxResult = try? await client.call("inbox.list", InboxListParams(roomIDs: chunk)) {
                    for row in result.rooms {
                        map[row.roomID] = row
                    }
                }
            }
        }
        return map
    }

    private func showArchived(_ changed: [String]) {
        guard !changed.isEmpty else { return }
        let count = visibleChatCount(for: changed)
        let message = count == 1
            ? String(localized: "Archived 1 chat") : String(localized: "Archived \(count) chats")
        showToast(message) { [weak self] in
            _ = try? await self?.changeEach("room.setArchived", changed) { ArchiveParams(roomIDs: $0, archived: false) }
        }
    }

    private func showToast(_ message: String, undo: (@MainActor () async -> Void)? = nil) {
        toastTimer?.cancel()
        let shown = Toast(message: message, canUndo: undo != nil)
        toast = shown
        undoAction = undo
        toastTimer = Task { [weak self, toastSleep, toastDuration] in
            await toastSleep(toastDuration)
            guard let self, self.toast?.id == shown.id else { return }
            self.toast = nil
            self.undoAction = nil
        }
    }

    private func dismissToast() {
        toastTimer?.cancel()
        toastTimer = nil
        toast = nil
        undoAction = nil
    }

    /// A toast about something done outside this model (the spaces bar saved, a message unsent). It has no Undo.
    public func announce(_ message: String) {
        dismissToast()
        showToast(message)
    }

    /// The toast for an error from something done outside this model.
    func report(_ error: Error) {
        dismissToast()
        fail(error)
    }

    /// A feature the plan doesn't include: nothing is asked of the engine.
    private func denied() {
        dismissToast()
        showToast(String(localized: "Available with a plan"))
    }

    /// What went wrong, in the toast. The list is read again either way, and shows what the engine has.
    private func fail(_ error: Error) {
        if case let .rpc(code, _, _)? = error as? EngineError {
            switch code {
            case .pinned:
                showToast(String(localized: "Unpin a chat to archive it."))
                return
            case .notEntitled:
                showToast(String(localized: "Available with a plan"))
                return
            default:
                break
            }
        }
        showToast(EngineErrorText.text(for: error, fallback: String(localized: "That didn’t work. Try again.")))
    }

    // MARK: - Doing it

    /// The chats an action acts on: those given, else `targets`. A new action takes the toast down.
    private func beginAction(_ ids: [String]? = nil) -> [String] {
        dismissToast()
        return ids ?? targets
    }

    /// A bulk action is done: selecting ends.
    private func finishBulk() {
        if isSelecting { endSelecting() }
    }

    private var rowsByID: [String: InboxRow] {
        var map: [String: InboxRow] = [:]
        for row in rows {
            if map[row.id] == nil { map[row.id] = row }
            if map[row.roomID] == nil { map[row.roomID] = row }
        }
        return map
    }

    /// Expands any merged row ID (`merge:...`, or a row with a non-empty `mergeID`) to all of its member room IDs
    /// so organise actions apply to every member room. In account spaces (`account:<network>`), rows are unmerged.
    private func expandRoomIDs(_ ids: [String]) -> [String] {
        guard !query.space.hasPrefix("account:") else { return ids }
        let shown = rowsByID
        var out: [String] = []
        var seen = Set<String>()
        for id in ids {
            if let merged = mergedChats[id] {
                for roomID in merged.roomIDs where seen.insert(roomID).inserted {
                    out.append(roomID)
                }
            } else if let row = shown[id], !row.mergeID.isEmpty, let merged = mergedChats[row.mergeID] {
                for roomID in merged.roomIDs where seen.insert(roomID).inserted {
                    out.append(roomID)
                }
            } else if seen.insert(id).inserted {
                out.append(id)
            }
        }
        return out
    }

    private func mergedMemberRoomSet(for ids: [String]) -> Set<String> {
        guard !query.space.hasPrefix("account:") else { return [] }
        let shown = rowsByID
        var out = Set<String>()
        for id in ids {
            if let merged = mergedChats[id] {
                out.formUnion(merged.roomIDs)
            } else if let row = shown[id], !row.mergeID.isEmpty, let merged = mergedChats[row.mergeID] {
                out.formUnion(merged.roomIDs)
            }
        }
        return out
    }

    /// Calls `method` for `ids`, at most `batchSize` a call, and answers every chat the engine said it changed, in
    /// order. A batch that fails is left out; when nothing changed and one failed, that failure is thrown.
    private func changeEach<P: Encodable & Sendable>(_ method: String, _ ids: [String],
                                                     _ params: ([String]) -> P) async throws -> [String] {
        guard !ids.isEmpty else { return [] }
        guard let client = appModel.client else { throw EngineError.notConnected }
        var changed: [String] = []
        var failure: Error?
        for chunk in ids.chunked(Self.batchSize) {
            do {
                let result: RoomsChanged = try await client.call(method, params(chunk))
                changed += result.roomIDs
            } catch {
                failure = failure ?? error
            }
        }
        if changed.isEmpty, let failure { throw failure }
        return changed
    }

    /// Where the open chat goes after an action.
    private enum Next {
        case keep
        case open(String?)
    }

    /// `leaving`: the chats the action takes out of the list, which are skipped. `fallBack`: with nothing after
    /// (or before) the open chat, take the other side, since the open chat is going.
    private func neighbor(for after: AfterAction, leaving: Set<String>, fallBack: Bool) -> Next {
        guard let index = selectedIndex else { return .keep }
        let following = rows[(index + 1)...].first { !leaving.contains($0.id) && !leaving.contains($0.roomID) }?.id
        let preceding = rows[..<index].last { !leaving.contains($0.id) && !leaving.contains($0.roomID) }?.id
        switch after {
        case .selectNext:
            if let following { return .open(following) }
            return fallBack ? .open(preceding) : .keep
        case .selectPrevious:
            if let preceding { return .open(preceding) }
            return fallBack ? .open(following) : .keep
        case .closeChat:
            return .open(nil)
        case .nothing:
            return .keep
        }
    }

    private func apply(_ next: Next) {
        if case let .open(id) = next { select(id) }
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: - Keeping the list right

    /// A change the engine reported. Rows change with a chat's events, read marker, name, typing and reminder, and
    /// with the spaces (a muted label changes many rows' muted_by with no room change). A status change can move a
    /// row's preview (Delete for Me, a refused edit or unsend), a scheduled one its place in Send Later, and a receipt
    /// its preview's status (sent, delivered, seen). The accounts are the app model's.
    public func handle(_ change: Change) {
        switch change {
        case .room, .event, .status, .read, .spaces, .typing, .reminder, .scheduled, .receipt:
            requestRead(waiting: true)
        case .resync:
            requestRead(waiting: false)
        case .bridge:
            break
        }
    }

    /// Asks for the inbox to be read. `waiting`: gather changes for the window first.
    private func requestRead(waiting: Bool) {
        if readInFlight {
            readAgain = true
            return
        }
        guard reading == nil else { return } // inside the window already: this change is covered
        let window = waiting ? window : nil
        reading = Task { [weak self, sleep] in
            if let window { await sleep(window) }
            await self?.readUntilQuiet()
        }
    }

    /// Reads, and reads again for as long as changes came in during the read, each time after a window. A read
    /// that failed (the engine did not answer in time) is tried again after `retryDelay`, so the list does not
    /// wait for the next change to show up.
    private func readUntilQuiet() async {
        readInFlight = true
        var again: Bool
        repeat {
            readAgain = false
            if let loadingMore { await loadingMore.value } // the rows it adds are shown, so they are read again
            if await read() {
                again = readAgain
                if again { await sleep(window) }
            } else {
                again = true
                await sleep(retryDelay)
            }
        } while again
        readInFlight = false
        reading = nil
    }

    /// Reads from the top as many chats as are shown (for a new query, one page), in pages of `refreshPageSize`,
    /// until it has that many or the cursor ends. False when the engine that is up failed to answer: the caller
    /// tries again.
    private func read() async -> Bool {
        guard let client = appModel.client else { return true }
        let generation = queryGeneration
        let query = self.query
        let wanted = firstPageOnly ? Self.pageSize : max(rows.count, Self.pageSize)
        var collected: [InboxRow] = []
        var seen = Set<String>()
        var cursor: String?
        repeat {
            let limit = min(Self.refreshPageSize, wanted - collected.count)
            let result: InboxResult
            do {
                result = try await client.call("inbox.list", query.params(cursor: cursor, limit: limit))
            } catch {
                // A client that is gone has nothing to retry: the new engine's greeting reads again.
                return client !== appModel.client
            }
            // The engine may have restarted while this was in flight: its answer is not today's. And a new query
            // has asked for a read of its own.
            guard client === appModel.client, generation == queryGeneration else { return true }
            // A chat that moved between pages is in both: the first copy stays.
            for row in result.rooms where seen.insert(row.roomID).inserted { collected.append(row) }
            cursor = result.nextCursor
            if result.rooms.isEmpty { break } // never spin on a page with nothing in it
        } while cursor != nil && collected.count < wanted
        if collected.contains(where: { !$0.mergeID.isEmpty || $0.roomID.hasPrefix("merge:") }) || !mergedChats.isEmpty {
            if let merges: MergeListResult = try? await client.call("merge.list", Empty()),
               client === appModel.client, generation == queryGeneration {
                mergedChats = Dictionary(
                    merges.mergedChats.map { ($0.mergeID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        }
        if query.space.hasPrefix("account:") {
            rows = collected.map { var r = $0; r.mergeID = ""; return r }
        } else {
            rows = Self.collapseMergedRows(collected, mergedChats: mergedChats)
        }
        nextCursor = cursor
        hasMore = cursor != nil
        firstPageOnly = false
        listVersion += 1
        isLoaded = true
        return true
    }

    /// Collapses member rows sharing a non-empty `mergeID` into a single row in the inbox,
    /// applying the merged chat's name/avatar and keeping the newest member row without re-summing unread counts
    /// (unread is summed across members in the engine only).
    public static func collapseMergedRows(_ input: [InboxRow], mergedChats: [String: MergedChat]) -> [InboxRow] {
        var result: [InboxRow] = []
        var firstIndexByMergeID: [String: Int] = [:]
        for var row in input {
            guard !row.mergeID.isEmpty else {
                result.append(row)
                continue
            }
            if let merged = mergedChats[row.mergeID] {
                if !merged.name.isEmpty { row.name = merged.name }
                if !merged.avatarPath.isEmpty { row.avatarPath = merged.avatarPath }
            }
            if let existingIndex = firstIndexByMergeID[row.mergeID] {
                if row.lastTS > result[existingIndex].lastTS {
                    result[existingIndex] = row
                }
            } else {
                firstIndexByMergeID[row.mergeID] = result.count
                result.append(row)
            }
        }
        return result
    }

    // MARK: - Start New Chat, New Group, Blasts, and Merged Chats (Task 11)

    /// Opens the Start New Chat sheet (`⌘N` when `multiSelect == false`, `⌘⇧N` when `multiSelect == true`).
    public func openStartNewChat(multiSelect: Bool = false) {
        let draft = StartNewChatDraft(
            accounts: accounts,
            candidates: [],
            startsInMultiSelect: multiSelect
        )
        startNewChatDraft = draft
        Task { [weak self] in
            await self?.refreshStartNewChatCandidates()
        }
    }

    /// Updates the Start New Chat search query and/or account filter, debounced by 300 ms.
    public func updateStartNewChatQuery(_ query: String, accountFilter: String? = nil) {
        guard startNewChatDraft != nil else { return }
        startNewChatDraft?.query = query
        if let accountFilter {
            startNewChatDraft?.selectedAccountFilter = accountFilter
        }
        scheduleStartNewChatSearch()
    }

    /// Updates the Start New Chat draft, debouncing contact search by 300 ms when the query or account filter changed.
    public func updateStartNewChatDraft(_ updated: StartNewChatDraft) {
        let queryChanged = startNewChatDraft?.query != updated.query
            || startNewChatDraft?.selectedAccountFilter != updated.selectedAccountFilter
        startNewChatDraft = updated
        if queryChanged {
            scheduleStartNewChatSearch()
        }
    }

    private func scheduleStartNewChatSearch() {
        startNewChatSearchTask?.cancel()
        let sleep = self.sleep
        startNewChatSearchTask = Task { [weak self] in
            await sleep(0.3)
            guard !Task.isCancelled else { return }
            await self?.refreshStartNewChatCandidates()
        }
    }

    /// Queries `people.contacts` for the current `startNewChatDraft` query and optional account filter.
    public func refreshStartNewChatCandidates() async {
        guard let draft = startNewChatDraft, let client = appModel.client else { return }
        let query = draft.query
        let filter = draft.selectedAccountFilter
        let params: PeopleContactsParams
        if let filter, let sep = filter.firstIndex(of: ":") {
            let net = String(filter[..<sep])
            let acc = String(filter[filter.index(after: sep)...])
            params = PeopleContactsParams(network: net, accountID: acc.isEmpty ? nil : acc, query: query.isEmpty ? nil : query)
        } else if let filter {
            params = PeopleContactsParams(network: filter, query: query.isEmpty ? nil : query)
        } else {
            params = PeopleContactsParams(query: query.isEmpty ? nil : query)
        }
        guard let result: PeopleContactsResult = try? await client.call("people.contacts", params) else { return }
        guard startNewChatDraft?.query == query, startNewChatDraft?.selectedAccountFilter == filter else { return }
        startNewChatDraft?.candidates = result.contacts
    }

    /// Opens or creates a 1:1 chat with `candidate` and closes the Start New Chat sheet.
    public func openDirectChat(with candidate: ContactCandidate) async {
        if let existingRoomID = candidate.roomID, !existingRoomID.isEmpty {
            startNewChatDraft = nil
            select(existingRoomID)
            return
        }
        guard let client = appModel.client else { return }
        startNewChatDraft?.isSubmitting = true
        startNewChatDraft?.errorMessage = nil
        do {
            let res: RoomResult = try await client.call(
                "room.directChat",
                DirectChatParams(network: candidate.network, accountID: candidate.accountID.isEmpty ? nil : candidate.accountID, userID: candidate.userID)
            )
            startNewChatDraft = nil
            requestRead(waiting: false)
            select(res.roomID)
        } catch {
            startNewChatDraft?.isSubmitting = false
            startNewChatDraft?.errorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t start a chat with that person.")
            )
        }
    }

    /// Resolves `action.query` on `action.network` / `action.accountID` via `people.resolve(startChat: true)`.
    public func performStartNewChatLookup(_ action: StartNewChatLookupAction) async {
        guard let client = appModel.client else { return }
        startNewChatDraft?.isSubmitting = true
        startNewChatDraft?.errorMessage = nil
        do {
            let contact: ContactCandidate = try await client.call(
                "people.resolve",
                PeopleResolveParams(
                    network: action.network,
                    accountID: action.accountID.isEmpty ? nil : action.accountID,
                    identifier: action.query.trimmingCharacters(in: .whitespacesAndNewlines),
                    startChat: true
                )
            )
            if let draft = startNewChatDraft, draft.startsInMultiSelect || !draft.selectedRecipients.isEmpty {
                startNewChatDraft?.isSubmitting = false
                startNewChatDraft?.toggleRecipient(contact)
            } else {
                startNewChatDraft = nil
                requestRead(waiting: false)
                if let roomID = contact.roomID, !roomID.isEmpty {
                    select(roomID)
                }
            }
        } catch {
            startNewChatDraft?.isSubmitting = false
            startNewChatDraft?.errorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t find anyone matching that on \(action.networkDisplayName).")
            )
        }
    }

    /// Creates a group chat via `room.createGroup` for the selected recipients in `startNewChatDraft`.
    public func submitNewGroupChat() async {
        guard let draft = startNewChatDraft,
              let first = draft.selectedRecipients.first,
              let client = appModel.client else { return }
        startNewChatDraft?.isSubmitting = true
        startNewChatDraft?.errorMessage = nil
        do {
            let result: RoomResult = try await client.call(
                "room.createGroup",
                CreateGroupParams(
                    network: first.network,
                    accountID: first.accountID.isEmpty ? nil : first.accountID,
                    name: draft.groupName.trimmingCharacters(in: .whitespacesAndNewlines),
                    userIDs: draft.selectedRecipients.map(\.userID)
                )
            )
            startNewChatDraft = nil
            requestRead(waiting: false)
            select(result.roomID)
        } catch {
            startNewChatDraft?.isSubmitting = false
            startNewChatDraft?.errorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t create the group.")
            )
        }
    }

    /// Ensures each recipient has a 1:1 `roomID`, then calls `blast.send` and records per-recipient outcomes.
    public func submitBlast() async {
        guard let draft = startNewChatDraft, let client = appModel.client else { return }
        let text = draft.blastText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        startNewChatDraft?.isSubmitting = true
        startNewChatDraft?.errorMessage = nil
        do {
            var resolvedRecipients: [ContactCandidate] = []
            for var recipient in draft.selectedRecipients {
                if recipient.roomID == nil || recipient.roomID?.isEmpty == true {
                    let dm: RoomResult = try await client.call(
                        "room.directChat",
                        DirectChatParams(network: recipient.network, accountID: recipient.accountID.isEmpty ? nil : recipient.accountID, userID: recipient.userID)
                    )
                    recipient.roomID = dm.roomID
                }
                resolvedRecipients.append(recipient)
            }
            startNewChatDraft?.replaceSelectedRecipients(resolvedRecipients)
            let messages: [BlastMessage] = resolvedRecipients.compactMap { recipient -> BlastMessage? in
                guard let roomID = recipient.roomID, !roomID.isEmpty else { return nil }
                let trimmedName = recipient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let isHandleOrPhone = trimmedName.isEmpty
                    || trimmedName == recipient.userID
                    || trimmedName.hasPrefix("@")
                    || recipient.identifiers.contains(trimmedName)
                    || ContactsBridge.normalizePhone(trimmedName) != nil
                let fullName = isHandleOrPhone ? "" : trimmedName
                let account = accounts.first { $0.network == recipient.network }
                let rawSender = (account?.logins.first { $0.accountID == recipient.accountID }?.remoteName ?? account?.remoteName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let senderIsHandle = rawSender.isEmpty || rawSender.hasPrefix("@") || ContactsBridge.normalizePhone(rawSender) != nil
                let senderFull = senderIsHandle ? "" : rawSender
                let expanded = QuickReplies.expand(
                    text,
                    context: QuickReplyContext(recipientFullName: fullName, senderFullName: senderFull)
                )
                return BlastMessage(roomID: roomID, text: expanded)
            }
            let result: BlastSendResult = try await client.call(
                "blast.send",
                BlastSendParams(messages: messages)
            )
            startNewChatDraft?.isSubmitting = false
            startNewChatDraft?.isConfirmingBlast = false
            startNewChatDraft?.applyBlastResults(result.events.map(BlastItemResult.init(event:)))
            requestRead(waiting: false)
        } catch {
            startNewChatDraft?.isSubmitting = false
            startNewChatDraft?.errorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t send the blast.")
            )
        }
    }

    /// Returns the merged chat definition for `row`, if it represents a merged chat.
    public func mergedChat(for row: InboxRow) -> MergedChat? {
        if !row.mergeID.isEmpty, let merged = mergedChats[row.mergeID] {
            return merged
        }
        if row.roomID.hasPrefix("merge:"), let merged = mergedChats[row.roomID] {
            return merged
        }
        return nil
    }

    /// Returns the list of networks for a merged row, or `[]` for an unmerged row.
    public func mergedNetworks(for row: InboxRow) -> [String] {
        mergedChat(for: row)?.networks ?? []
    }

    /// Replaces the cached merged chats dictionary (used by tests and `merge.*` updates).
    public func setMergedChats(_ chats: [MergedChat]) {
        mergedChats = Dictionary(chats.map { ($0.mergeID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Opens `MergedChatEditorSheet` for creating a merge starting with `row` or editing an existing merged chat.
    public func openMergeEditor(for row: InboxRow) {
        let existing = mergedChat(for: row)
        let directRooms = rows.filter { $0.isDirect && !$0.roomID.hasPrefix("merge:") }
        mergedChatEditorDraft = MergedChatEditorDraft(
            existingMerge: existing,
            initialRows: existing == nil ? [row] : [],
            suggestions: [],
            availableDirectRooms: directRooms.isEmpty ? [row] : directRooms
        )
        Task { [weak self] in
            guard let self, let client = self.appModel.client else { return }
            if let merges: MergeListResult = try? await client.call("merge.list", Empty()) {
                self.setMergedChats(merges.mergedChats)
                if self.mergedChatEditorDraft?.existingMerge == nil,
                   let found = self.mergedChat(for: row) {
                    self.mergedChatEditorDraft?.existingMerge = found
                    self.mergedChatEditorDraft?.name = found.name
                    self.mergedChatEditorDraft?.selectedRoomIDs = Set(found.roomIDs)
                    self.mergedChatEditorDraft?.orderedSelectedRoomIDs = found.roomIDs
                }
            }
            if let suggested: MergeSuggestResult = try? await client.call("merge.suggest", Empty()) {
                self.mergedChatEditorDraft?.suggestions = suggested.suggestions
            }
        }
    }

    /// Saves the active `mergedChatEditorDraft` via `merge.create` or `merge.update`.
    public func saveMergedChatEditor() async {
        guard let draft = mergedChatEditorDraft, draft.canSave, let client = appModel.client else { return }
        mergedChatEditorDraft?.isSubmitting = true
        mergedChatEditorDraft?.errorMessage = nil
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomIDs = draft.orderedSelectedRoomIDs.filter { draft.selectedRoomIDs.contains($0) }
        do {
            let saved: MergedChat
            if let existing = draft.existingMerge {
                saved = try await client.call(
                    "merge.update",
                    MergeUpdateParams(
                        mergeID: existing.mergeID,
                        name: name,
                        roomIDs: roomIDs,
                        lastRoomID: roomIDs.contains(existing.lastRoomID) ? existing.lastRoomID : roomIDs.first
                    )
                )
            } else {
                saved = try await client.call(
                    "merge.create",
                    MergeCreateParams(name: name, roomIDs: roomIDs)
                )
            }
            mergedChats[saved.mergeID] = saved
            mergedChatEditorDraft = nil
            requestRead(waiting: false)
        } catch {
            mergedChatEditorDraft?.isSubmitting = false
            mergedChatEditorDraft?.errorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t save the merged chat.")
            )
        }
    }

    /// Unmerges `mergeID` via `merge.delete`.
    public func unmergeChat(_ mergeID: String) async {
        guard let client = appModel.client else { return }
        mergedChatEditorDraft?.isSubmitting = true
        mergedChatEditorDraft?.errorMessage = nil
        do {
            let _: Empty = try await client.call("merge.delete", MergeDeleteParams(mergeID: mergeID))
            mergedChats.removeValue(forKey: mergeID)
            mergedChatEditorDraft = nil
            requestRead(waiting: false)
        } catch {
            mergedChatEditorDraft?.isSubmitting = false
            mergedChatEditorDraft?.errorMessage = EngineErrorText.text(
                for: error,
                fallback: String(localized: "Couldn’t unmerge the chat.")
            )
        }
    }
}

/// Which mode `StartNewChatView` is operating in.
public enum StartNewChatMode: String, Equatable, Sendable {
    case directChat
    case newGroup
    case blast
}

/// One room's delivery result from `blast.send`.
public struct BlastItemResult: Equatable, Sendable, Identifiable {
    public var id: String { roomID }
    public var roomID: String
    public var eventID: String
    public var status: String
    public var error: String

    public init(roomID: String, eventID: String = "", status: String, error: String = "") {
        self.roomID = roomID
        self.eventID = eventID
        self.status = status
        self.error = error
    }

    public init(event: Event) {
        self.roomID = event.roomID
        self.eventID = event.eventID
        self.status = event.status.rawValue
        self.error = Self.localizeStatusReason(event.statusReason)
    }

    /// Maps a fixed protocol `status_reason` code to localized Courier copy (never raw bridge text).
    public static func localizeStatusReason(_ reason: String) -> String {
        switch reason {
        case "":
            return ""
        case "not connected", "not_connected":
            return String(localized: "The account isn’t connected.")
        case "network_refused":
            return String(localized: "The network didn’t accept the message.")
        case "no account":
            return String(localized: "No account is signed in for this chat.")
        case "not sent":
            return String(localized: "Couldn’t send the message.")
        case "may have been sent":
            return String(localized: "The engine stopped before confirming whether this message was sent.")
        default:
            return String(localized: "Couldn’t send the message.")
        }
    }
}

/// Per-recipient blast status shown in `StartNewChatView` after sending.
public struct BlastRecipientOutcome: Equatable, Sendable, Identifiable {
    public var id: String { recipient.id }
    public let recipient: ContactCandidate
    public let roomID: String
    public let eventID: String
    public let status: String
    public let error: String

    public init(recipient: ContactCandidate, roomID: String, eventID: String, status: String, error: String) {
        self.recipient = recipient
        self.roomID = roomID
        self.eventID = eventID
        self.status = status
        self.error = error
    }
}

/// An action row offering to look up a phone number or `@username` on a specific connected account (`people.resolve`).
public struct StartNewChatLookupAction: Equatable, Sendable, Identifiable {
    public var id: String { "\(network):\(accountID)" }
    public let network: String
    public let networkDisplayName: String
    public let accountID: String
    public let accountLabel: String
    public let query: String

    public init(network: String, networkDisplayName: String, accountID: String, accountLabel: String, query: String) {
        self.network = network
        self.networkDisplayName = networkDisplayName
        self.accountID = accountID
        self.accountLabel = accountLabel
        self.query = query
    }

    public var title: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if accountLabel.isEmpty {
            return String(localized: "Look up \(trimmed) on \(networkDisplayName)")
        }
        return String(localized: "Look up \(trimmed) on \(networkDisplayName) (\(accountLabel))")
    }
}

/// Draft state for `StartNewChatView` (`⌘N` / `⌘⇧N`).
public struct StartNewChatDraft: Equatable, Sendable {
    public var accounts: [Account]
    public var candidates: [ContactCandidate]
    /// `nil` for All Networks, or `"<network>:<accountID>"` / `"<network>"`.
    public var selectedAccountFilter: String?
    public var startsInMultiSelect: Bool
    public var query: String
    public private(set) var selectedRecipients: [ContactCandidate]
    public var mode: StartNewChatMode
    public var groupName: String
    public var blastText: String
    public var isConfirmingBlast: Bool
    public private(set) var blastOutcomes: [BlastRecipientOutcome]
    public var errorMessage: String?
    public var isSubmitting: Bool

    public init(
        accounts: [Account] = [],
        candidates: [ContactCandidate] = [],
        selectedAccountFilter: String? = nil,
        startsInMultiSelect: Bool = false,
        query: String = "",
        selectedRecipients: [ContactCandidate] = [],
        mode: StartNewChatMode = .directChat,
        groupName: String = "",
        blastText: String = "",
        isConfirmingBlast: Bool = false,
        blastOutcomes: [BlastRecipientOutcome] = [],
        errorMessage: String? = nil,
        isSubmitting: Bool = false
    ) {
        self.accounts = accounts
        self.candidates = candidates
        self.selectedAccountFilter = selectedAccountFilter
        self.startsInMultiSelect = startsInMultiSelect
        self.query = query
        self.selectedRecipients = selectedRecipients
        self.mode = mode
        self.groupName = groupName
        self.blastText = blastText
        self.isConfirmingBlast = isConfirmingBlast
        self.blastOutcomes = blastOutcomes
        self.errorMessage = errorMessage
        self.isSubmitting = isSubmitting
        if selectedRecipients.count >= 2 {
            recomputeMode()
        }
    }

    public func isSelected(_ candidate: ContactCandidate) -> Bool {
        selectedRecipients.contains { $0.id == candidate.id }
    }

    public mutating func toggleRecipient(_ candidate: ContactCandidate) {
        if let index = selectedRecipients.firstIndex(where: { $0.id == candidate.id }) {
            selectedRecipients.remove(at: index)
        } else {
            selectedRecipients.append(candidate)
        }
        recomputeMode()
    }

    public mutating func removeRecipient(_ candidate: ContactCandidate) {
        selectedRecipients.removeAll { $0.id == candidate.id }
        recomputeMode()
    }

    public mutating func replaceSelectedRecipients(_ recipients: [ContactCandidate]) {
        selectedRecipients = recipients
        recomputeMode()
    }

    private mutating func recomputeMode() {
        if selectedRecipients.count < 2 {
            mode = .directChat
            isConfirmingBlast = false
        } else if !isNewGroupEnabled {
            mode = .blast
        } else if mode == .directChat {
            mode = .newGroup
        }
    }

    /// Why **New Group** is unavailable when 2+ recipients are selected, or `nil` when **New Group** is allowed.
    /// Follows Ruling 1: checks single network, single account, and `Account`/`Login.canCreateGroup`, never network names.
    public var newGroupDisabledReason: String? {
        guard selectedRecipients.count >= 2, let first = selectedRecipients.first else { return nil }
        let networks = Set(selectedRecipients.map(\.network))
        if networks.count > 1 {
            return String(localized: "Group members must be on the same network")
        }
        let accountIDs = Set(selectedRecipients.map(\.accountID))
        if accountIDs.count > 1 {
            return String(localized: "Group members must be on the same account")
        }
        if let account = accounts.first(where: { $0.network == first.network }) {
            let canCreate: Bool
            if !first.accountID.isEmpty,
               let login = account.logins.first(where: { $0.accountID == first.accountID }) {
                canCreate = login.canCreateGroup
            } else {
                canCreate = account.canCreateGroup
            }
            if !canCreate {
                return String(localized: "This account can’t create groups")
            }
        }
        return nil
    }

    public var isNewGroupEnabled: Bool {
        selectedRecipients.count >= 2 && newGroupDisabledReason == nil
    }

    public var isBlastEnabled: Bool {
        selectedRecipients.count >= 2
    }

    /// Distinct networks among the selected recipients, in selection order.
    public var blastNetworks: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for recipient in selectedRecipients where seen.insert(recipient.network).inserted {
            out.append(recipient.network)
        }
        return out
    }

    /// Confirmation copy required before sending a blast (Ruling 2: `"Send to 5 people on 3 networks?"`).
    public var blastConfirmationText: String {
        let peopleCount = selectedRecipients.count
        let networkCount = blastNetworks.count
        if networkCount == 1 {
            return String(localized: "Send to \(peopleCount) people on 1 network?")
        }
        return String(localized: "Send to \(peopleCount) people on \(networkCount) networks?")
    }

    public mutating func applyBlastResults(_ results: [BlastItemResult]) {
        var outcomes: [BlastRecipientOutcome] = []
        for (index, recipient) in selectedRecipients.enumerated() {
            if let recipientRoomID = recipient.roomID,
               !recipientRoomID.isEmpty,
               let matched = results.first(where: { $0.roomID == recipientRoomID }) {
                outcomes.append(
                    BlastRecipientOutcome(
                        recipient: recipient,
                        roomID: matched.roomID,
                        eventID: matched.eventID,
                        status: matched.status,
                        error: matched.error
                    )
                )
            } else if index < results.count {
                let item = results[index]
                outcomes.append(
                    BlastRecipientOutcome(
                        recipient: recipient,
                        roomID: item.roomID,
                        eventID: item.eventID,
                        status: item.status,
                        error: item.error
                    )
                )
            }
        }
        blastOutcomes = outcomes
    }

    /// Whether `query` looks like a phone number (`+...` or >= 7 digits) or `@username` for `people.resolve`.
    public var isLookupQuery: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("@") && trimmed.count >= 2 { return true }
        let digits = trimmed.filter(\.isNumber).count
        if trimmed.hasPrefix("+") && digits >= 5 { return true }
        return digits >= 7
    }

    /// Ruling 5: offers `"Look up <query> on <Network>"` on every connected account (filtered by `selectedAccountFilter`
    /// when set) without hard-coding per-network phone/username rules.
    public var lookupActions: [StartNewChatLookupAction] {
        guard isLookupQuery else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var actions: [StartNewChatLookupAction] = []
        for account in accounts {
            let matchingLogins = account.logins.filter { $0.state == .connected }
            let multipleLogins = matchingLogins.count > 1
            for login in matchingLogins {
                if let filter = selectedAccountFilter {
                    let filterKey = "\(account.network):\(login.accountID)"
                    if filter != filterKey && filter != account.network && filter != login.accountID {
                        continue
                    }
                }
                actions.append(
                    StartNewChatLookupAction(
                        network: account.network,
                        networkDisplayName: account.displayName,
                        accountID: login.accountID,
                        accountLabel: multipleLogins ? login.remoteName : "",
                        query: trimmed
                    )
                )
            }
        }
        return actions
    }

    /// Candidates filtered by the selected account pill and query text.
    public var filteredCandidates: [ContactCandidate] {
        let byAccount = candidates.filter { candidate in
            guard let filter = selectedAccountFilter else { return true }
            let key = "\(candidate.network):\(candidate.accountID)"
            return filter == key || filter == candidate.network || filter == candidate.accountID
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return byAccount }
        let matches = byAccount.filter { candidate in
            candidate.name.localizedCaseInsensitiveContains(trimmed)
                || candidate.userID.localizedCaseInsensitiveContains(trimmed)
                || candidate.identifiers.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
        return matches.isEmpty ? byAccount : matches
    }
}

/// Draft state for `MergedChatEditorSheet` (`merge.create`, `merge.update`, `merge.delete`, `merge.suggest`).
public struct MergedChatEditorDraft: Equatable, Sendable {
    public var existingMerge: MergedChat?
    public var name: String
    public var selectedRoomIDs: Set<String>
    public var orderedSelectedRoomIDs: [String]
    public var searchQuery: String
    public var suggestions: [MergeSuggestion]
    public var availableDirectRooms: [InboxRow]
    public var errorMessage: String?
    public var isSubmitting: Bool

    public init(
        existingMerge: MergedChat? = nil,
        initialRows: [InboxRow] = [],
        suggestions: [MergeSuggestion] = [],
        availableDirectRooms: [InboxRow] = [],
        searchQuery: String = "",
        errorMessage: String? = nil,
        isSubmitting: Bool = false
    ) {
        self.existingMerge = existingMerge
        if let existingMerge {
            self.name = existingMerge.name
            self.selectedRoomIDs = Set(existingMerge.roomIDs)
            self.orderedSelectedRoomIDs = existingMerge.roomIDs
        } else {
            self.name = initialRows.first?.name ?? ""
            self.selectedRoomIDs = Set(initialRows.map(\.roomID))
            self.orderedSelectedRoomIDs = initialRows.map(\.roomID)
        }
        self.searchQuery = searchQuery
        self.suggestions = suggestions
        self.availableDirectRooms = availableDirectRooms
        self.errorMessage = errorMessage
        self.isSubmitting = isSubmitting
    }

    public var canSave: Bool {
        selectedRoomIDs.count >= 2 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public mutating func toggleRoom(_ row: InboxRow) {
        if selectedRoomIDs.contains(row.roomID) {
            selectedRoomIDs.remove(row.roomID)
            orderedSelectedRoomIDs.removeAll { $0 == row.roomID }
        } else {
            selectedRoomIDs.insert(row.roomID)
            orderedSelectedRoomIDs.append(row.roomID)
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = row.name
            }
        }
    }

    public mutating func applySuggestion(_ suggestion: MergeSuggestion) {
        name = suggestion.displayName
        selectedRoomIDs = Set(suggestion.roomIDs)
        orderedSelectedRoomIDs = suggestion.roomIDs
    }

    public var filteredDirectRooms: [InboxRow] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableDirectRooms }
        return availableDirectRooms.filter { row in
            row.name.localizedCaseInsensitiveContains(trimmed)
                || row.network.localizedCaseInsensitiveContains(trimmed)
                || row.loginName.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

extension Array {
    /// The array in pieces of at most `size`, in order.
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}

/// The coalescing window's wait.
public func waitForInboxWindow(_ seconds: TimeInterval) async {
    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
}
