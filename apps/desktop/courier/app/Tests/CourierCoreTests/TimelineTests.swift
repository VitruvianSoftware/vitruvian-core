// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Timeline.build turns the raw events of room.events (messages, edits, reactions, redactions) into what the
/// conversation shows. All data here is made up.
final class TimelineTests: XCTestCase {
    private let me = Timeline.meUserID
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Fixtures

    /// Milliseconds for a moment in UTC.
    private func at(_ day: Int, _ hour: Int, _ minute: Int, second: Int = 0) -> Int64 {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = day
        parts.hour = hour; parts.minute = minute; parts.second = second
        return Int64(utc.date(from: parts)!.timeIntervalSince1970 * 1000)
    }

    private func json(_ text: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private func message(_ id: String, ts: Int64, seq: Int64 = 0, from sender: String = "@ann:example.test",
                         name: String = "Ann", mine: Bool = false, body: String = "Hello", msgtype: String = "m.text",
                         extra: String = "", status: String = "sent", media: String = "") -> Event {
        let content = #"{"msgtype":"\#(msgtype)","body":\#(quoted(body))\#(extra)}"#
        return Event(eventID: id, roomID: "!room", sender: mine ? me : sender, senderName: mine ? "me" : name,
                     mine: mine, type: "m.room.message", content: json(content), ts: ts, seq: seq,
                     status: EventStatus(rawValue: status), mediaPath: media)
    }

    private func edit(_ id: String, of target: String, to body: String, ts: Int64, seq: Int64 = 0,
                      from sender: String = "@ann:example.test") -> Event {
        let content = """
        {"msgtype":"m.text","body":\(quoted("* " + body)),
         "m.new_content":{"msgtype":"m.text","body":\(quoted(body))},
         "m.relates_to":{"rel_type":"m.replace","event_id":"\(target)"}}
        """
        return Event(eventID: id, roomID: "!room", sender: sender, senderName: "x", mine: sender == me,
                     type: "m.room.message", content: json(content), ts: ts, seq: seq, status: .sent)
    }

    private func reaction(_ id: String, to target: String, key: String, ts: Int64, seq: Int64 = 0,
                          from sender: String = "@bob:example.test", mine: Bool = false,
                          status: String = "sent") -> Event {
        let content = #"{"m.relates_to":{"rel_type":"m.annotation","event_id":"\#(target)","key":"\#(key)"}}"#
        return Event(eventID: id, roomID: "!room", sender: mine ? me : sender, senderName: "x", mine: mine,
                     type: "m.reaction", content: json(content), ts: ts, seq: seq, status: EventStatus(rawValue: status))
    }

    private func redaction(_ id: String, of target: String, ts: Int64, seq: Int64 = 0) -> Event {
        Event(eventID: id, roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
              type: "m.room.redaction", content: json(#"{"redacts":"\#(target)"}"#), ts: ts, seq: seq, status: .sent)
    }

    private func quoted(_ text: String) -> String {
        let data = try! JSONEncoder().encode(text)
        return String(decoding: data, as: UTF8.self)
    }

    private func messages(_ items: [TimelineItem]) -> [TimelineMessage] {
        items.compactMap { if case let .message(m) = $0 { m } else { nil } }
    }

    private func build(_ events: [Event], firstUnread: String? = nil) -> [TimelineItem] {
        Timeline.build(events: events, me: me, firstUnreadID: firstUnread, calendar: utc)
    }

    // MARK: - Edits

    func testEditReplacesBody() {
        let events = [
            message("$1", ts: at(14, 10, 0), body: "helo"),
            edit("$2", of: "$1", to: "hello", ts: at(14, 10, 1)),
        ]
        let shown = messages(build(events))
        XCTAssertEqual(shown.count, 1, "the edit is applied to its message, not shown as one of its own")
        XCTAssertEqual(shown[0].id, "$1")
        XCTAssertEqual(shown[0].body, "hello")
        XCTAssertTrue(shown[0].isEdited)

        // The newest edit wins, whatever order the events come in.
        let again = messages(build([
            edit("$3", of: "$1", to: "hello there", ts: at(14, 10, 2)),
            edit("$2", of: "$1", to: "hello", ts: at(14, 10, 1)),
            message("$1", ts: at(14, 10, 0), body: "helo"),
        ]))
        XCTAssertEqual(again[0].body, "hello there")

        // Someone else cannot edit it, and an edit of a message that is not loaded shows nothing.
        let others = messages(build([
            message("$1", ts: at(14, 10, 0), body: "mine"),
            edit("$2", of: "$1", to: "forged", ts: at(14, 10, 1), from: "@eve:example.test"),
            edit("$3", of: "$gone", to: "orphan", ts: at(14, 10, 2)),
        ]))
        XCTAssertEqual(others.count, 1)
        XCTAssertEqual(others[0].body, "mine")
        XCTAssertFalse(others[0].isEdited)
    }

    func testAnEditThatHasNoNewContentFallsBackToItsBody() {
        let edited = Event(eventID: "$2", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                           type: "m.room.message",
                           content: json(#"{"msgtype":"m.text","body":"* fixed","m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}"#),
                           ts: at(14, 10, 1), seq: 0, status: .sent)
        let shown = messages(build([message("$1", ts: at(14, 10, 0), body: "broken"), edited]))
        XCTAssertEqual(shown[0].body, "fixed", "the replacement's leading \"* \" is not part of the text")
    }

    // MARK: - Redactions

    func testRedactionLeavesPlaceholder() {
        let events = [
            message("$1", ts: at(14, 10, 0), body: "secret"),
            reaction("$r", to: "$1", key: "👍", ts: at(14, 10, 1)),
            redaction("$d", of: "$1", ts: at(14, 10, 2)),
        ]
        let shown = messages(build(events))
        XCTAssertEqual(shown.count, 1, "the redaction event is not shown")
        XCTAssertEqual(shown[0].kind, .deleted)
        XCTAssertEqual(shown[0].body, "", "the text is gone, not hidden")
        XCTAssertTrue(shown[0].reactions.isEmpty, "a deleted message keeps no reactions")
    }

    func testRedactingAReactionRemovesIt() {
        let events = [
            message("$1", ts: at(14, 10, 0)),
            reaction("$r1", to: "$1", key: "👍", ts: at(14, 10, 1)),
            reaction("$r2", to: "$1", key: "❤️", ts: at(14, 10, 2)),
            redaction("$d", of: "$r1", ts: at(14, 10, 3)),
        ]
        let shown = messages(build(events))
        XCTAssertEqual(shown[0].reactions.map(\.key), ["❤️"])
    }

    func testARedactedEditIsNotApplied() {
        let events = [
            message("$1", ts: at(14, 10, 0), body: "original"),
            edit("$2", of: "$1", to: "changed", ts: at(14, 10, 1)),
            redaction("$d", of: "$2", ts: at(14, 10, 2)),
        ]
        let shown = messages(build(events))
        XCTAssertEqual(shown[0].body, "original")
        XCTAssertFalse(shown[0].isEdited)
    }

    // MARK: - Reactions

    func testReactionsGroupUnderTarget() {
        let events = [
            message("$1", ts: at(14, 10, 0)),
            message("$2", ts: at(14, 10, 1)),
            reaction("$r1", to: "$1", key: "👍", ts: at(14, 10, 2), from: "@bob:example.test"),
            reaction("$r2", to: "$1", key: "👍", ts: at(14, 10, 3), from: "@cy:example.test"),
            reaction("$r3", to: "$1", key: "❤️", ts: at(14, 10, 4), mine: true),
            // The same person with the same key twice counts once.
            reaction("$r4", to: "$1", key: "👍", ts: at(14, 10, 5), from: "@bob:example.test"),
            // A reaction that failed to send is not shown.
            reaction("$r5", to: "$1", key: "😂", ts: at(14, 10, 6), mine: true, status: "failed"),
            reaction("$r6", to: "$2", key: "🙏", ts: at(14, 10, 7)),
        ]
        let shown = messages(build(events))
        XCTAssertEqual(shown.map(\.id), ["$1", "$2"], "reactions are not rows of their own")
        XCTAssertEqual(shown[0].reactions.map(\.key), ["👍", "❤️"], "in the order each was first given")
        XCTAssertEqual(shown[0].reactions.map(\.count), [2, 1])
        XCTAssertEqual(shown[0].reactions.map(\.mine), [false, true])
        XCTAssertEqual(shown[1].reactions.map(\.key), ["🙏"])
    }

    func testReactionToUnknownTargetIsDropped() {
        let events = [
            message("$1", ts: at(14, 10, 0)),
            reaction("$r1", to: "$not-loaded", key: "👍", ts: at(14, 10, 1)),
        ]
        let items = build(events)
        XCTAssertEqual(messages(items).count, 1)
        XCTAssertTrue(messages(items)[0].reactions.isEmpty)
    }

    // MARK: - Replies

    func testReplyResolvesQuoted() {
        let reply = message("$2", ts: at(14, 10, 1), from: "@bob:example.test", name: "Bob",
                            body: "> <@ann:example.test> Lunch at one?\n\nYes please",
                            extra: #","m.relates_to":{"m.in_reply_to":{"event_id":"$1"}}"#)
        let shown = messages(build([message("$1", ts: at(14, 10, 0), body: "Lunch at one?"), reply]))
        XCTAssertEqual(shown[1].body, "Yes please", "the quoted text the sender's app added is not part of the reply")
        XCTAssertEqual(shown[1].reply,
                       .quoted(QuotedMessage(eventID: "$1", senderName: "Ann", mine: false, text: "Lunch at one?",
                                             kind: .text)))
    }

    func testReplyToAnEditedMessageQuotesTheNewText() {
        let reply = message("$3", ts: at(14, 10, 2), body: "ok", extra: #","m.relates_to":{"m.in_reply_to":{"event_id":"$1"}}"#)
        let shown = messages(build([
            message("$1", ts: at(14, 10, 0), body: "old"),
            edit("$2", of: "$1", to: "new", ts: at(14, 10, 1)),
            reply,
        ]))
        guard case let .quoted(quote)? = shown[1].reply else { return XCTFail("not resolved") }
        XCTAssertEqual(quote.text, "new")
    }

    func testReplyToAMessageThatIsNotLoadedSaysSo() {
        let reply = message("$2", ts: at(14, 10, 1), body: "answer",
                            extra: #","m.relates_to":{"m.in_reply_to":{"event_id":"$old"}}"#)
        let shown = messages(build([reply]))
        XCTAssertEqual(shown[0].reply, .notLoaded(eventID: "$old"))
    }

    func testAReplyThatStartsWithAQuoteMarkIsNotCutWhenItIsNotAReply() {
        let plain = message("$1", ts: at(14, 10, 0), body: "> just a quote\n\nand a thought")
        XCTAssertEqual(messages(build([plain]))[0].body, "> just a quote\n\nand a thought")
    }

    // MARK: - Grouping, dates and the New divider

    func testGroupingAndDateSeparators() {
        let events = [
            message("$1", ts: at(14, 10, 0), name: "Ann"),
            message("$2", ts: at(14, 10, 3), name: "Ann"), // 3 minutes later: same group
            message("$3", ts: at(14, 10, 9), name: "Ann"), // 6 minutes after the last: a new group
            message("$4", ts: at(14, 10, 10), from: "@bob:example.test", name: "Bob"), // another sender
            message("$5", ts: at(14, 10, 11), mine: true), // me
            message("$6", ts: at(15, 0, 5), mine: true), // the next day, from the same sender
        ]
        // Reversed, as the engine sends them.
        let items = build(events.reversed())
        XCTAssertEqual(items.map(\.id), [
            "day-\(at(14, 0, 0))", "$1", "$2", "$3", "$4", "$5", "day-\(at(15, 0, 0))", "$6",
        ])
        let starts = Dictionary(uniqueKeysWithValues: messages(items).map { ($0.id, $0.startsGroup) })
        XCTAssertEqual(starts, ["$1": true, "$2": false, "$3": true, "$4": true, "$5": true, "$6": true])
        if case let .dateSeparator(day) = items[0] {
            XCTAssertEqual(day, utc.startOfDay(for: Date(timeIntervalSince1970: Double(at(14, 10, 0)) / 1000)))
        } else {
            XCTFail("the first item is the day")
        }
    }

    func testMessagesWithTheSameTimeKeepTheEnginesArrivalOrder() {
        let events = [
            message("$b", ts: at(14, 10, 0), seq: 2),
            message("$a", ts: at(14, 10, 0), seq: 1),
        ]
        XCTAssertEqual(messages(build(events)).map(\.id), ["$a", "$b"])
    }

    func testNewDividerAtReadMarker() {
        let events = [
            message("$1", ts: at(14, 10, 0)),
            message("$2", ts: at(14, 10, 1)),
            message("$3", ts: at(14, 10, 2)),
        ]
        let items = build(events, firstUnread: "$2")
        XCTAssertEqual(items.map(\.id), ["day-\(at(14, 0, 0))", "$1", "new", "$2", "$3"])
        let starts = messages(items).map(\.startsGroup)
        XCTAssertEqual(starts, [true, true, false], "the divider starts a new group")

        XCTAssertFalse(build(events).contains { $0.id == "new" }, "nothing unread, no divider")
        XCTAssertFalse(build(events, firstUnread: "$unknown").contains { $0.id == "new" })
    }

    func testFirstUnreadIsFoundFromTheUnreadCount() {
        let events = [
            message("$1", ts: at(14, 10, 0)),
            message("$2", ts: at(14, 10, 1), mine: true),
            message("$3", ts: at(14, 10, 2)),
            reaction("$r", to: "$1", key: "👍", ts: at(14, 10, 3)),
            message("$4", ts: at(14, 10, 4)),
        ]
        XCTAssertNil(Timeline.firstUnreadID(events: events, me: me, unread: 0))
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 1), "$4")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 2), "$3",
                       "my own messages and reactions are not unread")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 3), "$1")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 40), "$1",
                       "more unread than loaded: everything loaded is new")
    }

    func testOnlyMessagesAndStickersCountAsUnread() {
        let locked = Event(eventID: "$e", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                           type: "m.room.encrypted", content: json("{}"), ts: at(14, 10, 3), seq: 0, status: .sent)
        let sticker = Event(eventID: "$s", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                            type: "m.sticker", content: json(#"{"body":"wave"}"#), ts: at(14, 10, 4), seq: 0, status: .sent)
        let events = [message("$1", ts: at(14, 10, 0)), message("$2", ts: at(14, 10, 1)), locked, sticker]
        // Two unread: the sticker and $2. The message that could not be decrypted is not one of them, as the
        // engine's count does not have it.
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 2), "$2")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 3), "$1")
    }

    // MARK: - Kinds, media and status

    func testKindsAndMedia() {
        let events = [
            message("$img", ts: at(14, 10, 0), body: "beach.jpg", msgtype: "m.image",
                    extra: #","info":{"w":1600,"h":900,"mimetype":"image/jpeg","size":2048}"#, media: "/tmp/beach.jpg"),
            message("$cap", ts: at(14, 10, 1), body: "Look at this", msgtype: "m.image",
                    extra: #","filename":"dog.png","info":{"w":10,"h":10}"#, media: "/tmp/dog.png"),
            message("$file", ts: at(14, 10, 2), body: "report.pdf", msgtype: "m.file",
                    extra: #","info":{"mimetype":"application/pdf","size":1048576}"#, media: "/tmp/report.pdf"),
            message("$voice", ts: at(14, 10, 3), body: "Voice message", msgtype: "m.audio",
                    extra: #","org.matrix.msc3245.voice":{}"#, media: "/tmp/v.ogg"),
            message("$vid", ts: at(14, 10, 4), body: "clip.mp4", msgtype: "m.video", media: "/tmp/clip.mp4"),
            message("$emote", ts: at(14, 10, 5), body: "waves", msgtype: "m.emote"),
            message("$note", ts: at(14, 10, 6), body: "Bridge connected", msgtype: "m.notice"),
        ]
        let shown = Dictionary(uniqueKeysWithValues: messages(build(events)).map { ($0.id, $0) })

        XCTAssertEqual(shown["$img"]?.kind, .image)
        XCTAssertEqual(shown["$img"]?.fileName, "beach.jpg")
        XCTAssertEqual(shown["$img"]?.body, "", "the file name is not a caption")
        XCTAssertEqual(shown["$img"]?.width, 1600)
        XCTAssertEqual(shown["$img"]?.height, 900)
        XCTAssertEqual(shown["$img"]?.mediaPath, "/tmp/beach.jpg")

        XCTAssertEqual(shown["$cap"]?.fileName, "dog.png")
        XCTAssertEqual(shown["$cap"]?.body, "Look at this", "with a file name of its own, the body is the caption")

        XCTAssertEqual(shown["$file"]?.kind, .file)
        XCTAssertEqual(shown["$file"]?.byteSize, 1_048_576)
        XCTAssertEqual(shown["$file"]?.mimeType, "application/pdf")

        XCTAssertEqual(shown["$voice"]?.kind, .voiceNote)
        XCTAssertEqual(shown["$vid"]?.kind, .video)
        XCTAssertEqual(shown["$emote"]?.kind, .emote)
        XCTAssertEqual(shown["$note"]?.kind, .notice)
    }

    func testStickersEncryptedAndUnknownEvents() {
        let sticker = Event(eventID: "$s", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                            type: "m.sticker", content: json(#"{"body":"wave","info":{"w":128,"h":128}}"#),
                            ts: at(14, 10, 0), seq: 0, status: .sent, mediaPath: "/tmp/s.webp")
        let locked = Event(eventID: "$e", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                           type: "m.room.encrypted", content: json("{}"), ts: at(14, 10, 1), seq: 0, status: .sent)
        let member = Event(eventID: "$m", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                           type: "m.room.member", content: json(#"{"membership":"join"}"#), ts: at(14, 10, 2), seq: 0,
                           status: .sent)
        let shown = messages(build([sticker, locked, member]))
        XCTAssertEqual(shown.map(\.id), ["$s", "$e"], "an event the app cannot show leaves no row")
        XCTAssertEqual(shown[0].kind, .sticker)
        XCTAssertEqual(shown[1].kind, .undecryptable)
    }

    func testStatusLineIsOnlyOnMyMessages() {
        let events = [
            message("$a", ts: at(14, 10, 0)),
            message("$b", ts: at(14, 10, 1), mine: true, status: "pending"),
            message("$c", ts: at(14, 10, 2), mine: true, status: "sent"),
            Event(eventID: "$d", roomID: "!room", sender: me, senderName: "me", mine: true, type: "m.room.message",
                  content: json(#"{"msgtype":"m.text","body":"x"}"#), ts: at(14, 10, 3), seq: 0, status: .failed,
                  statusReason: "the network refused it"),
        ]
        let shown = messages(build(events))
        XCTAssertNil(shown[0].statusLine)
        XCTAssertEqual(shown[1].statusLine, .sending)
        XCTAssertEqual(shown[2].statusLine, .sent)
        XCTAssertEqual(shown[3].statusLine, .failed(reason: "the network refused it"))
    }

    // MARK: - Day labels

    func testDayLabels() {
        let now = Date(timeIntervalSince1970: Double(at(14, 12, 0)) / 1000)
        func label(_ day: Int) -> DayLabel {
            DayLabel.of(day: utc.startOfDay(for: Date(timeIntervalSince1970: Double(at(day, 9, 0)) / 1000)),
                        now: now, calendar: utc)
        }
        XCTAssertEqual(label(14), .today)
        XCTAssertEqual(label(13), .yesterday)
        if case .date = label(11) {} else { XCTFail("older days are dated") }
    }
}
