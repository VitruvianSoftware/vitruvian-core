// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// When a message makes a notification, what the notification says, and what the Dock badge counts. Plain values and
// pure functions, so the rules are tested here and the system's notification centre only carries them out.

/// Which set of buttons a notification carries.
public enum NotificationCategory: String, Equatable, Sendable, CaseIterable {
    /// A new message: Mark as Read, Reply and the remind-later buttons.
    case message
    /// A reminder that came due: the same without Reply, because there is nothing new to answer.
    case reminder
    /// A scheduled message that didn't go (canceled, or missed): no buttons, since there is nothing to read or
    /// answer; a click opens the chat, whose strip offers Send Now, Reschedule and Delete.
    case scheduled
    /// Someone started typing: no buttons either, since nothing has come yet to read or answer; a click opens the
    /// chat.
    case typing

    /// The buttons, in the order they are shown. The remind-later ones are part of a plan, so they are left out
    /// when it doesn't include reminders (spec §3): a button that could only say no is not offered.
    public func actions(entitlement: any EntitlementProvider) -> [NotificationAction] {
        guard self != .scheduled, self != .typing else { return [] }
        var actions: [NotificationAction] = [.markRead]
        if self == .message { actions.append(.reply) }
        if entitlement.isEntitled(.reminders) { actions += [.remindOneHour, .remindEightHours] }
        return actions
    }
}

