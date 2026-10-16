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

/// The line under a message of mine.
public enum StatusLine: Equatable, Sendable {
    case sending
    case sent
    /// The network did not take it. `reason` is the engine's own words and may be empty.
    case failed(reason: String)
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
    /// The text; for a file, its caption (empty if it has none). Empty for a deleted message.
    public let body: String
    public let isEdited: Bool
    /// The file's name, for media.
    public let fileName: String
    public let mimeType: String
    public let byteSize: Int64?
    public let width: Int?
    public let height: Int?
    /// The file on disk, when the engine has it; empty when not.
    public let mediaPath: String
    public let statusLine: StatusLine?
    /// The engine counts this kind of event as unread when it is from someone else: a message or a sticker, not
    /// a message that could not be decrypted (or one that has since been deleted and was something else).
    public let countsAsUnread: Bool
    public internal(set) var reply: ReplyPreview?
    public internal(set) var reactions: [ReactionChip]
    /// The first message of a run from one sender: it shows the name and the picture, and the others do not.
    public internal(set) var startsGroup: Bool

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

    // MARK: - Building

    /// The items to show, oldest first. `events` can be in any order, and can hold events a message needs from
    /// more than one page. `firstUnreadID` is the message the "New" divider goes above.
    public static func build(events: [Event], me: String, firstUnreadID: String? = nil,
                             calendar: Calendar = .autoupdatingCurrent) -> [TimelineItem] {
        var items: [TimelineItem] = []
        var previous: TimelineMessage?
        var previousDay: Date?
        for var message in messages(events: events, me: me) {
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
                || message.ts - (previous?.ts ?? 0) > groupingGapMillis
            items.append(.message(message))
            previous = message
        }
        return items
    }

    /// The oldest of the `unread` newest messages from others (the engine counts messages and stickers only): where
    /// the "New" divider goes when a chat is opened with that many unread. More unread than are loaded puts it
    /// above everything loaded. Nil with none unread.
    public static func firstUnreadID(events: [Event], me: String, unread: Int) -> String? {
        guard unread > 0 else { return nil }
        let incoming = messages(events: events, me: me).filter { !$0.mine && $0.countsAsUnread }
        guard !incoming.isEmpty else { return nil }
        return incoming[max(0, incoming.count - unread)].id
    }

    /// Whether an event is a message from someone else that people read: not mine, not an edit, reaction or
    /// anything else that is not a row of its own.
    public static func isIncomingMessage(_ event: Event) -> Bool {
        !event.mine && event.status != .failed && isMessageLike(event) && !isEdit(event)
    }

    // MARK: - Messages

