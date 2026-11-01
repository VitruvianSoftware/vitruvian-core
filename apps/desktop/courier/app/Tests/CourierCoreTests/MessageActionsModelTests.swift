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

        // Mark as Unread: the message only, and the engine finds its chat.
        await actions.perform(.markUnread, on: "$1")
        XCTAssertEqual(dicts(h.server.receivedParams("room.setUnreadFrom")), dicts([["event_id": "$1"]]))

        // Last: it takes the message off this Mac.
        await actions.perform(.deleteForMe, on: "$1")
        await actions.confirm()
        XCTAssertEqual(dicts(h.server.receivedParams("message.deleteForMe")), dicts([["event_id": "$1"]]))
        try await waitUntil { h.message("$1") == nil }

        // Reply Privately, in a group on a network that runs: the private chat with the message's sender.
        let group = try await startConversation(
            ["!g": [textEvent(id: "$g1", room: "!g", at: 1, body: "Lunch?")], "!d": []],
            features: ["!g": featuresJSON(), "!d": featuresJSON()],
            rows: ["!g": chatRow("!g", name: "Book club", direct: false), "!d": chatRow("!d", name: "Ann")])
        harnesses.append(group)
        group.script.accounts = [account("whatsapp", "CONNECTED")]
        await group.app.refreshAccounts()
        group.script.directChat = "!d"
        try await group.open("!g")
        let groupActions = MessageActionsModel(conversation: group.conversation, appModel: group.app,
                                               preferences: group.preferences, pasteboard: FakePasteboard())
        await groupActions.perform(.replyPrivately, on: "$g1")
        XCTAssertEqual(dicts(group.server.receivedParams("room.directChat")),
                       dicts([["room_id": "!g", "user_id": "@ann:example.test"]]))
        XCTAssertEqual(group.app.selectedRoomID, "!d")
    }

    /// Review Focus 1: a waiting message offers nothing in its menu; its line's Don't Send takes it back as Undo does
    /// (message.undo), and what was typed comes back into the composer.
    func testDontSendOnAWaitingMessageUndoes() async throws {
        let (h, actions, _, _) = try await start()
        h.script.add("!a", textEvent(id: "$w", room: "!a", at: 3, body: "On my way", mine: true, status: "waiting"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$w"])
        try await waitUntil { h.message("$w")?.statusLine == .waiting }
        let waiting = try XCTUnwrap(h.message("$w"))
        XCTAssertEqual(h.conversation.availableActions(for: waiting).actions, [.copy, .copyWithTimestamp],
                       "Copy only: Don't Send is on its line")
        XCTAssertEqual(h.conversation.composer.heldIDs, ["$w"], "held, with no window: it waits for its network")

        h.script.overrides["message.undo"] = .result(["text": "On my way", "entities": [[String: Any]](),
                                                      "reply_to": NSNull(), "thread_root": NSNull()])
        await actions.dontSend("$w")
        XCTAssertEqual(dicts(h.server.receivedParams("message.undo")), dicts([["event_id": "$w"]]))
        XCTAssertEqual(h.conversation.composer.text, "On my way")
        XCTAssertEqual(h.conversation.composer.heldIDs, [])

        // Only a waiting message of mine: anything else is left alone.
        await actions.dontSend("$2")
        await actions.dontSend("$1")
        XCTAssertEqual(h.count("message.undo"), 1)
    }

    /// B10: Don't Send that can't take the message up (Undo already took it back, and a page not read since still
    /// shows it waiting) says so in a toast, and asks nothing of the engine.
    func testDontSendThatCantTakeItBackSaysSo() async throws {
        let (h, actions, _, toasts) = try await start()
        h.script.add("!a", textEvent(id: "$w", room: "!a", at: 3, body: "On my way", mine: true, status: "waiting"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$w"])
        try await waitUntil { h.message("$w")?.statusLine == .waiting }
        h.script.overrides["message.undo"] = .result(["text": "On my way", "entities": [[String: Any]](),
                                                      "reply_to": NSNull(), "thread_root": NSNull()])
        await actions.dontSend("$w")
        XCTAssertEqual(toasts.all, [])

        XCTAssertEqual(h.message("$w")?.statusLine, .waiting, "the page hasn't been read again")
        await actions.dontSend("$w")
        XCTAssertEqual(toasts.all, ["Couldn’t take the message back. Try again."])
        XCTAssertEqual(h.count("message.undo"), 1, "nothing more was asked")
    }

    /// Ruling 18: after a network flap (waiting, Sending…, waiting again) Don't Send still takes the message back.
    func testDontSendWorksAfterTheNetworkFlaps() async throws {
        let (h, actions, _, _) = try await start()
        for status in ["waiting", "pending", "waiting"] {
            h.script.replace("!a", textEvent(id: "$w", room: "!a", at: 3, body: "On my way", mine: true, status: status))
            h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$w"])
            let line: StatusLine = status == "pending" ? .sending : .waiting
            try await waitUntil { h.message("$w")?.statusLine == line }
        }
        h.script.overrides["message.undo"] = .result(["text": "On my way", "entities": [[String: Any]](),
                                                      "reply_to": NSNull(), "thread_root": NSNull()])
        await actions.dontSend("$w")
        XCTAssertEqual(dicts(h.server.receivedParams("message.undo")), dicts([["event_id": "$w"]]))
        XCTAssertEqual(h.conversation.composer.text, "On my way")
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
        await actions.perform(.deleteForMe, on: "$2")
        XCTAssertEqual(actions.request, .confirm(.deleteForMe, messageID: "$2",
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

    /// Final fix wave: a forward the engine didn't answer (timed out, or the connection ended) may have sent copies,
    /// so it never says "Couldn’t forward"; it says the message may have gone, by name, and to check first.
    func testForwardWithNoAnswerSaysItMayHaveGone() async throws {
        let (h, actions, _, toasts) = try await start()
        h.script.overrides["message.forward"] = .later
        actions.forwardTimeout = 0.2

        let unanswered = await actions.forward("$1", to: ["!b", "!c"])
        XCTAssertEqual(unanswered.sent, 0)
        XCTAssertEqual(unanswered.failed, [], "not failed: the copies may have gone")
        XCTAssertEqual(unanswered.unanswered, ["Chat B", "Chat C"])
        XCTAssertEqual(toasts.all.last,
                       "Courier’s engine did not answer. The message may have been forwarded to Chat B and Chat C: "
                           + "check before forwarding it again.")
        XCTAssertFalse(toasts.all.contains { $0.hasPrefix("Couldn’t forward") })

        // A refusal for one chunk and no answer for another says both, each by name.
        h.script.overrides = [:]
        h.script.forwardFailures = ["!b": -32018]
        let refused = await actions.forward("$1", to: ["!b"])
        XCTAssertEqual(refused.failed, ["Chat B"])
        XCTAssertEqual(refused.unanswered, [])
    }

    /// A reply in the thread pane (in Slack, every reply) is acted on as a chat message is, and what goes into a
    /// composer goes into the pane's.
    /// A Slack chat !a whose root $r (Ann's) has my reply $t1 and Ann's $t2, with the pane open on it.
    private func startPane() async throws -> (ConversationHarness, MessageActionsModel, Toasts) {
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
        let toasts = Toasts()
        actions.onToast = { toasts.all.append($0) }
        h.conversation.openThread("$r")
        try await waitUntil { h.conversation.thread.message("$t2") != nil }
        return (h, actions, toasts)
    }

    /// Delete for Me and bookmarks are store writes the engine sends no change for: the pane reads again itself.
    func testPaneRepliesShowWhatWasDone() async throws {
        let (h, actions, _) = try await startPane()
        let thread = h.conversation.thread
        await actions.perform(.bookmark, on: "$t2", from: .thread)
        try await waitUntil { thread.message("$t2")?.bookmarked == true }
        await actions.perform(.deleteForMe, on: "$t2", from: .thread)
        await actions.confirm()
        try await waitUntil { thread.message("$t2") == nil }
        XCTAssertNotNil(thread.message("$t1"))
    }

    /// A refused edit of a reply in the pane is told, once.
    func testARefusedPaneEditIsToldOnce() async throws {
        let (h, actions, toasts) = try await startPane()
        defer { withExtendedLifetime(actions) {} } // it watches the timelines only while it lives
        let thread = h.conversation.thread
        h.script.add("!a", editEvent(id: "$e1", of: "$t1", room: "!a", at: 4, text: "Changed", status: "pending"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$e1"])
        try await waitUntil { thread.message("$t1")?.rich.text == "Changed" }
        h.script.replace("!a", editEvent(id: "$e1", of: "$t1", room: "!a", at: 4, text: "Changed", status: "failed"))
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$e1"])
        try await waitUntil { toasts.all.count == 1 }
        XCTAssertEqual(toasts.all, ["Couldn’t edit: Slack said no."])
        XCTAssertEqual(thread.message("$t1")?.rich.text, "Mine in the thread")

        let reads = h.threadReads()
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$e1"])
        try await waitUntil { h.threadReads() > reads && thread.pagesApplied == h.threadReads() }
        XCTAssertEqual(toasts.all.count, 1)
    }

    /// The root is in the chat and the pane: what goes into a composer goes into the one it was acted on from.
    func testTheRootActedOnFromThePaneUsesThePanesComposer() async throws {
        let (h, actions, _) = try await startPane()
        let thread = h.conversation.thread
        await actions.perform(.insertAsDraft, on: "$r", from: .thread)
        XCTAssertEqual(thread.composer.text, "Root 1")
        XCTAssertEqual(h.conversation.composer.text, "")
        await actions.perform(.insertAsDraft, on: "$r")
        XCTAssertEqual(h.conversation.composer.text, "Root 1", "from the chat, the chat's composer")
    }

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

// MARK: - Task 12, fix round 1: ⌘C, Edit History's timeline, Reply, ↑

extension MessageActionsModelTests {
    func testCommandCCopiesWhatTheResponderCanElseTheSelectedMessageInTheChat() async throws {
        // The rule, over its inputs.
        func choice(_ can: Bool, _ place: CopyPlace) -> CopyChoice {
            MessageActionsModel.copyChoice(responderCanCopy: can, place: place, chatSelection: "$c", paneSelection: "$p")
        }
        for place in [CopyPlace.chat, .pane, .elsewhere] {
            XCTAssertEqual(choice(true, place), .text, "selected text anywhere (a code block too) is the system's Copy")
        }
        XCTAssertEqual(choice(false, .chat), .message(id: "$c", source: .chat))
        XCTAssertEqual(choice(false, .pane), .message(id: "$p", source: .thread))
        XCTAssertEqual(choice(false, .elsewhere), .nothing, "search, a sheet or Settings copies no message")
        XCTAssertEqual(MessageActionsModel.copyChoice(responderCanCopy: false, place: .pane, chatSelection: "$c",
                                                      paneSelection: nil), .nothing, "nothing selected in the pane")

        // And done, with the fake pasteboard.
        let (h, actions, pasteboard, _) = try await start()
        let focus = MessageFocus()
        var done = await actions.copySelected(responderCanCopy: false, inConversation: true, focus: focus)
        XCTAssertEqual(done, .nothing, "nothing selected: the system's Copy")

        h.conversation.selectedMessageID = "$1"
        done = await actions.copySelected(responderCanCopy: true, inConversation: true, focus: focus)
        XCTAssertEqual(done, .text)
        done = await actions.copySelected(responderCanCopy: false, inConversation: false, focus: focus)
        XCTAssertEqual(done, .nothing)
        XCTAssertEqual(pasteboard.strings, [], "neither copied a message")

        done = await actions.copySelected(responderCanCopy: false, inConversation: true, focus: focus)
        XCTAssertEqual(done, .message(id: "$1", source: .chat))
        XCTAssertEqual(pasteboard.strings, ["Message 1"])

        h.preferences.copyWithTimestamps = true
        actions.formatTime = { _ in "t" }
        await actions.copySelected(responderCanCopy: false, inConversation: true, focus: focus)
        XCTAssertEqual(pasteboard.strings.last, "[t] Ann: Message 1", "Settings' timestamps hold for ⌘C")

        focus.inPane = true
        done = await actions.copySelected(responderCanCopy: false, inConversation: true, focus: focus)
        XCTAssertEqual(done, .nothing, "the pane has the keyboard, and nothing is selected there")
    }

    func testCommandCInThePaneCopiesThePanesMessage() async throws {
        let (h, actions, _) = try await startPane()
        let pasteboard = FakePasteboard()
        let copier = MessageActionsModel(conversation: h.conversation, appModel: h.app, preferences: h.preferences,
                                         pasteboard: pasteboard)
        defer { withExtendedLifetime(actions) {} }
        let focus = MessageFocus()
        focus.inPane = true
        focus.paneSelection = "$t2"
        let choice = await copier.copySelected(responderCanCopy: false, inConversation: true, focus: focus)
        XCTAssertEqual(choice, .message(id: "$t2", source: .thread))
        XCTAssertEqual(pasteboard.strings, ["Theirs in the thread"])
    }

    func testEditHistoryOpensInTheTimelineItWasAskedFrom() async throws {
        let h = try await startConversation(
            ["!a": [threadRoot(id: "$r", room: "!a", at: 1, replies: 1),
                    textEvent(id: "$m", room: "!a", at: 2, body: "Mine", mine: true),
                    editEvent(id: "$me", of: "$m", room: "!a", at: 3, text: "Mine, changed", status: "sent"),
                    threadReply(id: "$t1", root: "$r", room: "!a", at: 4, body: "In the thread", mine: true),
                    editEvent(id: "$te", of: "$t1", room: "!a", at: 5, text: "In the thread, changed", status: "sent")]],
            features: ["!a": featuresJSON(replyIsThread: true)],
            rows: ["!a": chatRow("!a", name: "Team", network: "slack", direct: false)])
        harnesses.append(h)
        try await h.open("!a")
        let actions = MessageActionsModel(conversation: h.conversation, appModel: h.app, preferences: h.preferences,
                                          pasteboard: FakePasteboard())
        h.conversation.openThread("$r")
        try await waitUntil { h.conversation.thread.message("$t1")?.isEdited == true }

        await actions.perform(.showHistory, on: "$t1", from: .thread)
        XCTAssertEqual(actions.request, .history(messageID: "$t1", source: .thread), "the pane's bubble")
        actions.dismissRequest()
        await actions.perform(.showHistory, on: "$m")
        XCTAssertEqual(actions.request, .history(messageID: "$m", source: .chat), "the chat's bubble")
    }

    func testOneRuleForReplyAndOneLookUpByWhereItWasActedOn() async throws {
        let (chat, _, _, _) = try await start()
        let theirs = try XCTUnwrap(chat.conversation.message("$1", from: .chat))
        XCTAssertEqual(chat.conversation.replyAction(for: theirs), .reply)

        let (h, _, _) = try await startPane()
        let root = try XCTUnwrap(h.conversation.message("$r", from: .thread))
        XCTAssertEqual(h.conversation.replyAction(for: root), .replyInThread, "Slack's replies are thread replies")
        XCTAssertNotNil(h.conversation.message("$t2", from: .chat), "a reply is only in the pane: found there")
        XCTAssertNil(h.conversation.message("$nope", from: .thread))
    }

    func testUpArrowWalksUpTheChat() async throws {
        let (h, _, _, _) = try await start()
        XCTAssertTrue(h.conversation.selectOlderMessage())
        XCTAssertEqual(h.conversation.selectedMessageID, "$2", "the newest first")
        XCTAssertTrue(h.conversation.selectOlderMessage())
        XCTAssertEqual(h.conversation.selectedMessageID, "$1", "then the one above")
        XCTAssertTrue(h.conversation.selectOlderMessage())
        XCTAssertEqual(h.conversation.selectedMessageID, "$1", "the oldest loaded stays")
    }

    func testMessageFocusPicksTheChatOrThePane() {
        let focus = MessageFocus()
        XCTAssertEqual(focus.target(chatSelection: "$1")?.id, "$1")
        XCTAssertEqual(focus.target(chatSelection: "$1")?.source, .chat)
        focus.inPane = true
        XCTAssertNil(focus.target(chatSelection: "$1"), "the pane was clicked, and nothing is selected there")
        focus.paneSelection = "$t"
        XCTAssertEqual(focus.target(chatSelection: "$1")?.source, .thread)
    }

    func testCopyMessageDetailsAndReportProblem() async throws {
        let (_, actions, pasteboard, toasts) = try await start()

        actions.copyMessageDetails("$1")
        let copied = try XCTUnwrap(pasteboard.strings.last)
        let data = try XCTUnwrap(copied.data(using: .utf8))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["event_id"] as? String, "$1")
        XCTAssertEqual(json["room_id"] as? String, "!a")
        XCTAssertEqual(json["network"] as? String, "whatsapp")
        XCTAssertEqual(json["type"] as? String, "m.room.message")
        XCTAssertEqual(json["status"] as? String, "sent")
        XCTAssertNotNil(json["ts"])
        XCTAssertNotNil(json["status_reason"])
        XCTAssertFalse(copied.contains("Message 1"), "message body must never be included in copied details")
        XCTAssertFalse(copied.contains("Ann"), "sender display name must never be included in copied details")
        XCTAssertEqual(toasts.all.last, "Message details copied")

        actions.reportProblem(for: "$1")
        XCTAssertEqual(actions.request, .reportProblem(roomID: "!a", eventID: "$1"))
    }

    func testTranslateMessageStoresCalmUnavailableTranslationOnEvent() async throws {
        let (_, actions, _, _) = try await start()

        actions.translateMessage(eventID: "$1", targetLanguage: "Spanish")
        XCTAssertEqual(
            actions.translations["$1"],
            .unavailable(reason: "Message translation isn’t available yet in Courier.")
        )
        XCTAssertEqual(actions.translationTargetLanguages["$1"], "Spanish")

        actions.dismissTranslation(eventID: "$1")
        XCTAssertNil(actions.translations["$1"])
        XCTAssertNil(actions.translationTargetLanguages["$1"])
    }
}
