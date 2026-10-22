// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// What the conversation hands its composers and its timeline: the open chat's features and network (read again
/// when the chat changes), the other person's name, and whether deleted messages leave a placeholder. And older
/// pages read by cursor, not by count. All data here is made up.
@MainActor
final class ConversationWiringTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
    }

    private func start(_ events: [String: [[String: Any]]], features: [String: [String: Any]] = [:],
                       rows: [String: InboxRow] = [:]) async throws -> ConversationHarness {
        let h = try await startConversation(events, features: features, rows: rows)
        harnesses.append(h)
        return h
    }

    func testFeaturesFollowTheChatAndReachTheComposer() async throws {
        let h = try await start(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1)], "!g": [textEvent(id: "$g1", room: "!g", at: 1)]],
            features: ["!a": featuresJSON(), "!g": featuresJSON(edit: false, source: "network")],
            rows: ["!a": chatRow("!a", name: "Ann Lee", network: "signal"),
                   "!g": chatRow("!g", name: "Book club", network: "telegram", direct: false)])
        try await h.open("!a")
        let composer = h.conversation.composer
        XCTAssertEqual(dicts(h.server.receivedParams("room.features")), dicts([["room_id": "!a"]]))
        XCTAssertTrue(composer.features.edit)
        XCTAssertEqual(composer.network, "signal")
        XCTAssertEqual(h.conversation.network, "signal")
        XCTAssertEqual(composer.otherPerson, "Ann Lee", "a one-to-one chat's quick replies take the other person's name")

        try await h.open("!g")
        XCTAssertFalse(composer.features.edit)
        XCTAssertEqual(composer.features.source, .network)
        XCTAssertEqual(composer.network, "telegram")
        XCTAssertNil(composer.otherPerson, "a group has no one other person")

        // The chat changes (its bridge wrote new features): read again.
        h.script.features["!g"] = featuresJSON(edit: true)
        h.server.notify(["kind": "room", "room_id": "!g"])
        try await waitUntil { composer.features.edit }
        // Another chat's change reads nothing.
        let reads = h.count("room.features")
        h.server.notify(["kind": "room", "room_id": "!a"])
        h.server.notify(["kind": "room", "room_id": "!g"])
        try await waitUntil { h.count("room.features") == reads + 1 }

        // A row the inbox looks up later still reaches the composer.
        h.rows.rows["!x"] = nil
        h.script.add("!x", textEvent(id: "$x1", room: "!x", at: 1))
        try await h.open("!x")
        XCTAssertEqual(composer.network, "")
        h.conversation.learnChat(chatRow("!x", name: "Sam", network: "whatsapp"))
        XCTAssertEqual(composer.network, "whatsapp")
        XCTAssertEqual(composer.otherPerson, "Sam")
        h.conversation.learnChat(chatRow("!a", name: "Ann Lee", network: "signal"))
        XCTAssertEqual(composer.network, "whatsapp", "another chat's row changes nothing")
    }

    func testHideDeletedFollowsThePreferenceAndTheChat() async throws {
        let deleted = redactionEvent(id: "$r", of: "$1", room: "!a", at: 3, status: "sent")
        let h = try await start(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1), textEvent(id: "$2", room: "!a", at: 2), deleted],
             "!t": [textEvent(id: "$t1", room: "!t", at: 1), redactionEvent(id: "$tr", of: "$t1", room: "!t", at: 2,
                                                                            status: "sent")]],
            features: ["!a": featuresJSON(), "!t": featuresJSON(hideDeletedPlaceholder: true)])
        try await h.open("!a")
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["$1", "$2"], "a placeholder by default")
        XCTAssertEqual(h.message("$1")?.kind, .deleted)

        h.preferences.hideDeletedMessages = true
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["$2"], "Hide deleted messages: no placeholder, at once")
        h.preferences.hideDeletedMessages = false
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["$1", "$2"])

        // A network that leaves no placeholder (Telegram) hides it whatever the setting.
        try await h.open("!t")
        try await waitUntil { h.conversation.features.hideDeletedPlaceholder && h.messageIDs(h.conversation.items).isEmpty }
    }

    func testAnEmptyOlderPageWithACursorReadsOnAgain() async throws {
        let h = try await start(["!a": (1 ... 60).map { textEvent(id: "$\($0)", room: "!a", at: Int64($0)) }])
        try await h.open("!a")
        XCTAssertEqual(h.messageIDs(h.conversation.items).count, 50)
        h.script.emptyOlderPages = 2
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs(h.conversation.items).count == 60 }
        XCTAssertEqual(h.server.receivedParams("room.events").filter { $0["before"] != nil }.count, 3,
                       "two empty pages with a cursor, then the page with the rest")
        XCTAssertFalse(h.conversation.hasOlder)
    }

    /// The keys that act on the selected message (Task 12 binds them): ⌘T edits it or my last editable one, ⌘⇧R
    /// reacts with the quick reaction, ⌘⇧H finds its first link, ⌘↓ opens its replies or else jumps to the newest.
    func testSelectedMessageKeys() async throws {
        var mine = textEvent(id: "$2", room: "!a", at: 2, body: "Mine", mine: true)
        mine["content"] = ["msgtype": "m.text", "body": "See https://example.com/a and https://example.com/b"]
        let h = try await start(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1, body: "Theirs"), mine,
                    threadRoot(id: "$r", room: "!a", at: 3, replies: 1),
                    threadReply(id: "$t", root: "$r", room: "!a", at: 4)]],
            features: ["!a": featuresJSON()])
        try await h.open("!a")
        let conversation = h.conversation

        // ⌘T with nothing selected: my last message I can still edit.
        XCTAssertTrue(conversation.editSelectedOrLast())
        if case let .editing(id, _) = conversation.composer.mode { XCTAssertEqual(id, "$2") } else { XCTFail() }
        _ = conversation.composer.escape()
        // ⌘T on someone else's message: mine is still the one.
        conversation.selectedMessageID = "$1"
        XCTAssertTrue(conversation.editSelectedOrLast())
        if case let .editing(id, _) = conversation.composer.mode { XCTAssertEqual(id, "$2") } else { XCTFail() }
        _ = conversation.composer.escape()

        // ⌘⇧H: the first link of the selected message.
        conversation.selectedMessageID = "$2"
        XCTAssertEqual(conversation.firstLinkOfSelected(), URL(string: "https://example.com/a"))
        conversation.selectedMessageID = "$1"
        XCTAssertNil(conversation.firstLinkOfSelected())

        // ⌘⇧R: the quick reaction.
        h.preferences.quickReaction = "🎉"
        await conversation.quickReactToSelected()
        XCTAssertEqual(dicts(h.server.receivedParams("message.react")),
                       dicts([["room_id": "!a", "event_id": "$1", "key": "🎉"]]))

        // ⌘↓: on a thread's root, its replies; on anything else, the newest message.
        let jumps = conversation.jumpToBottomRequest
        conversation.showRepliesOrJumpToBottom()
        XCTAssertEqual(conversation.jumpToBottomRequest, jumps + 1)
        XCTAssertNil(conversation.thread.rootID)
        conversation.selectedMessageID = "$r"
        conversation.showRepliesOrJumpToBottom()
        XCTAssertEqual(conversation.thread.rootID, "$r")
        XCTAssertEqual(conversation.jumpToBottomRequest, jumps + 1)
    }
}