    private static func messages(events: [Event], me: String) -> [TimelineMessage] {
        var seen = Set<String>()
        let ordered = events
            .filter { seen.insert($0.eventID).inserted }
            .sorted { ($0.ts, $0.seq, $0.eventID) < ($1.ts, $1.seq, $1.eventID) }

        var redacted = Set<String>()
        for event in ordered where event.type == "m.room.redaction" && event.status != .failed {
            if let target = event.content["redacts"]?.stringValue { redacted.insert(target) }
        }

        let bases = ordered.filter { isMessageLike($0) && !isEdit($0) }
        let baseByID = Dictionary(bases.map { ($0.eventID, $0) }, uniquingKeysWith: { first, _ in first })

        // The newest edit of each message, by its own sender. A later edit replaces an earlier one.
        var latestEdit: [String: Event] = [:]
        for event in ordered where event.type == "m.room.message" && isEdit(event) && event.status != .failed
            && !redacted.contains(event.eventID) {
            guard let target = relation(of: event).eventID, let base = baseByID[target], base.sender == event.sender,
                  base.type == "m.room.message" else { continue }
            latestEdit[target] = event
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
            let shown = describe(base, edit: isDeleted ? nil : latestEdit[base.eventID])
            let chips = isDeleted ? [] : (order[base.eventID] ?? []).compactMap { key -> ReactionChip? in
                guard let tally = tallies[base.eventID]?[key] else { return nil }
                return ReactionChip(key: key, count: tally.people.count, mine: tally.mine)
            }
            built.append(TimelineMessage(
                id: base.eventID, roomID: base.roomID, sender: base.sender, senderName: base.senderName,
                senderAvatarPath: base.senderAvatarPath, mine: base.mine || base.sender == me, ts: base.ts,
                kind: isDeleted ? .deleted : shown.kind, body: isDeleted ? "" : shown.body,
                isEdited: !isDeleted && latestEdit[base.eventID] != nil,
                fileName: isDeleted ? "" : shown.fileName, mimeType: isDeleted ? "" : shown.mimeType,
                byteSize: isDeleted ? nil : shown.byteSize, width: isDeleted ? nil : shown.width,
                height: isDeleted ? nil : shown.height, mediaPath: isDeleted ? "" : base.mediaPath,
                statusLine: statusLine(of: base, me: me),
                countsAsUnread: base.type == "m.room.message" || base.type == "m.sticker", reply: nil, reactions: chips, startsGroup: false))
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
        return Relation(relType: link["rel_type"]?.stringValue, eventID: link["event_id"]?.stringValue,
                        key: link["key"]?.stringValue,
                        replyTo: link["m.in_reply_to"]?["event_id"]?.stringValue)
    }

    private static func isEdit(_ event: Event) -> Bool {
        relation(of: event).relType == "m.replace"
    }

    private static func isMessageLike(_ event: Event) -> Bool {
        switch event.type {
        case "m.room.message", "m.sticker", "m.room.encrypted": true
        default: false
        }
    }

    private struct Shown {
        var kind: MessageKind
        var body: String
        var fileName = ""
        var mimeType = ""
        var byteSize: Int64?
        var width: Int?
        var height: Int?
    }

    /// What a message says: its kind, its text (the edit's, if it has one) and, for a file, what is known of it.
    private static func describe(_ event: Event, edit: Event?) -> Shown {
        let content = event.content
        let info = content["info"]
        func number(_ key: String) -> Int64? { info?[key]?.integerValue }

        switch event.type {
        case "m.room.encrypted":
            return Shown(kind: .undecryptable, body: "")
        case "m.sticker":
            return Shown(kind: .sticker, body: "", fileName: content["body"]?.stringValue ?? "",
                         mimeType: info?["mimetype"]?.stringValue ?? "", byteSize: number("size"),
                         width: number("w").map(Int.init), height: number("h").map(Int.init))
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
            return Shown(kind: kind, body: caption, fileName: name, mimeType: info?["mimetype"]?.stringValue ?? "",
                         byteSize: number("size"), width: number("w").map(Int.init), height: number("h").map(Int.init))
        }

        var body = original
        if let edit {
            if let replacement = edit.content["m.new_content"]?["body"]?.stringValue {
                body = replacement
            } else if let fallback = edit.content["body"]?.stringValue {
                body = fallback.hasPrefix("* ") ? String(fallback.dropFirst(2)) : fallback
            }
        } else if relation(of: event).replyTo != nil {
            body = withoutReplyFallback(original)
        }
        return Shown(kind: kind, body: body)
    }

    /// A reply made by an app that quotes in its text starts with the quoted lines ("> <@user> text"), then a
    /// blank line. Those lines are the quote, which the reply shows above it, so they are not part of the reply.
    static func withoutReplyFallback(_ body: String) -> String {
        guard body.hasPrefix("> "), let gap = body.range(of: "\n\n") else { return body }
        return String(body[gap.upperBound...])
    }

    private static func statusLine(of event: Event, me: String) -> StatusLine? {
        guard event.mine || event.sender == me else { return nil }
        switch event.status {
        case .pending: return .sending
        case .failed: return .failed(reason: event.statusReason)
        default: return .sent
        }
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
