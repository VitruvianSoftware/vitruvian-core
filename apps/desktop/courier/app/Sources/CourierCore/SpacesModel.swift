// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// The spaces bar: the inbox, the built-in spaces, an account's chats and a label's chats, and which of them the
/// inbox shows.
///
/// The engine owns the bar (its order, what is hidden, the counts); this model holds the last list it read. It
/// reads when the engine is greeted (or at once, when it already is) and when a change says the bar may have
/// changed: a `spaces` change (labels, layout, settings), and a chat, message or read change, which move the
/// counts. Changes are gathered for a short window and read once, as `InboxModel` does. A failed read leaves the
/// bar as it was: the next change reads again.
@MainActor
public final class SpacesModel: ObservableObject {
    /// Choosing a space puts these filters away: they are places of their own, so they don't make sense inside
    /// another place.
    public static let placeFilters: [InboxFilter] = [.archived, .lowPriority, .hidden, .requests, .reminders, .sendLater]

    /// The spaces, visible ones first and then the hidden ones, as spaces.list orders them.
    @Published public private(set) var spaces: [Space] = []
    /// The Edit spaces screen is wanted: the command (and the bar's own button) turn it on, the view turns it off.
    @Published public var isEditing = false

    /// The spaces on the bar, in its order. ⌘1–⌘9 count these.
    public var visible: [Space] { spaces.filter { !$0.hidden } }

    private let appModel: AppModel
    private let inbox: InboxModel
    private let window: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var subscription: AnyCancellable?

    /// The task that reads, from the first change until the last read is done. Nil when idle.
    private var reading: Task<Void, Never>?
    private var readInFlight = false
    private var readAgain = false

    /// - Parameters:
    ///   - window: how long changes are gathered before one read, in seconds.
    ///   - sleep: waits `window`; tests give one they can open.
    public init(appModel: AppModel, inbox: InboxModel, window: TimeInterval = 0.1,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) }) {
        self.appModel = appModel
        self.inbox = inbox
        self.window = window
        self.sleep = sleep
        // The views watch this model; the inbox's query (the space shown) is the inbox's.
        subscription = inbox.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        appModel.onConnect { [weak self] _ in self?.requestRead(waiting: false) }
        appModel.onChange { [weak self] change in self?.handle(change) }
        // Built after the engine was greeted: its greeting is gone, so read now.
        if appModel.client != nil { requestRead(waiting: false) }
    }

    // MARK: - Choosing a space

    /// Shows a space's chats. The place filters (Archived, Low priority, Hidden, Requests, Reminders, Send later)
    /// go, since the space is the place; Unread, DMs and the others stay.
    public func select(_ spaceID: String) {
        var query = inbox.query
        query.space = spaceID
        query.filters.subtract(Self.placeFilters)
        inbox.query = query
    }

    /// ⌘1–⌘9: the nth space on the bar. Past the last one, nothing happens.
    public func selectNumber(_ n: Int) {
        let bar = visible
        guard n >= 1, n <= bar.count else { return }
        select(bar[n - 1].spaceID)
    }

    /// ⌘⇧]: the next space on the bar, and after the last the first. From a hidden space, the first.
    public func selectNextAccount() { move(by: 1) }

    /// ⌘⇧[: the previous space on the bar, and before the first the last. From a hidden space, the last.
    public func selectPreviousAccount() { move(by: -1) }

    private func move(by step: Int) {
        let bar = visible
        guard !bar.isEmpty else { return }
        let target: Int
        if let current = bar.firstIndex(where: { $0.spaceID == inbox.query.space }) {
            target = (current + step + bar.count) % bar.count
        } else {
            target = step > 0 ? 0 : bar.count - 1
        }
        select(bar[target].spaceID)
    }

    // MARK: - Changing the bar

    /// Saves the bar's order and what is hidden. The toast says so; a layout the engine refuses says why instead.
    public func saveLayout(order: [String], hidden: [String]) async {
        guard let client = appModel.client else { return }
        do {
            let _: Empty = try await client.call("spaces.setLayout", SpaceLayoutParams(order: order, hidden: hidden))
            inbox.announce(String(localized: "Sidebar updated"))
        } catch {
            inbox.report(error)
        }
        requestRead(waiting: false)
    }

    /// Mutes or unmutes an account's or a label's chats. A built-in space has no such setting.
    public func setMuted(_ spaceID: String, _ muted: Bool) async {
        await update(SpaceUpdateParams(spaceID: spaceID, muted: muted))
    }

    /// Which of an account's or a label's chats also show in the inbox: "all", "dms" or "none". Anything else is
    /// not asked of the engine.
    public func setShowInInbox(_ spaceID: String, _ value: String) async {
        let value = ShowInInbox(rawValue: value)
        guard ShowInInbox.settable.contains(value) else { return }
        await update(SpaceUpdateParams(spaceID: spaceID, showInInbox: value))
    }

    private func update(_ params: SpaceUpdateParams) async {
        guard let client = appModel.client else { return }
        do {
            let _: Empty = try await client.call("spaces.update", params)
        } catch {
            inbox.report(error)
        }
        requestRead(waiting: false)
    }

    // MARK: - Keeping the bar right

    /// Counts move with chats, messages and reads and reminders; the bar itself moves with a `spaces` change.
    /// Typing, a message's send status and a bridge's state change neither.
    func handle(_ change: Change) {
        switch change {
        case .spaces, .room, .event, .read, .reminder:
            requestRead(waiting: true)
        case .resync:
            requestRead(waiting: false)
        case .status, .typing, .bridge:
            break
        }
    }

    /// Asks for the bar to be read. `waiting`: gather changes for the window first.
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

    private func readUntilQuiet() async {
        readInFlight = true
        repeat {
            readAgain = false
            await read()
        } while readAgain
        readInFlight = false
        reading = nil
    }

    private func read() async {
        guard let client = appModel.client else { return }
        guard let result: SpacesResult = try? await client.call("spaces.list", Empty()),
              client === appModel.client else { return }
        if spaces != result.spaces { spaces = result.spaces }
        // The space shown is gone (its label was deleted): the inbox is what is left to show.
        if !result.spaces.isEmpty, !result.spaces.contains(where: { $0.spaceID == inbox.query.space }) {
            select("inbox")
        }
    }
}
