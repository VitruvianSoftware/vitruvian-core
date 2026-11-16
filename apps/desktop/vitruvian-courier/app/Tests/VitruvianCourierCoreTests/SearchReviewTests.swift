// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// What QA's review of the search polish found, and what the panel's chat-row reads do (one request per chat,
/// remembered while the panel is open, dropped when the query changes). Against a stand-in engine.
@MainActor
final class SearchReviewTests: XCTestCase {
    private var harnesses: [SearchHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    private func start(rooms: [[String: Any]]) async throws -> SearchHarness {
        let harness = try await startSearch(rooms: rooms)
        harnesses.append(harness)
        return harness
    }

    private func rowReads(_ h: SearchHarness) -> [[String]] {
        h.server.receivedParams("inbox.list").compactMap { $0["room_ids"] as? [String] }
    }

    // MARK: - The hover bar after a cover closes (QA)

    func testActionBarReturnsAfterSheetUncoversWhilePointerRemainsInRow() {
        var pointer = ActionBarPointer()
        pointer.rowHover(true)
        XCTAssertTrue(ActionBarVisibility.isShown(
            canAct: true, isSelected: true, menuOpen: false, pickingReaction: false,
            pointer: pointer, timelineCovered: false))
        // Covered by a sheet and then uncovered, with no pointer event between.
        XCTAssertFalse(ActionBarVisibility.isShown(
            canAct: true, isSelected: true, menuOpen: false, pickingReaction: false,
            pointer: pointer, timelineCovered: true))
        XCTAssertTrue(
            ActionBarVisibility.isShown(
                canAct: true, isSelected: true, menuOpen: false, pickingReaction: false,
                pointer: pointer, timelineCovered: false),
            "the bar returns once the cover lifts, the pointer never having left the row")
    }

    // MARK: - The open chat's title (QA)

    func testInChatOfferUsesOpenChatTitleWhenOpenChatHasNoInboxRow() async throws {
        let h = try await start(rooms: [room("!archived", ts: 1, name: "Dinner crew", archived: true)])
        let inbox = InboxModel(
            appModel: h.app, preferences: InboxPreferences(defaults: h.store.defaults), followsAppSelection: false)
        let hotkeys = HotkeyRegistry(defaults: h.store.defaults)

        h.script.results["picnic"] = searchResult(messages: [messageHit("$t1", room: "!archived")])
        h.app.selectedRoomID = "!archived"
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { h.search.hitRows["!archived"] != nil }

        let roomID = try XCTUnwrap(h.search.inChatOfferRoomID)
        XCTAssertNil(inbox.row(of: roomID), "precondition: the open chat has no row in the inbox's list")
        // What SearchPanel does: the list's row, else the row the panel read.
        let title = inbox.chatTitle(forRoomID: roomID, fetchedRow: h.search.hitRows[roomID]) ?? ""
        let offer = try XCTUnwrap(SearchInChatOffer.make(roomID: roomID, title: title, hotkeys: hotkeys))
        XCTAssertEqual(offer.text, "Press ⌘F to search in Dinner crew")
    }

    func testOpenChatRowIsReadOnHomeWhenNoResultNamesIt() async throws {
        let h = try await start(rooms: [room("!archived", ts: 1, name: "Dinner crew", archived: true)])
        h.app.selectedRoomID = "!archived"
        try await h.showHome()
        try await waitUntil { h.search.hitRows["!archived"] != nil }
        XCTAssertEqual(h.search.hitRows["!archived"]?.name, "Dinner crew",
                       "the line never has to say \"this chat\" for a real chat")
    }

    // MARK: - Bookmarks on home

    func testHomeBookmarksNameTheirChatsFromTheirRows() async throws {
        let h = try await start(rooms: [room("!old", ts: 1, name: "Dinner crew")])
        h.script.homeBookmarks = [messageHit("$b1", room: "!old")]
        try await h.showHome()
        try await waitUntil { h.search.hitRows["!old"] != nil }
        XCTAssertEqual(h.search.hitRows["!old"]?.name, "Dinner crew")
        XCTAssertEqual(rowReads(h), [["!old"]])
    }

    // MARK: - Fetch churn

    func testAChatIsReadOncePerPanelSession() async throws {
        let h = try await start(rooms: [room("!old", ts: 1)])
        h.script.results["picnic"] = searchResult(messages: [messageHit("$t1", room: "!old")])
        h.script.results["pizza"] = searchResult(messages: [messageHit("$t2", room: "!old")])
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { h.search.hitRows["!old"] != nil }
        try await h.type("pizza")
        try await waitUntil { h.search.sections.first?.items.first?.id == "message:$t2" }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(rowReads(h), [["!old"]], "the second query's hit in the same chat reads nothing")

        h.search.close()
        XCTAssertEqual(h.search.hitRows, [:], "the cache lasts as long as the panel is open")
    }

    /// Waits until the stand-in engine has gone quiet about chat-row reads: the count has not changed across a run of
    /// polls. A request the model was about to send has been sent by then, so a count taken after this is the count.
    private func settle(_ h: SearchHarness) async throws {
        var last = -1
        var stable = 0
        while stable < 25 {
            let count = h.server.receivedParams("inbox.list").count
            stable = count == last ? stable + 1 : 0
            last = count
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testAReadUnderWayIsNotAskedForAgainByAMorePage() async throws {
        let h = try await start(rooms: [room("!old", ts: 1)])
        h.script.holdRows = true
        h.script.respond = { params in
            if params["cursor"] != nil { return searchResult(messages: [messageHit("$t2", room: "!old")]) }
            guard params["text"] as? String == "picnic" else { return nil }
            return searchResult(messages: [messageHit("$t1", room: "!old")], messagesCursor: "c1")
        }
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { !self.rowReads(h).isEmpty }
        let held = try XCTUnwrap(h.server.received.last { $0["method"] as? String == "inbox.list" }?["id"] as? Int)

        await h.search.showMore(.messages)
        XCTAssertTrue(h.search.sections.first?.items.contains { $0.id == "message:$t2" } == true)
        // The second page's hit is in the same chat, and its read would have been sent by now.
        try await settle(h)
        XCTAssertEqual(rowReads(h), [["!old"]], "one request in flight for the chat, not two")

        h.server.reply(to: held, with: page([room("!old", ts: 1)]))
        try await waitUntil { h.search.hitRows["!old"] != nil }
        try await settle(h)
        XCTAssertEqual(rowReads(h), [["!old"]], "and none after it answers")
    }

    func testAnAnswerThatArrivesAfterANewQueryIsDropped() async throws {
        let h = try await start(rooms: [room("!old", ts: 1)])
        h.script.holdRows = true
        h.script.results["picnic"] = searchResult(messages: [messageHit("$t1", room: "!old")])
        h.script.results["pizza"] = searchResult(messages: [messageHit("$t2", room: "!old")])
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { !self.rowReads(h).isEmpty }
        let held = try XCTUnwrap(h.server.received.last { $0["method"] as? String == "inbox.list" }?["id"] as? Int)

        try await h.type("pizza")
        try await waitUntil { h.search.sections.first?.items.first?.id == "message:$t2" }
        // The old read answers late. Only the read's own token says it is for an older query: nothing of it is kept.
        h.server.reply(to: held, with: page([room("!old", ts: 1, name: "Stale")]))
        try await settle(h)
        XCTAssertNil(h.search.hitRows["!old"], "its answer was for the old query")

        // The new answer asks again, since the first never counted.
        try await waitUntil { self.rowReads(h).count == 2 }
        XCTAssertEqual(rowReads(h), [["!old"], ["!old"]])
    }

    func testChangingTheQueryCancelsTheChunksOfAReadNotYetSent() async throws {
        let rooms = manyRooms(150)
        let h = try await start(rooms: rooms)
        h.script.holdRows = true
        // 150 chats: the read goes in two requests of 100 and 50, the second only after the first answers.
        h.script.results["picnic"] = searchResult(
            messages: (0 ..< 150).map { messageHit("$t\($0)", room: "!r\($0)") })
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { !self.rowReads(h).isEmpty }
        let held = try XCTUnwrap(h.server.received.last { $0["method"] as? String == "inbox.list" }?["id"] as? Int)
        XCTAssertEqual(rowReads(h).first?.count, 100)

        try await h.type("pizza")
        try await waitUntil { h.search.sections.isEmpty && h.searches.last?["text"] as? String == "pizza" }
        h.server.reply(to: held, with: page(Array(rooms.prefix(100))))
        try await settle(h)
        XCTAssertEqual(rowReads(h).count, 1, "the cancelled read never sends its second request")
        XCTAssertEqual(h.search.hitRows, [:])
    }

    func testAChatTheEngineHasNoRowForIsNotAskedForAgain() async throws {
        let h = try await start(rooms: [])
        h.script.results["picnic"] = searchResult(messages: [messageHit("$t1", room: "!gone")])
        h.script.results["pizza"] = searchResult(messages: [messageHit("$t2", room: "!gone")])
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { !self.rowReads(h).isEmpty }
        try await settle(h)
        try await h.type("pizza")
        try await waitUntil { h.search.sections.first?.items.first?.id == "message:$t2" }
        try await settle(h)
        XCTAssertEqual(rowReads(h), [["!gone"]], "the engine said it has no such chat; once is enough")
        XCTAssertNil(h.search.hitRows["!gone"])
    }

    func testANewerInboxRowReplacesTheCachedOneSoARenameShows() async throws {
        let h = try await start(rooms: [room("!old", ts: 1, name: "Dinner crew")])
        h.script.results["picnic"] = searchResult(messages: [messageHit("$t1", room: "!old")])
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { h.search.hitRows["!old"] != nil }
        XCTAssertEqual(h.search.hitRows["!old"]?.name, "Dinner crew")

        var renamed = try XCTUnwrap(h.search.hitRows["!old"])
        renamed.name = "Dinner club"
        var other = renamed
        other.roomID = "!never-read"
        h.search.refreshHitRows { $0 == "!old" ? renamed : other }
        XCTAssertEqual(h.search.hitRows["!old"]?.name, "Dinner club")
        XCTAssertNil(h.search.hitRows["!never-read"], "only the chats the panel already named are refreshed")

        h.search.refreshHitRows { _ in nil }
        XCTAssertEqual(h.search.hitRows["!old"]?.name, "Dinner club", "no newer row: nothing changes")
    }
}
