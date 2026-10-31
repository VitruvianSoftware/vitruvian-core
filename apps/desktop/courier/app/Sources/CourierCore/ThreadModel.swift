// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The thread pane (01 §10): one thread's root and its replies, and a composer that writes in it.
///
/// The replies are `room.events` with `thread`: newest first, paged with `before`, the oldest page ending with the
/// root. They carry what the chat has for them (their edits, reactions and deletions), so the pane shows them as the
/// timeline would. The root shows first even before the oldest page is read: it is read on its own (`around` it,
/// one event). Pages are joined as the conversation joins its pages (by event, a newer page replacing what it
/// covers), and paged by cursor only: a page with no events and a cursor reads on.
///
/// What the pane reads again: a new event in its chat (it may be a reply), a status change of something it shows,
/// and a new engine (or a resync). Another chat's changes, and status changes of messages it doesn't show, read
/// nothing.
///
/// Its composer is a composer of its own, in `.thread(rootID)`, that never touches the chat's draft: the engine
/// keeps one draft per chat, and it is the chat composer's. What is typed in a thread stays with that thread while
/// the pane goes to another one or closes, for as long as Courier runs.
@MainActor
public final class ThreadModel: ObservableObject {
    public static let pageSize = 50
    /// How many older pages the pane reads, at most, to reach the reply it was opened at.
    static let pagesToFindTarget = 20

    @Published public private(set) var rootID: String?
    @Published public private(set) var roomID: String?
    /// The root first, then the replies oldest first.
    @Published public private(set) var items: [TimelineItem] = []
    /// The newest page of the thread has been read.
    @Published public private(set) var isLoaded = false
    @Published public private(set) var hasOlder = false
    @Published public private(set) var isLoadingOlder = false
    /// The last read of an older page failed: the view offers a button instead of trying again by itself.
    @Published public private(set) var olderFailed = false
    /// The newest page could not be read.
    @Published public private(set) var loadFailed = false
    /// The reply the pane was opened at (a search result), once it is in, for `ConversationModel.highlightDuration`.
    @Published public private(set) var highlightedMessageID: String?
    /// The view scrolls to this message whenever it changes.
    @Published public private(set) var scrollToMessageRequest: ConversationModel.MessageScrollRequest?

    public let composer: ComposerModel
    /// Deleted messages leave no placeholder (the person's setting, or a network that leaves none).
    public var hideDeleted = false {
        didSet { if hideDeleted != oldValue { rebuild() } }
    }

    private let appModel: AppModel
    private let now: @MainActor () -> Date
    private let calendar: Calendar
    private let sleep: @Sendable (Duration) async throws -> Void

    private var events: [String: Event] = [:]
    /// The root, read on its own until the oldest page brings it.
    private var rootEvent: Event?
    private var olderCursor: Cursor?
    private var olderPagesLoaded = false
    /// The reply to show once it is loaded, and how many older pages were read to find it.
    private var target: String?
    private var pagesForTarget = 0
    private var scrollSerial = 0
    private var highlightTask: Task<Void, Never>?
    /// Tests: how many of the newest pages have been applied, to know every change so far has been read.
    private(set) var pagesApplied = 0
    /// What was typed in each thread the pane left, by chat and root.
    private var drafts: [String: RichText] = [:]

    // Which answers still count.
    private var generation = 0
    private var pageEpoch = 0
    private var fetchSerial = 0
    private var appliedSerial = 0
    private var refetching = false
    private var refetchAgain = false

    /// - Parameters:
    ///   - now: the time now, for disappearing messages and the composer; tests give their own.
    ///   - sleep: how the highlight waits out `ConversationModel.highlightDuration`.
    public init(appModel: AppModel, now: @escaping @MainActor () -> Date = Date.init,
                calendar: Calendar = .autoupdatingCurrent,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.appModel = appModel
        self.now = now
        self.calendar = calendar
        self.sleep = sleep
        composer = ComposerModel(sender: ThreadMessageSender(base: EngineMessageSender(appModel: appModel)), now: now)
        // The chat's draft is the chat composer's: the pane's composer neither takes it nor saves over it.
        composer.savedDraft = { _ in "" }
        composer.onSettled = { [weak self] in self?.requestRefetch() }
        composer.quote = { [weak self] id in self?.message(id)?.quoted }
        appModel.onConnect { [weak self] client in
            guard let self, self.rootID != nil, client === self.appModel.client else { return }
            self.requestRefetch()
        }
        appModel.onChange { [weak self] change in self?.handle(change) }
    }

