// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Something the conversation could not do, shown in a bar above the composer.
public enum ConversationProblem: Equatable, Sendable {
    /// The newest messages could not be read.
    case loadFailed
    /// A reaction, retry or delete was refused or not answered. The text is for people.
    case actionFailed(String)
}

/// The open chat: its timeline, what is new in it, and its composer.
///
/// The timeline keeps the pages it has loaded. A change in the open chat (a new event, a status, the read marker)
/// reads the newest page again and merges it by event id, so older pages stay; a `resync`, and a new engine's
/// greeting, read the newest page and drop the older ones. A read that was in flight when the chat was closed, or
/// when the engine restarted, is dropped when its answer comes.
@MainActor
public final class ConversationModel: ObservableObject {
    public static let pageSize = 50
    /// The reactions offered on hover, the default first.
    public static let quickReactions = ["❤️", "👍", "😂", "😮", "😢", "🙏"]

    /// The open chat; nil when none is.
    @Published public private(set) var roomID: String?
    /// Oldest first.
    @Published public private(set) var items: [TimelineItem] = []
    /// The newest page of the open chat has been read.
    @Published public private(set) var isLoaded = false
    /// There are older messages than the ones loaded.
    @Published public private(set) var hasOlder = false
    @Published public private(set) var isLoadingOlder = false
    /// The last read of an older page failed: the view offers a button instead of trying again by itself.
    @Published public private(set) var olderFailed = false
    @Published public private(set) var problem: ConversationProblem?
    /// Messages from others that came while the chat was scrolled up: the jump-to-bottom button's count.
    @Published public private(set) var newMessageCount = 0
    @Published public private(set) var isAtBottom = true
    /// Goes up by one each time the view is asked to scroll to the newest message.
    @Published public private(set) var jumpToBottomRequest = 0
    /// The message a keyboard action (⌘R) is about.
    @Published public var selectedMessageID: String?
    /// The newest message of mine: the only one whose "Sent" is shown.
    public private(set) var lastOutgoingID: String?

    public let composer: ComposerModel
    /// Whether the person is looking at the open chat (see `Attention`): it is marked read only then.
    public let attention: Attention

    private let appModel: AppModel
    private let unreadCount: @MainActor (String) -> Int
    private let calendar: Calendar
    private var subscription: AnyCancellable?

    // What is loaded.
    private var events: [String: Event] = [:]
    private var seenIDs = Set<String>()
    private var olderCursor: Cursor?
    private var olderPagesLoaded = false
    private var firstUnreadID: String?
    private var unreadAtOpen = 0

    // Which answers still count.
    private var generation = 0
    private var pageEpoch = 0
    private var fetchSerial = 0
    private var appliedSerial = 0
    private var refetching = false
    private var refetchAgain = false
    /// A resync (or a new engine) asked for the older pages to be dropped, and no answer has done it yet. Whichever
    /// answer lands first does it, so a refetch that overtakes the resync's own read cannot keep them.
    private var dropPending = false

    // Reading.
    private var needsRead = false

    /// - Parameters:
    ///   - unreadCount: a chat's unread count as the inbox has it, read when the chat is opened (the "New" divider
    ///     goes above that many of the newest messages from others).
    ///   - attention: whether the person is looking; nil makes one that only follows `setWindowKey`.
    public init(appModel: AppModel, unreadCount: @escaping @MainActor (String) -> Int = { _ in 0 },
                attention: Attention? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.appModel = appModel
        self.unreadCount = unreadCount
        self.attention = attention ?? Attention(source: StaticPresence(), pollInterval: nil)
        self.calendar = calendar
        composer = ComposerModel(sender: EngineMessageSender(appModel: appModel))
        composer.onSettled = { [weak self] in self?.requestRefetch() }
        composer.onSubmit = { [weak self] in self?.jumpToBottom() }
        subscription = appModel.$selectedRoomID.removeDuplicates().sink { [weak self] room in
            self?.open(room)
        }
        appModel.onConnect { [weak self] client in await self?.reload(from: client) }
        appModel.onChange { [weak self] change in self?.handle(change) }
        self.attention.onReturn { [weak self] in self?.personReturned() }
    }

    // MARK: - Opening

