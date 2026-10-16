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
        /// The engine could not start the network; `detail` says why.
        case notStarted
    }

    /// The button on the banner.
    public enum Action: Equatable, Sendable {
        /// Starts that network's login again.
        case reconnect
        /// Asks for what the network needs before it can start (Telegram's api_id and api_hash).
        case setUp
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

/// The inbox: every chat newest first, the open chat, and what the accounts need.
///
/// The model reads `inbox.list` when the engine is greeted, on a resync, and when a change says a chat's row may
/// have changed. A burst of changes is read once: the first change opens a short window, changes inside it add
/// nothing, and the read follows. A change that comes while a read is in flight asks for one more read after it,
/// however many come, so a burst costs at most two reads and the list is never stale for long.
///
/// An answer is written only if it came from the client that is up now. A read that was in flight when the engine
/// restarted is dropped, and the new engine's greeting reads again.
@MainActor
public final class InboxModel: ObservableObject {
    /// Every chat, newest message first.
    @Published public private(set) var rows: [InboxRow] = []
    /// Whether the inbox has been read at least once from the engine that is up or was.
    @Published public private(set) var isLoaded = false

    /// "Reconnect" on a banner: start that network's login again. Task 9 sets it.
    public var onReconnect: @MainActor (_ network: String) -> Void = { _ in }
    /// "Set up" on a banner: ask for what the network needs. Task 9 sets it.
    public var onSetUp: @MainActor (_ network: String) -> Void = { _ in }
    /// "Add a network". Task 9 sets it.
    public var onAddNetwork: @MainActor () -> Void = {}

    private let appModel: AppModel
    private let window: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var subscription: AnyCancellable?

    /// The task that reads, from the first change until the last read is done. Nil when idle.
    private var reading: Task<Void, Never>?
    /// A read is in flight (or about to be, once the window is over): changes now ask for one more read.
    private var readInFlight = false
    private var readAgain = false

    /// - Parameters:
    ///   - window: how long changes are gathered before one read, in seconds.
    ///   - sleep: waits `window`; tests give one they can open.
    public init(appModel: AppModel, window: TimeInterval = 0.1,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) }) {
        self.appModel = appModel
        self.window = window
        self.sleep = sleep
        // The views watch this model; the open chat and the accounts are the app model's.
        subscription = appModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        appModel.onConnect { [weak self] _ in self?.requestRead(waiting: false) }
        appModel.onChange { [weak self] change in self?.handle(change) }
    }

    // MARK: - What the views show

    public var accounts: [Account] { appModel.accounts }

    /// The open chat's id. It is the app model's; a refresh never changes it.
    public var selectedRoomID: String? { appModel.selectedRoomID }

    /// The open chat's row, nil when nothing is open or the open chat is not in the list now.
    public var selectedRow: InboxRow? {
        guard let id = appModel.selectedRoomID else { return nil }
        return rows.first { $0.roomID == id }
    }

    public func select(_ roomID: String?) {
        appModel.selectedRoomID = roomID
    }

    /// A network's name for people, for its badge's tooltip: the engine's, or the network's own id before the
    /// accounts are read.
    public func networkName(_ network: String) -> String {
        accounts.first { $0.network == network }?.displayName ?? network
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
            case .notStarted:
                AccountBanner(network: account.network, displayName: account.displayName, reason: .notStarted,
                              detail: account.notStarted, action: account.network == "telegram" ? .setUp : nil)
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
        case .setUp: onSetUp(banner.network)
        case nil: break
        }
    }

    public func addNetwork() {
        onAddNetwork()
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

    /// The next chat with unread messages after the open one, and after the last, the first. Nothing moves when no
    /// other chat is unread.
    public func selectNextUnread() {
        guard !rows.isEmpty else { return }
        let start = selectedIndex ?? -1
        for step in 1 ... rows.count {
            let index = (start + step) % rows.count
            guard index != start else { continue }
            if rows[index].unread > 0 {
                select(rows[index].roomID)
                return
            }
        }
    }

    private var selectedIndex: Int? {
        guard let id = appModel.selectedRoomID else { return nil }
        return rows.firstIndex { $0.roomID == id }
    }

    // MARK: - Reading and muting

    /// Toggle read marks the open chat read when it has unread messages. Marking a chat unread is milestone 4.
    public var canToggleRead: Bool { (selectedRow?.unread ?? 0) > 0 }

    public var selectedRowIsMuted: Bool { selectedRow?.muted ?? false }

    public func toggleRead() async {
        guard let row = selectedRow, row.unread > 0, let client = appModel.client else { return }
        let _: Empty? = try? await client.call("room.markRead", RoomParams(roomID: row.roomID))
        // The engine says the marker moved too; this makes the list right even if that is slow.
        requestRead(waiting: false)
    }

    public func toggleMute() async {
        guard let row = selectedRow, let client = appModel.client else { return }
        let _: Empty? = try? await client.call("room.setMuted", SetMutedParams(roomID: row.roomID, muted: !row.muted))
        requestRead(waiting: false)
    }

    // MARK: - Keeping the list right

    /// A change the engine reported. Only a chat's row can change the list; the accounts are the app model's.
    public func handle(_ change: Change) {
        switch change {
        case .room, .event, .status, .read:
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

    /// Reads, and reads again for as long as changes came in during the read, each time after a window.
    private func readUntilQuiet() async {
        readInFlight = true
        repeat {
            readAgain = false
            await read()
            if readAgain { await sleep(window) }
        } while readAgain
        readInFlight = false
        reading = nil
    }

    private func read() async {
        guard let client = appModel.client else { return }
        let result: InboxResult? = try? await client.call("inbox.list", Empty())
        // The engine may have restarted while this was in flight: its answer is not today's.
        guard let result, client === appModel.client else { return }
        rows = Self.sorted(result.rooms)
        isLoaded = true
    }

    /// Newest first; chats with the same time in the id's order, so the list does not shuffle.
    static func sorted(_ rooms: [InboxRow]) -> [InboxRow] {
        rooms.sorted { ($0.lastTS, $1.roomID) > ($1.lastTS, $0.roomID) }
    }
}

/// The coalescing window's wait.
public func waitForInboxWindow(_ seconds: TimeInterval) async {
    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
}