    // MARK: - Opening and closing

    /// Opens the pane on `rootID`'s thread in `roomID`, and, with `replyID`, at that reply: older pages are read
    /// until it is in (at most `pagesToFindTarget`), and the view is asked to scroll to it.
    public func open(_ rootID: String, in roomID: String, at replyID: String? = nil) {
        if rootID == self.rootID, roomID == self.roomID {
            if let replyID { aim(at: replyID) }
            return
        }
        leaveThread()
        generation += 1
        pageEpoch += 1
        self.rootID = rootID
        self.roomID = roomID
        composer.open(roomID)
        composer.startThread(rootID)
        if let kept = drafts.removeValue(forKey: Self.key(roomID, rootID)) {
            composer.text = kept.text
            composer.entities = kept.entities
        }
        target = replyID
        pagesForTarget = 0
        requestRefetch()
    }

    /// Closes the pane. What was typed stays with the thread, for when it opens again.
    public func close() {
        leaveThread()
        generation += 1
        pageEpoch += 1
        composer.open(nil)
    }

    /// Keeps what was typed in the open thread, and forgets what was loaded.
    private func leaveThread() {
        if let room = roomID, let root = rootID {
            if case .editing = composer.mode { _ = composer.escape() }
            if !composer.text.isEmpty {
                drafts[Self.key(room, root)] = RichText(text: composer.text, entities: composer.entities)
            }
            // The composer keeps each chat's contents itself; the pane's are kept by thread instead.
            composer.cancelReply()
            for attachment in composer.attachments { composer.removeAttachment(attachment.id) }
            composer.text = ""
            composer.entities = []
            composer.endThread()
        }
        rootID = nil
        roomID = nil
        items = []
        events = [:]
        rootEvent = nil
        olderCursor = nil
        olderPagesLoaded = false
        hasOlder = false
        isLoaded = false
        isLoadingOlder = false
        olderFailed = false
        loadFailed = false
        refetching = false
        refetchAgain = false
        target = nil
        clearHighlight()
        scrollToMessageRequest = nil
    }

    private static func key(_ room: String, _ root: String) -> String { room + "\n" + root }

    // MARK: - Reading

    private func handle(_ change: Change) {
        guard let room = roomID else { return }
        switch change {
        case let .event(changed, _):
            if changed == room { requestRefetch() }
        case let .status(changed, eventID):
            if changed == room, events[eventID] != nil || eventID == rootID { requestRefetch() }
        case let .receipt(changed):
            // Who read my replies, and whether they were delivered: the pane's status lines.
            if changed == room { requestRefetch() }
        case .room, .read, .bridge, .resync, .spaces, .typing, .reminder, .scheduled:
            break // resync reads through the connect hook; the others change no reply.
        }
    }

    /// Reads the thread again: after an action whose result the engine stores without a change notice (Delete for
    /// Me, a bookmark), or one it reports only for the chat.
    public func refresh() {
        requestRefetch()
    }

    /// Reads the newest page; changes that come while a read is in flight cost one more read, however many.
    private func requestRefetch() {
        guard rootID != nil else { return }
        if refetching {
            refetchAgain = true
            return
        }
        refetching = true
        let owner = generation
        Task { [weak self] in
            var again = true
            while again {
                guard let self else { return }
                self.refetchAgain = false
                await self.fetchNewest()
                guard owner == self.generation else { return }
                again = self.refetchAgain
            }
            self?.refetching = false
        }
    }

    private func fetchNewest() async {
        guard let room = roomID, let root = rootID, let client = appModel.client else { return }
        let owner = generation
        fetchSerial += 1
        let serial = fetchSerial
        let page: EventsPage
        do {
            page = try await client.call("room.events",
                                         RoomEventsParams(roomID: room, thread: root, limit: Self.pageSize))
        } catch {
            guard owner == generation, client === appModel.client else { return }
            loadFailed = true
            return
        }
        guard owner == generation, client === appModel.client, serial > appliedSerial else { return }
        appliedSerial = serial
        loadFailed = false
        apply(page)
        pagesApplied += 1
        if rootEvent == nil, events[root] == nil { await fetchRoot(room, root, client, owner) }
        findTarget()
    }