    private func open(_ room: String?) {
        generation += 1
        pageEpoch += 1
        events = [:]
        seenIDs = []
        olderCursor = nil
        olderPagesLoaded = false
        firstUnreadID = nil
        unreadAtOpen = room.map { unreadCount($0) } ?? 0
        refetching = false
        refetchAgain = false
        dropPending = false
        needsRead = room != nil

        roomID = room
        items = []
        lastOutgoingID = nil
        isLoaded = false
        hasOlder = false
        isLoadingOlder = false
        olderFailed = false
        problem = nil
        newMessageCount = 0
        isAtBottom = true
        selectedMessageID = nil
        composer.open(room)

        if room != nil, appModel.client != nil { requestRefetch() }
    }

    // MARK: - Reading the engine

    /// The engine was greeted, or said `resync`: read the newest page, and forget the older ones.
    private func reload(from client: EngineClient) async {
        guard roomID != nil, client === appModel.client else { return }
        dropPending = true
        await fetchNewest()
    }

    /// "Try again" on the bar: read the newest page again.
    public func reload() {
        requestRefetch()
    }

    private func handle(_ change: Change) {
        guard let open = roomID else { return }
        switch change {
        case let .event(room, _), let .status(room, _), let .read(room, _):
            if room == open { requestRefetch() }
        case let .room(room):
            // With no room, names or pictures changed in chats unknown: this one may be among them.
            if room == nil || room == open { requestRefetch() }
        case .bridge, .resync:
            break // resync reads through the app model's connect hooks
        }
    }

    /// Reads the newest page. Changes that come while a read is in flight cost one more read, however many.
    private func requestRefetch() {
        guard roomID != nil else { return }
        if refetching {
            refetchAgain = true
            return
        }
        refetching = true
        let owner = generation
        Task { [weak self] in await self?.refetchUntilQuiet(owner: owner) }
    }

    private func refetchUntilQuiet(owner: Int) async {
        var again = true
        while again {
            refetchAgain = false
            await fetchNewest()
            guard owner == generation else { return } // another chat is open: it owns the flags now
            again = refetchAgain
        }
        refetching = false
    }

    private func fetchNewest() async {
        guard let room = roomID, let client = appModel.client else { return }
        let owner = generation
        fetchSerial += 1
        let serial = fetchSerial
        let page: EventsPage
        do {
            page = try await client.call("room.events", RoomEventsParams(roomID: room, limit: Self.pageSize))
        } catch {
            guard owner == generation, client === appModel.client else { return }
            problem = .loadFailed
            return
        }
        // Only the answer for the chat that is open now, from the engine that is up now, and not older than one
        // already shown.
        guard owner == generation, client === appModel.client, serial > appliedSerial else { return }
        appliedSerial = serial
        let drop = dropPending
        dropPending = false
        apply(page, dropOlder: drop)
    }

    private func apply(_ page: EventsPage, dropOlder: Bool) {
        let wasLoaded = isLoaded
        let pageIDs = Set(page.events.map(\.eventID))
        let fresh = page.events.filter { !seenIDs.contains($0.eventID) }

        // A page that does not reach back to what is loaded leaves a hole: more came than one page holds.
        var hasHole = false
        if page.before != nil, let oldestOfPage = page.events.last, let newestLoaded = events.values.map(Self.position).max() {
            hasHole = Self.position(oldestOfPage) > newestLoaded
        }
        if dropOlder || hasHole {
            events = [:]
            olderCursor = nil
            olderPagesLoaded = false
            pageEpoch += 1
        } else if let oldest = page.events.last {
            // What the page covers is what the engine has now: a message it no longer lists (discarded) goes.
            let from = Self.position(oldest)
            events = events.filter { Self.position($0.value) < from || pageIDs.contains($0.key) }
        } else {
            events = [:] // an empty page with nothing older: the chat has no events
        }
        for event in page.events { events[event.eventID] = event }
        seenIDs.formUnion(pageIDs)
        if !olderPagesLoaded { olderCursor = page.before }
        hasOlder = olderCursor != nil
        problem = nil

        if !wasLoaded {
            firstUnreadID = Timeline.firstUnreadID(events: Array(events.values), me: Timeline.meUserID,
                                                   unread: unreadAtOpen)
        }
        rebuild()
        isLoaded = true

        if !wasLoaded {
            if attention.isLooking { markRead() }
        } else {
            let incoming = fresh.filter(Timeline.isIncomingMessage)
            if !incoming.isEmpty {
                if !isAtBottom { newMessageCount += incoming.count }
                if attention.isLooking { markRead() } else { needsRead = true }
            }
        }
    }

    /// Where an event is in the chat's order: by time, then by arrival.
    private struct Position: Comparable {
        let ts: Int64
        let seq: Int64

        static func < (lhs: Position, rhs: Position) -> Bool { (lhs.ts, lhs.seq) < (rhs.ts, rhs.seq) }
    }

