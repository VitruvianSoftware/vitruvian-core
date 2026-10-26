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
                         expiresAt: Int64 = 0, delivered: Bool = false, readBy: [Reader] = []) -> Event {
        let content = #"{"msgtype":"\#(msgtype)","body":\#(quoted(body))\#(extra)}"#
        return Event(eventID: id, roomID: "!room", sender: mine ? me : sender, senderName: mine ? "me" : name,
                     mine: mine, type: "m.room.message", content: json(content), ts: ts, seq: seq,
                     status: EventStatus(rawValue: status), statusReason: reason, mediaPath: media,
                     expiresAt: expiresAt, delivered: delivered, readBy: readBy)
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
                       hideDeleted: Bool = false, isDirect: Bool = false) -> [TimelineItem] {
        Timeline.build(events: events, me: me, firstUnreadID: firstUnread, now: now ?? self.now,
                       hideDeleted: hideDeleted, isDirect: isDirect, calendar: utc)
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
        XCTAssertEqual(shown[2].statusLine, .sent, "my newest message that went: $d after it never did")
        XCTAssertEqual(shown[3].statusLine, .failed(reason: "the network refused it"))
    }

    /// Ruling 20: the receipt line is under my newest message that has gone. A newer one still waiting or failed keeps
    /// its own line and doesn't hide it, and a message I deleted never takes it.
    func testTheReceiptLineIsOnMyNewestMessageThatWent() {
        let ana = Reader(userID: "@ana:example.test", name: "Ana", ts: at(14, 10, 5))
        let seen = message("$1", ts: at(14, 10, 0), mine: true, readBy: [ana])
        var shown = messages(build([seen, message("$2", ts: at(14, 10, 1), mine: true, status: "waiting"),
                                    message("$3", ts: at(14, 10, 2), mine: true, status: "failed")]))
        XCTAssertEqual(shown.map(\.statusLine), [.seen(by: ["Ana"], at: nil), .waiting, .failed(reason: "")])

        // My newest message, deleted: the one before it says how far it got.
        let deleted = message("$4", ts: at(14, 10, 3), mine: true, readBy: [ana])
        shown = messages(build([seen, deleted, redaction("$r", of: "$4", ts: at(14, 10, 4))]))
        XCTAssertEqual(shown.map(\.id), ["$1", "$4"])
        XCTAssertEqual(shown[0].statusLine, .seen(by: ["Ana"], at: nil))
        XCTAssertNil(shown[1].statusLine, "a deleted message takes no line")
    }

    /// Ruling 20: Delivered only in a one-to-one chat (the networks report it nowhere else).
    func testDeliveredOnlyOneToOne() {
        let delivered = message("$1", ts: at(14, 10, 0), mine: true, delivered: true)
        XCTAssertEqual(messages(build([delivered], isDirect: true))[0].statusLine, .delivered)
        XCTAssertEqual(messages(build([delivered], isDirect: false))[0].statusLine, .sent)
    }

    // MARK: - Protocol 5: delivered, seen, waiting

    /// Review Focus 2: "Seen" is never a lie. Only my newest message says how far it got, from its own receipts: an
    /// older message's receipts never mark a newer one, and a group's Seen names the newest reader and counts the rest.
    func testSeenIsOnlyOnMyNewestMessageAndNamesTheReaders() {
        let ana = Reader(userID: "@ana:example.test", name: "Ana", ts: at(14, 10, 5))
        let bo = Reader(userID: "@bo:example.test", name: "Bo", ts: at(14, 10, 4))
        let cy = Reader(userID: "@cy:example.test", name: "Cy", ts: at(14, 10, 3))
        // The engine counts a reader of a newer message as a reader of the older ones: $1 has Ana, $2 has no one.
        let older = message("$1", ts: at(14, 10, 0), mine: true, readBy: [ana])
        let newest = message("$2", ts: at(14, 10, 1), mine: true)
        var shown = messages(build([older, newest]))
        XCTAssertNil(shown[0].statusLine, "an older message never says Seen, whatever it has")
        XCTAssertEqual(shown[1].statusLine, .sent, "a receipt for an older message doesn't mark a newer one")

        // A group: the newest receipt first, by name, with how many others.
        shown = messages(build([older, message("$2", ts: at(14, 10, 1), mine: true, readBy: [ana, bo, cy])]))
        XCTAssertEqual(shown[1].statusLine, .seen(by: ["Ana", "Bo", "Cy"], at: nil))
        XCTAssertEqual(StatusLine.seenText(shown[1].statusLine!, time: { _ in "x" }), "Seen by Ana & 2 others")

        // One-to-one: no one is named, and the time is the receipt's.
        let direct = messages(build([message("$2", ts: at(14, 10, 1), mine: true, delivered: true, readBy: [ana])],
                                    isDirect: true))
        XCTAssertEqual(direct[0].statusLine, .seen(by: [], at: at(14, 10, 5)))
        // A receipt with no time says only Seen.
        let untimed = Reader(userID: "@ana:example.test", name: "Ana", ts: 0)
        XCTAssertEqual(messages(build([message("$2", ts: at(14, 10, 1), mine: true, readBy: [untimed])],
                                      isDirect: true))[0].statusLine, .seen(by: [], at: nil))

        // Delivered, until someone reads it; a note after it (a call I made) never takes the line.
        let delivered = message("$2", ts: at(14, 10, 1), mine: true, delivered: true)
        let call = Event(eventID: "$call", roomID: "!room", sender: me, senderName: "me", mine: true,
                         type: "m.room.message",
                         content: json(#"{"msgtype":"m.notice","body":"Call","com.beeper.action_message":{"type":"call"},"fi.courier.call":{"state":"ended","media":"voice"}}"#),
                         ts: at(14, 10, 2), seq: 0, status: .sent)
        shown = messages(build([older, delivered, call], isDirect: true))
        XCTAssertEqual(shown.map(\.id), ["$1", "$2", "$call"])
        XCTAssertNil(shown[0].statusLine)
        XCTAssertEqual(shown[1].statusLine, .delivered)
        XCTAssertNil(shown[2].statusLine, "a note says nothing of how far it got")

        // Someone else's newest message takes nothing from mine: my newest still says it.
        shown = messages(build([delivered, message("$3", ts: at(14, 10, 3))], isDirect: true))
        XCTAssertEqual(shown[0].statusLine, .delivered)
        XCTAssertNil(shown[1].statusLine)
    }

    func testDeliveredAndSeenWording() {
        let time: (Date) -> String = { [utc] date in
            let parts = utc.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour!, parts.minute!)
        }
        XCTAssertEqual(StatusLine.seenText(.seen(by: [], at: nil), time: time), "Seen")
        XCTAssertEqual(StatusLine.seenText(.seen(by: [], at: at(14, 10, 42)), time: time), "Seen 10:42")
        XCTAssertEqual(StatusLine.seenText(.seen(by: ["Ana"], at: nil), time: time), "Seen by Ana")
        XCTAssertEqual(StatusLine.seenText(.seen(by: ["Ana", "Bo"], at: nil), time: time), "Seen by Ana & 1 other")
        XCTAssertEqual(StatusLine.seenText(.seen(by: ["Ana", "Bo", "Cy"], at: nil), time: time),
                       "Seen by Ana & 2 others")
        for other in [StatusLine.sent, .delivered, .sending, .queued, .waiting, .noAccount, .failed(reason: "")] {
            XCTAssertNil(StatusLine.seenText(other, time: time), "\(other)")
        }
        XCTAssertEqual(StatusLine.deliveredLabel, "Delivered")
        XCTAssertEqual(StatusLine.waitingLabel, "Waiting to send")
        XCTAssertEqual(StatusLine.waitingHelp(network: "whatsapp"), "It goes when WhatsApp is back online.")
        XCTAssertEqual(StatusLine.waitingHelp(network: "matrix"), "It goes when the network is back online.",
                       "never a raw network id")
        XCTAssertEqual(StatusLine.noAccountLabel, "Can’t send: none of your accounts is in this chat")
        XCTAssertEqual(StatusLine.dontSendTitle, "Don’t Send")
    }

    /// Review Focus 1: a message waiting for its network shows it the whole time, on every waiting message, never as
    /// Sent; one no account of mine can send says so, in Courier's words.
    func testWaitingShowsOnEveryWaitingMessage() {
        let shown = messages(build([
            message("$1", ts: at(14, 10, 0), mine: true),
            message("$2", ts: at(14, 10, 1), mine: true, status: "waiting"),
            message("$3", ts: at(14, 10, 2), mine: true, status: "waiting"),
            message("$4", ts: at(14, 10, 3), mine: true, status: "waiting", reason: "no account"),
            message("$5", ts: at(14, 10, 4), mine: true, status: "waiting", reason: "No account"),
        ]))
        XCTAssertEqual(shown[0].statusLine, .sent, "the newest that went keeps its line above the waiting ones")
        XCTAssertEqual(shown[1].statusLine, .waiting)
        XCTAssertEqual(shown[2].statusLine, .waiting)
        XCTAssertEqual(shown[3].statusLine, .noAccount)
        XCTAssertEqual(shown[4].statusLine, .waiting, "only the engine's exact words")
        XCTAssertEqual(StatusLine.noAccountReason, "no account")
        XCTAssertTrue(shown[1].statusLine!.isWaiting)
        XCTAssertTrue(shown[3].statusLine!.isWaiting)
    }

    func testOthersMessagesNeverHaveAStatusLine() {
        let ana = Reader(userID: "@me:courier.local", name: "me", ts: at(14, 10, 5))
        // Whatever an event of someone else's carries (a stray read_by, delivered), it has no line.
        let shown = messages(build([
            message("$1", ts: at(14, 10, 0), mine: true),
            message("$2", ts: at(14, 10, 1), delivered: true, readBy: [ana]),
            message("$3", ts: at(14, 10, 2), status: "waiting"),
        ], isDirect: true))
        XCTAssertEqual(shown[0].statusLine, .sent, "my newest message")
        XCTAssertNil(shown[1].statusLine)
        XCTAssertNil(shown[2].statusLine)
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
        // The "N new messages" pill counts as the engine counts unread: a timer note is no new message, another
        // action message (a call notice) is.
        XCTAssertEqual(events.map(Timeline.isIncomingMessage), [false, false, true, true])
        XCTAssertNil(shown[3].timerChange)
        XCTAssertEqual(shown.map(\.kind), [.notice, .notice, .notice, .notice], "still counted among the messages")
        // As the engine counts: a timer note is never unread, so the "New" divider never lands on one.
        XCTAssertEqual(shown.map(\.countsAsUnread), [false, false, true, true])
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 1), "$plain")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 2), "$other")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: me, unread: 3), "$other", "more than there are")
    }

    /// Final fix wave: the engine clamps the times it stores, and the app never traps on any Int64 it is handed
    /// either (an older row, a newer engine): a message's age, a countdown, its next change and the gap between two
    /// messages all hold at the extremes.
    func testExtremeTimesNeverTrap() {
        let now = Date(timeIntervalSince1970: Double(at(15, 9, 0)) / 1000)
        let items = build([
            message("$oldest", ts: Int64.min, mine: true, expiresAt: Int64.max),
            message("$newest", ts: Int64.max),
        ], now: now)
        let shown = messages(items)
        XCTAssertEqual(shown.map(\.id), ["$oldest", "$newest"])
        XCTAssertTrue(shown[1].startsGroup, "a gap past any Int64 still starts a group")

        XCTAssertNotNil(Disappearing.countdown(expiresAt: Int64.max, now: Date(timeIntervalSince1970: -1e9),
                                               locale: Locale(identifier: "en_US")))
        XCTAssertNil(Disappearing.countdown(expiresAt: Int64.min, now: now, locale: Locale(identifier: "en_US")))
        XCTAssertGreaterThan(Disappearing.steps(remaining: Int64.max).shown, 0)
        XCTAssertGreaterThan(Disappearing.millisUntilNextChange(in: items, now: Date(timeIntervalSince1970: -1e9)) ?? 0, 0)

        let features = ChatFeatures(edit: true, editMaxAgeMS: 900_000, unsend: true, unsendMaxAgeMS: 900_000,
                                    source: .stored)
        let result = MessageActions.available(for: shown[0], in: features, network: "whatsapp", now: now,
                                              locale: Locale(identifier: "en_US"))
        XCTAssertFalse(result.actions.contains(.edit), "older than any limit")
        XCTAssertTrue(result.unavailable.contains { $0.action == .edit })
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

    func testConsecutiveMembershipEventsCollapseAndRespectToggle() {
        func memberEvent(_ id: String, _ name: String, membership: String, ts: Int64, seq: Int64,
                         extra: String = "") -> Event {
            Event(
                eventID: id,
                roomID: "!room:courier.local",
                sender: "@\(name.lowercased()):courier.local",
                senderName: name,
                mine: false,
                type: "m.room.member",
                content: json(#"{"membership":"\#(membership)"\#(extra)}"#),
                ts: ts,
                seq: seq,
                status: .sent
            )
        }
        let msg = Event(
            eventID: "$msg1",
            roomID: "!room:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice",
            mine: false,
            type: "m.room.message",
            content: json(#"{"msgtype":"m.text","body":"Hello"}"#),
            ts: 1_700_000_010_000,
            seq: 10,
            status: .sent
        )

        // 1, 2, and 3 consecutive joins: "Alice joined", "Alice and Bob joined", "Alice and 2 others joined"
        let oneJoin = Timeline.build(
            events: [memberEvent("$m1", "Alice", membership: "join", ts: 1_700_000_001_000, seq: 1)],
            me: "@me:courier.local",
            showChatUpdates: true
        )
        if case let .membershipRun(_, events1, summary1) = oneJoin[1] {
            XCTAssertEqual(events1.count, 1)
            XCTAssertEqual(summary1, "Alice joined")
        } else {
            XCTFail("Expected membershipRun at index 1, got \(oneJoin)")
        }

        let twoJoins = Timeline.build(
            events: [
                memberEvent("$m1", "Alice", membership: "join", ts: 1_700_000_001_000, seq: 1),
                memberEvent("$m2", "Bob", membership: "join", ts: 1_700_000_002_000, seq: 2),
            ],
            me: "@me:courier.local",
            showChatUpdates: true
        )
        if case let .membershipRun(_, events2, summary2) = twoJoins[1] {
            XCTAssertEqual(events2.count, 2)
            XCTAssertEqual(summary2, "Alice and Bob joined")
        } else {
            XCTFail("Expected membershipRun at index 1, got \(twoJoins)")
        }

        let threeJoinsAndMsg = [
            memberEvent("$m1", "Alice", membership: "join", ts: 1_700_000_001_000, seq: 1),
            memberEvent("$m2", "Bob", membership: "join", ts: 1_700_000_002_000, seq: 2),
            memberEvent("$m3", "Carol", membership: "join", ts: 1_700_000_003_000, seq: 3),
            msg,
        ]
        let itemsShown = Timeline.build(
            events: threeJoinsAndMsg,
            me: "@me:courier.local",
            showChatUpdates: true
        )
        XCTAssertEqual(itemsShown.count, 3) // date separator + 1 membership run + 1 message
        if case let .membershipRun(_, runEvents, summary) = itemsShown[1] {
            XCTAssertEqual(runEvents.count, 3)
            XCTAssertEqual(summary, "Alice and 2 others joined")
        } else {
            XCTFail("Expected membershipRun at index 1, got \(itemsShown)")
        }

        // Single and multiple left / was removed / was invited
        let leftItems = Timeline.build(
            events: [memberEvent("$l1", "Alice", membership: "leave", ts: 1_700_000_001_000, seq: 1)],
            me: "@me:courier.local",
            showChatUpdates: true
        )
        if case let .membershipRun(_, _, summary) = leftItems[1] {
            XCTAssertEqual(summary, "Alice left")
        } else {
            XCTFail("Expected membershipRun")
        }

        let removedItems = Timeline.build(
            events: [memberEvent("$k1", "Alice", membership: "ban", ts: 1_700_000_001_000, seq: 1)],
            me: "@me:courier.local",
            showChatUpdates: true
        )
        if case let .membershipRun(_, _, summary) = removedItems[1] {
            XCTAssertEqual(summary, "Alice was removed")
        } else {
            XCTFail("Expected membershipRun")
        }

        let invitedItems = Timeline.build(
            events: [memberEvent("$i1", "Alice", membership: "invite", ts: 1_700_000_001_000, seq: 1)],
            me: "@me:courier.local",
            showChatUpdates: true
        )
        if case let .membershipRun(_, _, summary) = invitedItems[1] {
            XCTAssertEqual(summary, "Alice was invited")
        } else {
            XCTFail("Expected membershipRun")
        }

        // Mixed kinds in one consecutive run: one clause per kind ("Alice joined, Bob left")
        let mixedItems = Timeline.build(
            events: [
                memberEvent("$m1", "Alice", membership: "join", ts: 1_700_000_001_000, seq: 1),
                memberEvent("$m2", "Bob", membership: "leave", ts: 1_700_000_002_000, seq: 2),
            ],
            me: "@me:courier.local",
            showChatUpdates: true
        )
        if case let .membershipRun(_, _, summary) = mixedItems[1] {
            XCTAssertEqual(summary, "Alice joined, Bob left")
        } else {
            XCTFail("Expected mixed membershipRun")
        }

        // Non-consecutive m.room.member events separated by a message stay in separate runs
        let splitByMessage = Timeline.build(
            events: [
                memberEvent("$m1", "Alice", membership: "join", ts: 1_700_000_001_000, seq: 1),
                msg,
                memberEvent("$m2", "Bob", membership: "leave", ts: 1_700_000_020_000, seq: 20),
            ],
            me: "@me:courier.local",
            showChatUpdates: true
        )
        let summaries = splitByMessage.compactMap { item -> String? in
            if case let .membershipRun(_, _, s) = item { return s }
            return nil
        }
        XCTAssertEqual(summaries, ["Alice joined", "Bob left"])

        // Hidden when showChatUpdates is false
        let itemsHidden = Timeline.build(
            events: threeJoinsAndMsg,
            me: "@me:courier.local",
            showChatUpdates: false
        )
        XCTAssertEqual(itemsHidden.count, 2) // date separator + 1 message
    }

    // MARK: - Part 4.5b Task 5: Gallery Grouping & View-Once Played State

    func testGroupsConsecutiveSameSenderMediaIntoGallery() {
        let baseTS = at(14, 15, 0)
        func media(
            _ id: String,
            sender: String = "@alice:courier.local",
            senderName: String = "Alice Example",
            msgtype: String = "m.image",
            body: String = "photo.jpg",
            filename: String? = "photo.jpg",
            offsetMS: Int64,
            seq: Int64,
            width: Int = 1200,
            height: Int = 800,
            blurhash: String = "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
            durationMS: Int64? = nil,
            viewOnce: Bool = false
        ) -> Event {
            var contentObj: [String: JSONValue] = [
                "msgtype": .string(msgtype),
                "body": .string(body),
                "info": .object([
                    "mimetype": .string(msgtype == "m.video" ? "video/mp4" : "image/jpeg"),
                    "w": .int(Int64(width)),
                    "h": .int(Int64(height)),
                    "size": .int(102_400),
                    "xyz.amorgan.blurhash": .string(blurhash),
                ]),
            ]
            if let filename {
                contentObj["filename"] = .string(filename)
            }
            return Event(
                eventID: id,
                roomID: "!room:courier.local",
                sender: sender,
                senderName: senderName,
                mine: false,
                type: "m.room.message",
                content: .object(contentObj),
                ts: baseTS + offsetMS,
                seq: seq,
                status: .sent,
                mediaPath: "/tmp/courier-test-\(id).dat",
                thumbnailPath: "/tmp/courier-test-\(id)-thumb.jpg",
                blurhash: blurhash,
                durationMS: durationMS,
                viewOnce: viewOnce
            )
        }

        // 1. 4 consecutive image/video events from @alice:courier.local within 15 seconds collapse into a single Message
        //    with galleryItems.count == 4 (with an optional caption on the last item).
        let fourRun = [
            media("$g1", offsetMS: 0, seq: 1),
            media("$g2", offsetMS: 5_000, seq: 2),
            media("$g3", msgtype: "m.video", body: "clip.mp4", filename: "clip.mp4", offsetMS: 10_000, seq: 3, durationMS: 42_000),
            media("$g4", body: "Weekend hike photos", filename: "photo4.jpg", offsetMS: 15_000, seq: 4),
        ]
        let groupedShown = messages(build(fourRun))
        XCTAssertEqual(groupedShown.count, 1, "4 consecutive media events within 15s should collapse into 1 Message")
        XCTAssertEqual(groupedShown[0].galleryItems.count, 4)
        XCTAssertEqual(groupedShown[0].galleryItems.map(\.id), ["$g1", "$g2", "$g3", "$g4"])
        XCTAssertEqual(groupedShown[0].galleryItems[2].kind, .video)
        XCTAssertEqual(groupedShown[0].galleryItems[2].durationMS, 42_000)
        XCTAssertEqual(groupedShown[0].body, "Weekend hike photos", "Caption on the last gallery item is preserved on the message")

        // 2. A message from @bob:courier.local in the middle breaks the run.
        let brokenBySender = [
            media("$s1", offsetMS: 0, seq: 1),
            media("$s2", offsetMS: 4_000, seq: 2),
            media("$bob", sender: "@bob:courier.local", senderName: "Bob Example", offsetMS: 8_000, seq: 3),
            media("$s3", offsetMS: 12_000, seq: 4),
            media("$s4", offsetMS: 15_000, seq: 5),
        ]
        let senderShown = messages(build(brokenBySender))
        XCTAssertEqual(senderShown.count, 3, "Expected Alice's first 2, Bob's 1, and Alice's last 2 as 3 messages")
        XCTAssertEqual(senderShown[0].galleryItems.count, 2)
        XCTAssertEqual(senderShown[1].galleryItems.count, 0)
        XCTAssertEqual(senderShown[2].galleryItems.count, 2)

        // 3. A message with a caption in the middle breaks the run.
        let brokenByCaption = [
            media("$c1", offsetMS: 0, seq: 1),
            media("$c2", body: "Look at this summit", filename: "photo2.jpg", offsetMS: 5_000, seq: 2),
            media("$c3", offsetMS: 10_000, seq: 3),
            media("$c4", offsetMS: 15_000, seq: 4),
        ]
        let captionShown = messages(build(brokenByCaption))
        XCTAssertTrue(captionShown.count >= 2, "Caption in the middle must break the 4-item gallery run")
        XCTAssertFalse(captionShown.contains { $0.galleryItems.count == 4 })

        // 4. Any other event between them (e.g. a text message) or a gap > 60 seconds breaks the group.
        let textInMiddle = [
            media("$t1", offsetMS: 0, seq: 1),
            Event(
                eventID: "$txt",
                roomID: "!room:courier.local",
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                type: "m.room.message",
                content: json(#"{"msgtype":"m.text","body":"Wait, one more"}"#),
                ts: baseTS + 5_000,
                seq: 2,
                status: .sent
            ),
            media("$t2", offsetMS: 10_000, seq: 3),
        ]
        let textShown = messages(build(textInMiddle))
        XCTAssertEqual(textShown.count, 3)
        XCTAssertTrue(textShown.allSatisfy { $0.galleryItems.isEmpty })

        let overSixtySeconds = [
            media("$w1", offsetMS: 0, seq: 1),
            media("$w2", offsetMS: 61_000, seq: 2),
        ]
        let gapShown = messages(build(overSixtySeconds))
        XCTAssertEqual(gapShown.count, 2, "Media events separated by >60s must not group")
        XCTAssertTrue(gapShown.allSatisfy { $0.galleryItems.isEmpty })

        // 5. Caps gallery at 10 items (12 consecutive items -> 10 + 2).
        let twelveRun = (1 ... 12).map { idx in
            media("$m\(idx)", offsetMS: Int64(idx) * 1_000, seq: Int64(idx))
        }
        let twelveShown = messages(build(twelveRun))
        XCTAssertEqual(twelveShown.count, 2)
        XCTAssertEqual(twelveShown[0].galleryItems.count, 10)
        XCTAssertEqual(twelveShown[1].galleryItems.count, 2)
    }

    func testViewOnceMessageTracksPlayedState() {
        let baseTS = at(14, 20, 0)
        let unopenedEvent = Event(
            eventID: "$vo1",
            roomID: "!room:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            type: "m.room.message",
            content: json(#"{"msgtype":"m.image","body":"secret.jpg","com.beeper.view_once":true,"info":{"mimetype":"image/jpeg","w":800,"h":600}}"#),
            ts: baseTS,
            seq: 1,
            status: .sent,
            mediaPath: "/tmp/secret-unopened.jpg",
            thumbnailPath: "/tmp/secret-thumb.jpg",
            blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
            viewOnce: true,
            played: false
        )
        let openedEvent = Event(
            eventID: "$vo2",
            roomID: "!room:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            type: "m.room.message",
            content: json(#"{"msgtype":"m.image","body":"secret2.jpg","com.beeper.disappearing_timer":{"type":"after_read","timer":10000},"info":{"mimetype":"image/jpeg","w":800,"h":600}}"#),
            ts: baseTS + 2_000,
            seq: 2,
            status: .sent,
            mediaPath: "/tmp/secret-opened.jpg",
            thumbnailPath: "/tmp/secret-opened-thumb.jpg",
            blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
            viewOnce: true,
            played: true
        )

        let shown = messages(build([unopenedEvent, openedEvent]))
        XCTAssertEqual(shown.count, 2, "View-once messages must never collapse into a gallery")
        XCTAssertTrue(shown[0].viewOnce)
        XCTAssertFalse(shown[0].played)
        XCTAssertEqual(shown[0].mediaPath, "/tmp/secret-unopened.jpg")

        XCTAssertTrue(shown[1].viewOnce)
        XCTAssertTrue(shown[1].played)
        XCTAssertEqual(shown[1].mediaPath, "", "Opened view-once media path must be cleared on this Mac")
        XCTAssertNil(shown[1].thumbnailPath, "Opened view-once thumbnail path must be nil on this Mac")
    }
}
