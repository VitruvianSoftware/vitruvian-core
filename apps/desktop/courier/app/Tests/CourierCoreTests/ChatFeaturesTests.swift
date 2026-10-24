// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// MessageActions.available: what a message offers in its chat, from the chat's features (room.features), and why
/// an action is greyed. The features here are the ones each network's bridge advertises (the plan's action table);
/// all data is made up.
final class ChatFeaturesTests: XCTestCase {
    private let me = Timeline.meUserID
    private let english = Locale(identifier: "en_US")
    /// When the messages were sent.
    private let sentAt: Int64 = 1_760_600_000_000

    // MARK: - Fixtures

    private var whatsApp: ChatFeatures {
        ChatFeatures(reply: true, edit: true, editMaxAgeMS: 15 * 60 * 1000, unsend: true,
                     unsendMaxAgeMS: 2 * 24 * 3600 * 1000, poll: PollFeatures(maxOptions: 12, optionMaxLength: 100),
                     formatting: [.bold, .italic, .strikethrough, .code, .pre, .blockquote, .bulletList, .orderedList,
                                  .link, .mention],
                     maxTextLength: 65536, source: .stored)
    }

    private var signal: ChatFeatures {
        ChatFeatures(reply: true, edit: true, editMaxAgeMS: 24 * 3600 * 1000, editMaxCount: 10, unsend: true,
                     unsendMaxAgeMS: 24 * 3600 * 1000, source: .stored)
    }

    private var googleMessagesRCS: ChatFeatures {
        ChatFeatures(reply: true, edit: false, unsend: false, deleteReachesPhone: true, source: .stored)
    }

    private var googleMessagesSMS: ChatFeatures {
        ChatFeatures(reply: false, thread: false, edit: false, unsend: false, deleteReachesPhone: true, source: .stored)
    }

    private var slack: ChatFeatures {
        ChatFeatures(reply: false, thread: true, replyIsThread: true, edit: true, unsend: true, mentionRoom: true,
                     source: .stored)
    }

