// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// What a conversation shows, built from the raw events of room.events.
//
// How the stored Matrix content is read (the keys are the Matrix ones, as the bridge wrote them):
//   edit        type m.room.message, content "m.relates_to": {"rel_type": "m.replace", "event_id": <target>}, and the
//               new text in content "m.new_content": {"body": ...}. Only the target's own sender can edit it.
//   reply       content "m.relates_to": {"m.in_reply_to": {"event_id": <target>}} on a message.
//   reaction    type m.reaction, content "m.relates_to": {"rel_type": "m.annotation", "event_id": <target>, "key": <emoji>}.
//   redaction   type m.room.redaction, content "redacts": <target>. The target can be a message (it becomes a
//               placeholder), a reaction (it is taken back) or an edit (it is not applied).
//   formatting  content "format": "org.matrix.custom.html" and "formatted_body": the HTML (RichTextHTML reads it); an
//               edit's is in its "m.new_content".
//   poll        type org.matrix.msc3381.poll.start; the engine's tally (Event.poll) says how it stands. Its votes and
//               its end are events of their own, which are not rows.
//   thread      content "m.relates_to": {"rel_type": "m.thread", "event_id": <root>}, with "is_falling_back": true and
//               an "m.in_reply_to" of the root for apps without threads: that is not a reply. The main timeline's
//               pages leave out replies that stay in their thread, but carry their edits and reactions, which have
//               nothing to apply to there; the thread's own pages carry both.
//
// The engine leaves messages deleted for me out of every page. Whatever still points at one (a reaction, an edit, a
// reply) finds nothing, as for any message not loaded.

/// What a message is, which says how it is drawn.
public enum MessageKind: Equatable, Sendable {
    case text, notice, emote
    case image, video, file, sticker
    /// Audio sent as a voice note. Other audio is `.file`.
    case voiceNote
    /// A message that was deleted: a placeholder, with no text.
    case deleted
    /// A message the engine could not decrypt.
    case undecryptable
    /// A poll: its question is the text, and `TimelineMessage.poll` how it stands.
    case poll

    /// Media that is a file on disk.
    public var isMedia: Bool {
        switch self {
        case .image, .video, .file, .sticker, .voiceNote: true
        default: false
        }
    }
}

/// A message as another message quotes it, and as the composer's reply chip shows it.
public struct QuotedMessage: Equatable, Sendable {
    public let eventID: String
    public let senderName: String
    public let mine: Bool
    /// The text, or the caption of a file. Empty for a file with none.
    public let text: String
    public let kind: MessageKind

    public init(eventID: String, senderName: String, mine: Bool, text: String, kind: MessageKind) {
        self.eventID = eventID
        self.senderName = senderName
        self.mine = mine
        self.text = text
        self.kind = kind
    }
}

/// What a reply shows above its text.
public enum ReplyPreview: Equatable, Sendable {
    case quoted(QuotedMessage)
    /// The message replied to is not among the loaded events (it is in an older page).
    case notLoaded(eventID: String)
}

/// One emoji under a message, with how many people gave it.
public struct ReactionChip: Equatable, Identifiable, Sendable {
    public let key: String
    public let count: Int
    /// I gave this one.
    public let mine: Bool
    public var id: String { key }
}

/// Why a message of mine was never sent: the engine's exact status_reason, which the app words itself.
public enum NotSentCause: Equatable, Sendable {
    /// Held for undo send, it came due over an hour before the engine could send it: Courier was closed.
    case appClosed
    /// Held or scheduled, its network wasn't connected when it was due.
    case notConnected
}

