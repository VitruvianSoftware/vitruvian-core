// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The system's notification centre, as the coordinator uses it. The app's adapter is `UNUserNotificationCenter`;
/// tests give a fake. An adapter in a process with no app bundle (a bare `swift run`) does nothing, because the
/// real centre aborts there.
@MainActor
public protocol NotificationDelivering: AnyObject {
    /// Asks the person to allow notifications. The system asks once; later calls do nothing.
    func requestPermission()
    /// Shows a notification, grouped by chat. The same event shown twice is shown once.
    func deliver(_ content: NotificationContent)
    /// Takes down what is shown for a chat (it was read).
    func clear(roomID: String)
}

/// Turns the engine's new events into notifications, and what is done on a notification into engine calls.
///
/// A `changed` event says only that a chat has a new event, so the coordinator reads that chat's newest page and
/// looks at each event it has not looked at before. Every event it reads is noted, notified or not: a message
/// that was silent because the chat was open stays silent when the person looks away.
///
/// A burst of changes in one chat is read once: the first change opens a short window, changes inside it add
/// nothing, and the read follows; a change that comes while that read is in flight asks for one more after it. So
/// the first sync's hundreds of events in a chat cost two reads, not hundreds. A chat the inbox has not listed
/// yet is looked up with one inbox read that every chat waiting for it shares.
///
/// An answer is used only if it came from the client that is up now, as the other models do.
@MainActor
public final class NotificationCoordinator {
    /// How many of a chat's newest events are read for one change. A burst larger than this loses its oldest
    /// messages, which is fine for a notification.
    public static let pageSize = 10

    private let appModel: AppModel
    private let delivery: any NotificationDelivering
    private let row: @MainActor (String) -> InboxRow?
    private let isLooking: @MainActor () -> Bool
    private let restoreDraft: @MainActor (_ roomID: String, _ text: String, _ mayHaveBeenSent: Bool) -> Void
    private let replyTimeout: TimeInterval?
    private let showWindow: @MainActor () -> Void
    private let window: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let clock: @Sendable () -> Date
    private var seen = SeenEvents()
    /// Chats with a read waiting for its window, or in flight.
    private var scheduled: Set<String> = []
    /// Chats with a read in flight, and those that changed again during it.
    private var inFlight: Set<String> = []
    private var readAgain: Set<String> = []
    /// The inbox read that chats the inbox has not listed are waiting on.
    private var inboxLookup: Task<[InboxRow], Never>?

    /// - Parameters:
    ///   - row: the inbox's row for a chat, if it has one (its name and whether it is muted).
    ///   - isLooking: whether the person is looking at the open chat (`Attention.isLooking`).
    ///   - restoreDraft: puts text that could not be sent into a chat's composer draft; the last argument says the
    ///     engine did not answer, so it may have been sent.
    ///   - replyTimeout: how long a reply waits for the engine; nil is the client's own limit (30 s).
    ///   - showWindow: brings the main window forward, opening it again if it was closed.
    ///   - window: how long a chat's changes are gathered before it is read, in seconds.
    ///   - sleep: waits `window`.
    ///   - clock: the time now; tests give one they move.
    public init(appModel: AppModel, delivery: any NotificationDelivering,
                row: @escaping @MainActor (String) -> InboxRow?, isLooking: @escaping @MainActor () -> Bool,
                restoreDraft: @escaping @MainActor (_ roomID: String, _ text: String, _ mayHaveBeenSent: Bool) -> Void,
                showWindow: @escaping @MainActor () -> Void, window: TimeInterval = 0.1, replyTimeout: TimeInterval? = nil,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { await waitForInboxWindow($0) },
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.appModel = appModel
        self.delivery = delivery
        self.row = row
        self.isLooking = isLooking
        self.restoreDraft = restoreDraft
        self.replyTimeout = replyTimeout
        self.showWindow = showWindow
        self.window = window
        self.sleep = sleep
        self.clock = clock
        appModel.onChange { [weak self] change in self?.handle(change) }
    }

    /// Asks for permission to notify; the app calls it once at launch.
    public func start() {
        delivery.requestPermission()
    }

    public func handle(_ change: Change) {
        switch change {
        case let .event(roomID, _):
            examine(roomID: roomID)
        case let .read(roomID, _):
            delivery.clear(roomID: roomID)
        default:
            break
        }
    }

    // MARK: - New events