    /// Joins the newest page to what is loaded: what it covers, down to its before cursor, is what the engine has
    /// now; a page that doesn't reach what is loaded (more came than a page holds) starts again from it.
    private func apply(_ page: EventsPage) {
        let pageIDs = Set(page.events.map(\.eventID))
        var hole = false
        if let before = page.before, let newest = events.values.map(Self.position).max() {
            hole = Self.Position(ts: before.ts, seq: before.seq) > newest
        }
        if hole {
            events = [:]
            olderCursor = nil
            olderPagesLoaded = false
            pageEpoch += 1
        } else if let before = page.before {
            let from = Self.Position(ts: before.ts, seq: before.seq)
            events = events.filter { Self.position($0.value) < from || pageIDs.contains($0.key) }
        } else {
            events = events.filter { pageIDs.contains($0.key) }
        }
        for event in page.events { events[event.eventID] = event }
        if !olderPagesLoaded { olderCursor = page.before }
        hasOlder = olderCursor != nil
        rebuild()
        isLoaded = true
    }

    /// The root on its own (`around` it, one event): it heads the pane before the oldest page is read.
    private func fetchRoot(_ room: String, _ root: String, _ client: EngineClient, _ owner: Int) async {
        let page: EventsPage? = try? await client.call("room.events",
                                                       RoomEventsParams(roomID: room, around: root, limit: 1))
        guard owner == generation, client === appModel.client,
              let event = page?.events.first(where: { $0.eventID == root }) else { return }
        rootEvent = event
        rebuild()
    }

    /// Reads the next older page, when the view scrolls to the top (or to reach the reply opened at). A page with
    /// no events and a cursor reads on.
    public func loadOlder() {
        guard let room = roomID, let root = rootID, let cursor = olderCursor, !isLoadingOlder,
              let client = appModel.client else { return }
        isLoadingOlder = true
        olderFailed = false
        let owner = generation
        let epoch = pageEpoch
        Task { [weak self] in
            let page: EventsPage? = try? await client.call(
                "room.events", RoomEventsParams(roomID: room, thread: root, before: cursor, limit: Self.pageSize))
            guard let self, owner == self.generation else { return }
            self.isLoadingOlder = false
            guard client === self.appModel.client, epoch == self.pageEpoch else { return }
            guard let page else {
                self.olderFailed = true
                return
            }
            for event in page.events { self.events[event.eventID] = event }
            self.olderPagesLoaded = true
            self.olderCursor = page.before
            self.hasOlder = page.before != nil
            self.rebuild()
            if page.events.isEmpty, let next = page.before, next != cursor {
                self.loadOlder()
            } else {
                self.findTarget()
            }
        }
    }

    // MARK: - The reply opened at

    private func aim(at replyID: String) {
        target = replyID
        pagesForTarget = 0
        if isLoaded { findTarget() }
    }

    /// Shows the reply opened at once it is loaded; until then reads older pages, a bounded number of them.
    private func findTarget() {
        guard let target else { return }
        if message(target) != nil {
            self.target = nil
            highlight(target)
            scrollSerial += 1
            scrollToMessageRequest = ConversationModel.MessageScrollRequest(messageID: target, serial: scrollSerial)
        } else if hasOlder, pagesForTarget < Self.pagesToFindTarget {
            pagesForTarget += 1
            loadOlder()
        } else {
            self.target = nil // not in this thread (deleted since): the pane shows it from the newest reply
        }
    }

