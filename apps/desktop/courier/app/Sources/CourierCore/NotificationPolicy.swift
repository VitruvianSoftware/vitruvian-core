// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// When a message makes a notification, what the notification says, and what the Dock badge counts. Plain values and
// pure functions, so the rules are tested here and the system's notification centre only carries them out.

/// A notification, before the system draws it.
public struct NotificationContent: Equatable, Sendable {
    public let eventID: String
    public let roomID: String
    /// The chat's name.
    public let title: String
    /// For a group, who wrote it. Nil in a direct chat.
    public let subtitle: String?
    /// The text, or what kind of file it is.
    public let body: String

    public init(eventID: String, roomID: String, title: String, subtitle: String?, body: String) {
        self.eventID = eventID
        self.roomID = roomID
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }

    /// Notifications of one chat are stacked together.
    public var threadIdentifier: String { roomID }

    /// All a notification carries to say where a click goes: the chat. No text, no names.
    public var userInfo: [String: String] { ["room_id": roomID] }
}

public enum NotificationPolicy {
    /// A message counts as live for this long after it was sent: a bridge that catches up later than this is
    /// bringing history, not news.
    public static let liveWindowMillis: Int64 = 120_000
    /// A longer text is cut to this many characters and an ellipsis.
    public static let maxBodyLength = 200

    /// What the decision depends on besides the event and its chat.
    public struct Context: Equatable, Sendable {
        /// Who I am in every chat (`Timeline.meUserID`).
        public var me: String
        /// When the app connected to the engine, in ms since 1970.
        public var connectedAt: Int64
        /// The time now, in ms since 1970.
        public var now: Int64
        /// The chat that is open.
        public var openRoomID: String?
        /// The person is looking at the open chat (`Attention`): the window is key, the screen unlocked and awake,
        /// and they are not idle.
        public var isLooking: Bool

        public init(me: String, connectedAt: Int64, now: Int64, openRoomID: String?, isLooking: Bool) {
            self.me = me
            self.connectedAt = connectedAt
            self.now = now
            self.openRoomID = openRoomID
            self.isLooking = isLooking
        }
    }

    /// Whether `event`, new in `room`, makes a notification.
    ///
    /// Yes for a message or a sticker that is not from me, in a chat that is not muted, that is live (sent after the
    /// app connected and not more than two minutes ago: the first sync's history must not notify), and that is not
    /// in the chat the person is looking at. Reactions, edits, deletions and anything the app cannot read do not.
    /// A notification for another chat does come while the window is in front, and one for the open chat does
    /// while nobody is looking at it (the screen locked or asleep, or the person away).
    public static func shouldNotify(event: Event, room: InboxRow, context: Context) -> Bool {
        guard event.type == "m.room.message" || event.type == "m.sticker" else { return false }
        guard !Timeline.isEdit(event) else { return false }
        guard !event.mine, event.sender != context.me else { return false }
        guard !room.muted else { return false }
        guard event.ts >= context.connectedAt, context.now - event.ts <= liveWindowMillis else { return false }
        if context.isLooking, context.openRoomID == event.roomID { return false }
        return true
    }

    /// What the notification for `event` says.
    public static func content(for event: Event, room: InboxRow) -> NotificationContent {
        var name = room.name.isEmpty ? event.senderName : room.name
        if name.isEmpty { name = String(localized: "Courier") }
        let sender = event.senderName.trimmingCharacters(in: .whitespaces)
        return NotificationContent(
            eventID: event.eventID, roomID: event.roomID, title: name,
            subtitle: room.isDirect || sender.isEmpty ? nil : sender, body: body(of: event))
    }

    /// What a chat says when a reply typed in a notification could not be sent: the text is waiting in the chat.
    /// `mayHaveGone`: the engine did not answer, so the reply may have been sent after all.
    public static func replyNotSent(roomID: String, title: String, mayHaveGone: Bool = false) -> NotificationContent {
        NotificationContent(
            eventID: "reply-not-sent-" + UUID().uuidString, roomID: roomID,
            title: title.isEmpty ? String(localized: "Courier") : title, subtitle: nil,
            body: mayHaveGone
                ? String(localized: "Your reply may not have been sent — check the chat before sending again.")
                : String(localized: "Your reply wasn’t sent — it’s waiting in the chat."))
    }

    /// The events a page says were deleted (by a redaction in the page that was not itself refused).
    public static func redactedEventIDs(in events: [Event]) -> Set<String> {
        Set(events.compactMap { event in
            guard event.type == "m.room.redaction", event.status != .failed else { return nil }
            return event.content["redacts"]?.stringValue
        })
    }

    private static func body(of event: Event) -> String {
        let shown = Timeline.summary(of: event)
        let text = shown.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let label = label(of: shown.kind) else { return truncated(text) }
        return text.isEmpty ? label.title : label.title + " " + truncated(text)
    }

    private static func label(of kind: MessageKind) -> PreviewLabel? {
        switch kind {
        case .image: .image
        case .video: .video
        case .voiceNote: .voiceNote
        case .file: .file
        case .sticker: .sticker
        default: nil
        }
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maxBodyLength else { return text }
        let cut = String(text.prefix(maxBodyLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + "…"
    }

    // MARK: - The Dock badge

    /// How many chats have unread messages and are not muted. Chats, not messages: three messages in one chat
    /// are one.
    public static func badgeCount(rows: [InboxRow]) -> Int {
        rows.filter { $0.unread > 0 && !$0.muted }.count
    }

    /// The Dock tile's text; nil at zero, which clears it.
    public static func badgeLabel(count: Int) -> String? {
        count > 0 ? String(count) : nil
    }
}

/// The events already looked at, so a message is announced once however many times its chat is read. Bounded: when
/// full, the oldest is forgotten.
public struct SeenEvents: Sendable {
    private var order: [String] = []
    private var members = Set<String>()
    private let capacity: Int

    public init(capacity: Int = 1000) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { members.count }

    /// Notes the event; false if it was noted already.
    @discardableResult
    public mutating func insert(_ eventID: String) -> Bool {
        guard members.insert(eventID).inserted else { return false }
        order.append(eventID)
        if order.count > capacity {
            let overflow = order.count - capacity
            for forgotten in order.prefix(overflow) { members.remove(forgotten) }
            order.removeFirst(overflow)
        }
        return true
    }
}