/// The line under a message of mine. Sent, Delivered and Seen are only ever on my newest message; the others are on
/// every message in that state (`Timeline.build`).
public enum StatusLine: Equatable, Sendable {
    /// Held for undo send: Undo takes it back until its window ends.
    case queued
    /// Its network is starting, down or logging in: it goes when the chat's account is back, however long that takes
    /// (Inferred (inventory 01 §5): no cut-off, as WhatsApp's own app). Don't Send takes it back, as Undo does.
    case waiting
    /// Waiting, but none of my accounts is in the chat any more: it can't go until one is. Don't Send takes it back.
    case noAccount
    case sending
    case sent
    /// Someone's device has it (the networks say so in one-to-one chats only).
    case delivered
    /// Read. `by`: who, newest first, in a group; [] in a one-to-one chat. `at`: when, in a one-to-one chat, when the
    /// receipt had a time.
    case seen(by: [String], at: Int64?)
    /// The network did not take it. `reason` is the engine's own words and may be empty.
    case failed(reason: String)
    /// Courier's engine stopped while this was being sent, so it may or may not have gone. Retry and Delete are
    /// offered as for a failed one; nothing is sent again unasked.
    case mayHaveBeenSent
    /// Nothing was sent (see the cause): Retry and Delete are offered.
    case notSent(NotSentCause)

    /// The engine's status_reason for a send it was cut off from (the engine stopped while it was pending).
    public static let mayHaveBeenSentReason = "may have been sent"
    /// The engine's status_reason for a held message that came due over an hour before it could be sent.
    public static let notSentReason = "not sent"
    /// The engine's status_reason for a held or scheduled message whose network wasn't connected when it was due.
    public static let notConnectedReason = "not connected"
    /// The engine's status_reason for a waiting message that none of my accounts can send: none is in the chat.
    public static let noAccountReason = "no account"

    /// What the line says, in short, for a message that may have been sent.
    public static var mayHaveBeenSentLabel: String { String(localized: "May have been sent") }
    /// The same, in full: the composer's words for a send the engine did not answer.
    public static var mayHaveBeenSentText: String {
        String(localized: "Courier’s engine did not answer. The message may have been sent: check the chat before sending it again.")
    }

    /// What the line says for a held message.
    public static var queuedLabel: String { String(localized: "Queued") }

    /// What the line says for a message waiting for its network.
    public static var waitingLabel: String { String(localized: "Waiting to send") }

    /// The help under "Waiting to send": when it goes. `network` is the engine's id; one this app doesn't know reads
    /// as "the network", never as the raw id.
    public static func waitingHelp(network: String) -> String {
        guard let name = NetworkNames.displayName(of: network) else {
            return String(localized: "It goes when the network is back online.")
        }
        return String(localized: "It goes when \(name) is back online.")
    }

    /// What the line says for a waiting message no account of mine can send.
    public static var noAccountLabel: String { String(localized: "Can’t send: none of your accounts is in this chat") }

    /// What the line says for a message someone's device has.
    public static var deliveredLabel: String { String(localized: "Delivered") }

    /// The "Don't Send" button on a waiting message's line: it takes the message back, as Undo does.
    public static var dontSendTitle: String { String(localized: "Don’t Send") }

    /// How a Seen line reads: "Seen", or "Seen 10:42" when a one-to-one receipt had a time; in a group, "Seen by Ana",
    /// "Seen by Ana & 1 other", "Seen by Ana & 2 others", naming the newest reader. `time` writes the receipt's time.
    /// Nil for any other line. Inferred (inventory 01 §5), which lists the words, not when each is used.
    public static func seenText(_ line: StatusLine, time: (Date) -> String) -> String? {
        guard case let .seen(by, at) = line else { return nil }
        guard let first = by.first else {
            guard let at, at > 0 else { return String(localized: "Seen") }
            return String(localized: "Seen \(time(Date(timeIntervalSince1970: Double(at) / 1000)))")
        }
        let others = by.count - 1
        if others == 0 { return String(localized: "Seen by \(first)") }
        return others == 1 ? String(localized: "Seen by \(first) & \(others) other")
            : String(localized: "Seen by \(first) & \(others) others")
    }

    /// Waiting for its network, with or without an account to go through: held as a queued message is (it offers
    /// nothing in the menu, and Don't Send takes it back).
    public var isWaiting: Bool { self == .waiting || self == .noAccount }

    /// Gone: Sent, Delivered or Seen.
    public var hasGone: Bool {
        switch self {
        case .sent, .delivered, .seen: true
        default: false
        }
    }

    /// Why a message was never sent, in Courier's words.
    public static func notSentText(_ cause: NotSentCause) -> String {
        switch cause {
        case .appClosed: String(localized: "Courier was closed when this was due to go. Nothing was sent.")
        case .notConnected: String(localized: "The network wasn’t connected when this was due to go. Nothing was sent.")
        }
    }

