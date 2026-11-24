// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Selecting a chat leaves nothing of the previous chat to act on: every piece of per-chat state is cleared or re-keyed
/// in the same turn, for a merged chat as for any other.
@MainActor
final class ChatSwitchStateTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    override func tearDown() async throws {
        for h in harnesses { await h.stop() }
        harnesses = []
    }

    private func mergedHarness() async throws -> ConversationHarness {
        let h = try await startConversation(
            ["!a": (1 ... 3).map { textEvent(id: "!a$\($0)", room: "!a", at: Int64($0)) },
             "!wa": [textEvent(id: "$w1", room: "!wa", at: 1)],
             "!sig": [textEvent(id: "$s1", room: "!sig", at: 2)]],
            features: ["!a": featuresJSON(), "!wa": featuresJSON(), "!sig": featuresJSON()],
            rows: ["!a": chatRow("!a", name: "Team", network: "slack", direct: false),
                   "!wa": chatRow("!wa", name: "Alice", network: "whatsapp"),
                   "!sig": chatRow("!sig", name: "Alice", network: "signal")])
        harnesses.append(h)
        h.script.unreadThreads["!a"] = [
            ["root_id": "$r", "unread": 1, "unread_mentions_me": false, "first_unread_id": "$r1"],
        ]
        h.app.mergedChats["merge:alice"] = MergedChat(
            mergeID: "merge:alice", name: "Alice", avatarPath: "", lastRoomID: "!sig",
            roomIDs: ["!wa", "!sig"], networks: ["whatsapp", "signal"], createdTS: 1)
        return h
    }

    /// The reported leak: the unread-thread banner of the old chat, still on the merged chat, opened the old chat's
    /// message in it.
    func testTheOldChatsUnreadThreadsDoNotSurviveIntoAMergedChat() async throws {
        let h = try await mergedHarness()
        try await h.open("!a")
        try await waitUntil { h.conversation.unreadThreads.count == 1 }
        let eventsAsked = h.count("room.events")

        h.app.selectedRoomID = "merge:alice"
        // The same turn: nothing of !a is left on the merged chat.
        XCTAssertEqual(h.conversation.roomID, "merge:alice")
        XCTAssertTrue(h.conversation.unreadThreads.isEmpty, "!a's threads with news are not the merged chat's")
        XCTAssertNil(h.conversation.unreadThreadsBanner)
        h.conversation.showNextUnreadThread()
        XCTAssertNil(h.app.pendingMessage, "the old chat's first unread reply is not opened in the merged chat")
        XCTAssertEqual(h.app.selectedRoomID, "merge:alice")
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertFalse(
            h.server.receivedParams("room.events").dropFirst(eventsAsked).contains { $0["around"] != nil },
            "no page was read around a message of the old chat"
        )
    }

    /// Everything a chat keeps while it is open, after selecting a merged chat from a plain one (and back): cleared,
    /// or re-keyed to the new chat; nothing still names the old room.
    func testEveryPieceOfPerChatStateIsClearedOrReKeyedWhenAMergedChatIsSelected() async throws {
        let h = try await mergedHarness()
        try await h.open("!a")
        try await waitUntil { h.conversation.unreadThreads.count == 1 }
        h.conversation.selectedMessageID = "!a$2"
        h.conversation.composer.text = "half written in the team chat"

        h.app.selectedRoomID = "merge:alice"
        XCTAssertEqual(h.conversation.roomID, "merge:alice")
        XCTAssertNil(h.conversation.selectedMessageID)
        XCTAssertNil(h.conversation.highlightedMessageID)
        XCTAssertNil(h.conversation.scrollToMessageRequest)
        XCTAssertNil(h.conversation.thread.rootID)
        XCTAssertNil(h.conversation.chatInfo)
        XCTAssertNil(h.conversation.typingLine)
        XCTAssertNil(h.conversation.chatSummary)
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertFalse(h.conversation.isHeldAwayFromLatest)
        XCTAssertTrue(h.conversation.items.isEmpty, "the old chat's messages are not shown")
        XCTAssertEqual(h.conversation.composer.roomID, "!sig", "sends go to a room of the merged chat")
        XCTAssertEqual(h.conversation.activeReplyRoomID, "!sig")
        XCTAssertEqual(h.conversation.otherPerson, "Alice")
        XCTAssertNotEqual(h.conversation.composer.text, "half written in the team chat")
        XCTAssertEqual(h.conversation.headerRow?.roomID, "merge:alice")

        // And back to a plain chat: the merged chat's reply room and name are gone.
        h.app.selectedRoomID = "!a"
        XCTAssertEqual(h.conversation.roomID, "!a")
        XCTAssertNil(h.conversation.activeReplyRoomID)
        XCTAssertNil(h.conversation.mergedChat)
        XCTAssertEqual(h.conversation.composer.roomID, "!a")
        XCTAssertTrue(h.conversation.items.isEmpty || h.messageIDs(h.conversation.items).allSatisfy { $0.hasPrefix("!a") })
    }

    /// An answer for the chat that was open, arriving after the switch, changes nothing on the new one.
    func testALateThreadAnswerForTheOldChatIsDropped() async throws {
        let h = try await mergedHarness()
        try await h.open("!a")
        h.app.selectedRoomID = "merge:alice"
        try await h.open("merge:alice")
        try await Task.sleep(for: .milliseconds(150)) // !a's thread.unread read comes back now, if it has not
        XCTAssertTrue(h.conversation.unreadThreads.isEmpty)
    }
}