    private func examine(roomID: String) {
        guard appModel.client != nil, appModel.connectedAt != nil else { return }
        if inFlight.contains(roomID) {
            readAgain.insert(roomID)
            return
        }
        guard scheduled.insert(roomID).inserted else { return } // inside the window already: covered
        Task { [weak self, sleep, window] in
            await sleep(window)
            await self?.readUntilQuiet(roomID)
        }
    }

    /// Reads the chat, and again for as long as changes came in during a read.
    private func readUntilQuiet(_ roomID: String) async {
        inFlight.insert(roomID)
        repeat {
            readAgain.remove(roomID)
            await readOnce(roomID)
        } while readAgain.contains(roomID)
        inFlight.remove(roomID)
        scheduled.remove(roomID)
    }

    private func readOnce(_ roomID: String) async {
        guard let client = appModel.client else { return }
        let page: EventsPage? = try? await client.call(
            "room.events", RoomEventsParams(roomID: roomID, limit: Self.pageSize))
        guard let page, client === appModel.client else { return }
        // The row is the inbox's when it has the chat, and read only for a chat it has not listed yet.
        var chat = row(roomID)
        if chat == nil {
            chat = await lookUp(roomID, with: client)
            guard client === appModel.client else { return }
        }
        guard let chat else { return }
        announce(page.events, in: chat)
    }

    /// One inbox read at a time, shared by every chat that is waiting for it. A chat that is not in an answer it
    /// joined gets one read of its own: that read may have started before the chat existed.
    private func lookUp(_ roomID: String, with client: EngineClient) async -> InboxRow? {
        var read: Task<[InboxRow], Never>
        var joined = false
        if let running = inboxLookup {
            read = running
            joined = true
        } else {
            read = startInboxRead(with: client)
        }
        var found = await read.value.first { $0.roomID == roomID }
        if inboxLookup == read { inboxLookup = nil }
        if found == nil, joined {
            read = startInboxRead(with: client)
            found = await read.value.first { $0.roomID == roomID }
            if inboxLookup == read { inboxLookup = nil }
        }
        return found
    }

    /// Starts an inbox read and makes it the one that later chats join.
    private func startInboxRead(with client: EngineClient) -> Task<[InboxRow], Never> {
        let read = Task {
            let inbox: InboxResult? = try? await client.call("inbox.list", Empty())
            return inbox?.rooms ?? []
        }
        inboxLookup = read
        return read
    }

    /// `events` are newest first, as room.events has them; the oldest is announced first.
    private func announce(_ events: [Event], in room: InboxRow) {
        // Read at the moment of deciding: the person may have moved on while the page was on its way.
        guard let connectedAt = appModel.connectedAt else { return }
        let context = NotificationPolicy.Context(
            me: Timeline.meUserID, connectedAt: Self.millis(connectedAt), now: Self.millis(clock()),
            openRoomID: appModel.selectedRoomID, isLooking: isLooking())
        // A message deleted before it was announced is not announced.
        let deleted = NotificationPolicy.redactedEventIDs(in: events)
        for event in events.reversed() where seen.insert(event.eventID) {
            guard !deleted.contains(event.eventID),
                  NotificationPolicy.shouldNotify(event: event, room: room, context: context) else { continue }
            delivery.deliver(NotificationPolicy.content(for: event, room: room))
        }
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    // MARK: - What is done on a notification

    /// A click: the chat opens in the main window, which comes forward.
    public func open(roomID: String) {
        appModel.selectedRoomID = roomID
        showWindow()
    }

    /// "Mark as Read".
    public func markRead(roomID: String) async {
        if let client = appModel.client {
            // A failure is ignored: the inbox shows the truth the next time it reads.
            let _: Empty? = try? await client.call("room.markRead", RoomParams(roomID: roomID))
        }
        delivery.clear(roomID: roomID)
    }

    /// The inline "Reply": sends the typed text to the chat. If it cannot be sent (the engine is not up, or refuses),
    /// the text goes into that chat's draft and a notification says so, so the words are never lost.
    public func reply(roomID: String, text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var mayHaveGone = false
        if let client = appModel.client {
            do {
                let _: Sent = try await client.call("message.send", SendParams(roomID: roomID, text: text),
                                                    timeout: replyTimeout)
                return
            } catch {
                // Falls through, whatever the reason: the text is kept below. When the engine did not answer, the
                // send may have gone, and the person is told to look before sending it again.
                mayHaveGone = (error as? EngineError)?.mayHaveBeenHandled ?? false
            }
        }
        restoreDraft(roomID, text, mayHaveGone)
        delivery.deliver(NotificationPolicy.replyNotSent(roomID: roomID, title: row(roomID)?.name ?? "",
                                                         mayHaveGone: mayHaveGone))
    }
}
