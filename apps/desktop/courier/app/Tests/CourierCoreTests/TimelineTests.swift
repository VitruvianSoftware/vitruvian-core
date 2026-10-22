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
                         extra: String = "", status: String = "sent", media: String = "", reason: String = "",
                         expiresAt: Int64 = 0) -> Event {
        let content = #"{"msgtype":"\#(msgtype)","body":\#(quoted(body))\#(extra)}"#
        return Event(eventID: id, roomID: "!room", sender: mine ? me : sender, senderName: mine ? "me" : name,
                     mine: mine, type: "m.room.message", content: json(content), ts: ts, seq: seq,
                     status: EventStatus(rawValue: status), statusReason: reason, mediaPath: media,
                     expiresAt: expiresAt)
    }

    private func edit(_ id: String, of target: String, to body: String, ts: Int64, seq: Int64 = 0,
                      from sender: String = "@ann:example.test", status: EventStatus = .sent, reason: String = "",
                      html: String? = nil) -> Event {
        let formatted = html.map { #","format":"org.matrix.custom.html","formatted_body":\#(quoted($0))"# } ?? ""
        let content = """
        {"msgtype":"m.text","body":\(quoted("* " + body)),
         "m.new_content":{"msgtype":"m.text","body":\(quoted(body))\(formatted)},
         "m.relates_to":{"rel_type":"m.replace","event_id":"\(target)"}}
        """
        return Event(eventID: id, roomID: "!room", sender: sender, senderName: "x", mine: sender == me,
                     type: "m.room.message", content: json(content), ts: ts, seq: seq, status: status,
                     statusReason: reason)
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

    /// The moment the timeline is built at, for messages with a disappearing timer: well after every fixture.
    private var now: Date { Date(timeIntervalSince1970: Double(at(20, 12, 0)) / 1000) }

    private func build(_ events: [Event], firstUnread: String? = nil, now: Date? = nil,
                       hideDeleted: Bool = false) -> [TimelineItem] {
        Timeline.build(events: events, me: me, firstUnreadID: firstUnread, now: now ?? self.now,
                       hideDeleted: hideDeleted, calendar: utc)
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

    /// The engine fails what was still pending when it stopped with this exact reason; the line says it may have
    /// gone, in the composer's words, rather than "Not sent".
    func testASendCutOffByTheEngineStoppingMayHaveBeenSent() {
        let cutOff = Event(eventID: "$d", roomID: "!room", sender: me, senderName: "me", mine: true,
                           type: "m.room.message", content: json(#"{"msgtype":"m.text","body":"x"}"#),
                           ts: at(14, 10, 3), seq: 0, status: .failed, statusReason: "may have been sent")
        XCTAssertEqual(messages(build([cutOff]))[0].statusLine, .mayHaveBeenSent)
        XCTAssertEqual(StatusLine.mayHaveBeenSentReason, "may have been sent", "the engine's constant, exactly")
        XCTAssertTrue(StatusLine.mayHaveBeenSentText.contains("may have been sent"))
        XCTAssertEqual(StatusLine.of(status: .failed, reason: "May have been sent"), .failed(reason: "May have been sent"),
                       "only the exact text")
    }

    // MARK: - Protocol 4: edits, held messages, deletes, timers, polls and threads

    func testEditedMessageShowsTheNewestLiveEdit() {
        let events = [
            message("$1", ts: at(14, 10, 0), mine: true, body: "helo"),
            edit("$2", of: "$1", to: "hello", ts: at(14, 10, 1), from: me, html: "<strong>hello</strong>"),
            // Pending is live: it reads as sent while the network answers.
            edit("$3", of: "$1", to: "hello there", ts: at(14, 10, 2), from: me, status: .pending,
                 html: "hello <em>there</em>"),
            // A deleted edit, and a refused one, don't count.
            edit("$4", of: "$1", to: "deleted", ts: at(14, 10, 3), from: me),
            redaction("$r", of: "$4", ts: at(14, 10, 4)),
        ]
        let shown = messages(build(events))
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown[0].body, "hello there")
        XCTAssertEqual(shown[0].rich, RichText(text: "hello there", entities: [
            TextEntity(kind: .italic, offset: 6, length: 5),
        ]))
        XCTAssertTrue(shown[0].isEdited)
        XCTAssertEqual(shown[0].editCount, 2)
        XCTAssertNil(shown[0].editFailed)

        // A message's own formatting, before any edit.
        let formatted = message("$5", ts: at(14, 11, 0), body: "make it bold",
                                extra: #","format":"org.matrix.custom.html","formatted_body":"make it <b>bold</b>""#)
        XCTAssertEqual(messages(build([formatted]))[0].rich,
                       RichText(text: "make it bold", entities: [TextEntity(kind: .bold, offset: 8, length: 4)]))
        // Plain text is plain.
        XCTAssertEqual(messages(build([message("$6", ts: at(14, 11, 1), body: "2*3*4 <b>")]))[0].rich,
                       RichText(text: "2*3*4 <b>", entities: []))
    }

    func testFailedEditShowsTheOldTextAndEditNotSent() {
        let events = [
            message("$1", ts: at(14, 10, 0), mine: true, body: "original"),
            edit("$2", of: "$1", to: "refused", ts: at(14, 10, 1), from: me, status: .failed,
                 reason: "the network refused it"),
        ]
        let shown = messages(build(events))[0]
        XCTAssertEqual(shown.body, "original", "a refused edit never looks done")
        XCTAssertEqual(shown.rich.text, "original")
        XCTAssertFalse(shown.isEdited)
        XCTAssertEqual(shown.editCount, 0)
        XCTAssertEqual(shown.editFailed, .failed(reason: "the network refused it"))
        XCTAssertEqual(shown.failedEditID, "$2", "what Retry and Discard act on")

        // A later edit that went through settles it.
        let settled = messages(build(events + [edit("$3", of: "$1", to: "fixed", ts: at(14, 10, 2), from: me)]))[0]
        XCTAssertEqual(settled.body, "fixed")
        XCTAssertNil(settled.editFailed)
        XCTAssertNil(settled.failedEditID)

        // A live edit, then a newer one refused: the live edit's text stays, with "Edit not sent" for the newer.
        let refusedAfterLive = messages(build([
            message("$1", ts: at(14, 10, 0), mine: true, body: "original"),
            edit("$2", of: "$1", to: "first edit", ts: at(14, 10, 1), from: me, html: "<em>first</em> edit"),
            edit("$3", of: "$1", to: "second edit", ts: at(14, 10, 2), from: me, status: .failed, reason: "refused"),
        ]))[0]
        XCTAssertEqual(refusedAfterLive.body, "first edit")
        XCTAssertEqual(refusedAfterLive.rich, RichText(text: "first edit", entities: [
            TextEntity(kind: .italic, offset: 0, length: 5),
        ]))
        XCTAssertTrue(refusedAfterLive.isEdited)
        XCTAssertEqual(refusedAfterLive.editCount, 1)
        XCTAssertEqual(refusedAfterLive.editFailed, .failed(reason: "refused"))
        XCTAssertEqual(refusedAfterLive.failedEditID, "$3")
    }

    func testQueuedMessageShowsQueued() {
        let shown = messages(build([
            message("$1", ts: at(14, 10, 0), mine: true, status: "queued"),
            message("$2", ts: at(14, 10, 1), mine: true, status: "failed", reason: "not sent"),
            message("$3", ts: at(14, 10, 2), mine: true, status: "failed", reason: "not connected"),
            message("$4", ts: at(14, 10, 3), mine: true, status: "failed", reason: "Not sent"),
        ]))
        XCTAssertEqual(shown[0].statusLine, .queued)
        XCTAssertEqual(shown[1].statusLine, .notSent(.appClosed))
        XCTAssertEqual(shown[2].statusLine, .notSent(.notConnected))
        XCTAssertEqual(shown[3].statusLine, .failed(reason: "Not sent"), "only the engine's exact words")
        XCTAssertEqual(StatusLine.notSentReason, "not sent")
        XCTAssertEqual(StatusLine.notConnectedReason, "not connected")
    }

    func testDeletedForMeLeavesNoRow() {
        // The engine leaves a message deleted for me out of every page; what the page still carries for it (its
        // reactions, its edits, a reply quoting it) makes no row and no placeholder.
        let events = [
            reaction("$r", to: "$gone", key: "👍", ts: at(14, 10, 1)),
            edit("$e", of: "$gone", to: "changed", ts: at(14, 10, 2)),
            redaction("$d", of: "$gone", ts: at(14, 10, 3)),
            message("$2", ts: at(14, 10, 4), body: "yes",
                    extra: #","m.relates_to":{"m.in_reply_to":{"event_id":"$gone"}}"#),
        ]
        let shown = messages(build(events))
        XCTAssertEqual(shown.map(\.id), ["$2"])
        XCTAssertEqual(shown[0].reply, .notLoaded(eventID: "$gone"))
    }

    func testRelationsOfThreadRepliesAreAppliedInTheThreadAndIgnoredOutsideIt() {
        let threadReply = message("$t", ts: at(14, 10, 1), body: "Count me in",
                                  extra: #","m.relates_to":{"rel_type":"m.thread","event_id":"$root","is_falling_back":true,"m.in_reply_to":{"event_id":"$root"}}"#)
        let relations = [
            edit("$te", of: "$t", to: "Count me in!", ts: at(14, 10, 2)),
            reaction("$tr", to: "$t", key: "🎉", ts: at(14, 10, 3)),
        ]
        let root = message("$root", ts: at(14, 10, 0), body: "Who's in for lunch?")
        // The main timeline: the reply stays in its thread, but the page carries its edit and reaction.
        XCTAssertEqual(messages(build([root] + relations)).map(\.id), ["$root"])
        // The thread pane: the reply takes them, and isn't shown as a reply to the root it is in.
        let thread = messages(build([root, threadReply] + relations))
        XCTAssertEqual(thread.map(\.id), ["$root", "$t"])
        XCTAssertEqual(thread[1].body, "Count me in!")
        XCTAssertEqual(thread[1].reactions.map(\.key), ["🎉"])
        XCTAssertNil(thread[1].reply)
    }

    func testMessagePastItsTimerIsHidden() {
        let nowMillis = at(15, 9, 0)
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1000)
        let events = [
            message("$past", ts: at(14, 9, 0), body: "gone by now", expiresAt: nowMillis),
            message("$soon", ts: at(14, 9, 1), body: "still here", expiresAt: nowMillis + 1),
            message("$never", ts: at(14, 9, 2), body: "no timer"),
            reaction("$r", to: "$past", key: "👍", ts: at(14, 9, 3)),
            message("$reply", ts: at(14, 9, 4), body: "reply",
                    extra: #","m.relates_to":{"m.in_reply_to":{"event_id":"$past"}}"#),
        ]
        let shown = messages(build(events, now: now))
        XCTAssertEqual(shown.map(\.id), ["$soon", "$never", "$reply"],
                       "a message whose time has come leaves even before the engine deletes it")
        XCTAssertEqual(shown[0].expiresAt, nowMillis + 1)
        XCTAssertNil(shown[1].expiresAt, "0 on the wire is never")
        XCTAssertEqual(shown[2].reply, .notLoaded(eventID: "$past"), "its text isn't quoted either")
        // A moment earlier it was there.
        let earlier = Date(timeIntervalSince1970: Double(nowMillis - 1) / 1000)
        XCTAssertEqual(messages(build(events, now: earlier)).map(\.id), ["$past", "$soon", "$never", "$reply"])

        // The "New" divider never lands on a message that is gone: counted among what is shown.
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 3, now: now), "$soon")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 9, now: now), "$soon")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 4, now: earlier), "$past")
    }

    func testTimerChangeNoticesAreRecognised() {
        func note(_ id: String, _ action: String, ts: Int64) -> Event {
            message(id, ts: ts, body: "Set the disappearing message timer to a while", msgtype: "m.notice",
                    extra: #","com.beeper.action_message":\#(action)"#)
        }
        let events = [
            note("$on", #"{"type":"disappearing_timer","timer":86400000,"timer_type":"after_send","implicit":false}"#,
                 ts: at(14, 9, 0)),
            note("$off", #"{"type":"disappearing_timer","timer":0,"timer_type":"","implicit":true}"#, ts: at(14, 9, 1)),
            note("$other", #"{"type":"something_else","timer":5}"#, ts: at(14, 9, 2)),
            message("$plain", ts: at(14, 9, 3), body: "a notice", msgtype: "m.notice"),
        ]
        let shown = messages(build(events))
        XCTAssertEqual(shown[0].timerChange, TimerChange(type: .afterSend, timerMS: 86_400_000, implicit: false))
        XCTAssertEqual(shown[1].timerChange, TimerChange(type: .off, timerMS: 0, implicit: true))
        XCTAssertNil(shown[2].timerChange, "only the timer's own note")
        XCTAssertNil(shown[3].timerChange)
        XCTAssertEqual(shown.map(\.kind), [.notice, .notice, .notice, .notice], "still counted among the messages")
        // As the engine counts: a timer note is never unread, so the "New" divider never lands on one.
        XCTAssertEqual(shown.map(\.countsAsUnread), [false, false, true, true])
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 1), "$plain")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 2), "$other")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 3), "$other", "more than there are")
    }

    func testNextClockChange() {
        let nowMillis = at(15, 9, 0)
        let now = Date(timeIntervalSince1970: Double(nowMillis) / 1000)
        func shown(_ timed: [Int64]) -> [TimelineItem] {
            build(timed.enumerated().map { message("$\($0.offset)", ts: at(14, 9, $0.offset), expiresAt: $0.element) }
                + [message("$never", ts: at(14, 10, 0))], now: Date(timeIntervalSince1970: 0))
        }
        // Nothing timed: nothing to wait for.
        XCTAssertNil(Disappearing.millisUntilNextChange(in: shown([]), now: now))
        // 90 s left: the countdown reads "2 minutes" for 30 s, then "1 minute".
        XCTAssertEqual(Disappearing.millisUntilNextChange(in: shown([nowMillis + 90_000]), now: now), 30_000)
        // Exactly 2 minutes left reads "2 minutes" until the very next moment.
        XCTAssertEqual(Disappearing.millisUntilNextChange(in: shown([nowMillis + 120_000]), now: now), 60_000)
        // Under a minute: the message itself is what changes.
        XCTAssertEqual(Disappearing.millisUntilNextChange(in: shown([nowMillis + 20_000]), now: now), 20_000)
        // The soonest of several.
        XCTAssertEqual(Disappearing.millisUntilNextChange(
            in: shown([nowMillis + 600_000, nowMillis + 150_000, nowMillis + 45_000]), now: now), 30_000)
        // Past a day the countdown reads in days and hours, so it changes once an hour, not every minute.
        XCTAssertEqual(Disappearing.millisUntilNextChange(in: shown([nowMillis + 90 * 86_400_000]), now: now), 3_600_000)
        XCTAssertEqual(Disappearing.millisUntilNextChange(in: shown([nowMillis + 1530 * 60_000]), now: now), 1_800_000,
                       "25 h 30 min reads as 1 day, 2 hours until 25 h 0 min")
        // A day exactly is the last of the hours-and-minutes: its next change is a minute away.
        XCTAssertEqual(Disappearing.millisUntilNextChange(in: shown([nowMillis + 1440 * 60_000]), now: now), 60_000)
        // One that is already past is not waited for (a rebuild hides it).
        XCTAssertNil(Disappearing.millisUntilNextChange(in: shown([nowMillis - 1, nowMillis]), now: now))
    }

    func testHideDeletedRemovesPlaceholders() {
        let events = [
            message("$1", ts: at(14, 10, 0), body: "secret"),
            redaction("$d", of: "$1", ts: at(14, 10, 1)),
            message("$2", ts: at(14, 10, 2), body: "after"),
        ]
        XCTAssertEqual(messages(build(events)).map(\.kind), [.deleted, .text])
        XCTAssertEqual(messages(build(events, hideDeleted: true)).map(\.id), ["$2"])
    }

    func testPollAndThreadSummaryReachTheMessage() {
        let tally = PollTally(question: "Lunch?", options: [PollOption(id: "a", text: "Noon", votes: 2),
                                                           PollOption(id: "b", text: "One", votes: 0)],
                              maxSelections: 1, voters: 2, mine: ["a"], ended: false)
        let poll = Event(eventID: "$p", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                         type: Timeline.pollStartType,
                         content: json(#"{"org.matrix.msc1767.text":"Lunch?\n1. Noon\n2. One","org.matrix.msc3381.poll.start":{"question":{"org.matrix.msc1767.text":"Lunch?"},"max_selections":1,"answers":[{"id":"a","org.matrix.msc1767.text":"Noon"},{"id":"b","org.matrix.msc1767.text":"One"}]}}"#),
                         ts: at(14, 10, 0), seq: 1, status: .sent, bookmarked: true, poll: tally)
        let vote = Event(eventID: "$v", roomID: "!room", sender: "@bob:example.test", senderName: "Bob", mine: false,
                         type: "org.matrix.msc3381.poll.response",
                         content: json(#"{"m.relates_to":{"rel_type":"m.reference","event_id":"$p"},"org.matrix.msc3381.poll.response":{"answers":["a"]}}"#),
                         ts: at(14, 10, 1), seq: 2, status: .sent)
        let summary = ThreadSummary(replies: 3, lastTS: at(14, 11, 0), lastSenders: ["Ann", "Bob"])
        let root = Event(eventID: "$root", roomID: "!room", sender: me, senderName: "me", mine: true,
                         type: "m.room.message", content: json(#"{"msgtype":"m.text","body":"Plans?"}"#),
                         ts: at(14, 10, 2), seq: 3, status: .sent, thread: summary)
        let shown = messages(build([poll, vote, root]))
        XCTAssertEqual(shown.map(\.id), ["$p", "$root"], "a vote is not a row")
        XCTAssertEqual(shown[0].kind, .poll)
        XCTAssertEqual(shown[0].poll, tally)
        XCTAssertEqual(shown[0].body, "Lunch?")
        XCTAssertTrue(shown[0].bookmarked)
        XCTAssertTrue(shown[0].countsAsUnread, "Ruling 17: an incoming poll is a message")
        XCTAssertEqual(shown[1].thread, summary)
        XCTAssertNil(shown[0].thread)
        XCTAssertFalse(shown[1].bookmarked)
        XCTAssertEqual(Timeline.firstUnreadID(events: [poll, vote, root], me: me, unread: 1), "$p")
        XCTAssertTrue(Timeline.isIncomingMessage(poll))
        XCTAssertEqual(Timeline.summary(of: poll).kind, .poll)
        XCTAssertEqual(Timeline.summary(of: poll).text, "Lunch?")
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