    private func highlight(_ eventID: String) {
        highlightTask?.cancel()
        highlightedMessageID = eventID
        let sleep = self.sleep
        highlightTask = Task { [weak self] in
            do {
                try await sleep(ConversationModel.highlightDuration)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.highlightedMessageID = nil
            self.highlightTask = nil
        }
    }

    private func clearHighlight() {
        highlightTask?.cancel()
        highlightTask = nil
        highlightedMessageID = nil
    }

    // MARK: - What it shows

    private struct Position: Comparable {
        let ts: Int64
        let seq: Int64

        static func < (lhs: Position, rhs: Position) -> Bool { (lhs.ts, lhs.seq) < (rhs.ts, rhs.seq) }
    }

    private static func position(_ event: Event) -> Position { Position(ts: event.ts, seq: event.seq) }

    /// The clock moved on: a reply whose disappearing time has passed leaves the pane, with no read of the engine.
    func clockMoved() {
        guard rootID != nil else { return }
        rebuild()
    }

    private func rebuild() {
        var all = Array(events.values)
        if let rootEvent, events[rootEvent.eventID] == nil { all.append(rootEvent) }
        items = Timeline.build(events: all, me: Timeline.meUserID, now: now(), hideDeleted: hideDeleted,
                               calendar: calendar)
        // My held replies, as the thread has them now: the pane's ⌘Z takes back the newest.
        if let room = roomID, room == composer.roomID { composer.updateHeld(from: items) }
    }

    /// An event the pane has loaded, as the engine wrote it; nil when it hasn't.
    func event(_ eventID: String) -> Event? { events[eventID] }

    /// A message of the pane, as loaded.
    func message(_ eventID: String) -> TimelineMessage? {
        for case let .message(message) in items where message.id == eventID { return message }
        return nil
    }

    /// Populates `roomID`, `rootID`, `items`, and `isLoaded` directly for deterministic testing without an engine.
    public func setSnapshotStateForTesting(roomID: String, rootID: String, items: [TimelineItem]) {
        self.roomID = roomID
        self.rootID = rootID
        self.items = items
        self.isLoaded = true
        composer.open(roomID)
        composer.startThread(rootID)
    }
}

/// The engine's sender for the thread pane's composer: everything as the chat's composer sends it, except the
/// chat's draft, which is the chat composer's to keep.
final class ThreadMessageSender: MessageSending {
    private let base: MessageSending

    init(base: MessageSending) { self.base = base }

    func saveDraft(roomID: String, text: String) async throws {}

    func sendText(roomID: String, text: String, replyTo: String?) async throws {
        try await base.sendText(roomID: roomID, text: text, replyTo: replyTo)
    }

    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?) async throws {
        try await base.sendFile(roomID: roomID, url: url, size: size, replyTo: replyTo)
    }

    func send(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, holdMillis: Int) async throws
        -> String {
        try await base.send(roomID: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot, holdMillis: holdMillis)
    }

    func sendFile(roomID: String, url: URL, size: Int64, replyTo: String?, threadRoot: String?, holdMillis: Int)
        async throws -> String {
        try await base.sendFile(roomID: roomID, url: url, size: size, replyTo: replyTo, threadRoot: threadRoot,
                                holdMillis: holdMillis)
    }

    func sendVoice(roomID: String, url: URL, durationMS: Int64, waveform: [Int], replyTo: String?) async throws
        -> String {
        try await base.sendVoice(roomID: roomID, url: url, durationMS: durationMS, waveform: waveform, replyTo: replyTo)
    }

    func edit(eventID: String, rich: RichText) async throws {
        try await base.edit(eventID: eventID, rich: rich)
    }

    func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                  condition: SendLaterCondition) async throws {
        try await base.schedule(roomID: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot, due: due,
                                condition: condition)
    }

    func schedule(roomID: String, rich: RichText, replyTo: String?, threadRoot: String?, due: Date,
                  condition: SendLaterCondition, disableLinkPreview: Bool?) async throws {
        try await base.schedule(roomID: roomID, rich: rich, replyTo: replyTo, threadRoot: threadRoot, due: due,
                                condition: condition, disableLinkPreview: disableLinkPreview)
    }

    func undo(eventID: String) async throws -> Draft {
        try await base.undo(eventID: eventID)
    }

    func setTyping(roomID: String, typing: Bool) async throws {
        try await base.setTyping(roomID: roomID, typing: typing)
    }

    func setUnreadFrom(eventID: String) async throws {
        try await base.setUnreadFrom(eventID: eventID)
    }

    func directChat(roomID: String, userID: String) async throws -> String {
        try await base.directChat(roomID: roomID, userID: userID)
    }

    func sendHeld(roomID: String?) async throws {
        try await base.sendHeld(roomID: roomID)
    }

    func members(roomID: String, query: String) async throws -> [Member] {
        try await base.members(roomID: roomID, query: query)
    }

    func status(of eventID: String, in roomID: String, thread: String?) async throws -> StatusLine? {
        try await base.status(of: eventID, in: roomID, thread: thread)
    }
}