/// A button on a notification.
public enum NotificationAction: String, Equatable, Sendable, CaseIterable {
    case markRead, reply, remindOneHour, remindEightHours
}

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
    /// Which buttons it carries.
    public let category: NotificationCategory

    public init(eventID: String, roomID: String, title: String, subtitle: String?, body: String,
                category: NotificationCategory = .message) {
        self.eventID = eventID
        self.roomID = roomID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.category = category
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
        /// The setting "notify for message requests" (`InboxPreferences.requestNotifications`).
        public var requestNotifications: Bool

        public init(me: String, connectedAt: Int64, now: Int64, openRoomID: String?, isLooking: Bool,
                    requestNotifications: Bool = true) {
            self.me = me
            self.connectedAt = connectedAt
            self.now = now
            self.openRoomID = openRoomID
            self.isLooking = isLooking
            self.requestNotifications = requestNotifications
        }
    }

    /// Whether `event`, new in `room`, makes a notification.
    ///
    /// Yes for a message, a sticker or a poll that is not from me, in a chat that is not muted (by itself, its account or
    /// a label), is not low priority or hidden, and is not a request while requests are turned off, that is live (sent
    /// after the app connected and not more than two minutes ago: the first sync's history must not notify), and that
    /// is not in the chat the person is looking at. An archived chat is none of these: its new message brings it back
    /// to the inbox, and it notifies. Reactions, edits, deletions, timer-change notes, call records (a call that
    /// ended, was declined or dropped: `CallNote.isNews`) and anything the app cannot read do not.
    /// A notification for another chat does come while the window is in front, and one for the open chat does
    /// while nobody is looking at it (the screen locked or asleep, or the person away).
    public static func shouldNotify(event: Event, room: InboxRow, context: Context) -> Bool {
        // Ruling 17: someone starting a poll is a message (its votes and its end are not).
        guard event.type == "m.room.message" || event.type == "m.sticker" || event.type == Timeline.pollStartType
        else { return false }
        guard !Timeline.isEdit(event) else { return false }
        // A note that the disappearing timer changed is a system line, not news (Ruling 40), and the engine doesn't
        // count it unread.
        guard TimerChange.of(event.content) == nil else { return false }
        // Nor is the record that a call ended, was declined or dropped: only a call that rang or was missed is news.
        guard CallNote.isNews(event) else { return false }
        guard !event.mine, event.sender != context.me else { return false }
        guard !isMuted(room) else { return false }
        // Inferred (inventory 01 §18): Low Priority hides a chat "for good" and Hide removes it from the inbox, so a
        // new message in one is not news.
        guard !room.lowPriority, !room.hidden else { return false }
        guard !room.request || context.requestNotifications else { return false }
        guard event.ts >= context.connectedAt, context.now - event.ts <= liveWindowMillis else { return false }
        if context.isLooking, context.openRoomID == event.roomID { return false }
        return true
    }

    /// Whether the chat is muted: by itself, or by its account or one of its labels.
    public static func isMuted(_ room: InboxRow) -> Bool {
        room.muted || room.mutedBy != .none
    }

    // MARK: - Someone starts typing

    /// Whether someone typing in `room` makes a notification: "Notify when someone starts typing" is `on`, someone
    /// is typing, and the chat would notify for a message from them: not muted (by itself, its account or a label),
    /// not Low Priority or Hidden, not a request while requests don't notify, and not the chat the person is looking
    /// at. Inferred (inventory 02 §1.5, which names the setting but not its rules): the rules a message follows. The
    /// coordinator tells one per burst (`NotificationCoordinator`).
    public static func shouldNotifyTyping(room: InboxRow, context: Context, on: Bool) -> Bool {
        guard on, !room.typing.isEmpty else { return false }
        guard !isMuted(room), !room.lowPriority, !room.hidden else { return false }
        guard !room.request || context.requestNotifications else { return false }
        if context.isLooking, context.openRoomID == room.roomID { return false }
        return true
    }

    /// The id of a chat's typing notification: one per chat, so the next burst replaces it and the message that
    /// follows can take it down (C42: a typing notification has no event of its own).
    public static func typingID(roomID: String) -> String { "typing:" + roomID }

    /// What a typing notification says: the chat's name as its title, and who is typing as the chat's row words it
    /// ("Ana is typing…", "3 people are typing…").
    public static func typingContent(room: InboxRow) -> NotificationContent {
        NotificationContent(
            eventID: typingID(roomID: room.roomID), roomID: room.roomID,
            title: room.name.isEmpty ? String(localized: "Courier") : room.name, subtitle: nil,
            body: room.typingLine ?? "", category: .typing)
    }

    /// What the notification for a reminder that came due says. The title is the chat's name; there is no message
    /// text, and nothing else about the chat. Each reminder has an id of its own, so one never replaces another.
    ///
    /// Inferred (inventory 01 §18): a reminder notifies even when the chat is muted, low priority or hidden. The
    /// inventory describes the remind-later buttons (§18, §19) but not how a muted chat treats a reminder; the person
    /// asked for this one, and a mute is about messages, so it is not held back.
    public static func reminderContent(room: InboxRow) -> NotificationContent {
        NotificationContent(
            eventID: "reminder-" + room.roomID + "-" + UUID().uuidString, roomID: room.roomID,
            title: room.name.isEmpty ? String(localized: "Courier") : room.name, subtitle: nil,
            body: String(localized: "You asked to be reminded about this chat."), category: .reminder)
    }

    /// A scheduled message that won't go by itself: canceled because they wrote first, or missed while Courier was
    /// closed. The chat's name comes from its row; without one, "the chat".
    public static func scheduledContent(_ message: ScheduledMessage, room: InboxRow?) -> NotificationContent {
        let name = room?.name.isEmpty == false ? room!.name : String(localized: "the chat")
        let body = message.state == .canceled
            ? String(localized: "A scheduled message to \(name) wasn’t sent: they wrote first.")
            : String(localized: "A scheduled message to \(name) missed its time while Courier was closed.")
        return NotificationContent(
            eventID: "scheduled-\(message.outboxID)-\(message.state.rawValue)-\(message.setAt)",
            roomID: message.roomID, title: String(localized: "Courier"), subtitle: nil, body: body,
            category: .scheduled)
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

    /// A reply typed in a notification that is waiting for its network: it goes once the network is back.
    public static func replyWaiting(roomID: String, title: String) -> NotificationContent {
        NotificationContent(
            eventID: "reply-waiting-" + UUID().uuidString, roomID: roomID,
            title: title.isEmpty ? String(localized: "Courier") : title, subtitle: nil,
            body: String(localized: "Your reply will be sent when the network is back."))
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
        case .poll: .poll
        default: nil
        }
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maxBodyLength else { return text }
        let cut = String(text.prefix(maxBodyLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut + "…"
    }

    // MARK: - The Dock badge

    /// The Dock tile's text for a count of chats (SpacesModel.badgeCount, which the engine counts: the inbox's
    /// unread chats that nothing mutes; chats, not messages); nil at zero, which clears it.
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
