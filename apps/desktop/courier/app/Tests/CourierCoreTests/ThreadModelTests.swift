// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The thread pane against a stand-in engine: it shows the root and its replies, writes in the thread, and reads
/// again only for changes in its own chat's thread. All data here is made up.
@MainActor
final class ThreadModelTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
    }

    /// !a: a message, a root ($r) with two replies that stay in the thread, and a later message.
    private func start() async throws -> ConversationHarness {
        let h = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1),
                    threadRoot(id: "$r", room: "!a", at: 2, replies: 2),
                    threadReply(id: "$t1", root: "$r", room: "!a", at: 3),
                    threadReply(id: "$t2", root: "$r", room: "!a", at: 4, body: "Mine in the thread", mine: true),
                    textEvent(id: "$5", room: "!a", at: 5)],
             "!b": [textEvent(id: "$b1", room: "!b", at: 1)]],
            features: ["!a": featuresJSON(replyIsThread: true)],
            rows: ["!a": chatRow("!a", name: "Team", network: "slack", direct: false)])
        harnesses.append(h)
        try await h.open("!a")
        return h
    }

    private func threadReads(_ h: ConversationHarness) -> Int {
        h.server.receivedParams("room.events").filter { $0["thread"] != nil }.count
    }

    func testOpensWithRootAndReplies() async throws {
        let h = try await start()
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["$1", "$r", "$5"], "the chat leaves the replies out")

        let thread = h.conversation.thread
        h.conversation.openThread("$r")
        try await waitUntil { thread.isLoaded }
        XCTAssertEqual(thread.rootID, "$r")
        XCTAssertEqual(thread.roomID, "!a")
        XCTAssertEqual(h.messageIDs(thread.items), ["$r", "$t1", "$t2"], "the root first, then the replies oldest first")
        let read = try XCTUnwrap(h.server.receivedParams("room.events").last { $0["thread"] != nil })
        XCTAssertEqual(read["thread"] as? String, "$r")
        XCTAssertEqual(read["room_id"] as? String, "!a")
        XCTAssertEqual(thread.composer.features, h.conversation.features, "the pane's composer knows the chat")
        XCTAssertEqual(thread.composer.network, "slack")

        thread.close()
        XCTAssertNil(thread.rootID)
        XCTAssertTrue(thread.items.isEmpty)

        // Opening another chat closes the pane.
        h.conversation.openThread("$r")
        try await waitUntil { thread.isLoaded }
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.conversation.roomID == "!b" }
        XCTAssertNil(thread.rootID)
    }

    func testReplySendsThreadRoot() async throws {
        let h = try await start()
        let thread = h.conversation.thread
        h.conversation.openThread("$r")
        try await waitUntil { thread.isLoaded }
        XCTAssertEqual(thread.composer.mode, .thread(rootID: "$r"))

        thread.composer.text = "In the thread"
        await thread.composer.submit()?.value
        let sent = try XCTUnwrap(h.server.receivedParams("message.send").last)
        XCTAssertEqual(sent["thread_root"] as? String, "$r")
        XCTAssertEqual(sent["text"] as? String, "In the thread")
        XCTAssertEqual(h.count("room.setDraft"), 0, "the pane's text is never the chat's draft")
        XCTAssertEqual(h.conversation.composer.text, "", "the chat's own composer is untouched")
    }

    /// A draft kept with its thread comes back when the thread opens again, as the composer's own text: opening
    /// the thread does not tell the chat I'm typing.
    func testReopeningAThreadWithADraftIsNotTyping() async throws {
        let h = try await start()
        let thread = h.conversation.thread
        h.conversation.openThread("$r")
        try await waitUntil { thread.isLoaded }
        thread.composer.text = "Back in a minute"
        thread.close()
        await thread.composer.waitForTyping()
        let typingBefore = h.count("room.setTyping")

        h.conversation.openThread("$r")
        try await waitUntil { thread.isLoaded }
        XCTAssertEqual(thread.composer.text, "Back in a minute", "the kept draft comes back")
        await thread.composer.waitForTyping()
        XCTAssertEqual(h.count("room.setTyping"), typingBefore, "a draft coming back is not typing")
    }

    func testOnlyThreadEventsRefetch() async throws {
        let h = try await start()
        let thread = h.conversation.thread
        h.conversation.openThread("$r")
        try await waitUntil { thread.isLoaded }
        let reads = threadReads(h)

        // Another chat's event, and a status change of a message the pane doesn't show: nothing to read.
        h.server.notify(["kind": "event", "room_id": "!b", "event_id": "$b2"])
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$1"])
        // A new reply in the thread's chat: read. Its newest page brings it.
        h.script.add("!a", threadReply(id: "$t3", root: "$r", room: "!a", at: 6))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$t3"])
        try await waitUntil { h.messageIDs(thread.items).contains("$t3") }
        XCTAssertEqual(threadReads(h), reads + 1, "one read, for the thread's chat")

        // A status change of a reply in the pane: read again.
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$t2"])
        try await waitUntil { self.threadReads(h) == reads + 2 }
        XCTAssertEqual(h.messageIDs(thread.items), ["$r", "$t1", "$t2", "$t3"])
    }

    /// With two threads on the page, the one nearest its middle is a guess: when the reply turns out to be in the
    /// other, the chat's highlight moves to that root.
    func testFindingTheThreadMovesTheHighlightToItsRoot() async throws {
        let h = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1),
                    threadRoot(id: "$rA", room: "!a", at: 2, replies: 1),
                    threadRoot(id: "$rB", room: "!a", at: 3, replies: 1),
                    threadReply(id: "$tA", root: "$rA", room: "!a", at: 4),
                    threadReply(id: "$tB", root: "$rB", room: "!a", at: 5),
                    textEvent(id: "$6", room: "!a", at: 6), textEvent(id: "$7", room: "!a", at: 7),
                    textEvent(id: "$8", room: "!a", at: 8), textEvent(id: "$9", room: "!a", at: 9)]],
            features: ["!a": featuresJSON(replyIsThread: true)])
        harnesses.append(h)
        // The page around $tA is the whole chat, so $rB is nearest its middle.
        h.app.open(.message(roomID: "!a", eventID: "$tA"))
        let thread = h.conversation.thread
        try await waitUntil { thread.rootID == "$rA" && thread.highlightedMessageID == "$tA" }
        try await waitUntil { h.conversation.highlightedMessageID == "$rA" }
        XCTAssertEqual(h.conversation.scrollToMessageRequest?.messageID, "$rA")
    }

    /// Ruling 23: a search hit that is a reply in a thread opens the chat around the root, and the pane at the reply.
    func testAThreadOnlySearchHitOpensThePaneAtTheReply() async throws {
        let h = try await start()
        h.app.selectedRoomID = nil
        h.app.open(.message(roomID: "!a", eventID: "$t1"))
        let thread = h.conversation.thread
        try await waitUntil { thread.rootID == "$r" && thread.highlightedMessageID == "$t1" }
        XCTAssertEqual(h.conversation.highlightedMessageID, "$r", "the chat shows the root, which is in it")
        XCTAssertEqual(h.conversation.scrollToMessageRequest?.messageID, "$r")
        XCTAssertEqual(thread.scrollToMessageRequest?.messageID, "$t1")
    }
}
