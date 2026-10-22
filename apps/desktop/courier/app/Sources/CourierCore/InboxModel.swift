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
    /// The engine's own words: the bridge's message, or why the network did not start. May be empty.
    public let detail: String
    public let action: Action?

    public var id: String { network }
}

/// One linked account in the strip at the top of the inbox.
public struct AccountStatusItem: Equatable, Identifiable, Sendable {
    public let network: String
    public let displayName: String
    /// The bridge is connecting, or has lost its connection and is trying again.
    public let isReconnecting: Bool

    public var id: String { network }
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

    /// The chats shown, in the engine's order for `query`.
    @Published public private(set) var rows: [InboxRow] = []
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

    /// The open chat's row was looked up because the list doesn't have it: its unread count is known only now,
    /// after the chat opened, for the conversation's "New" divider. The app sets it.
    public var onSelectedRowLookedUp: @MainActor (InboxRow) -> Void = { _ in }
    /// "Reconnect" on a banner: start that network's login again. Task 9 sets it.
    public var onReconnect: @MainActor (_ network: String) -> Void = { _ in }
    /// "Add a network". Task 9 sets it.
    public var onAddNetwork: @MainActor () -> Void = {}

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

    /// The list's row of a chat, else the open chat's looked-up row.
    private func knownRow(_ roomID: String) -> InboxRow? {
        rows.first { $0.roomID == roomID } ?? lookedUpRow.flatMap { $0.roomID == roomID ? $0 : nil }
    }

    /// Another chat opened: the row looked up for the last is let go, and one the list doesn't have is looked up,
    /// once, by id (as SearchModel reads the chat it searches in).
    private func selectionChanged(to roomID: String?) {
        // A lookup still out for the chat left behind isn't cancelled: a draft may be waiting on its answer.
        lookedUpRow = nil
        rowLookup = nil
        guard let roomID, !rows.contains(where: { $0.roomID == roomID }), let client = appModel.client else { return }
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

    /// Accounts that need the person, in the engine's order.
    public var banners: [AccountBanner] {
        accounts.compactMap { account in
            switch account.state {
            case .loggedOut:
                AccountBanner(network: account.network, displayName: account.displayName, reason: .loggedOut,
                              detail: account.error, action: .reconnect)
            case .badCredentials:
                AccountBanner(network: account.network, displayName: account.displayName, reason: .badCredentials,
                              detail: account.error, action: .reconnect)
            case .unknownError:
                AccountBanner(network: account.network, displayName: account.displayName, reason: .unknownError,
                              detail: account.error, action: .reconnect)
            case .notStarted:
                // Telegram without an app ID is not a fault: Add a network asks for the keys when it is picked.
                // Nor is the "not started" of a list that is not the connected engine's word: the engine is not up,
                // or it is up and has not yet answered accounts.list, so the list is still the previous engine's (as
                // when the engine restarts to start Telegram with keys just saved).
                account.network == "telegram"
                    && (appModel.engineState != .connected || appModel.accountsReadAt == nil || !telegramHasKeys)
                    ? nil
                    : AccountBanner(network: account.network, displayName: account.displayName,
                                    reason: .notStarted, detail: account.notStarted, action: nil)
            default:
                nil
            }
        }
    }

    /// One item per linked account, in the engine's order.
    public var statusItems: [AccountStatusItem] {
        accounts.filter(Self.isLinked).map {
            AccountStatusItem(network: $0.network, displayName: $0.displayName,
                              isReconnecting: Self.reconnectingStates.contains($0.state))
        }
    }

    /// No network is linked yet, so the window offers to add one. False until the engine has listed its accounts.
    public var showsAddNetwork: Bool {
        !accounts.isEmpty && !accounts.contains(where: Self.isLinked)
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
        linkedStates.contains(account.state) || !account.remoteName.isEmpty
    }

    public func perform(_ banner: AccountBanner) {
        switch banner.action {
        case .reconnect: onReconnect(banner.network)
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
        select(rows[target].roomID)
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
                select(rows[index].roomID)
                return
            }
        }
    }

    private var selectedIndex: Int? {
        guard let id = appModel.selectedRoomID else { return nil }
        return rows.firstIndex { $0.roomID == id }
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
            var seen = Set(self.rows.map(\.roomID))
            self.rows += result.rooms.filter { seen.insert($0.roomID).inserted }
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
        let shown = rows.map(\.roomID).filter(selection.contains)
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
        let start = (cursor ?? anchor).flatMap { id in rows.firstIndex { $0.roomID == id } }
        let index: Int
        if let start {
            index = min(max(start + step, 0), rows.count - 1)
        } else {
            index = step > 0 ? 0 : rows.count - 1
        }
        let id = rows[index].roomID
        selection.insert(id)
        if anchor == nil { anchor = id }
        cursor = id
    }

    /// What plain E acts on: the chats selected while selecting; else, with no chat open, the chat the pointer or
    /// keyboard is on (`pointedAt`); else nothing (with a chat open, E is a letter, not a key).
    public func plainKeyTargets(pointedAt pointed: String?) -> [String] {
        if isSelecting { return targets }
        guard selectedRoomID == nil, let pointed else { return [] }
        return [pointed]
    }

