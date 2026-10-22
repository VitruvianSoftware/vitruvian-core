// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// What a message's menu does, against a stand-in engine: each action reaches its method (Unsend and Delete for Me
/// only after a yes), a refusal is a toast that names the network and never looks done, Copy and Insert as Draft
/// take the right text, and Forward says which chats it couldn't reach. All data here is made up.
@MainActor
final class MessageActionsModelTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
    }

    /// A WhatsApp chat !a with one message from Ann ($1) and one of mine ($2); !b and !c to forward to.
    private func start(features: [String: Any] = featuresJSON(),
                       network: String = "whatsapp") async throws -> (ConversationHarness, MessageActionsModel,
                                                                       FakePasteboard, Toasts) {
        let h = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1, body: "Message 1"),
                    textEvent(id: "$2", room: "!a", at: 2, body: "Mine", mine: true)]],
            features: ["!a": features],
            rows: ["!a": chatRow("!a", name: "Ann", network: network)])
        harnesses.append(h)
        h.script.rooms = [room("!b", ts: 1, name: "Chat B"), room("!c", ts: 1, name: "Chat C")]
        try await h.open("!a")
        let pasteboard = FakePasteboard()
        let toasts = Toasts()
        let actions = MessageActionsModel(conversation: h.conversation, appModel: h.app, preferences: h.preferences,
                                          pasteboard: pasteboard)
        actions.onToast = { toasts.all.append($0) }
        return (h, actions, pasteboard, toasts)
    }

    @MainActor final class Toasts {
        var all: [String] = []
    }

    func testEachActionSendsItsMethod() async throws {
        let (h, actions, _, _) = try await start()

        await actions.perform(.bookmark, on: "$1")
        XCTAssertEqual(dicts(h.server.receivedParams("message.setBookmarked")), dicts([["event_id": "$1", "on": true]]))

        await actions.perform(.unsend, on: "$2")
        await actions.confirm()
        XCTAssertEqual(dicts(h.server.receivedParams("message.unsend")), dicts([["event_id": "$2"]]))

        await actions.perform(.deleteForMe, on: "$1")
        await actions.confirm()
        XCTAssertEqual(dicts(h.server.receivedParams("message.deleteForMe")), dicts([["event_id": "$1"]]))

        let result = await actions.forward("$1", to: ["!b", "!c"])
        XCTAssertEqual(result.sent, 2)
        XCTAssertEqual(result.failed, [])
        XCTAssertEqual(dicts(h.server.receivedParams("message.forward")),
                       dicts([["event_id": "$1", "room_ids": ["!b", "!c"]]]))

        await actions.vote("$poll", options: ["2"])
        XCTAssertEqual(dicts(h.server.receivedParams("poll.vote")), dicts([["event_id": "$poll", "option_ids": ["2"]]]))

        _ = await actions.history(of: "$2")
        XCTAssertEqual(dicts(h.server.receivedParams("message.history")), dicts([["event_id": "$2"]]))

        // What the composer or a picker does: no method yet.
        await actions.perform(.edit, on: "$2")
        XCTAssertEqual(h.conversation.composer.mode, .editing(eventID: "$2", original: RichText(text: "Mine")))
        _ = h.conversation.composer.escape()
        await actions.perform(.reply, on: "$1")
        XCTAssertEqual(h.conversation.composer.replyTarget?.eventID, "$1")
        await actions.perform(.forward, on: "$1")
        XCTAssertEqual(actions.request, .forward(messageID: "$1"))
        await actions.perform(.react, on: "$1")
        XCTAssertEqual(actions.request, .reactionPicker(messageID: "$1"))
        await actions.perform(.replyInThread, on: "$1")
        XCTAssertEqual(h.conversation.thread.rootID, "$1", "Reply in Thread opens the pane on the message")
        XCTAssertEqual(h.conversation.thread.composer.mode, .thread(rootID: "$1"))
    }

    func testUnsendAndDeleteConfirmFirst() async throws {
        let (h, actions, _, _) = try await start()

        await actions.perform(.unsend, on: "$2")
        XCTAssertEqual(actions.request, .confirm(.unsend, messageID: "$2",
                                                 prompt: "Unsend this message? It’s removed for everyone in the chat."))
        XCTAssertEqual(h.count("message.unsend"), 0, "nothing goes before a yes")
        actions.dismissRequest()
        XCTAssertNil(actions.request)
        await actions.confirm()
        XCTAssertEqual(h.count("message.unsend"), 0, "a no is a no")

        await actions.perform(.deleteForMe, on: "$1")
        XCTAssertEqual(actions.request, .confirm(.deleteForMe, messageID: "$1", prompt: "Delete this message from this Mac?"))
        XCTAssertEqual(h.count("message.deleteForMe"), 0)
        await actions.confirm()
        XCTAssertEqual(h.count("message.deleteForMe"), 1)
        XCTAssertNil(actions.request)

        // Where Delete for Me reaches the phone too (Google Messages), the question says so.
        h.script.features["!a"] = featuresJSON(unsend: false, deleteReachesPhone: true)
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await waitUntil { h.conversation.features.deleteReachesPhone }
        await actions.perform(.deleteForMe, on: "$1")
        XCTAssertEqual(actions.request, .confirm(.deleteForMe, messageID: "$1",
                                                 prompt: "Delete this message from this Mac and your phone?"))
    }

    func testRefusalsBecomeToasts() async throws {
        let (h, actions, _, toasts) = try await start()

        // Refused before anything was sent: too old (Ruling 35's words).
        h.script.overrides["message.unsend"] = .error(code: -32024, message: "too old")
        await actions.perform(.unsend, on: "$2")
        await actions.confirm()
        try await waitUntil { toasts.all.count == 1 }
        XCTAssertEqual(toasts.all.last, "That message can’t be changed any more.")
        XCTAssertNotEqual(try XCTUnwrap(h.message("$2")).kind, .deleted)

        // Taken by the engine, then refused by the network: the message comes back, and the toast names WhatsApp.
        h.script.overrides["message.unsend"] = nil
        await actions.perform(.unsend, on: "$2")
        await actions.confirm()
        h.script.add("!a", redactionEvent(id: "$redaction", of: "$2", room: "!a", at: 3, status: "failed"))
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$redaction"])
        try await waitUntil { toasts.all.count == 2 }
        XCTAssertEqual(toasts.all.last, "Couldn’t unsend: WhatsApp said no.")
        try await waitUntil { h.message("$2") != nil }
        XCTAssertNotEqual(try XCTUnwrap(h.message("$2")).kind, .deleted, "a refused unsend never looks done")

        // An edit the network refused: the old text stays, and the toast says so.
        h.script.add("!a", editEvent(id: "$e1", of: "$2", room: "!a", at: 4, text: "Changed", status: "failed"))
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$e1"])
        try await waitUntil { toasts.all.count == 3 }
        XCTAssertEqual(toasts.all.last, "Couldn’t edit: WhatsApp said no.")
        XCTAssertEqual(h.message("$2")?.rich.text, "Mine")

        // The same refusals read again (another change, another page) are not told twice.
        let requests = h.newestRequests()
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$e1"])
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$redaction"])
        try await waitUntil { h.newestRequests() > requests && h.conversation.pagesApplied == h.newestRequests() }
        XCTAssertEqual(toasts.all.count, 3)

        // A greyed action says why, in the network's name, and sends nothing.
        h.script.features["!a"] = featuresJSON(unsend: false)
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await waitUntil { !h.conversation.features.unsend }
        let unsends = h.count("message.unsend")
        await actions.perform(.unsend, on: "$2")
        XCTAssertEqual(toasts.all.last, "WhatsApp can’t unsend")
        XCTAssertNil(actions.request)
        XCTAssertEqual(h.count("message.unsend"), unsends)
    }

    func testCopyWithTimestamps() async throws {
        let (h, actions, pasteboard, _) = try await start()
        actions.formatTime = { date in "t\(Int64(date.timeIntervalSince1970))" }
        let stamp = "t\(ConversationScript.timestamp(1) / 1000)"

        await actions.perform(.copy, on: "$1")
        XCTAssertEqual(pasteboard.strings.last, "Message 1")

        h.preferences.copyWithTimestamps = true
        await actions.perform(.copy, on: "$1")
        XCTAssertEqual(pasteboard.strings.last, "[\(stamp)] Ann: Message 1")

        h.preferences.copyWithTimestamps = false
        await actions.perform(.copyWithTimestamp, on: "$1")
        XCTAssertEqual(pasteboard.strings.last, "[\(stamp)] Ann: Message 1", "Copy with Timestamp always has it")
        XCTAssertEqual(pasteboard.strings.count, 3)

        // My own message is "You", as the timeline names me.
        await actions.perform(.copyWithTimestamp, on: "$2")
        XCTAssertEqual(pasteboard.strings.last, "[t\(ConversationScript.timestamp(2) / 1000)] You: Mine")
    }

    func testInsertAsDraftOnlyOnOthersMessages() async throws {
        let (h, actions, _, _) = try await start()
        await actions.perform(.insertAsDraft, on: "$2")
        XCTAssertEqual(h.conversation.composer.text, "", "my own message is never offered")

        h.conversation.composer.text = "Typed"
        await actions.perform(.insertAsDraft, on: "$1")
        XCTAssertEqual(h.conversation.composer.text, "Typed\n\nMessage 1", "what was typed stays, the message below it")
    }

    func testForwardReportsFailures() async throws {
        let (h, actions, _, toasts) = try await start()
        let all = await actions.forward("$1", to: ["!b", "!c"])
        XCTAssertEqual(all.sent, 2)
        XCTAssertEqual(toasts.all.last, "Forwarded to 2 chats")

        h.script.forwardFailures = ["!c": -32018]
        let some = await actions.forward("$1", to: ["!b", "!c"])
        XCTAssertEqual(some.sent, 1)
        XCTAssertEqual(some.failed, ["Chat C"], "by name, never by id")
        XCTAssertEqual(toasts.all.last, "Couldn’t forward to Chat C")

        h.script.overrides["message.forward"] = .error(code: -32018, message: "not connected")
        let none = await actions.forward("$1", to: ["!b"])
        XCTAssertEqual(none.sent, 0)
        XCTAssertEqual(none.failed, ["Chat B"])
        XCTAssertEqual(toasts.all.last, "Couldn’t forward to Chat B")
    }

    /// A reply in the thread pane (in Slack, every reply) is acted on as a chat message is, and what goes into a
    /// composer goes into the pane's.
    func testActionsOnAThreadReplyUseThePane() async throws {
        let h = try await startConversation(
            ["!a": [threadRoot(id: "$r", room: "!a", at: 1, replies: 2),
                    threadReply(id: "$t1", root: "$r", room: "!a", at: 2, body: "Mine in the thread", mine: true),
                    threadReply(id: "$t2", root: "$r", room: "!a", at: 3, body: "Theirs in the thread")]],
            features: ["!a": featuresJSON(replyIsThread: true)],
            rows: ["!a": chatRow("!a", name: "Team", network: "slack", direct: false)])
        harnesses.append(h)
        try await h.open("!a")
        let actions = MessageActionsModel(conversation: h.conversation, appModel: h.app, preferences: h.preferences,
                                          pasteboard: FakePasteboard())
        let thread = h.conversation.thread
        h.conversation.openThread("$r")
        try await waitUntil { thread.isLoaded && thread.message("$t2") != nil }

        await actions.perform(.unsend, on: "$t1")
        await actions.confirm()
        XCTAssertEqual(dicts(h.server.receivedParams("message.unsend")), dicts([["event_id": "$t1"]]))

        await actions.perform(.edit, on: "$t1")
        if case let .editing(id, _) = thread.composer.mode { XCTAssertEqual(id, "$t1") } else { XCTFail("not editing") }
        XCTAssertEqual(h.conversation.composer.mode, .new, "the chat's composer is untouched")
        _ = thread.composer.escape()
        XCTAssertEqual(thread.composer.mode, .thread(rootID: "$r"))

        await actions.perform(.insertAsDraft, on: "$t2")
        XCTAssertEqual(thread.composer.text, "Theirs in the thread")
        XCTAssertEqual(h.conversation.composer.text, "")

        await actions.perform(.reply, on: "$t2")
        XCTAssertNil(h.conversation.composer.replyTarget)
        await actions.perform(.bookmark, on: "$t2")
        XCTAssertEqual(dicts(h.server.receivedParams("message.setBookmarked")), dicts([["event_id": "$t2", "on": true]]))
    }

    /// A poll goes as poll.create with the draft's question and options, trimmed and without the empty rows.
    func testCreatePollSendsTheDraft() async throws {
        let (h, actions, _, _) = try await start()
        var draft = PollDraft()
        draft.question = " Lunch? "
        draft.options = ["Pizza", " Soup ", ""]
        let sent = await actions.createPoll(draft)
        XCTAssertTrue(sent)
        XCTAssertEqual(dicts(h.server.receivedParams("poll.create")),
                       dicts([["room_id": "!a", "question": "Lunch?", "options": ["Pizza", "Soup"], "multiple": false]]))

        draft.options = ["Pizza", "pizza"]
        let refused = await actions.createPoll(draft)
        XCTAssertFalse(refused, "a draft with problems is never sent")
        XCTAssertEqual(h.count("poll.create"), 1)
    }
}
