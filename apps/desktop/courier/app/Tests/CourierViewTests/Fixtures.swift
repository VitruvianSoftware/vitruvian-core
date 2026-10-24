// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation

/// Made-up chats and messages for the snapshots. No real names, numbers or messages.
enum Fixture {
    /// 2026-10-20 14:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_792_504_800)
    static let room = "!chat:courier.local"
    static let ann = "@ann:courier.local"

    static func millis(_ minutesAgo: Int) -> Int64 {
        Int64(now.timeIntervalSince1970 * 1000) - Int64(minutesAgo) * 60_000
    }

    static func event(_ id: String, type: String = "m.room.message", mine: Bool, ts minutesAgo: Int,
                      content: [String: JSONValue], status: EventStatus = .sent, reason: String = "",
                      bookmarked: Bool = false, poll: PollTally? = nil, thread: ThreadSummary? = nil,
                      expiresAt: Int64 = 0, sender: String? = nil, name: String = "Ann Example",
                      delivered: Bool = false, readBy: [Reader] = []) -> Event {
        Event(eventID: id, roomID: room, sender: sender ?? (mine ? Timeline.meUserID : ann),
              senderName: mine ? "" : name, mine: mine, type: type, content: .object(content),
              ts: millis(minutesAgo), seq: Int64(10000 - minutesAgo), status: status, statusReason: reason,
              bookmarked: bookmarked, poll: poll, thread: thread, expiresAt: expiresAt, delivered: delivered,
              readBy: readBy)
    }

    static func text(_ id: String, _ body: String, mine: Bool, ts minutesAgo: Int, html: String? = nil,
                     status: EventStatus = .sent, reason: String = "", bookmarked: Bool = false,
                     thread: ThreadSummary? = nil, expiresAt: Int64 = 0, sender: String? = nil,
                     name: String = "Ann Example", delivered: Bool = false, readBy: [Reader] = []) -> Event {
        var content: [String: JSONValue] = ["msgtype": .string("m.text"), "body": .string(body)]
        if let html {
            content["format"] = .string("org.matrix.custom.html")
            content["formatted_body"] = .string(html)
        }
        return event(id, mine: mine, ts: minutesAgo, content: content, status: status, reason: reason,
                     bookmarked: bookmarked, thread: thread, expiresAt: expiresAt, sender: sender, name: name,
                     delivered: delivered, readBy: readBy)
    }

    /// An edit of `target`, as the engine stores it.
    static func edit(_ id: String, of target: String, _ body: String, ts minutesAgo: Int,
                     status: EventStatus = .sent) -> Event {
        event(id, mine: true, ts: minutesAgo, content: [
            "msgtype": .string("m.text"), "body": .string("* " + body),
            "m.new_content": .object(["msgtype": .string("m.text"), "body": .string(body)]),
            "m.relates_to": .object(["rel_type": .string("m.replace"), "event_id": .string(target)]),
        ], status: status)
    }

    static func poll(_ id: String, mine: Bool, ts minutesAgo: Int, tally: PollTally) -> Event {
        event(id, type: Timeline.pollStartType, mine: mine, ts: minutesAgo,
              content: ["body": .string(tally.question)], poll: tally)
    }

    static func timerNote(_ id: String, mine: Bool, ts minutesAgo: Int, timerMS: Int64) -> Event {
        event(id, mine: mine, ts: minutesAgo, content: [
            "msgtype": .string("m.notice"), "body": .string("Set the disappearing message timer"),
            "com.beeper.action_message": .object([
                "type": .string("disappearing_timer"), "timer": .int(timerMS), "timer_type": .string("after_send"),
                "implicit": .bool(false),
            ]),
        ])
    }

    /// A bridge's call notice as the engine stores it: the bridge's English body, and Courier's reading beside it.
    static func callNote(_ id: String, mine: Bool, ts minutesAgo: Int, body: String, state: String,
                         media: String) -> Event {
        event(id, mine: mine, ts: minutesAgo, content: [
            "msgtype": .string("m.notice"), "body": .string(body),
            "com.beeper.action_message": .object(["type": .string("call")]),
            "fi.courier.call": .object(["state": .string(state), "media": .string(media)]),
        ])
    }

    static func items(_ events: [Event], isDirect: Bool = false) -> [TimelineItem] {
        Timeline.build(events: events, me: Timeline.meUserID, now: now, isDirect: isDirect)
    }

    /// A chat in the inbox, its newest message `minutesAgo`.
    static func row(_ id: String, _ name: String, network: String = "whatsapp", direct: Bool = true,
                    ts minutesAgo: Int, preview: String, mine: Bool = false, unread: Int = 0,
                    status: PreviewStatus = .none, login: String = "", typing: [String] = []) -> InboxRow {
        InboxRow(roomID: id, network: network, name: name, avatarPath: "", isDirect: direct,
                 lastTS: millis(minutesAgo), preview: preview, previewKind: .text, previewMine: mine, unread: unread,
                 muted: false, typing: typing, previewStatus: status, loginName: login)
    }

    static func messages(_ events: [Event]) -> [TimelineMessage] {
        items(events).compactMap { if case let .message(message) = $0 { message } else { nil } }
    }

    /// What WhatsApp's chats can do, with every formatting kind but spoilers.
    static let features = ChatFeatures(
        reply: true, edit: true, editMaxAgeMS: 15 * 60_000, unsend: true, unsendMaxAgeMS: 2 * 86_400_000,
        poll: PollFeatures(maxOptions: 12, optionMaxLength: 100),
        disappearing: DisappearingFeatures(type: .afterSend, timersMS: [86_400_000, 604_800_000, 7_776_000_000]),
        formatting: [.bold, .italic, .strikethrough, .code, .pre, .blockquote, .bulletList, .orderedList, .link,
                     .mention],
        maxTextLength: 65536, source: .stored)

    /// Every formatting kind, as another app's HTML would bring it.
    static let formattedHTML = """
    Plain, <strong>bold</strong>, <em>italic</em>, <del>struck</del>, <code>code()</code>, a \
    <a href="https://example.test/page">link</a>, <a href="https://matrix.to/#/@bo:courier.local">Bo</a> and \
    <span data-mx-spoiler>a secret</span>.<blockquote>A quoted line</blockquote><ul><li>First item</li>\
    <li>Second item</li></ul><ol><li>One</li><li>Two</li></ol><pre><code>let answer = 42 // a long line of code \
    that scrolls sideways rather than wrapping</code></pre>Last line.
    """
}