    /// The line for a message of mine with `status` and `reason`, as the engine has it.
    static func of(status: EventStatus, reason: String) -> StatusLine {
        switch status {
        case .queued: .queued
        case .waiting: reason == noAccountReason ? .noAccount : .waiting
        case .pending: .sending
        case .failed:
            switch reason {
            case mayHaveBeenSentReason: .mayHaveBeenSent
            case notSentReason: .notSent(.appClosed)
            case notConnectedReason: .notSent(.notConnected)
            default: .failed(reason: reason)
            }
        default: .sent
        }
    }

    /// The line of my message that has gone, from what its receipts say: Seen when anyone has read it, else Delivered,
    /// else Sent. In a one-to-one chat Seen names no one, and says when if the receipt had a time.
    static func gone(delivered: Bool, readBy: [Reader], isDirect: Bool) -> StatusLine {
        guard let newest = readBy.first else { return delivered ? .delivered : .sent }
        if isDirect { return .seen(by: [], at: newest.ts > 0 ? newest.ts : nil) }
        return .seen(by: readBy.map(\.name), at: nil)
    }
}

public struct TimelineMessage: Equatable, Identifiable, Sendable {
    public let id: String
    public let roomID: String
    public let sender: String
    public let senderName: String
    public let senderAvatarPath: String
    public let mine: Bool
    public let ts: Int64
    public let kind: MessageKind
    /// The text as plain text; for a file, its caption (empty if it has none); for a poll, its question. Empty for a
    /// deleted message.
    public let body: String
    /// The text and its formatting, as drawn: the newest live edit's when it was edited. Empty for a deleted message.
    public let rich: RichText
    public let isEdited: Bool
    /// The live edits loaded: not refused, not deleted.
    public let editCount: Int
    /// "Edit not sent", with Retry and Discard: my newest edit of it was refused (and none went through since). The
    /// message reads as before it.
    public let editFailed: StatusLine?
    /// The refused edit `editFailed` is about: what message.retry and message.discard take.
    public let failedEditID: String?
    /// The file's name, for media.
    public let fileName: String
    public let mimeType: String
    public let byteSize: Int64?
    public let width: Int?
    public let height: Int?
    /// The file on disk, when the engine has it; empty when not.
    public let mediaPath: String
    public let statusLine: StatusLine?
    /// The engine counts this kind of event as unread when it is from someone else: a message, a sticker or a poll
    /// (Ruling 17), not a message that could not be decrypted (or one that has since been deleted and was something
    /// else), and not a note that the disappearing timer changed (Ruling 40) or the record that a call ended, was
    /// declined or dropped (`CallNote.isNews`).
    public let countsAsUnread: Bool
    /// For a poll, how it stands.
    public let poll: PollTally?
    /// For a thread's root, its replies.
    public let thread: ThreadSummary?
    /// I bookmarked it, on this Mac.
    public let bookmarked: Bool
    /// When its disappearing timer takes it, in Unix milliseconds; nil is never.
    public let expiresAt: Int64?
    /// For the bridge's note that the chat's disappearing timer changed: what changed. The view draws a note from it
    /// (`ConversationModel.timerChangeNote`) in place of the body, which is the bridge's English.
    public let timerChange: TimerChange?
    /// For a bridge's notice of a call: what happened. The body is then Courier's words for it (`CallNote.words`),
    /// never the bridge's English, and the view draws it as a note.
    public let call: CallNote?
    public internal(set) var reply: ReplyPreview?
    public internal(set) var reactions: [ReactionChip]
    /// The first message of a run from one sender: it shows the name and the picture, and the others do not.
    public internal(set) var startsGroup: Bool

    /// A note of something that happened (a timer change, a call), not anyone's words: drawn as a line across the
    /// chat, never with a Sent mark, and it can only leave this Mac.
    public var isNote: Bool { timerChange != nil || call != nil }

    /// The message as a reply chip or a quote shows it.
    public var quoted: QuotedMessage {
        QuotedMessage(eventID: id, senderName: senderName, mine: mine, text: body, kind: kind)
    }
}

