// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

@testable import CourierCore
import XCTest

/// A bridge's call notice, in Courier's words: in the chat, in the chat list and in a notification. The bridge's
/// English body is never what a person reads.
final class CallNoteTests: XCTestCase {
    /// The bridges' own words, none of which may reach a person.
    private let bridgeEnglish = ["Use the WhatsApp app", "Started a", "Incoming call. ", "video chat", "rejected",
                                 "disconnected"]

    private func event(_ json: [String: Any]) throws -> Event {
        try JSONDecoder().decode(Event.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func content(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private func messages(_ events: [Event]) -> [TimelineMessage] {
        Timeline.build(events: events, me: Timeline.meUserID, now: Date(timeIntervalSince1970: 1_900_000_000))
            .compactMap { if case let .message(m) = $0 { m } else { nil } }
    }

    private func assertCourierWords(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(text.isEmpty, file: file, line: line)
        for words in bridgeEnglish {
            XCTAssertFalse(text.contains(words), "\(text) has the bridge's \(words)", file: file, line: line)
        }
    }

    // MARK: Reading

    func testACallNoteIsReadFromItsContent() throws {
        XCTAssertEqual(CallNote.of(try content(#"""
            {"msgtype":"m.notice","body":"Video call missed","com.beeper.action_message":{"type":"call"},
             "fi.courier.call":{"state":"missed","media":"video"}}
            """#)), CallNote(state: .missed, media: .video))
        // Stored before the engine read calls: the action message alone says it rang, and its call_type the media.
        XCTAssertEqual(CallNote.of(try content(#"""
            {"msgtype":"m.notice","body":"Started a video call","com.beeper.action_message":{"type":"call","call_type":"video"}}
            """#)), CallNote(state: .ringing, media: .video))
        XCTAssertEqual(CallNote.of(try content(#"""
            {"msgtype":"m.text","body":"Incoming group call. Use the WhatsApp app to answer.",
             "com.beeper.action_message":{"type":"call","call_type":"group"}}
            """#)), CallNote(state: .ringing, media: .unknown), "group is no media")
        // A state or media this app doesn't know reads as the plainest note.
        XCTAssertEqual(CallNote.of(try content(#"""
            {"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"call"},
             "fi.courier.call":{"state":"exploded","media":"hologram"}}
            """#)), CallNote(state: .ringing, media: .unknown))
        XCTAssertEqual(CallNote.of(try content(#"""
            {"msgtype":"m.notice","body":"","com.beeper.action_message":{"type":"call","call_type":"voice"},
             "fi.courier.call":"missed"}
            """#)), CallNote(state: .ringing, media: .voice), "a reading that isn't one is no reading")
        // Anything else is no call note: words alone, a timer note, another action message.
        XCTAssertNil(CallNote.of(try content(#"{"msgtype":"m.notice","body":"Call ended"}"#)))
        XCTAssertNil(CallNote.of(try content(#"""
            {"msgtype":"m.notice","body":"x","com.beeper.action_message":{"type":"disappearing_timer","timer":0}}
            """#)))
        XCTAssertNil(CallNote.of(try content(#"{"msgtype":"m.notice","body":"x","fi.courier.call":{"state":"missed"}}"#)))
    }

    // MARK: Words

    func testEveryCallIsSaidInCourierWords() {
        let said: [(CallNote, Bool, String)] = [
            (CallNote(state: .ringing, media: .unknown), false, "Incoming call"),
            (CallNote(state: .ringing, media: .voice), false, "Incoming voice call"),
            (CallNote(state: .ringing, media: .video), false, "Incoming video call"),
            (CallNote(state: .ringing, media: .video), true, "Outgoing video call"),
            (CallNote(state: .started, media: .video), false, "Video call started"),
            (CallNote(state: .missed, media: .voice), false, "Missed voice call"),
            (CallNote(state: .missed, media: .video), true, "Video call not answered"),
            (CallNote(state: .missed, media: .unknown), true, "Call not answered"),
            (CallNote(state: .ended, media: .unknown), false, "Call ended"),
            (CallNote(state: .ended, media: .voice), true, "Voice call ended"),
            (CallNote(state: .declined, media: .video), false, "Video call declined"),
            (CallNote(state: .dropped, media: .voice), false, "Voice call dropped"),
        ]
        for (note, mine, words) in said {
            XCTAssertEqual(note.words(mine: mine), words, "\(note) mine: \(mine)")
        }
        for state in CallState.known {
            for media in CallMedia.known {
                for mine in [false, true] {
                    assertCourierWords(CallNote(state: state, media: media).words(mine: mine))
                }
            }
        }
    }

    // MARK: The chat

    /// In the chat a call note is a note (`call`), its text Courier's words; it is a message from them that counts as
    /// unread and as a new message, as the engine counts it. Mine is neither.
    func testACallInTheChatIsANoteInCourierWords() throws {
        let events = try [
            event(callNote(id: "$wa", room: "!a", at: 1)),
            event(callNote(id: "$tg", room: "!a", at: 2, body: "Video call missed", call: ("missed", "video"))),
            event(callNote(id: "$old", room: "!a", at: 3, body: "Started a call", call: nil)),
            event(callNote(id: "$mine", room: "!a", at: 4, by: Timeline.meUserID, body: "Call missed",
                           call: ("missed", "voice"))),
        ]
        let shown = messages(events)
        XCTAssertEqual(shown.map(\.call), [CallNote(state: .ringing, media: .unknown),
                                            CallNote(state: .missed, media: .video),
                                            CallNote(state: .ringing, media: .unknown),
                                            CallNote(state: .missed, media: .voice)])
        XCTAssertEqual(shown.map(\.body), ["Incoming call", "Missed video call", "Incoming call",
                                           "Voice call not answered"])
        XCTAssertEqual(shown.map(\.rich.text), shown.map(\.body), "copied and quoted as shown")
        XCTAssertNil(shown[0].timerChange)
        XCTAssertTrue(shown.allSatisfy(\.isNote))
        XCTAssertEqual(shown.map(\.countsAsUnread), [true, true, true, true], "a call is news")
        XCTAssertEqual(events.map(Timeline.isIncomingMessage), [true, true, true, false], "mine isn't new to me")
        XCTAssertEqual(Timeline.firstUnreadID(events: events, me: Timeline.meUserID, unread: 1), "$old")
        for message in shown { assertCourierWords(message.body) }
    }

    func testACallNoteOffersOnlyDeleteForMe() throws {
        let features = ChatFeatures(reply: true, edit: true, editMaxAgeMS: 15 * 60_000, unsend: true,
                                    unsendMaxAgeMS: 2 * 86_400_000, formatting: [.bold], source: .stored)
        let shown = messages(try [
            event(callNote(id: "$theirs", room: "!a", at: 1)),
            event(callNote(id: "$mine", room: "!a", at: 2, by: Timeline.meUserID, body: "Call ended (1 minute)",
                           call: ("ended", "voice"))),
        ])
        for note in shown {
            let offered = MessageActions.available(for: note, in: features, network: "telegram",
                                                   now: Date(timeIntervalSince1970: 1_760_600_700))
            XCTAssertEqual(offered.actions, [.deleteForMe], note.id)
            XCTAssertTrue(offered.unavailable.isEmpty)
        }
    }

    // MARK: The chat list

    func testACallPreviewsInCourierWords() throws {
        func row(_ json: [String: Any]) throws -> InboxRow {
            try JSONDecoder().decode(InboxRow.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let missed = try row(room("!a", ts: 1, preview: "", kind: "call",
                                  previewCall: ["state": "missed", "media": "video"]))
        XCTAssertEqual(missed.previewCall, CallNote(state: .missed, media: .video))
        XCTAssertEqual(missed.previewLabel, .call(CallNote(state: .missed, media: .video), mine: false))
        XCTAssertEqual(missed.previewLabel?.title, "Missed video call")

        var mine = room("!a", ts: 1, preview: "", kind: "call", previewCall: ["state": "ringing", "media": ""])
        mine["preview_mine"] = true
        XCTAssertEqual(try row(mine).previewLabel?.title, "Outgoing call")

        // A call row from an engine that sent no reading still says it was a call.
        XCTAssertEqual(try row(room("!a", ts: 1, preview: "", kind: "call")).previewLabel?.title, "Incoming call")
        XCTAssertNil(try row(room("!a", ts: 1, kind: "text")).previewCall)
    }

    // MARK: Notifications

    func testSomeoneElsesCallNotifiesInCourierWords() throws {
        let context = NotificationPolicy.Context(me: Timeline.meUserID, connectedAt: 1_000_000, now: 1_030_000,
                                                 openRoomID: nil, isLooking: false)
        let chat = try JSONDecoder().decode(InboxRow.self, from: JSONSerialization.data(
            withJSONObject: room("!a", ts: 1, name: "Ann")))
        func live(_ json: [String: Any]) throws -> Event {
            var e = try event(json)
            e.ts = 1_020_000
            return e
        }
        let ringing = try live(callNote(id: "$1", room: "!a", at: 1))
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: ringing, room: chat, context: context), "a call is news")
        XCTAssertEqual(NotificationPolicy.content(for: ringing, room: chat).body, "Incoming call")

        let missed = try live(callNote(id: "$2", room: "!a", at: 2, body: "Video call missed", call: ("missed", "video")))
        XCTAssertEqual(NotificationPolicy.content(for: missed, room: chat).body, "Missed video call")
        let ended = try live(callNote(id: "$3", room: "!a", at: 3, body: "Call ended", call: ("ended", "")))
        XCTAssertEqual(NotificationPolicy.content(for: ended, room: chat).body, "Call ended")

        let mine = try live(callNote(id: "$4", room: "!a", at: 4, by: Timeline.meUserID, body: "Call missed",
                                     call: ("missed", "voice")))
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: mine, room: chat, context: context))
    }

    // MARK: News

    /// Only a call that is news counts unread, makes the "N new messages" pill and notifies: it rang (or a group's
    /// call started), or was missed. That it ended, was declined or dropped is a record; a call I made never counts.
    func testOnlyACallThatIsNewsCounts() throws {
        let context = NotificationPolicy.Context(me: Timeline.meUserID, connectedAt: 1_000_000, now: 1_030_000,
                                                 openRoomID: nil, isLooking: false)
        let chat = try JSONDecoder().decode(InboxRow.self, from: JSONSerialization.data(
            withJSONObject: room("!a", ts: 1, name: "Ann")))
        let cases: [(String, [(body: String, call: (state: String, media: String)?, mine: Bool)], [Bool])] = [
            ("signal: rang, then ended", [("Incoming call", ("ringing", ""), false), ("Call ended", ("ended", ""), false)],
             [true, false]),
            ("signal: ended, after a call I made", [("Call ended", ("ended", ""), false)], [false]),
            ("telegram: answered", [("Started a call", ("ringing", "voice"), false),
                                    ("Call ended (5 minutes)", ("ended", "voice"), false)], [true, false]),
            ("telegram: missed", [("Started a call", ("ringing", "voice"), false),
                                  ("Call missed", ("missed", "voice"), false)], [true, true]),
            ("telegram: declined, dropped", [("Video call rejected", ("declined", "video"), false),
                                             ("Call disconnected", ("dropped", "voice"), false)], [false, false]),
            ("telegram: a group's video chat", [("Started a video chat", ("started", "video"), false),
                                                ("Ended the video chat (1 minute)", ("ended", "video"), false)],
             [true, false]),
            ("telegram: stored before calls were read", [("Started a call", nil, false)], [true]),
            ("a call I made", [("Call missed", ("missed", "voice"), true)], [false]),
        ]
        for (name, notices, news) in cases {
            let events = try notices.enumerated().map { index, notice in
                var e = try event(callNote(id: "$\(index)", room: "!a", at: Int64(index + 1),
                                           by: notice.mine ? Timeline.meUserID : "@ann:example.test",
                                           body: notice.body, call: notice.call))
                e.ts = 1_020_000 + Int64(index)
                return e
            }
            let shown = messages(events)
            XCTAssertEqual(zip(shown, events).map { !$1.mine && $0.countsAsUnread }, news, name)
            XCTAssertEqual(events.map(Timeline.isIncomingMessage), news, name)
            XCTAssertEqual(events.map { NotificationPolicy.shouldNotify(event: $0, room: chat, context: context) },
                           news, name)
        }
    }

    /// In a group, a call note names who called; in a one-to-one chat it doesn't need to. Mine never does.
    func testTheCallerIsNamedOnlyInAGroup() throws {
        let shown = messages(try [
            event(callNote(id: "$theirs", room: "!a", at: 1)),
            event(callNote(id: "$mine", room: "!a", at: 2, by: Timeline.meUserID)),
            event(textEvent(id: "$text", room: "!a", at: 3)),
        ])
        XCTAssertEqual(shown.map { CallNote.caller(of: $0, direct: false) }, ["Ann", nil, nil])
        XCTAssertEqual(shown.map { CallNote.caller(of: $0, direct: true) }, [nil, nil, nil])
    }
}