    private static func position(_ event: Event) -> Position { Position(ts: event.ts, seq: event.seq) }

    private func rebuild() {
        items = Timeline.build(events: Array(events.values), me: Timeline.meUserID, firstUnreadID: firstUnreadID,
                               calendar: calendar)
        lastOutgoingID = items.reversed().lazy.compactMap { item -> String? in
            if case let .message(message) = item, message.mine { message.id } else { nil }
        }.first
        if let selected = selectedMessageID, !items.contains(where: { $0.id == selected }) {
            selectedMessageID = nil
        }
    }

    // MARK: - Older messages

    /// Reads the next older page, when the view scrolls to the top.
    public func loadOlder() {
        guard let room = roomID, let cursor = olderCursor, !isLoadingOlder, let client = appModel.client else { return }
        isLoadingOlder = true
        olderFailed = false
        let owner = generation
        let epoch = pageEpoch
        Task { [weak self] in
            let page: EventsPage?
            do {
                page = try await client.call(
                    "room.events", RoomEventsParams(roomID: room, before: cursor, limit: Self.pageSize))
            } catch {
                page = nil
            }
            guard let self, owner == self.generation else { return }
            self.isLoadingOlder = false
            // The pages may have been dropped (a resync) while this was out: then it joins nothing.
            guard client === self.appModel.client, epoch == self.pageEpoch else { return }
            guard let page else {
                self.olderFailed = true
                return
            }
            for event in page.events {
                self.events[event.eventID] = event
                self.seenIDs.insert(event.eventID)
            }
            self.olderPagesLoaded = true
            self.olderCursor = page.before
            self.hasOlder = page.before != nil
            self.rebuild()
        }
    }

    // MARK: - Reading and scrolling

    /// The window of the open chat became key, or stopped being key (or the conversation view went away).
    public func setWindowKey(_ isKey: Bool) {
        attention.setWindowKey(isKey)
    }

    /// The person is looking again: what waited for them is read now.
    private func personReturned() {
        if needsRead, isLoaded { markRead() }
    }

    /// Tells the engine the open chat is read. The engine does nothing for a chat that already is.
    private func markRead() {
        needsRead = false
        guard let room = roomID, let client = appModel.client else { return }
        Task {
            // A failure is ignored: the unread count shows the truth the next time the inbox reads.
            let _: Empty? = try? await client.call("room.markRead", RoomParams(roomID: room))
        }
    }

    /// The view says whether the newest message is on screen.
    public func scrolled(toBottom: Bool) {
        guard isAtBottom != toBottom else { return }
        isAtBottom = toBottom
        if toBottom { newMessageCount = 0 }
    }

    /// ⌘↓, the jump button, and sending: scroll to the newest message.
    public func jumpToBottom() {
        jumpToBottomRequest += 1
    }

    // MARK: - Actions

    /// Starts a reply to the message in the composer.
    public func reply(to eventID: String) {
        for case let .message(message) in items where message.id == eventID && message.kind != .deleted {
            composer.startReply(to: message.quoted)
            return
        }
    }

    /// ⌘R: replies to the selected message.
    public func replyToSelected() {
        guard let id = selectedMessageID else { return }
        reply(to: id)
    }

    public func react(to eventID: String, key: String) async {
        await act { client, room in
            let _: Sent = try await client.call("message.react", ReactParams(roomID: room, eventID: eventID, key: key))
        }
    }

    /// Sends a message that failed again, as the same message.
    public func retry(_ eventID: String) async {
        await act { client, _ in
            let _: Empty = try await client.call("message.retry", EventParams(eventID: eventID))
        }
    }

    /// Deletes a message that failed, from this device only.
    public func discard(_ eventID: String) async {
        await act { client, _ in
            let _: Empty = try await client.call("message.discard", EventParams(eventID: eventID))
        }
    }

    private func act(_ call: (EngineClient, String) async throws -> Void) async {
        guard let room = roomID, let client = appModel.client else { return }
        let owner = generation
        do {
            try await call(client, room)
        } catch {
            guard owner == generation, client === appModel.client else { return }
            problem = .actionFailed(Self.describe(error))
        }
        // Whatever the answer was, the store knows best: read it. (A call that was not answered may still have
        // happened, and is never repeated.)
        if owner == generation { requestRefetch() }
    }

    static func describe(_ error: Error) -> String {
        EngineErrorText.text(for: error, fallback: String(localized: "Courier’s engine could not do that."))
    }
}
