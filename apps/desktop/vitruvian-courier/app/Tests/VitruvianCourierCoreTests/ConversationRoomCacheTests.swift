// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Going back to a chat opened before draws it at once from what it had, and reads the newest page again behind it.
/// All data here is made up.
@MainActor
final class ConversationRoomCacheTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
    }

    private func history(_ count: Int, room: String) -> [[String: Any]] {
        (1 ... count).map { textEvent(id: "\(room)$\($0)", room: room, at: Int64($0), body: "Message \($0)") }
    }

    private func start(_ events: [String: [[String: Any]]],
                       rows: [String: InboxRow] = [:]) async throws -> ConversationHarness {
        let harness = try await startConversation(events, rows: rows)
        harnesses.append(harness)
        return harness
    }

    func testReopeningAChatShowsItsMessagesAtOnce() async throws {
        let h = try await start(["!a": history(3, room: "!a"), "!b": history(2, room: "!b")])
        try await h.open("!a")
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["!a$1", "!a$2", "!a$3"])
        try await h.open("!b")
        XCTAssertTrue(h.conversation.isCached("!a"))

        // The engine is slow to answer: the chat still shows at once, from what it had.
        h.script.hold("!a")
        h.app.selectedRoomID = "!a"
        XCTAssertEqual(h.conversation.roomID, "!a")
        XCTAssertTrue(h.conversation.isLoaded, "no spinner for a chat opened before")
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["!a$1", "!a$2", "!a$3"])
    }

    func testAChatNeverOpenedStillWaitsForItsPage() async throws {
        let h = try await start(["!a": history(1, room: "!a"), "!b": history(1, room: "!b")])
        try await h.open("!a")
        h.script.hold("!b")
        h.app.selectedRoomID = "!b"
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertTrue(h.conversation.items.isEmpty, "nothing of another chat shows")
    }

    func testWhatCameWhileAwayIsMergedInBehindTheCachedMessages() async throws {
        let mineToEdit = textEvent(id: "!a$2", room: "!a", at: 2, body: "Original", mine: true)
        let h = try await start(["!a": [history(1, room: "!a")[0], mineToEdit], "!b": history(1, room: "!b")])
        try await h.open("!a")
        try await h.open("!b")

        // While !b is open, a message comes in !a and one of !a's messages is edited.
        h.script.add("!a", textEvent(id: "!a$3", room: "!a", at: 3, body: "New"))
        h.script.add("!a", editEvent(id: "!a$e", of: "!a$2", room: "!a", at: 4, text: "Changed", status: "sent"))
        let before = h.newestRequests()
        h.app.selectedRoomID = "!a"
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["!a$1", "!a$2"], "drawn at once from the cache")
        try await waitUntil { h.newestRequests() > before && h.messageIDs(h.conversation.items).count == 3 }
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["!a$1", "!a$2", "!a$3"])
        try await waitUntil { h.message("!a$2")?.body == "Changed" }
    }

    func testTheCacheKeepsOnlyTheChatsOpenedMostRecently() async throws {
        let limit = ConversationModel.roomCacheLimit
        var events: [String: [[String: Any]]] = [:]
        for index in 0 ... limit + 1 { events["!r\(index)"] = history(1, room: "!r\(index)") }
        let h = try await start(events)
        for index in 0 ... limit + 1 { try await h.open("!r\(index)") }
        // The open chat is saved when its page lands too; the oldest ones went.
        XCTAssertFalse(h.conversation.isCached("!r0"))
        XCTAssertFalse(h.conversation.isCached("!r1"))
        XCTAssertTrue(h.conversation.isCached("!r2"))
        XCTAssertTrue(h.conversation.isCached("!r\(limit + 1)"))
    }

    func testComposerPlaceholderNamesTheChatAndItsNetwork() {
        XCTAssertEqual(ConversationModel.composerPlaceholder(chatName: "Florian Burgos", network: "gmessages"),
                       "Message Florian Burgos on Google Messages")
        XCTAssertEqual(ConversationModel.composerPlaceholder(chatName: "Ann", network: "Matrix"), "Message Ann on Matrix")
        XCTAssertEqual(ConversationModel.composerPlaceholder(chatName: "Ann", network: ""), "Message Ann")
        XCTAssertEqual(ConversationModel.composerPlaceholder(chatName: "  ", network: "whatsapp"), "Type a message…")
        XCTAssertEqual(ConversationModel.composerPlaceholder(chatName: nil, network: nil), "Type a message…")
    }

    func testOpenChatHeaderAndPlaceholderSurviveInboxListChangeExcludingOpenChat() async throws {
        let dmRow = chatRow("!dm", name: "Florian Burgos", network: "gmessages", direct: true)
        var grpRow = chatRow("!grp", name: "Eddie Stecker, Kent Hua, GitHub", network: "slack", direct: false)
        grpRow.memberPreview = [
            RowMember(userID: "@eddie", name: "Eddie Stecker"),
            RowMember(userID: "@kent", name: "Kent Hua"),
            RowMember(userID: "@gh", name: "GitHub"),
        ]
        let otherRow = chatRow("!other", name: "Alice Example", network: "signal", direct: true)
        let h = try await start(
            [
                "!dm": [textEvent(id: "$d1", room: "!dm", at: 1)],
                "!grp": [textEvent(id: "$g1", room: "!grp", at: 1)],
                "!other": [textEvent(id: "$o1", room: "!other", at: 1)],
            ],
            rows: ["!dm": dmRow, "!grp": grpRow, "!other": otherRow]
        )
        let inbox = InboxModel(
            appModel: h.app,
            preferences: InboxPreferences(defaults: h.store.defaults),
            window: 0,
            sleep: { _ in }
        )
        let spaces = SpacesModel(appModel: h.app, inbox: inbox, window: 0, sleep: { _ in })
        inbox.onSelectedRowLookedUp = { [weak conversation = h.conversation] row in
            conversation?.learnUnreadCount(row.unread, of: row.roomID)
            conversation?.learnChat(row)
        }
        inbox.onOpenRowUpdated = { [weak conversation = h.conversation] row in
            conversation?.learnChat(row)
        }
        inbox.setSnapshotRowsForTesting([dmRow, grpRow])

        try await h.open("!dm")
        XCTAssertEqual(h.conversation.headerRow?.roomID, "!dm")
        XCTAssertEqual(h.conversation.openChatDisplayTitle, "Florian Burgos")
        XCTAssertEqual(h.conversation.composerPlaceholderText(), "Message Florian Burgos on Google Messages")

        // Switching to Reminders / Low Priority / Requests / Send Later / Archive / another network excludes the
        // open chat from the active inbox list.
        spaces.select("reminders")
        h.rows.rows = ["!other": otherRow]
        inbox.setSnapshotRowsForTesting([otherRow])
        try await waitUntil { inbox.rows.allSatisfy { $0.roomID != "!dm" } }

        XCTAssertEqual(h.app.selectedRoomID, "!dm")
        XCTAssertEqual(h.conversation.roomID, "!dm")
        XCTAssertEqual(h.conversation.headerRow?.roomID, "!dm")
        XCTAssertEqual(h.conversation.headerRow?.network, "gmessages")
        XCTAssertEqual(h.conversation.openChatDisplayTitle, "Florian Burgos")
        XCTAssertEqual(h.conversation.composerPlaceholderText(), "Message Florian Burgos on Google Messages")

        // Verify an unnamed group also preserves its shortened display title and composer placeholder when excluded.
        h.rows.rows = ["!grp": grpRow]
        inbox.setSnapshotRowsForTesting([grpRow])
        try await h.open("!grp")
        XCTAssertEqual(h.conversation.openChatDisplayTitle, "Eddie, Kent & GitHub")
        XCTAssertEqual(h.conversation.composerPlaceholderText(), "Message Eddie, Kent & GitHub on Slack")

        spaces.select("low_priority")
        h.rows.rows = [:]
        inbox.setSnapshotRowsForTesting([])
        try await waitUntil { inbox.rows.isEmpty }

        XCTAssertEqual(h.app.selectedRoomID, "!grp")
        XCTAssertEqual(h.conversation.roomID, "!grp")
        XCTAssertEqual(h.conversation.headerRow?.roomID, "!grp")
        XCTAssertEqual(h.conversation.openChatDisplayTitle, "Eddie, Kent & GitHub")
        XCTAssertEqual(h.conversation.composerPlaceholderText(), "Message Eddie, Kent & GitHub on Slack")
    }
}