    private func json(_ text: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// One message as the timeline shows it.
    private func message(_ id: String = "$1", mine: Bool = true, body: String = "Lunch at noon?",
                         msgtype: String = "m.text", extra: String = "", status: EventStatus = .sent,
                         bookmarked: Bool = false, more: [Event] = []) -> TimelineMessage {
        let encoded = String(decoding: try! JSONEncoder().encode(body), as: UTF8.self)
        let event = Event(eventID: id, roomID: "!room", sender: mine ? me : "@ann:example.test",
                          senderName: mine ? "me" : "Ann", mine: mine, type: "m.room.message",
                          content: json(#"{"msgtype":"\#(msgtype)","body":\#(encoded)\#(extra)}"#), ts: sentAt, seq: 1,
                          status: status, bookmarked: bookmarked)
        let items = Timeline.build(events: [event] + more, me: me, now: date(after: 0))
        for case let .message(shown) in items where shown.id == id { return shown }
        fatalError("no message \(id)")
    }

    private func date(after millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(sentAt + millis) / 1000)
    }

    private func available(_ message: TimelineMessage, _ features: ChatFeatures, network: String,
                           after millis: Int64 = 60_000, isDirect: Bool = true, networkRunning: Bool = false)
        -> (actions: [MessageAction], unavailable: [Unavailable]) {
        MessageActions.available(for: message, in: features, network: network, now: date(after: millis),
                                 locale: english, isDirect: isDirect, networkRunning: networkRunning)
    }

    private func reason(_ action: MessageAction, in result: (actions: [MessageAction], unavailable: [Unavailable]))
        -> String? {
        result.unavailable.first { $0.action == action }?.reason
    }

    // MARK: - The tests

    func testWhatsAppEditGreysAfter15Minutes() {
        let mine = message()
        let early = available(mine, whatsApp, network: "whatsapp", after: 15 * 60 * 1000)
        XCTAssertTrue(early.actions.contains(.edit), "at 15 minutes exactly it can still be edited")
        XCTAssertNil(reason(.edit, in: early))

        let late = available(mine, whatsApp, network: "whatsapp", after: 15 * 60 * 1000 + 1)
        XCTAssertFalse(late.actions.contains(.edit))
        XCTAssertEqual(reason(.edit, in: late), "WhatsApp only lets you edit for 15 minutes")
        XCTAssertTrue(late.actions.contains(.unsend), "unsend has two days")

        let days = available(mine, whatsApp, network: "whatsapp", after: 3 * 24 * 3600 * 1000)
        XCTAssertFalse(days.actions.contains(.unsend))
        XCTAssertEqual(reason(.unsend, in: days), "WhatsApp only lets you unsend for 2 days")

        // Signal counts edits too: ten live edits is the most.
        let edits = (1 ... 10).map { index in
            Event(eventID: "$e\(index)", roomID: "!room", sender: me, senderName: "me", mine: true,
                  type: "m.room.message",
                  content: json(#"{"msgtype":"m.text","body":"* v\#(index)","m.new_content":{"msgtype":"m.text","body":"v\#(index)"},"m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}"#),
                  ts: sentAt + Int64(index), seq: Int64(index + 1), status: .sent)
        }
        let edited = message(more: edits)
        XCTAssertEqual(edited.editCount, 10)
        let counted = available(edited, signal, network: "signal")
        XCTAssertEqual(reason(.edit, in: counted), "Signal only lets you edit a message 10 times")
        XCTAssertTrue(counted.actions.contains(.showHistory), "an edited message has a history")
    }

    func testGoogleMessagesOffersDeleteFromPhoneNotUnsend() {
        let result = available(message(), googleMessagesRCS, network: "gmessages")
        XCTAssertTrue(result.actions.contains(.deleteForMe))
        XCTAssertFalse(result.actions.contains(.unsend))
        XCTAssertEqual(reason(.unsend, in: result), "Google Messages can’t unsend")
        XCTAssertEqual(reason(.edit, in: result), "Google Messages can’t edit messages")
        XCTAssertEqual(MessageActions.deleteForMeTitle(in: googleMessagesRCS), "Delete from This Mac and Your Phone…")
        XCTAssertEqual(MessageActions.deleteForMeTitle(in: whatsApp), "Delete for Me…")
    }

    func testSlackReplyIsReplyInThread() {
        let result = available(message(mine: false), slack, network: "slack")
        XCTAssertTrue(result.actions.contains(.replyInThread))
        XCTAssertFalse(result.actions.contains(.reply))
        XCTAssertNil(reason(.reply, in: result))
    }

    func testSMSHasNoReply() {
        let result = available(message(mine: false), googleMessagesSMS, network: "gmessages")
        for action in [MessageAction.reply, .replyInThread] {
            XCTAssertFalse(result.actions.contains(action), "\(action)")
            XCTAssertNil(reason(action, in: result), "an SMS chat has no replies to grey: \(action)")
        }
        XCTAssertTrue(result.actions.contains(.react))
    }

    func testOthersMessagesCantBeEditedOrUnsent() {
        let result = available(message(mine: false), whatsApp, network: "whatsapp")
        for action in [MessageAction.edit, .unsend] {
            XCTAssertFalse(result.actions.contains(action), "\(action)")
            XCTAssertNil(reason(action, in: result), "not greyed either: it was never mine to change")
        }
        XCTAssertTrue(result.actions.contains(.insertAsDraft), "Insert as Draft is for others' messages")
        XCTAssertTrue(result.actions.contains(.deleteForMe), "anyone's message can leave this Mac")
        XCTAssertFalse(available(message(), whatsApp, network: "whatsapp").actions.contains(.insertAsDraft))
    }

    func testNoFeaturesOffersOnlyTheBasics() {
        let result = available(message(), .noFeatures, network: "telegram")
        XCTAssertEqual(result.actions, [.reply, .react, .bookmark, .markUnread, .deleteForMe, .copy, .copyWithTimestamp,
                                        .forward],
                       "in the message menu's order")
        XCTAssertEqual(result.unavailable, [
            Unavailable(action: .edit, reason: "Not available until Telegram connects"),
            Unavailable(action: .unsend, reason: "Not available until Telegram connects"),
        ])
    }

    func testTheMenuOrderAndEveryAction() {
        let link = #","format":"org.matrix.custom.html","formatted_body":"see <a href=\"https://x.test\">this</a>""#
        let others = message(mine: false, body: "see this (https://x.test)", extra: link, bookmarked: true)
        XCTAssertEqual(available(others, whatsApp, network: "whatsapp").actions,
                       [.reply, .react, .removeBookmark, .markUnread, .deleteForMe, .copy, .copyWithTimestamp,
                        .insertAsDraft, .openFirstLink, .forward])
        // In a group, on a network that runs: Reply Privately after Reply; Mark as Unread after Bookmark.
        XCTAssertEqual(available(others, whatsApp, network: "whatsapp", isDirect: false, networkRunning: true).actions,
                       [.reply, .replyPrivately, .react, .removeBookmark, .markUnread, .deleteForMe, .copy,
                        .copyWithTimestamp, .insertAsDraft, .openFirstLink, .forward])
        let slackGroup = available(others, slack, network: "slack", isDirect: false, networkRunning: true)
        XCTAssertEqual(Array(slackGroup.actions.prefix(2)), [.replyInThread, .replyPrivately])
        XCTAssertEqual(MessageActions.firstLink(in: others.rich), URL(string: "https://x.test"))
        // A bare address in plain text is a link too.
        XCTAssertEqual(MessageActions.firstLink(in: RichText(text: "go to https://y.test/a_b now", entities: [])),
                       URL(string: "https://y.test/a_b"))
        XCTAssertNil(MessageActions.firstLink(in: RichText(text: "no link here", entities: [])))
        XCTAssertEqual(available(message(), whatsApp, network: "whatsapp").actions,
                       [.edit, .reply, .react, .bookmark, .markUnread, .unsend, .deleteForMe, .copy, .copyWithTimestamp,
                        .forward])
        let inGroup = available(message(), whatsApp, network: "whatsapp", isDirect: false, networkRunning: true)
        XCTAssertEqual(inGroup.actions,
                       [.edit, .reply, .react, .bookmark, .markUnread, .unsend, .deleteForMe, .copy, .copyWithTimestamp,
                        .forward], "never Reply Privately to myself")
    }

    /// Reply Privately is someone else's message in a group, while the chat's network runs; anywhere else it is
    /// absent, never greyed.
    func testReplyPrivatelyOnlyInGroupsOnOthersMessages() {
        let others = message(mine: false)
        func offers(_ message: TimelineMessage, isDirect: Bool, running: Bool) -> Bool {
            let result = available(message, whatsApp, network: "whatsapp", isDirect: isDirect, networkRunning: running)
            XCTAssertNil(reason(.replyPrivately, in: result), "never greyed")
            return result.actions.contains(.replyPrivately)
        }
        XCTAssertTrue(offers(others, isDirect: false, running: true))
        XCTAssertFalse(offers(others, isDirect: true, running: true), "a one-to-one chat is private already")
        XCTAssertFalse(offers(others, isDirect: false, running: false), "the network isn't running")
        XCTAssertFalse(offers(message(mine: true), isDirect: false, running: true), "my own message")
        // Not on a note, a deleted message or one that couldn't be decrypted.
        let note = message(mine: false, msgtype: "m.notice",
                           extra: #","com.beeper.action_message":{"type":"call"},"fi.courier.call":{"state":"ended","media":"voice"}"#)
        XCTAssertTrue(note.isNote)
        XCTAssertFalse(offers(note, isDirect: false, running: true))
        let deleted = message(mine: false, more: [
            Event(eventID: "$d", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                  type: "m.room.redaction", content: json(#"{"redacts":"$1"}"#), ts: sentAt + 1, seq: 2, status: .sent),
        ])
        XCTAssertFalse(offers(deleted, isDirect: false, running: true))
        // The menu's line.
        XCTAssertEqual(MessageMenu.title(of: .replyPrivately, features: whatsApp), "Reply Privately…")
    }

    /// Ruling 19: Mark as Unread is on any message with a place in the chat everyone sees: others' (their deleted and
    /// undecryptable ones too) and mine that went (my deleted one too). Never on a note, or one of mine that hasn't
    /// gone (held, waiting, sending, failed). Never greyed.
    func testMarkUnreadOnAnyMessageButNotesAndQueued() {
        func offers(_ message: TimelineMessage) -> Bool {
            let result = available(message, whatsApp, network: "whatsapp")
            XCTAssertNil(reason(.markUnread, in: result), "never greyed")
            return result.actions.contains(.markUnread)
        }
        XCTAssertTrue(offers(message(mine: false)))
        XCTAssertTrue(offers(message(mine: true)))
        XCTAssertFalse(offers(message(status: .failed)), "it never went: no one else sees it")
        XCTAssertFalse(offers(message(status: .pending)))
        XCTAssertTrue(offers(message(mine: true, more: [
            Event(eventID: "$d", roomID: "!room", sender: me, senderName: "me", mine: true,
                  type: "m.room.redaction", content: json(#"{"redacts":"$1"}"#), ts: sentAt + 1, seq: 2, status: .sent),
        ])), "my deleted message's place")
        XCTAssertTrue(offers(message(mine: false, more: [
            Event(eventID: "$d", roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                  type: "m.room.redaction", content: json(#"{"redacts":"$1"}"#), ts: sentAt + 1, seq: 2, status: .sent),
        ])), "a deleted message's place")
        XCTAssertFalse(offers(message(status: .queued)), "a held message offers nothing")
        XCTAssertFalse(offers(message(status: .waiting)), "a waiting message offers nothing: Don't Send is on its line")
        let note = message(mine: false, msgtype: "m.notice",
                           extra: #","com.beeper.action_message":{"type":"call"},"fi.courier.call":{"state":"ended","media":"voice"}"#)
        XCTAssertFalse(offers(note), "the engine refuses a note (Ruling P2)")
        XCTAssertEqual(MessageMenu.title(of: .markUnread, features: whatsApp), "Mark as Unread")
    }

    func testHeldFailedAndDeletedMessagesOfferLittle() {
        let held = available(message(status: .queued), whatsApp, network: "whatsapp")
        XCTAssertEqual(held.actions, [], "a held message offers nothing: clicking it undoes")
        XCTAssertEqual(held.unavailable, [])

        let failed = available(message(status: .failed), whatsApp, network: "whatsapp")
        XCTAssertEqual(failed.actions, [.copy, .copyWithTimestamp], "Retry and Delete are on its status line")

        let deleted = message(more: [
            Event(eventID: "$d", roomID: "!room", sender: me, senderName: "me", mine: true, type: "m.room.redaction",
                  content: json(#"{"redacts":"$1"}"#), ts: sentAt + 1, seq: 2, status: .sent),
        ])
        XCTAssertEqual(available(deleted, whatsApp, network: "whatsapp").actions, [.markUnread, .deleteForMe])
        XCTAssertEqual(available(message(status: .waiting), whatsApp, network: "whatsapp").actions, [],
                       "a waiting message offers nothing either: Don't Send is on its line")

        // A photo of mine can't be edited, so Edit isn't offered at all; it can still be forwarded.
        let photo = available(message(body: "beach.jpg", msgtype: "m.image"), whatsApp, network: "whatsapp")
        XCTAssertFalse(photo.actions.contains(.edit))
        XCTAssertNil(reason(.edit, in: photo))
        XCTAssertFalse(photo.actions.contains(.copy), "nothing to copy: it has no caption")
        XCTAssertTrue(photo.actions.contains(.forward))
    }

    /// Ruling 30: the action takes the network's id, as the engine names it, and the greyed line its name. A raw id
    /// never reaches a person.
    func testGreyedLinesNameTheNetworkNeverItsID() throws {
        XCTAssertEqual(NetworkNames.displayName(of: "whatsapp"), "WhatsApp")
        XCTAssertEqual(NetworkNames.displayName(of: "signal"), "Signal")
        XCTAssertEqual(NetworkNames.displayName(of: "telegram"), "Telegram")
        XCTAssertEqual(NetworkNames.displayName(of: "gmessages"), "Google Messages")
        XCTAssertEqual(NetworkNames.displayName(of: "slack"), "Slack")
        XCTAssertNil(NetworkNames.displayName(of: "matrix"))
        // The protocol's list of every network, which the engine's registry is checked against too: all five,
        // Slack and Google Messages included, not only the ones the accounts example shows.
        let dir = try XCTUnwrap(ProtocolConformanceTests.protocolDirectory())
        let list = try JSONSerialization.jsonObject(with: Data(
            contentsOf: dir.appendingPathComponent("networks.json"))) as? [String: Any]
        let networks = try XCTUnwrap(list?["networks"] as? [[String: Any]])
        var listed: [String: String] = [:]
        for network in networks {
            listed[try XCTUnwrap(network["name"] as? String)] = try XCTUnwrap(network["display_name"] as? String)
        }
        XCTAssertEqual(NetworkNames.names, listed)
        // The protocol's own accounts example agrees.
        let example = try JSONSerialization.jsonObject(with: Data(
            contentsOf: dir.appendingPathComponent("examples/accounts.list.json"))) as? [String: Any]
        let accounts = try XCTUnwrap(((example?["response"] as? [String: Any])?["result"] as? [String: Any])?["accounts"]
            as? [[String: Any]])
        XCTAssertFalse(accounts.isEmpty)
        for account in accounts {
            let id = try XCTUnwrap(account["network"] as? String)
            XCTAssertEqual(NetworkNames.displayName(of: id), account["display_name"] as? String, id)
        }

        // A network this app doesn't know is "this network", never "matrix".
        let unknown = available(message(), googleMessagesRCS, network: "matrix")
        XCTAssertEqual(reason(.unsend, in: unknown), "This network can’t unsend")
        let nothing = available(message(), .noFeatures, network: "matrix")
        XCTAssertEqual(reason(.edit, in: nothing), "Not available until this network connects")
        XCTAssertEqual(ChatFeatures(source: .stored).pollsUnavailableReason(network: "matrix"),
                       "Polls aren’t available on this network")
        for line in unknown.unavailable + nothing.unavailable { XCTAssertFalse(line.reason.contains("matrix")) }
    }

    /// -32024 covers both limits (age and edit count), so its words fit both.
    func testTooOldIsWordedForEitherLimit() {
        let text = EngineErrorText.text(for: EngineError.rpc(.tooOld, message: "x", reason: nil), fallback: "")
        XCTAssertEqual(text, "That message can’t be changed any more.")
    }

    func testWhatAChatKeeps() {
        XCTAssertTrue(whatsApp.keeps(.bold))
        XCTAssertFalse(whatsApp.keeps(.spoiler))
        XCTAssertFalse(ChatFeatures.noFeatures.keeps(.bold))
        // max_text_length counts bytes of UTF-8, not characters: 🎉 is four.
        let short = ChatFeatures(maxTextLength: 8, source: .stored)
        XCTAssertTrue(short.fits(text: "12345678"))
        XCTAssertFalse(short.fits(text: "123456789"))
        XCTAssertTrue(short.fits(text: "🎉🎉"))
        XCTAssertFalse(short.fits(text: "🎉🎉1"))
        XCTAssertTrue(ChatFeatures(maxTextLength: 0, source: .stored).fits(text: String(repeating: "a", count: 100_000)),
                      "0 is no limit")
        XCTAssertNil(whatsApp.pollsUnavailableReason(network: "whatsapp"))
        XCTAssertEqual(ChatFeatures(source: .stored).pollsUnavailableReason(network: "telegram"),
                       "Polls aren’t available on Telegram")
    }
}