public enum TimelineItem: Equatable, Identifiable, Sendable {
    /// The start of a day, in the calendar the timeline was built with.
    case dateSeparator(Date)
    /// "New": the messages below it have not been read.
    case newDivider
    case message(TimelineMessage)

    public var id: String {
        switch self {
        case let .dateSeparator(day): "day-\(Int64(day.timeIntervalSince1970 * 1000))"
        case .newDivider: "new"
        case let .message(message): message.id
        }
    }
}

/// How a day separator reads: the view gives "Today" and "Yesterday" their words and dates their format.
public enum DayLabel: Equatable, Sendable {
    case today
    case yesterday
    case date(Date)

    public static func of(day: Date, now: Date, calendar: Calendar = .current) -> DayLabel {
        if calendar.isDate(day, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .date(day)
    }
}

public enum Timeline {
    /// Who I am in every chat, as the engine writes it.
    public static let meUserID = "@me:courier.local"
    /// Messages from one sender this close together share one name and picture.
    public static let groupingGapMillis: Int64 = 5 * 60 * 1000
    /// A poll's event type (MSC3381). Its votes and its end are other types, which are not rows.
    public static let pollStartType = "org.matrix.msc3381.poll.start"

    // MARK: - Building

    /// The items to show, oldest first. `events` can be in any order, and can hold events a message needs from
    /// more than one page. `firstUnreadID` is the message the "New" divider goes above.
    ///
    /// A message whose disappearing timer has run out by `now` is left out, even before the engine deletes it, and
    /// so is what points at it. With `hideDeleted` (the person's setting, or a chat whose network leaves no
    /// placeholder: ChatFeatures.hideDeletedPlaceholder) a deleted message leaves no placeholder either.
    /// `isDirect`: a one-to-one chat, whose Seen names no one (the one other person read it).
    ///
    /// Status lines: Sent, Delivered and Seen only under my newest message (not a note), so an older one never seems to
    /// say more than the newest; Queued, Waiting to send, Sending… and the failed lines under every message of mine in
    /// that state. Inferred (inventory 01 §5), which lists the states, not where they go.
    public static func build(events: [Event], me: String, firstUnreadID: String? = nil, now: Date,
                             hideDeleted: Bool = false, isDirect: Bool = false,
                             calendar: Calendar = .autoupdatingCurrent) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var previous: TimelineMessage?
        var previousDay: Date?
        for var message in messages(events: events, me: me, now: now, hideDeleted: hideDeleted, isDirect: isDirect) {
            var breaksGroup = false
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(message.ts) / 1000))
            if day != previousDay {
                items.append(.dateSeparator(day))
                previousDay = day
                breaksGroup = true
            }
            if message.id == firstUnreadID {
                items.append(.newDivider)
                breaksGroup = true
            }
            message.startsGroup = breaksGroup || previous == nil || previous?.sender != message.sender
                || message.ts.saturatingMinus(previous?.ts ?? 0) > groupingGapMillis
            items.append(.message(message))
            previous = message
        }
        return items
    }

    /// The oldest of the `unread` newest messages from others (the engine counts messages, stickers and polls only):
    /// where the "New" divider goes when a chat is opened with that many unread. More unread than are loaded puts it
    /// above everything loaded. Nil with none unread. With `now`, messages past their disappearing time are left out
    /// as `build` leaves them out, so the divider never lands on one that isn't shown.
    public static func firstUnreadID(events: [Event], me: String, unread: Int, now: Date? = nil) -> String? {
        guard unread > 0 else { return nil }
        let incoming = messages(events: events, me: me, now: now, hideDeleted: false, isDirect: false)
            .filter { !$0.mine && $0.countsAsUnread }
        guard !incoming.isEmpty else { return nil }
        return incoming[max(0, incoming.count - unread)].id
    }

    /// Whether an event is a message from someone else that people read: not mine, not an edit, reaction or
    /// anything else that is not a row of its own, and not a timer-change note or a call record (never unread, as
    /// `countsAsUnread`).
    public static func isIncomingMessage(_ event: Event) -> Bool {
        !event.mine && event.status != .failed && isMessageLike(event) && !isEdit(event)
            && TimerChange.of(event.content) == nil && CallNote.isNews(event)
    }

    /// What a message event says as a line: its kind and its text (the caption, for a file; the question, for a
    /// poll). For a notification, which has the event and nothing around it.
    public static func summary(of event: Event) -> (kind: MessageKind, text: String) {
        let shown = describe(event, edit: nil, mine: event.mine || event.sender == meUserID)
        return (shown.kind, shown.body)
    }

    // MARK: - Messages

    private static func messages(events: [Event], me: String, now: Date?, hideDeleted: Bool,
                                 isDirect: Bool) -> [TimelineMessage] {
        var seen = Set<String>()
        let ordered = events
            .filter { seen.insert($0.eventID).inserted }
            .sorted { ($0.ts, $0.seq, $0.eventID) < ($1.ts, $1.seq, $1.eventID) }

        var redacted = Set<String>()
        for event in ordered where event.type == "m.room.redaction" && event.status != .failed {
            if let target = event.content["redacts"]?.stringValue { redacted.insert(target) }
        }

        // A message past its disappearing time is gone, as if it were not on the page: nothing quotes it, and its
        // reactions and edits find nothing.
        let nowMillis = now.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        let bases = ordered.filter { event in
            guard isMessageLike(event), !isEdit(event) else { return false }
            if let nowMillis, event.expiresAt > 0, event.expiresAt <= nowMillis { return false }
            if hideDeleted, redacted.contains(event.eventID) { return false }
            return true
        }
        let baseByID = Dictionary(bases.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })
        func isMine(_ event: Event) -> Bool { event.mine || event.sender == me }
        // My newest message, not a note (a timer change, a call I made): the only one to say Sent, Delivered or Seen.
        let newestMine = bases.last { event in
            isMine(event) && !(event.type == "m.room.message"
                && (TimerChange.of(event.content) != nil || CallNote.of(event.content) != nil))
        }?.eventID

        // Edits by the message's own sender. The newest live one (not refused, not deleted) is what it says; my
        // newest edit, if refused, is "Edit not sent".
        var latestEdit: [String: Event] = [:]
        var liveEdits: [String: Int] = [:]
        var newestOwnEdit: [String: Event] = [:]
        for event in ordered where event.type == "m.room.message" && isEdit(event) && !redacted.contains(event.eventID) {
            guard let target = relation(of: event).eventID, let base = baseByID[target], base.sender == event.sender,
                  base.type == "m.room.message" else { continue }
            if event.status != .failed {
                latestEdit[target] = event
                liveEdits[target, default: 0] += 1
            }
            if isMine(base) { newestOwnEdit[target] = event }
        }

        // Reactions: one chip per emoji per message, counted by distinct people.
        struct Tally { var people = Set<String>(); var mine = false }
        var order: [String: [String]] = [:]
        var tallies: [String: [String: Tally]] = [:]
        for event in ordered where event.type == "m.reaction" && event.status != .failed
            && !redacted.contains(event.eventID) {
            let link = relation(of: event)
            guard link.relType == "m.annotation", let target = link.eventID, let key = link.key, !key.isEmpty,
                  baseByID[target] != nil, !redacted.contains(target) else { continue }
            var tally = tallies[target, default: [:]][key] ?? Tally()
            if tallies[target]?[key] == nil { order[target, default: []].append(key) }
            tally.people.insert(event.sender)
            if event.mine || event.sender == me { tally.mine = true }
            tallies[target, default: [:]][key] = tally
        }

        var built: [TimelineMessage] = []
        for base in bases {
            let isDeleted = redacted.contains(base.eventID)
            let shown = describe(base, edit: isDeleted ? nil : latestEdit[base.eventID], mine: isMine(base))
            let chips = isDeleted ? [] : (order[base.eventID] ?? []).compactMap { key -> ReactionChip? in
                guard let tally = tallies[base.eventID]?[key] else { return nil }
                return ReactionChip(key: key, count: tally.people.count, mine: tally.mine)
            }
            let refused = isDeleted ? nil : newestOwnEdit[base.eventID].flatMap { $0.status == .failed ? $0 : nil }
            built.append(TimelineMessage(
                id: base.eventID, roomID: base.roomID, sender: base.sender, senderName: base.senderName,
                senderAvatarPath: base.senderAvatarPath, mine: isMine(base), ts: base.ts,
                kind: isDeleted ? .deleted : shown.kind, body: isDeleted ? "" : shown.body,
                rich: isDeleted ? RichText(text: "") : shown.rich,
                isEdited: !isDeleted && latestEdit[base.eventID] != nil,
                editCount: isDeleted ? 0 : liveEdits[base.eventID, default: 0],
                editFailed: refused.map { StatusLine.of(status: .failed, reason: $0.statusReason) },
                failedEditID: refused?.eventID,
                fileName: isDeleted ? "" : shown.fileName, mimeType: isDeleted ? "" : shown.mimeType,
                byteSize: isDeleted ? nil : shown.byteSize, width: isDeleted ? nil : shown.width,
                height: isDeleted ? nil : shown.height, mediaPath: isDeleted ? "" : base.mediaPath,
                statusLine: statusLine(of: base, me: me, newest: base.eventID == newestMine, isDirect: isDirect),
                countsAsUnread: (base.type == "m.room.message" || base.type == "m.sticker" || base.type == pollStartType)
                    && TimerChange.of(base.content) == nil && CallNote.isNews(base),
                poll: isDeleted ? nil : base.poll, thread: base.thread, bookmarked: base.bookmarked,
                expiresAt: base.expiresAt > 0 ? base.expiresAt : nil,
                timerChange: base.type == "m.room.message" && !isDeleted ? TimerChange.of(base.content) : nil,
                call: base.type == "m.room.message" && !isDeleted ? CallNote.of(base.content) : nil,
                reply: nil, reactions: chips, startsGroup: false))
        }

        // Replies are resolved last, so a quote shows the text the quoted message has now.
        let byID = Dictionary(built.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for index in built.indices {
            guard let source = baseByID[built[index].id],
                  let target = relation(of: source).replyTo, built[index].kind != .deleted else { continue }
            if let quoted = byID[target] {
                built[index].reply = .quoted(quoted.quoted)
            } else {
                built[index].reply = .notLoaded(eventID: target)
            }
        }
        return built
    }

    // MARK: - Reading content

    private struct Relation {
        var relType: String?
        var eventID: String?
        var key: String?
        var replyTo: String?
    }

    private static func relation(of event: Event) -> Relation {
        guard let link = event.content["m.relates_to"] else { return Relation() }
        var relation = Relation(relType: link["rel_type"]?.stringValue, eventID: link["event_id"]?.stringValue,
                                key: link["key"]?.stringValue,
                                replyTo: link["m.in_reply_to"]?["event_id"]?.stringValue)
        // A thread reply names its root as what it replies to only for apps without threads: it isn't a reply.
        if relation.relType == "m.thread", link["is_falling_back"] == .bool(true) { relation.replyTo = nil }
        return relation
    }

    /// An edit of another message (m.replace): it is not a message of its own.
    public static func isEdit(_ event: Event) -> Bool {
        relation(of: event).relType == "m.replace"
    }

    private static func isMessageLike(_ event: Event) -> Bool {
        switch event.type {
        case "m.room.message", "m.sticker", "m.room.encrypted", pollStartType: true
        default: false
        }
    }

    private struct Shown {
        var kind: MessageKind
        var body: String
        var rich: RichText
        var fileName = ""
        var mimeType = ""
        var byteSize: Int64?
        var width: Int?
        var height: Int?
    }

    /// The HTML of a message's content, when it has some.
    private static func html(of content: JSONValue?) -> String? {
        guard content?["format"]?.stringValue == "org.matrix.custom.html" else { return nil }
        return content?["formatted_body"]?.stringValue
    }

    private static func rich(_ text: String, html: String?) -> RichText {
        guard let html, !text.isEmpty else { return RichText(text: text) }
        return RichTextHTML.parse(html: html, fallback: text)
    }

    /// What a message says: its kind, its text (the edit's, if it has one) and, for a file, what is known of it. A
    /// call note says Courier's words for the call, never the bridge's body; `mine` is whether I made the call.
    private static func describe(_ event: Event, edit: Event?, mine: Bool) -> Shown {
        let content = event.content
        if event.type == "m.room.message", let call = CallNote.of(content) {
            let words = call.words(mine: mine)
            return Shown(kind: .notice, body: words, rich: RichText(text: words))
        }
        let info = content["info"]
        func number(_ key: String) -> Int64? { info?[key]?.integerValue }

        switch event.type {
        case "m.room.encrypted":
            return Shown(kind: .undecryptable, body: "", rich: RichText(text: ""))
        case "m.sticker":
            return Shown(kind: .sticker, body: "", rich: RichText(text: ""), fileName: content["body"]?.stringValue ?? "",
                         mimeType: info?["mimetype"]?.stringValue ?? "", byteSize: number("size"),
                         width: number("w").map(Int.init), height: number("h").map(Int.init))
        case pollStartType:
            let start = content["org.matrix.msc3381.poll.start"]
            let question = event.poll?.question
                ?? start?["question"]?["org.matrix.msc1767.text"]?.stringValue
                ?? start?["question"]?["body"]?.stringValue
                ?? content["org.matrix.msc1767.text"]?.stringValue
                ?? content["body"]?.stringValue ?? ""
            return Shown(kind: .poll, body: question, rich: RichText(text: question))
        default:
            break
        }

        let msgtype = content["msgtype"]?.stringValue ?? "m.text"
        let original = content["body"]?.stringValue ?? ""
        let kind: MessageKind
        switch msgtype {
        case "m.image": kind = .image
        case "m.video": kind = .video
        case "m.audio": kind = content["org.matrix.msc3245.voice"] != nil ? .voiceNote : .file
        case "m.file": kind = .file
        case "m.notice": kind = .notice
        case "m.emote": kind = .emote
        default: kind = .text
        }

        if kind.isMedia {
            // A body that is not the file's name is a caption (MSC2530); without a filename the body is the name.
            let filename = content["filename"]?.stringValue
            let name = filename ?? original
            let caption = filename != nil && filename != original ? original : ""
            return Shown(kind: kind, body: caption, rich: rich(caption, html: html(of: content)), fileName: name,
                         mimeType: info?["mimetype"]?.stringValue ?? "", byteSize: number("size"),
                         width: number("w").map(Int.init), height: number("h").map(Int.init))
        }

        var body = original
        var formatted = html(of: content)
        if let edit {
            if let replacement = edit.content["m.new_content"], let text = replacement["body"]?.stringValue {
                body = text
                formatted = html(of: replacement)
            } else if let fallback = edit.content["body"]?.stringValue {
                body = fallback.hasPrefix("* ") ? String(fallback.dropFirst(2)) : fallback
                formatted = nil
            }
        } else if relation(of: event).replyTo != nil {
            body = withoutReplyFallback(original)
        }
        return Shown(kind: kind, body: body, rich: rich(body, html: formatted))
    }

    /// A reply made by an app that quotes in its text starts with the quoted lines ("> <@user> text"), then a
    /// blank line. Those lines are the quote, which the reply shows above it, so they are not part of the reply.
    static func withoutReplyFallback(_ body: String) -> String {
        guard body.hasPrefix("> "), let gap = body.range(of: "\n\n") else { return body }
        return String(body[gap.upperBound...])
    }

    /// Someone else's message has none. Mine that has gone has one only when it is my newest (`newest`).
    private static func statusLine(of event: Event, me: String, newest: Bool, isDirect: Bool) -> StatusLine? {
        guard event.mine || event.sender == me else { return nil }
        let line = StatusLine.of(status: event.status, reason: event.statusReason)
        guard line.hasGone else { return line }
        guard newest else { return nil }
        return StatusLine.gone(delivered: event.delivered, readBy: event.readBy, isDirect: isDirect)
    }
}

extension JSONValue {
    /// A whole number, from an integer or a float that has no fraction.
    public var integerValue: Int64? {
        switch self {
        case let .int(value): value
        case let .double(value) where value.rounded() == value && abs(value) < 9e15: Int64(value)
        default: nil
        }
    }
}
