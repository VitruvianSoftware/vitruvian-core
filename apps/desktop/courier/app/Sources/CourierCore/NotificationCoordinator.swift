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
/// An answer is used only if it came from the client that is up now, as the other models do.
@MainActor
public final class NotificationCoordinator {
    /// How many of a chat's newest events are read for one change. A burst larger than this loses its oldest
    /// messages, which is fine for a notification.
    public static let pageSize = 10

    private let appModel: AppModel
    private let delivery: any NotificationDelivering
    private let row: @MainActor (String) -> InboxRow?
    private let windowIsKey: @MainActor () -> Bool
    private let showWindow: @MainActor () -> Void
    private let clock: @Sendable () -> Date
    private var seen = SeenEvents()

    /// - Parameters:
    ///   - row: the inbox's row for a chat, if it has one (its name and whether it is muted).
    ///   - windowIsKey: whether the window being used is the app's (so the open chat is in front of the person).
    ///   - showWindow: brings the main window forward, opening it again if it was closed.
    ///   - clock: the time now; tests give one they move.
    public init(appModel: AppModel, delivery: any NotificationDelivering,
                row: @escaping @MainActor (String) -> InboxRow?, windowIsKey: @escaping @MainActor () -> Bool,
                showWindow: @escaping @MainActor () -> Void, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.appModel = appModel
        self.delivery = delivery
        self.row = row
        self.windowIsKey = windowIsKey
        self.showWindow = showWindow
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
        guard let client = appModel.client, appModel.connectedAt != nil else { return }
        Task { [weak self] in
            let page: EventsPage? = try? await client.call(
                "room.events", RoomEventsParams(roomID: roomID, limit: Self.pageSize))
            guard let page else { return }
            // The row comes after the page, and from the inbox when it has the chat: it is read only for a chat
            // the inbox has not listed yet.
            var chat = self?.row(roomID)
            if chat == nil {
                let inbox: InboxResult? = try? await client.call("inbox.list", Empty())
                chat = inbox?.rooms.first { $0.roomID == roomID }
            }
            guard let self, client === self.appModel.client, let chat else { return }
            self.announce(page.events, in: chat)
        }
    }

    /// `events` are newest first, as room.events has them; the oldest is announced first.
    private func announce(_ events: [Event], in room: InboxRow) {
        // Read at the moment of deciding: the person may have moved on while the page was on its way.
        guard let connectedAt = appModel.connectedAt else { return }
        let context = NotificationPolicy.Context(
            me: Timeline.meUserID, connectedAt: Self.millis(connectedAt), now: Self.millis(clock()),
            openRoomID: appModel.selectedRoomID, windowIsKey: windowIsKey())
        for event in events.reversed() where seen.insert(event.eventID) {
            guard NotificationPolicy.shouldNotify(event: event, room: room, context: context) else { continue }
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

    /// The inline "Reply": sends the typed text to the chat.
    public func reply(roomID: String, text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client = appModel.client else { return }
        // A failure is ignored: milestone 4's toasts can say more. The send is stored first, so a send the
        // network refuses shows as failed, with Retry, in the chat.
        let _: Sent? = try? await client.call("message.send", SendParams(roomID: roomID, text: text))
    }
}