    /// ⌃1–⌃9: opens the nth chat of the list. Past the last one, nothing happens.
    public func selectChat(number n: Int) {
        guard n >= 1, n <= rows.count else { return }
        select(rows[n - 1].roomID)
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
        guard let from = anchor.flatMap({ id in rows.firstIndex { $0.roomID == id } }),
              let to = rows.firstIndex(where: { $0.roomID == roomID }) else {
            selection.insert(roomID)
            anchor = roomID
            return
        }
        for row in rows[min(from, to) ... max(from, to)] { selection.insert(row.roomID) }
        cursor = roomID
    }

    /// ⌘A: every chat shown.
    public func selectAll() {
        beginSelecting()
        selection = Set(rows.map(\.roomID))
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
        let ids = beginAction(ids)
        guard !ids.isEmpty, let client = appModel.client else { return }
        let shown = rowsByID
        let next = neighbor(for: preferences.afterToggleRead, leaving: [], fallBack: false)
        if read {
            // room.markRead also clears an unread mark and a reminder that fired. A failure is shown by the read
            // below, which has the chat as the engine has it. A chat that isn't loaded is marked too.
            for id in ids where shown[id]?.isUnread ?? true {
                let _: Empty? = try? await client.call("room.markRead", RoomParams(roomID: id))
            }
        } else {
            _ = try? await changeEach("room.setMarkedUnread", ids) { RoomsFlagParams(roomIDs: $0, on: true) }
        }
        finishBulk()
        if let open = selectedRoomID, ids.contains(open) { apply(next) }
        requestRead(waiting: false)
    }

    /// Mutes the chats, or unmutes them when every one is muted already. A network that takes mutes hears it.
    public func toggleMute(ids: [String]? = nil) async {
        let ids = beginAction(ids)
        guard !ids.isEmpty, let client = appModel.client else { return }
        let shown = rowsByID
        let mute = !ids.allSatisfy { shown[$0]?.muted ?? false }
        for id in ids where shown[id]?.muted != mute {
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
        let ids = beginAction(ids)
        guard !ids.isEmpty else { return }
        let next = neighbor(for: preferences.afterArchive, leaving: Set(ids), fallBack: true)
        let markRead: Bool? = on && preferences.markReadOnArchive ? true : nil
        do {
            let changed = try await changeEach("room.setArchived", ids) {
                ArchiveParams(roomIDs: $0, archived: on, markRead: markRead)
            }
            finishBulk()
            if on {
                if let open = selectedRoomID, changed.contains(open) { apply(next) }
                showArchived(changed)
            }
        } catch {
            fail(error)
        }
        requestRead(waiting: false)
    }

    /// Pins the targets, or unpins them when every one is pinned already. A network that takes pins hears it.
    public func togglePin(ids: [String]? = nil) async {
        let ids = beginAction(ids)
        guard !ids.isEmpty, let client = appModel.client else { return }
        let shown = rowsByID
        let pin = !ids.allSatisfy { shown[$0]?.pinned ?? false }
        for id in ids {
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
        let ids = beginAction(ids)
        guard !ids.isEmpty else { return }
        do {
            _ = try await changeEach("room.setLabel", ids) { SetLabelParams(roomIDs: $0, labelID: id, on: on) }
            finishBulk()
        } catch {
            fail(error)
        }
        requestRead(waiting: false)
    }

    /// Low priority and hidden: a toast with Undo when turned on, which turns it off for exactly the chats changed.
    private func setFlag(_ method: String, _ on: Bool, ids: [String]?, toast message: String) async {
        let ids = beginAction(ids)
        guard !ids.isEmpty else { return }
        do {
            let changed = try await changeEach(method, ids) { RoomsFlagParams(roomIDs: $0, on: on) }
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
        let ids = beginAction(ids)
        guard !ids.isEmpty, let client = appModel.client else { return }
        let shown = rowsByID
        let archive = preferences.archiveAfterReminder
        let next = neighbor(for: preferences.afterArchive, leaving: Set(ids), fallBack: true)
        let dueAt = Self.millis(due)
        do {
            for chunk in ids.chunked(Self.batchSize) {
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
        let before = ids.map { (id: $0, reminder: shown[$0]?.reminder) }
        let archived = archive ? ids.filter { shown[$0].map { !$0.archived && !$0.pinned } ?? false } : []
        if let open = selectedRoomID, archived.contains(open) { apply(next) }
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
        let ids = beginAction(ids)
        guard !ids.isEmpty, let client = appModel.client else { return }
        for chunk in ids.chunked(Self.batchSize) {
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

    private func showArchived(_ changed: [String]) {
        guard !changed.isEmpty else { return }
        let message = changed.count == 1
            ? String(localized: "Archived 1 chat") : String(localized: "Archived \(changed.count) chats")
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

    /// A toast about something done outside this model (the spaces bar saved, say). It has no Undo.
    func announce(_ message: String) {
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
        Dictionary(rows.map { ($0.roomID, $0) }, uniquingKeysWith: { first, _ in first })
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
        let following = rows[(index + 1)...].first { !leaving.contains($0.roomID) }?.roomID
        let preceding = rows[..<index].last { !leaving.contains($0.roomID) }?.roomID
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
    /// row's preview (Delete for Me, a refused edit or unsend), and a scheduled one its place in Send Later. The
    /// accounts are the app model's.
    public func handle(_ change: Change) {
        switch change {
        case .room, .event, .status, .read, .spaces, .typing, .reminder, .scheduled:
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
        rows = collected
        nextCursor = cursor
        hasMore = cursor != nil
        firstPageOnly = false
        listVersion += 1
        isLoaded = true
        return true
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
