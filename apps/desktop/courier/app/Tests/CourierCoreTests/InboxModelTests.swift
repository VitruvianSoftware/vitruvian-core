// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The inbox model against a stand-in engine. The engine's answers come from an `InboxScript` the test edits, and
/// the coalescing window's sleep is one the test opens.
@MainActor
final class InboxModelTests: XCTestCase {
    private var harnesses: [InboxHarness] = []
    private var servers: [TestEngineServer] = []

    override func tearDown() async throws {
        for harness in harnesses { harness.cleanUp() }
        for server in servers { server.stop() }
        harnesses = []
        servers = []
    }

    /// An app model on a stand-in engine, an inbox model on that, and the first inbox read done.
    private func start(rooms: [[String: Any]] = [], accounts: [[String: Any]] = [account("whatsapp", "CONNECTED")],
                       autoRelease: Bool = false, failFirstReads: Int = 0,
                       hasTelegramCredentials: @escaping @MainActor () -> Bool = { true }) async throws -> InboxHarness {
        let harness = try await startInbox(rooms: rooms, accounts: accounts, autoRelease: autoRelease,
                                           failFirstReads: failFirstReads, hasTelegramCredentials: hasTelegramCredentials)
        harnesses.append(harness)
        return harness
    }

    private func stop(_ harness: InboxHarness) async {
        await harness.app.stop()
    }

    // MARK: - Order and selection

    func testTheEnginesOrderAndTheSelectionSurviveRefresh() async throws {
        // The engine sorts (pinned first, then the query's sort): the list is in its order, not re-sorted by time.
        let h = try await start(rooms: [
            room("!pinned", ts: 100, pinned: true), room("!b", ts: 300), room("!c", ts: 200),
        ], autoRelease: true)
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!pinned", "!b", "!c"])

        h.inbox.select("!c")
        XCTAssertEqual(h.app.selectedRoomID, "!c", "the selection lives on the app model")

        // A new message moves a chat up, and an old chat's row changes.
        h.script.rooms = [room("!pinned", ts: 100, pinned: true), room("!a", ts: 400, unread: 1), room("!b", ts: 300),
                          room("!c", ts: 200, unread: 2)]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.inbox.rows.count == 4 }
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!pinned", "!a", "!b", "!c"])
        XCTAssertEqual(h.inbox.selectedRoomID, "!c", "the open chat stays open")
        XCTAssertEqual(h.inbox.selectedRow?.unread, 2)

        // Even when the chat is gone from the list for a moment.
        h.script.rooms = [room("!a", ts: 400)]
        h.server.notify(["kind": "room"])
        try await waitUntil { h.inbox.rows.count == 1 }
        XCTAssertEqual(h.inbox.selectedRoomID, "!c")
        XCTAssertNil(h.inbox.selectedRow)
        await stop(h)
    }

    func testNextAndPreviousChat() async throws {
        let h = try await start(rooms: [room("!a", ts: 300), room("!b", ts: 200), room("!c", ts: 100)])
        // Nothing open: next opens the first chat, previous the last.
        h.inbox.selectNext()
        XCTAssertEqual(h.inbox.selectedRoomID, "!a")
        h.inbox.select(nil)
        h.inbox.selectPrevious()
        XCTAssertEqual(h.inbox.selectedRoomID, "!c")

        h.inbox.select("!a")
        h.inbox.selectNext()
        XCTAssertEqual(h.inbox.selectedRoomID, "!b")
        h.inbox.selectNext()
        XCTAssertEqual(h.inbox.selectedRoomID, "!c")
        h.inbox.selectNext()
        XCTAssertEqual(h.inbox.selectedRoomID, "!c", "the list does not wrap")
        h.inbox.selectPrevious()
        XCTAssertEqual(h.inbox.selectedRoomID, "!b")
        await stop(h)
    }

    func testNextUnreadWraps() async throws {
        let h = try await start(rooms: [
            room("!a", ts: 500), room("!b", ts: 400, unread: 3), room("!c", ts: 300),
            room("!d", ts: 200, unread: 1), room("!e", ts: 100),
        ], autoRelease: true)
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!b", "from nothing, the first unread chat")
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!d")
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!b", "after the last, back to the first")

        // From a read chat below the last unread one it wraps too.
        h.inbox.select("!e")
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!b")

        // Only the open chat is unread: nowhere else to go.
        h.script.rooms = [room("!a", ts: 500), room("!b", ts: 400, unread: 3)]
        h.server.notify(["kind": "room"])
        try await waitUntil { h.inbox.rows.count == 2 }
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!b")

        // Nothing unread: nothing moves.
        h.script.rooms = [room("!a", ts: 500), room("!b", ts: 400)]
        h.server.notify(["kind": "room"])
        try await waitUntil { h.inbox.rows.allSatisfy { $0.unread == 0 } }
        h.inbox.select("!a")
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!a")
        await stop(h)
    }

    /// A chat marked unread, or one whose reminder fired (the engine marks it unread), is unread to ⌘U as it is to
    /// the list's bold name and the Unread filter.
    func testNextUnreadStopsAtChatsMarkedUnread() async throws {
        let h = try await start(rooms: [
            room("!a", ts: 500), room("!marked", ts: 400, markedUnread: true), room("!c", ts: 300),
            room("!unread", ts: 200, unread: 2), room("!e", ts: 100),
        ], autoRelease: true)
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!marked")
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!unread")
        h.inbox.selectNextUnread()
        XCTAssertEqual(h.inbox.selectedRoomID, "!marked", "after the last, back to the first")
        await stop(h)
    }

    // MARK: - Pages

    func testFirstPageThenLoadMore() async throws {
        let h = try await start(rooms: manyRooms(250), autoRelease: true)
        XCTAssertEqual(h.inbox.rows.count, InboxModel.pageSize)
        XCTAssertTrue(h.inbox.hasMore)
        let first = try XCTUnwrap(h.server.receivedParams("inbox.list").first)
        XCTAssertEqual(first as NSDictionary, ["limit": 200] as NSDictionary,
                       "the first page of the inbox, All, newest: no space, no filters, no sort, no cursor")

        await h.inbox.loadMore()
        XCTAssertEqual(h.inbox.rows.map(\.roomID), manyRooms(250).map { $0["room_id"] as! String })
        XCTAssertFalse(h.inbox.hasMore, "next_cursor was null")
        let second = try XCTUnwrap(h.server.receivedParams("inbox.list").last)
        XCTAssertEqual(second["cursor"] as? String, "o:200", "the first page's next_cursor")
        XCTAssertEqual(second["limit"] as? Int, 200)

        // Nothing more to read: nothing is asked.
        await h.inbox.loadMore()
        XCTAssertEqual(h.count("inbox.list"), 2)
        await stop(h)
    }

    /// A page may end early (before 1 MiB) with a cursor: only a null cursor is the last page.
    func testAShortPageIsNotTheLastPage() async throws {
        let h = try await start(rooms: manyRooms(300), autoRelease: true)
        XCTAssertEqual(h.inbox.rows.count, 200)
        h.script.pageCap = 150
        h.inbox.handle(.room(roomID: "!r1"))
        try await waitUntil { h.count("inbox.list") == 3 }
        // The refresh asked for the 200 shown and got 150 and a cursor: it reads on for the other 50.
        let refresh = Array(h.server.receivedParams("inbox.list").dropFirst())
        XCTAssertEqual(refresh.map { $0["limit"] as? Int }, [200, 50])
        XCTAssertEqual(refresh.map { $0["cursor"] as? String }, [nil, "o:150"])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("inbox.list"), 3)
        XCTAssertEqual(h.inbox.rows.count, 200)
        XCTAssertTrue(h.inbox.hasMore, "the page ended early, and its cursor says there is more")

        await h.inbox.loadMore()
        XCTAssertEqual(h.server.receivedParams("inbox.list").last?["cursor"] as? String, "o:200")
        XCTAssertEqual(h.inbox.rows.count, 300)
        XCTAssertFalse(h.inbox.hasMore)
        await stop(h)
    }

    func testChangingQueryResetsToFirstPage() async throws {
        let h = try await start(rooms: manyRooms(250), autoRelease: true)
        await h.inbox.loadMore()
        XCTAssertEqual(h.server.receivedParams("inbox.list").last?["cursor"] as? String, "o:200")
        XCTAssertEqual(h.inbox.rows.count, 250)

        h.inbox.query.filters = [.unread]
        try await waitUntil { h.count("inbox.list") == 3 }
        let reset = try XCTUnwrap(h.server.receivedParams("inbox.list").last)
        XCTAssertEqual(reset as NSDictionary, ["filters": ["unread"], "limit": 200] as NSDictionary,
                       "the first page of the new query: no old cursor, and as many as a page, not as many as shown")
        try await waitUntil { h.inbox.rows.count == 200 }
        XCTAssertTrue(h.inbox.hasMore)

        // Space, filters and sort as the wire has them; filters in protocol.json's order.
        h.inbox.query = InboxQuery(space: "account:whatsapp", filters: [.dms, .unread], sort: .oldest)
        try await waitUntil { h.count("inbox.list") == 4 }
        XCTAssertEqual(h.server.receivedParams("inbox.list").last as NSDictionary?, [
            "space": "account:whatsapp", "filters": ["unread", "dms"], "sort": "oldest", "limit": 200,
        ] as NSDictionary)

        // All is no filter at all, never "all".
        h.inbox.query = InboxQuery()
        try await waitUntil { h.count("inbox.list") == 5 }
        XCTAssertEqual(h.server.receivedParams("inbox.list").last as NSDictionary?, ["limit": 200] as NSDictionary)

        // The same query again reads nothing.
        h.inbox.query = InboxQuery()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("inbox.list"), 5)
        await stop(h)
    }

    func testRefreshReReadsAsManyRowsAsShown() async throws {
        let h = try await start(rooms: manyRooms(700), autoRelease: true)
        for _ in 0 ..< 3 { await h.inbox.loadMore() }
        XCTAssertEqual(h.inbox.rows.count, 700)
        XCTAssertFalse(h.inbox.hasMore)
        let before = h.count("inbox.list")
        XCTAssertEqual(before, 4)

        h.server.notify(["kind": "room", "room_id": "!r3"])
        try await waitUntil { h.count("inbox.list") == before + 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        let refresh = Array(h.server.receivedParams("inbox.list").dropFirst(before))
        XCTAssertEqual(refresh.count, 2, "700 shown: one page of 500 and one of 200")
        XCTAssertEqual(refresh.map { $0["limit"] as? Int }, [500, 200])
        XCTAssertEqual(refresh.map { $0["cursor"] as? String }, [nil, "o:500"], "from the top")
        XCTAssertEqual(h.inbox.rows.count, 700)
        await stop(h)
    }

    func testRowsAreUniqueAcrossPagesWhenAChatMovesUp() async throws {
        let rooms = manyRooms(250)
        let h = try await start(rooms: rooms, autoRelease: true)
        XCTAssertEqual(h.inbox.rows.count, 200)

        // A chat further down gets a message and moves to the top before the next page is read: every chat after
        // it moves down one, so the next page starts with the last chat of the first.
        var moved = rooms
        let chat = moved.remove(at: 240)
        h.script.rooms = [chat] + moved
        await h.inbox.loadMore()

        let ids = h.inbox.rows.map(\.roomID)
        XCTAssertEqual(Set(ids).count, ids.count, "no chat is listed twice")
        XCTAssertEqual(ids.prefix(200), rooms.prefix(200).map { $0["room_id"] as! String }[...],
                       "the first copy is kept")
        XCTAssertEqual(ids.count, 249, "the later page's copy of r199 is dropped")
        await stop(h)
    }

    // MARK: - Filters

    func testCycleFilterOrder() async throws {
        let h = try await start(rooms: [room("!a", ts: 100)], autoRelease: true)
        XCTAssertEqual(h.inbox.query.filters, [])
        var seen: [Set<InboxFilter>] = []
        for _ in 0 ..< 7 {
            h.inbox.cycleFilter()
            seen.append(h.inbox.query.filters)
        }
        XCTAssertEqual(seen, [[.unread], [.drafts], [.unanswered], [.dms], [.groups], [], [.unread]])

        // From filters the cycle doesn't have, it starts again at Unread.
        h.inbox.query.filters = [.muted, .dms]
        h.inbox.cycleFilter()
        XCTAssertEqual(h.inbox.query.filters, [.unread])

        // ⌘⇧Y: Unread on and off, the other filters as they were.
        h.inbox.query.filters = [.dms]
        h.inbox.toggleUnreadFilter()
        XCTAssertEqual(h.inbox.query.filters, [.dms, .unread])
        h.inbox.toggleUnreadFilter()
        XCTAssertEqual(h.inbox.query.filters, [.dms])
        await stop(h)
    }

    // MARK: - Reading and muting

    /// C22: the one "After marking the open chat read or unread" rule, which Mark as Unread from a message uses too:
    /// worked out from the list when asked, done when called.
    func testPlanAfterToggleReadIsTheSettingsRule() async throws {
        let h = try await start(rooms: [room("!a", ts: 300), room("!b", ts: 200), room("!c", ts: 100)],
                                autoRelease: true)
        h.inbox.select("!b")
        h.preferences.afterToggleRead = .selectNext
        let next = h.inbox.planAfterToggleRead()
        XCTAssertEqual(h.inbox.selectedRoomID, "!b", "nothing moves until it is done")
        next()
        XCTAssertEqual(h.inbox.selectedRoomID, "!c")
        h.preferences.afterToggleRead = .selectPrevious
        h.inbox.planAfterToggleRead()()
        XCTAssertEqual(h.inbox.selectedRoomID, "!b")
        h.preferences.afterToggleRead = .closeChat
        h.inbox.planAfterToggleRead()()
        XCTAssertNil(h.inbox.selectedRoomID)
        h.inbox.select("!c")
        h.preferences.afterToggleRead = .selectNext
        h.inbox.planAfterToggleRead()()
        XCTAssertEqual(h.inbox.selectedRoomID, "!c", "nothing after the last: it stays")
        h.preferences.afterToggleRead = .nothing
        h.inbox.planAfterToggleRead()()
        XCTAssertEqual(h.inbox.selectedRoomID, "!c")
        await stop(h)
    }

    func testToggleReadMarksUnreadWhenRead() async throws {
        let h = try await start(rooms: [
            room("!read", ts: 300), room("!unread", ts: 200, unread: 2), room("!marked", ts: 100, markedUnread: true),
        ], autoRelease: true)
        h.preferences.afterToggleRead = .nothing

        h.inbox.select("!read")
        XCTAssertTrue(h.inbox.canToggleRead)
        await h.inbox.toggleRead()
        h.inbox.select("!unread")
        await h.inbox.toggleRead()
        h.inbox.select("!marked")
        await h.inbox.toggleRead()

        XCTAssertEqual(dicts(h.server.receivedParams("room.setMarkedUnread")),
                       dicts([["room_ids": ["!read"], "on": true]]), "a read chat is marked unread, on this Mac")
        XCTAssertEqual(h.server.receivedParams("room.markRead").map { $0["room_id"] as? String }, ["!unread", "!marked"],
                       "an unread or marked-unread chat is marked read")
        try await waitUntil { h.inbox.rows.first { $0.roomID == "!read" }?.markedUnread == true }
        XCTAssertEqual(h.inbox.selectedRoomID, "!marked", "afterToggleRead nothing: the chat stays open")
        await stop(h)
    }

    func testToggleReadDoesNothingWithNothingOpen() async throws {
        let h = try await start(rooms: [room("!a", ts: 200), room("!b", ts: 100, unread: 1)])
        XCTAssertFalse(h.inbox.canToggleRead)
        await h.inbox.toggleRead()
        XCTAssertEqual(h.count("room.markRead") + h.count("room.setMarkedUnread"), 0)
        await stop(h)
    }

    func testToggleMuteSetsTheOppositeOfTheRow() async throws {
        let h = try await start(rooms: [room("!a", ts: 200), room("!b", ts: 100, muted: true)], autoRelease: true)
        await h.inbox.toggleMute() // nothing open: nothing happens
        XCTAssertEqual(h.count("room.setMuted"), 0)

        h.inbox.select("!a")
        XCTAssertFalse(h.inbox.selectedRowIsMuted)
        await h.inbox.toggleMute()
        h.inbox.select("!b")
        XCTAssertTrue(h.inbox.selectedRowIsMuted)
        await h.inbox.toggleMute()

        let calls = h.server.receivedParams("room.setMuted")
        XCTAssertEqual(calls.map { $0["room_id"] as? String }, ["!a", "!b"])
        XCTAssertEqual(calls.map { $0["muted"] as? Bool }, [true, false])
        await stop(h)
    }

    // MARK: - Archive and undo

    func testAfterArchiveSelectsNextByDefault() async throws {
        let h = try await start(rooms: [room("!a", ts: 300), room("!b", ts: 200), room("!c", ts: 100)],
                                autoRelease: true)
        XCTAssertEqual(h.preferences.afterArchive, .selectNext)
        h.inbox.select("!b")
        await h.inbox.archive(true)
        XCTAssertEqual(dicts(h.server.receivedParams("room.setArchived")),
                       dicts([["room_ids": ["!b"], "archived": true]]), "mark_read only when the setting is on")
        XCTAssertEqual(h.inbox.selectedRoomID, "!c", "the next chat opens")
        XCTAssertEqual(h.inbox.toast?.message, "Archived 1 chat")
        XCTAssertEqual(h.inbox.toast?.canUndo, true)
        try await waitUntil { h.inbox.rows.count == 2 }

        // The last chat has no next: the one before it opens. And Mark as read on archive sends mark_read.
        h.preferences.markReadOnArchive = true
        await h.inbox.archive(true)
        XCTAssertEqual(h.server.receivedParams("room.setArchived").last as NSDictionary?,
                       ["room_ids": ["!c"], "archived": true, "mark_read": true] as NSDictionary)
        XCTAssertEqual(h.inbox.selectedRoomID, "!a")
        try await waitUntil { h.inbox.rows.count == 1 }

        // Close the chat.
        h.preferences.afterArchive = .closeChat
        await h.inbox.archive(true)
        XCTAssertNil(h.inbox.selectedRoomID)
        await stop(h)
    }

    func testArchivePinnedSaysWhy() async throws {
        let h = try await start(rooms: [room("!pinned", ts: 300, pinned: true), room("!b", ts: 200)], autoRelease: true)
        h.inbox.select("!pinned")
        await h.inbox.archive(true)
        XCTAssertEqual(h.count("room.setArchived"), 1)
        XCTAssertEqual(h.inbox.toast?.message, "Unpin a chat to archive it.")
        XCTAssertEqual(h.inbox.toast?.canUndo, false)
        XCTAssertEqual(h.inbox.selectedRoomID, "!pinned", "nothing moved, so the chat stays open")
        await stop(h)
    }

    /// Review Focus 4: "Archive all read" on 3,000 chats, then Undo, unarchives those 3,000, in calls of at most
    /// 500. It leaves alone the chats that were archived before, and a chat a new message already brought back.
    func testUndoUnarchivesOnlyWhatThatActionArchived() async throws {
        let read = (0 ..< 3000).map { room("!read-\($0)", ts: Int64(10_000 - $0)) }
        let unread = (0 ..< 5).map { room("!unread-\($0)", ts: 20_000 + Int64($0), unread: 1) }
        let pinned = (0 ..< 2).map { room("!pin-\($0)", ts: 30_000 + Int64($0), pinned: true) }
        let h = try await start(rooms: pinned + unread + read, autoRelease: true)
        let before = (0 ..< 4).map { room("!before-\($0)", ts: 5, archived: true) }
        h.script.archivedRooms = before

        let archived = await h.inbox.archiveAllRead()
        XCTAssertEqual(archived, 3000)
        XCTAssertEqual(dicts(h.server.receivedParams("inbox.archiveMatching")),
                       dicts([["read_only": true, "older_than_ms": 0, "dry_run": false]]), "the inbox space, any age")
        XCTAssertEqual(h.inbox.toast?.message, "Archived \(3000.formatted()) chats", "the count as the Mac writes numbers")
        XCTAssertEqual(h.inbox.toast?.canUndo, true)

        // A new message brings one of them back before Undo.
        h.script.bringBack("!read-7")
        await h.inbox.undo()
        XCTAssertNil(h.inbox.toast)

        let calls = h.server.receivedParams("room.setArchived")
        XCTAssertTrue(calls.allSatisfy { $0["archived"] as? Bool == false })
        XCTAssertTrue(calls.allSatisfy { ($0["room_ids"] as? [String])?.count ?? 0 <= 500 }, "at most 500 a call")
        XCTAssertEqual(calls.count, 6)
        XCTAssertEqual(calls.flatMap { $0["room_ids"] as? [String] ?? [] }, read.map { $0["room_id"] as! String },
                       "exactly the chats it archived")
        XCTAssertEqual(h.script.archivedRooms.map { $0["room_id"] as! String }, before.map { $0["room_id"] as! String },
                       "the chats archived before stay archived")
        XCTAssertTrue(h.script.rooms.contains { $0["room_id"] as? String == "!read-7" })
        await stop(h)
    }

    func testToastGoesAfterSixSecondsOrOnTheNextAction() async throws {
        let h = try await start(rooms: [room("!a", ts: 300), room("!b", ts: 200), room("!c", ts: 100)],
                                autoRelease: true)
        h.preferences.afterArchive = .nothing
        h.inbox.select("!a")
        await h.inbox.archive(true)
        XCTAssertNotNil(h.inbox.toast)
        try await waitUntil { await h.toastSleeps.waiting == 1 }
        let waits = await h.toastSleeps.durations
        XCTAssertEqual(waits, [6])
        await h.toastSleeps.releaseAll()
        try await waitUntil { h.inbox.toast == nil }

        h.inbox.select("!b")
        await h.inbox.archive(true)
        XCTAssertNotNil(h.inbox.toast)
        await h.inbox.togglePin()
        XCTAssertNil(h.inbox.toast, "the next action takes it down")
        await h.inbox.undo()
        XCTAssertEqual(h.server.receivedParams("room.setArchived").filter { $0["archived"] as? Bool == false }.count, 0,
                       "Undo does nothing once the toast is gone")
        await stop(h)
    }

    func testReminderArchivesWhenAskedAndUndoPutsItBack() async throws {
        let h = try await start(rooms: [room("!a", ts: 300), room("!b", ts: 200)], autoRelease: true)
        h.preferences.archiveAfterReminder = true
        h.preferences.afterArchive = .nothing
        h.inbox.select("!a")
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        await h.inbox.remind(at: due, condition: .ifNoReply)
        XCTAssertEqual(dicts(h.server.receivedParams("reminder.set")), dicts([[
            "room_ids": ["!a"], "due_at": 1_900_000_000_000, "condition": "if_no_reply", "archive": true,
        ]]))
        XCTAssertEqual(h.preferences.lastUsedReminder, due)
        XCTAssertEqual(h.inbox.toast?.message,
                       "Reminder set for \(due.formatted(date: .abbreviated, time: .shortened))")

        // !a had no reminder and was not archived: Undo ends the reminder and brings it back.
        await h.inbox.undo()
        XCTAssertEqual(dicts(h.server.receivedParams("reminder.clear")), dicts([["room_ids": ["!a"]]]))
        XCTAssertEqual(dicts(h.server.receivedParams("room.setArchived")),
                       dicts([["room_ids": ["!a"], "archived": false]]))

        // Without the setting, no archive is asked for.
        h.preferences.archiveAfterReminder = false
        await h.inbox.remind(at: due, condition: .always)
        XCTAssertEqual(h.server.receivedParams("reminder.set").last as NSDictionary?,
                       ["room_ids": ["!a"], "due_at": 1_900_000_000_000, "condition": "always"] as NSDictionary)
        await stop(h)
    }

    // MARK: - Drafts

    func testDraftSavedAfterOneSecondAndOnSwitch() async throws {
        let h = try await start(rooms: [room("!a", ts: 200), room("!b", ts: 100, draft: "kept on this Mac")],
                                autoRelease: true)
        let sleeps = SleepControl()
        let composer = ComposerModel(sender: EngineMessageSender(appModel: h.app), sleep: { await sleeps.sleep($0) })
        composer.savedDraft = { [inbox = h.inbox] id in inbox.rows.first { $0.roomID == id }?.draft }

        composer.open("!a")
        composer.text = "Hel"
        composer.text = "Hello"
        try await waitUntil { await sleeps.waiting == 2 }
        XCTAssertEqual(h.count("room.setDraft"), 0, "nothing is saved while typing")
        let waits = await sleeps.durations
        XCTAssertEqual(waits, [1, 1])
        await sleeps.releaseAll()
        try await waitUntil { h.count("room.setDraft") == 1 }
        XCTAssertEqual(dicts(h.server.receivedParams("room.setDraft")),
                       dicts([["room_id": "!a", "text": "Hello"]]), "once, a second after typing stopped")

        // Switching chats saves at once.
        composer.text = "Hello there"
        composer.open("!b")
        try await waitUntil { h.count("room.setDraft") == 2 }
        XCTAssertEqual(h.server.receivedParams("room.setDraft").last as NSDictionary?,
                       ["room_id": "!a", "text": "Hello there"] as NSDictionary)
        // A chat with no draft in memory takes the engine's.
        XCTAssertEqual(composer.text, "kept on this Mac")

        // The wait that switching overtook saves nothing more, and the engine's own draft is not sent back.
        await sleeps.releaseAll()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.setDraft"), 2)

        // Going back to !a finds its draft in memory.
        composer.open("!a")
        XCTAssertEqual(composer.text, "Hello there")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.setDraft"), 2, "opening a chat saves nothing it didn't change")
        await stop(h)
    }

    /// A chat opened from outside the rows loaded (a notification, from another space or past the pages read):
    /// its draft is looked up by id and shown, and nothing typed before it arrives saves over it.
    func testAChatOpenedFromOutsideTheListKeepsItsSavedDraft() async throws {
        let h = try await start(rooms: [room("!a", ts: 300)], autoRelease: true)
        h.script.archivedRooms = [
            room("!far", ts: 100, archived: true, draft: "engine words"),
            room("!far2", ts: 90, archived: true, draft: "kept"),
            room("!far3", ts: 80, archived: true, draft: "never seen"),
        ]
        let sleeps = SleepControl()
        let composer = ComposerModel(sender: EngineMessageSender(appModel: h.app), sleep: { await sleeps.sleep($0) })
        composer.savedDraft = { [inbox = h.inbox] id in inbox.rows.first { $0.roomID == id }?.draft }
        composer.lookUpDraft = { [inbox = h.inbox] id in await inbox.lookUpDraft(id) }

        // The lookup is slow. The person types before it answers: nothing is saved, not even once a second goes by.
        h.script.holdInbox = true
        composer.open("!far")
        XCTAssertEqual(composer.text, "")
        try await waitUntil { h.server.receivedParams("inbox.list").contains { $0["room_ids"] as? [String] == ["!far"] } }
        composer.text = "x"
        try await Task.sleep(nanoseconds: 100_000_000)
        let waiting = await sleeps.waiting
        XCTAssertEqual(waiting, 0, "no save is even scheduled while the engine's draft is unknown")
        XCTAssertEqual(h.count("room.setDraft"), 0)

        // The answer comes: the engine's draft is shown, with what was typed after it, and only then saved.
        h.script.holdInbox = false
        h.server.releaseHeld(with: page([room("!far", ts: 100, archived: true, draft: "engine words")]))
        try await waitUntil { composer.text == "engine words\n\nx" }
        try await waitUntil { await sleeps.waiting == 1 }
        await sleeps.releaseAll()
        try await waitUntil { h.count("room.setDraft") == 1 }
        XCTAssertEqual(dicts(h.server.receivedParams("room.setDraft")),
                       dicts([["room_id": "!far", "text": "engine words\n\nx"]]), "the engine's words are never lost")

        // Untouched, a looked-up draft is just shown, and not saved back.
        composer.open("!far2")
        try await waitUntil { composer.text == "kept" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.setDraft"), 1, "leaving !far had nothing new to save, and !far2's is not sent back")

        // A lookup that fails leaves the draft unknown: typing and leaving the chat save nothing over it.
        h.script.fail("inbox.list", code: -32603)
        composer.open("!far3")
        try await waitUntil { h.server.receivedParams("inbox.list").contains { $0["room_ids"] as? [String] == ["!far3"] } }
        try await Task.sleep(nanoseconds: 100_000_000)
        composer.text = "y"
        composer.open("!a")
        try await Task.sleep(nanoseconds: 100_000_000)
        let calls = h.server.receivedParams("room.setDraft")
        XCTAssertFalse(calls.contains { $0["room_id"] as? String == "!far3" }, "the unseen draft is not overwritten")
        await stop(h)
    }

    /// Ruling 35: a chat opened from outside the list (a search result in the archive, say) is looked up once by id,
    /// and that row is the open chat's until another opens: the header's name, the unread count for the "New"
    /// divider and the draft come from it.
    func testAChatOpenedFromOutsideTheListHasItsRow() async throws {
        let h = try await start(rooms: [room("!a", ts: 300)], autoRelease: true)
        h.script.archivedRooms = [
            room("!arch", ts: 100, unread: 3, name: "Archived chat", archived: true, draft: "kept words"),
            room("!arch2", ts: 90, archived: true, draft: "other words"),
        ]
        var lookups: [[String: Any]] { h.server.receivedParams("inbox.list").filter { $0["room_ids"] != nil } }
        var looked: [String: Any]?
        h.inbox.onSelectedRowLookedUp = { looked = ["room_id": $0.roomID, "unread": $0.unread] }

        h.inbox.select("!arch")
        try await waitUntil { h.inbox.selectedRow?.roomID == "!arch" }
        XCTAssertEqual(dicts(lookups), dicts([["room_ids": ["!arch"]]]), "one lookup, by id")
        XCTAssertEqual(h.inbox.selectedRow?.name, "Archived chat", "what the header shows")
        XCTAssertEqual(h.inbox.unreadCount(of: "!arch"), 3)
        XCTAssertEqual(h.inbox.savedDraft(of: "!arch"), "kept words")
        let draft = await h.inbox.lookUpDraft("!arch")
        XCTAssertEqual(draft, "kept words")
        XCTAssertEqual(lookups.count, 1, "the draft comes from the row looked up, not from a second lookup")
        XCTAssertEqual(looked as NSDictionary?, ["room_id": "!arch", "unread": 3] as NSDictionary)

        // A draft asked for while the lookup is still out waits for that same answer.
        h.script.holdInbox = true
        h.inbox.select("!arch2")
        XCTAssertNil(h.inbox.selectedRow, "not known yet")
        let draft2 = Task { await h.inbox.lookUpDraft("!arch2") }
        try await waitUntil { lookups.count == 2 }
        try await Task.sleep(nanoseconds: 50_000_000)
        h.script.holdInbox = false
        h.server.releaseHeld(with: page([room("!arch2", ts: 90, archived: true, draft: "other words")]))
        let second = await draft2.value
        XCTAssertEqual(second, "other words")
        try await waitUntil { h.inbox.selectedRow?.roomID == "!arch2" }
        XCTAssertEqual(lookups.count, 2)
        XCTAssertNil(h.inbox.savedDraft(of: "!arch"), "the row of the chat left behind is let go")
        XCTAssertEqual(h.inbox.unreadCount(of: "!arch"), 0)

        // A chat in the list is never looked up.
        h.inbox.select("!a")
        XCTAssertEqual(h.inbox.selectedRow?.roomID, "!a")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(lookups.count, 2)
        await stop(h)
    }

    // MARK: - Notifications

    /// Ruling 2: a chat the inbox hasn't listed is looked up by its id, not by reading the whole inbox (which
    /// pages now, so the chat may not be on the first page).
    func testNotificationLookupUsesRoomIDs() async throws {
        let h = try await start(rooms: [room("!a", ts: 100)], autoRelease: true)
        let delivery = FakeDelivery()
        let coordinator = NotificationCoordinator(
            appModel: h.app, delivery: delivery, row: { [inbox = h.inbox] id in inbox.rows.first { $0.roomID == id } },
            isLooking: { false }, restoreDraft: { _, _, _ in }, showWindow: {}, preferences: h.preferences, window: 0.01)
        _ = coordinator
        let reads = h.count("inbox.list")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        h.script.archivedRooms = [room("!new", ts: now, name: "New Chat", archived: true)]
        h.script.events["!new"] = [message("$1", ts: now, text: "first words", room: "!new")]
        h.server.notify(["kind": "event", "room_id": "!new", "event_id": "$1"])
        try await waitUntil { delivery.delivered.count == 1 }
        XCTAssertEqual(delivery.delivered[0].title, "New Chat")

        let lookups = Array(h.server.receivedParams("inbox.list").dropFirst(reads)).filter { $0["room_ids"] != nil }
        XCTAssertEqual(dicts(lookups), dicts([["room_ids": ["!new"]]]), "room_ids alone, as the wire has it")
        await stop(h)
    }

    // MARK: - Coalescing

    func testChangeTriggersSingleRefetch() async throws {
        let h = try await start(rooms: [room("!a", ts: 100)])
        let before = h.count("inbox.list")
        XCTAssertEqual(before, 1)
        h.script.rooms = [room("!a", ts: 100), room("!b", ts: 200)]

        // 50 changes inside the window: one read, once the window is over.
        for index in 0 ..< 50 { h.inbox.handle(.event(roomID: "!b", eventID: "$\(index)")) }
        try await waitUntil { await h.sleeps.waiting == 1 }
        XCTAssertEqual(h.count("inbox.list"), before, "nothing is read while the window is open")
        await h.sleeps.releaseAll()
        try await waitUntil { h.inbox.rows.count == 2 }
        XCTAssertEqual(h.count("inbox.list"), before + 1)
        await stop(h)
    }

    /// Ruling 6: a spaces change (a label or an account muted or renamed) changes many rows' muted_by with no room
    /// change, so it reads the rows again; typing and a reminder change a row too.
    func testSpacesTypingAndReminderChangesReadTheRowsAgain() async throws {
        let h = try await start(rooms: [room("!a", ts: 100)], autoRelease: true)
        for params: [String: Any] in [
            ["kind": "spaces"], ["kind": "typing", "room_id": "!a"], ["kind": "reminder", "room_id": "!a"],
        ] {
            let reads = h.count("inbox.list")
            h.server.notify(params)
            try await waitUntil { h.count("inbox.list") == reads + 1 }
        }
        await stop(h)
    }

    func testBurstDuringARunningReadQueuesOneMore() async throws {
        let h = try await start(rooms: [room("!a", ts: 100)])
        let before = h.count("inbox.list")
        h.script.holdInbox = true

        for index in 0 ..< 50 { h.inbox.handle(.event(roomID: "!a", eventID: "$\(index)")) }
        try await waitUntil { await h.sleeps.waiting == 1 }
        await h.sleeps.releaseAlways() // this window, and every later one
        try await waitUntil { h.count("inbox.list") == before + 1 }

        // The read is in flight and slow. 50 more changes ask for one more read, not 50.
        for index in 0 ..< 50 { h.inbox.handle(.status(roomID: "!a", eventID: "$\(index)")) }
        h.script.holdInbox = false
        h.script.rooms = [room("!a", ts: 100), room("!b", ts: 200)]
        h.server.releaseHeld(with: page([room("!a", ts: 100)]))

        try await waitUntil { h.inbox.rows.count == 2 }
        XCTAssertEqual(h.count("inbox.list"), before + 2, "one in flight and one queued")
        // And then it is quiet.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("inbox.list"), before + 2)
        await stop(h)
    }

    func testAFailedReadIsTriedAgainAfterTwoSeconds() async throws {
        // The first read fails (the engine did not answer); nothing else changes, so only a retry can fill the list.
        let h = try await start(rooms: [room("!a", ts: 100)], autoRelease: true, failFirstReads: 2)
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!a"])
        XCTAssertEqual(h.count("inbox.list"), 3, "two failures and then the read that worked")
        let waits = await h.sleeps.durations
        XCTAssertEqual(waits, [2, 2], "each retry waits two seconds")
        await stop(h)
    }

    func testResyncRefetchesEverything() async throws {
        let h = try await start(rooms: [room("!a", ts: 100)], accounts: [account("whatsapp", "CONNECTING")])
        XCTAssertEqual(h.count("inbox.list"), 1)
        XCTAssertEqual(h.count("accounts.list"), 1)
        h.script.rooms = [room("!a", ts: 100), room("!b", ts: 200)]
        h.script.accounts = [account("whatsapp", "CONNECTED")]

        h.server.notify(["kind": "resync"])
        try await waitUntil { h.inbox.rows.count == 2 && h.app.accounts.first?.state == .connected }
        XCTAssertEqual(h.count("inbox.list"), 2, "once, not once for the model and once for the resync")
        XCTAssertEqual(h.count("accounts.list"), 2)
        // The resync does not wait for the window.
        let waiting = await h.sleeps.waiting
        XCTAssertEqual(waiting, 0)
        await stop(h)
    }

    func testOnlyChangesTheInboxShowsRefetchIt() async throws {
        let h = try await start(rooms: [room("!a", ts: 100)], autoRelease: true)
        let before = h.count("inbox.list")

        for kind in ["room", "event", "status", "read"] {
            let reads = h.count("inbox.list")
            h.server.notify(["kind": kind, "room_id": "!a", "event_id": "$1"])
            try await waitUntil { h.count("inbox.list") == reads + 1 }
        }
        XCTAssertEqual(h.count("inbox.list"), before + 4)

        // An account changed state: the accounts are read again, the inbox is not.
        h.script.accounts = [account("whatsapp", "LOGGED_OUT")]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.app.accounts.first?.state == .loggedOut }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("inbox.list"), before + 4)
        XCTAssertEqual(h.count("accounts.list"), 2)
        await stop(h)
    }

    // MARK: - A reconnect

    func testAReplyFromAnEngineThatIsGoneIsDropped() async throws {
        let first = InboxScript(rooms: [room("!old", ts: 100)], accounts: [account("whatsapp", "CONNECTED")])
        let second = InboxScript(rooms: [room("!new", ts: 200)], accounts: [account("whatsapp", "CONNECTED")])
        let firstServer = try TestEngineServer(handler: first.handle)
        let secondServer = try TestEngineServer(handler: second.handle)
        servers += [firstServer, secondServer]
        let launcher = FakeLauncher { index, process in
            process.printReady(socket: index == 0 ? firstServer.path : secondServer.path)
        }
        let supervisor = EngineSupervisor(
            enginePath: "/x/courier-engine", dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"),
            environment: [:], launcher: launcher, credentials: InMemoryCredentialStore(), clientName: "Courier/test",
            timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        let store = TestDefaults()
        defer { store.remove() }
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store.defaults), window: 0.1,
                               sleep: { _ in })
        app.start()
        try await waitUntil { inbox.rows.map(\.roomID) == ["!old"] }

        // The first engine is asked again and sits on the question; then it dies.
        first.holdInbox = true
        firstServer.notify(["kind": "room"])
        try await waitUntil { firstServer.receivedMethods().filter { $0 == "inbox.list" }.count == 2 }
        launcher.processes[0].exit(1)
        firstServer.dropConnections()

        try await waitUntil { inbox.rows.map(\.roomID) == ["!new"] }
        // The old engine's late answer has nowhere to go.
        firstServer.releaseHeld(with: page([room("!old", ts: 100)]))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(inbox.rows.map(\.roomID), ["!new"])
        await app.stop()
    }

    // MARK: - Accounts

    func testBannerForLoggedOutAccount() async throws {
        let h = try await start(accounts: [
            account("whatsapp", "LOGGED_OUT", error: "You were logged out"),
            account("signal", "BAD_CREDENTIALS"),
            account("telegram", "NOT_STARTED", notStarted: "Telegram needs an api_id and api_hash."),
            account("slack", "NOT_STARTED", notStarted: "The Slack bridge could not start."),
            account("gmessages", "UNKNOWN_ERROR", error: "The phone did not answer"),
        ])
        XCTAssertEqual(h.inbox.banners.map(\.network), ["whatsapp", "signal", "telegram", "slack", "gmessages"])

        let whatsapp = h.inbox.banners[0]
        XCTAssertEqual(whatsapp.reason, .loggedOut)
        XCTAssertEqual(whatsapp.action, .reconnect)
        XCTAssertEqual(whatsapp.displayName, "whatsapp display")
        XCTAssertEqual(whatsapp.detail, "You were logged out")
        XCTAssertEqual(h.inbox.banners[1].reason, .badCredentials)
        XCTAssertEqual(h.inbox.banners[1].action, .reconnect)

        // Not started: the engine's reason, and no button. Telegram has keys here (see the next test for
        // when it has none), so its not starting is a fault like Slack's.
        XCTAssertEqual(h.inbox.banners[2].reason, .notStarted)
        XCTAssertEqual(h.inbox.banners[2].detail, "Telegram needs an api_id and api_hash.")
        XCTAssertNil(h.inbox.banners[2].action)
        XCTAssertEqual(h.inbox.banners[3].detail, "The Slack bridge could not start.")
        XCTAssertNil(h.inbox.banners[3].action)

        // An error the bridge could not get past: its message, and Reconnect.
        XCTAssertEqual(h.inbox.banners[4].reason, .unknownError)
        XCTAssertEqual(h.inbox.banners[4].detail, "The phone did not answer")
        XCTAssertEqual(h.inbox.banners[4].action, .reconnect)

        // The buttons go to the closures Task 9 fills in.
        var reconnected: [String] = []
        h.inbox.onReconnect = { network, accountID in
            XCTAssertNil(accountID, "an account with no logins listed: the network's own sign-in")
            reconnected.append(network)
        }
        for banner in h.inbox.banners { h.inbox.perform(banner) }
        XCTAssertEqual(reconnected, ["whatsapp", "signal", "gmessages"])
        XCTAssertTrue(h.inbox.banners.allSatisfy { $0.accountID == nil && $0.accountName == nil })

        // Logging in again clears the banner.
        h.script.accounts = [account("whatsapp", "CONNECTED")]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.inbox.banners.isEmpty }
        await stop(h)
    }

    /// Telegram without an app ID is not started by design, and Add a network asks for the keys when it is
    /// picked: no banner, and in particular no "Set up" button.
    func testNoBannerForTelegramThatHasNoKeysYet() async throws {
        let h = try await start(accounts: [
            account("whatsapp", "LOGGED_OUT", error: "You were logged out"),
            account("telegram", "NOT_STARTED", notStarted: "Telegram needs an api_id and api_hash."),
            account("slack", "NOT_STARTED", notStarted: "The Slack bridge could not start."),
        ], hasTelegramCredentials: { false })
        XCTAssertEqual(h.inbox.banners.map(\.network), ["whatsapp", "slack"])
        XCTAssertFalse(h.inbox.banners.contains { $0.network == "telegram" })
        await stop(h)
    }

    /// The bundle and the Keychain are not read on every redraw: once per change of the accounts or the engine.
    /// And while the engine restarts after the keys were saved, the old "not started" is no banner.
    func testTelegramKeysAreAskedForOncePerChangeAndNoBannerWhileRestarting() async throws {
        final class Keys: @unchecked Sendable {
            var asked = 0
            var has = false
        }
        let keys = Keys()
        let h = try await start(accounts: [
            account("whatsapp", "CONNECTED"),
            account("telegram", "NOT_STARTED", notStarted: "Telegram needs an api_id and api_hash."),
        ], hasTelegramCredentials: { keys.asked += 1; return keys.has })
        for _ in 0 ..< 5 { XCTAssertEqual(h.inbox.banners.count, 0) }
        XCTAssertEqual(keys.asked, 1, "five redraws, one read")

        // The keys are saved: nothing has changed in the accounts, so no banner flickers up before the
        // restarted engine has been read.
        keys.has = true
        XCTAssertEqual(h.inbox.banners.count, 0)
        XCTAssertEqual(keys.asked, 1)

        // The accounts change (the new engine's list): asked again, and a Telegram that still did not start
        // with keys in hand is a fault with a banner.
        h.script.accounts = [
            account("whatsapp", "CONNECTED"),
            account("telegram", "NOT_STARTED", notStarted: "Telegram needs an api_id and api_hash."),
            account("slack", "CONNECTED"),
        ]
        h.server.notify(["kind": "bridge", "network": "slack"])
        try await waitUntil { h.inbox.accounts.count == 3 }
        XCTAssertEqual(h.inbox.banners.map(\.network), ["telegram"])
        XCTAssertEqual(keys.asked, 2)
        _ = h.inbox.banners
        XCTAssertEqual(keys.asked, 2)

        // While the engine is not up, the stale "not started" shows nothing.
        await stop(h)
        try await waitUntil { h.app.engineState != .connected }
        XCTAssertEqual(h.inbox.banners.count, 0)
    }

    /// The engine restarts to start Telegram with keys just saved. The new engine is connected at once, but its
    /// accounts.list has not answered: the list is still the old engine's, and its "Telegram not started" is no
    /// banner. Once the new list arrives, a Telegram that still did not start (with keys in hand) is one.
    func testNoStaleTelegramBannerBetweenReconnectAndTheNewAccountList() async throws {
        let notStarted = account("telegram", "NOT_STARTED", notStarted: "Telegram needs an api_id and api_hash.")
        let h = try await start(accounts: [account("whatsapp", "CONNECTED"), notStarted],
                                hasTelegramCredentials: { true })
        // The first engine had no keys when it started: its list says "not started", and with keys now in hand
        // that is already a fault the person can see.
        XCTAssertEqual(h.inbox.banners.map(\.network), ["telegram"])
        let firstConnection = try XCTUnwrap(h.app.connectedAt)
        XCTAssertNotNil(h.app.accountsReadAt)

        // The restart: the new engine connects, and its accounts.list is held.
        h.script.holdAccounts = true
        h.supervisor.restart()
        try await waitUntil { h.app.engineState == .connected && h.app.connectedAt != firstConnection }
        try await waitUntil { h.server.receivedMethods().filter { $0 == "accounts.list" }.count >= 2 }
        XCTAssertNil(h.app.accountsReadAt, "the new engine has not answered")
        XCTAssertEqual(h.app.accounts.first { $0.network == "telegram" }?.state, .notStarted,
                       "the list on screen is the old engine's")
        XCTAssertEqual(h.inbox.banners.count, 0, "so its 'not started' is no banner")

        // The new engine answers: Telegram is running, so still no banner...
        h.script.accounts = [account("whatsapp", "CONNECTED"), account("telegram", "UNCONFIGURED")]
        h.script.holdAccounts = false
        h.server.releaseHeld(method: "accounts.list", with: ["accounts": h.script.accounts])
        try await waitUntil { h.app.accountsReadAt != nil }
        XCTAssertEqual(h.inbox.banners.count, 0)

        // ...and one that still did not start is a fault with a banner, now that the list is the engine's own.
        h.script.accounts = [account("whatsapp", "CONNECTED"), notStarted]
        h.server.notify(["kind": "bridge", "network": "telegram"])
        try await waitUntil { h.app.accounts.first { $0.network == "telegram" }?.state == .notStarted }
        XCTAssertEqual(h.inbox.banners.map(\.network), ["telegram"])
        await stop(h)
    }

    func testReconnectingStatusPerAccount() async throws {
        let h = try await start(accounts: [
            account("whatsapp", "CONNECTING"),
            account("signal", "TRANSIENT_DISCONNECT"),
            account("telegram", "BRIDGE_UNREACHABLE"),
            account("slack", "CONNECTED"),
            account("gmessages", "UNCONFIGURED"),
        ])
        // One item per linked account; Google Messages was never linked.
        XCTAssertEqual(h.inbox.statusItems.map(\.network), ["whatsapp", "signal", "telegram", "slack"])
        XCTAssertEqual(h.inbox.statusItems.map(\.isReconnecting), [true, true, true, false])
        XCTAssertEqual(h.inbox.networkName("signal"), "signal display")
        XCTAssertEqual(h.inbox.networkName("a-network-added-later"), "a-network-added-later")

        h.script.accounts = [
            account("whatsapp", "CONNECTED"), account("signal", "TRANSIENT_DISCONNECT"),
            account("telegram", "LOGGED_OUT"), account("slack", "BACKFILLING"), account("gmessages", "UNCONFIGURED"),
        ]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.inbox.statusItems.first?.isReconnecting == false }
        XCTAssertEqual(h.inbox.statusItems.map(\.isReconnecting), [false, true, false, false],
                       "a logged out account is not reconnecting: its banner says what to do")

        // Two WhatsApp accounts: one item each, each with its own state, named, and with ids that differ.
        h.script.accounts = [
            account("whatsapp", "CONNECTING", logins: [login("a1", "+1 555 0101", "CONNECTING"),
                                                       login("b2", "+1 555 0102", "CONNECTED")]),
            account("signal", "CONNECTED", logins: [login("s1", "+1 555 0103", "CONNECTED")]),
        ]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.inbox.statusItems.count == 3 }
        XCTAssertEqual(h.inbox.statusItems.map(\.network), ["whatsapp", "whatsapp", "signal"])
        XCTAssertEqual(h.inbox.statusItems.map(\.accountID), ["a1", "b2", "s1"])
        XCTAssertEqual(h.inbox.statusItems.map(\.isReconnecting), [true, false, false])
        XCTAssertEqual(h.inbox.statusItems.map(\.accountName), ["+1 555 0101", "+1 555 0102", nil],
                       "named only where the network has more than one")
        XCTAssertEqual(Set(h.inbox.statusItems.map(\.id)).count, 3)
        XCTAssertEqual(h.inbox.linkedNetworks.map(\.network), ["whatsapp", "signal"],
                       "a filter by network lists each network once")
        await stop(h)
    }

    /// Review Focus 5: two WhatsApp accounts, one signed out. Its banner names it and Reconnect signs that one in
    /// again; the other keeps its own state, with no banner of its own.
    func testBannerNamesTheSignedOutAccountAndTheOtherStaysUsable() async throws {
        let h = try await start(accounts: [
            account("whatsapp", "LOGGED_OUT", error: "You were logged out", logins: [
                login("a1", "+1 555 0101", "LOGGED_OUT", error: "You were logged out"),
                login("b2", "+1 555 0102", "CONNECTED"),
            ]),
            account("signal", "BAD_CREDENTIALS", logins: [login("s1", "+1 555 0103", "BAD_CREDENTIALS")]),
        ])
        XCTAssertEqual(h.inbox.banners.map(\.network), ["whatsapp", "signal"], "one per account that needs the person")
        let whatsapp = h.inbox.banners[0]
        XCTAssertEqual(whatsapp.accountID, "a1")
        XCTAssertEqual(whatsapp.accountName, "+1 555 0101")
        XCTAssertEqual(whatsapp.reason, .loggedOut)
        XCTAssertEqual(whatsapp.detail, "You were logged out", "the bridge's words, as help only")
        XCTAssertEqual(whatsapp.titleName, "whatsapp display (+1 555 0101)")
        let signal = h.inbox.banners[1]
        XCTAssertEqual(signal.accountID, "s1", "Reconnect names the account even when it is the only one")
        XCTAssertNil(signal.accountName, "the only account: the network's name is enough")
        XCTAssertEqual(signal.titleName, "signal display")
        XCTAssertNotEqual(whatsapp.id, signal.id)

        var reconnected: [String] = []
        h.inbox.onReconnect = { network, accountID in reconnected.append("\(network) \(accountID ?? "-")") }
        for banner in h.inbox.banners { h.inbox.perform(banner) }
        XCTAssertEqual(reconnected, ["whatsapp a1", "signal s1"])

        // The other WhatsApp account is linked and working: its item says nothing is wrong, and the window
        // doesn't offer to add a network.
        let b2 = try XCTUnwrap(h.inbox.statusItems.first { $0.accountID == "b2" })
        XCTAssertFalse(b2.isReconnecting)
        XCTAssertFalse(b2.isStarting)
        XCTAssertFalse(h.inbox.showsAddNetwork)

        // Both WhatsApp accounts need the person: two banners for one network, told apart by account.
        h.script.accounts = [
            account("whatsapp", "LOGGED_OUT", logins: [login("a1", "+1 555 0101", "LOGGED_OUT"),
                                                       login("b2", "+1 555 0102", "UNKNOWN_ERROR", error: "x")]),
        ]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.inbox.banners.count == 2 && h.inbox.banners.allSatisfy { $0.network == "whatsapp" } }
        XCTAssertEqual(h.inbox.banners.map(\.accountID), ["a1", "b2"])
        XCTAssertEqual(h.inbox.banners.map(\.reason), [.loggedOut, .unknownError])
        XCTAssertNotEqual(h.inbox.banners[0].id, h.inbox.banners[1].id, "two banners of one network are two items")

        // The first signs in again: only the other's banner is left.
        h.script.accounts = [
            account("whatsapp", "UNKNOWN_ERROR", logins: [login("a1", "+1 555 0101", "CONNECTED"),
                                                          login("b2", "+1 555 0102", "UNKNOWN_ERROR", error: "x")]),
        ]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.inbox.banners.map(\.accountID) == ["b2"] }
        await stop(h)
    }

    /// While the engine starts a network (STARTING), there is no banner and no "Add a network": its accounts are
    /// still the ones it had, whatever their last state was.
    func testNoAddNetworkPromptWhileAccountsAreStarting() async throws {
        let h = try await start(accounts: [
            account("whatsapp", "STARTING", logins: [login("a1", "+1 555 0101", "LOGGED_OUT")]),
            account("telegram", "UNCONFIGURED"),
        ])
        XCTAssertEqual(h.inbox.banners, [], "no banner while starting, whatever was last known")
        XCTAssertFalse(h.inbox.showsAddNetwork)

        // Nothing is known to be linked, but a network is still starting: no prompt yet.
        h.script.accounts = [account("whatsapp", "STARTING"), account("signal", "STARTING"),
                             account("telegram", "UNCONFIGURED")]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.inbox.accounts.count == 3 }
        XCTAssertEqual(h.inbox.statusItems, [], "nothing linked that the engine knows of")
        XCTAssertFalse(h.inbox.showsAddNetwork, "an account may be about to come back")

        // Everything has started, and nothing is linked: now the window offers to add one.
        h.script.accounts = [account("whatsapp", "UNCONFIGURED"), account("signal", "UNCONFIGURED"),
                             account("telegram", "UNCONFIGURED")]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.inbox.showsAddNetwork }
        await stop(h)
    }

    /// A starting network's accounts show in the strip as starting (Task 10: "Starting…"), not as reconnecting; a
    /// starting network with no account it knows of shows nothing.
    func testStartingShowsInTheStatusStrip() async throws {
        let h = try await start(accounts: [
            account("whatsapp", "STARTING", logins: [login("a1", "+1 555 0101", "CONNECTED"),
                                                     login("b2", "+1 555 0102", "CONNECTED")]),
            account("signal", "CONNECTED", logins: [login("s1", "+1 555 0103", "CONNECTED")]),
            account("slack", "STARTING"),
        ])
        XCTAssertEqual(h.inbox.statusItems.map(\.accountID), ["a1", "b2", "s1"])
        XCTAssertEqual(h.inbox.statusItems.map(\.isStarting), [true, true, false])
        XCTAssertEqual(h.inbox.statusItems.map(\.isReconnecting), [false, false, false])

        h.script.accounts = [
            account("whatsapp", "CONNECTING", logins: [login("a1", "+1 555 0101", "CONNECTING"),
                                                       login("b2", "+1 555 0102", "CONNECTED")]),
            account("signal", "CONNECTED", logins: [login("s1", "+1 555 0103", "CONNECTED")]),
            account("slack", "UNCONFIGURED"),
        ]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { h.inbox.statusItems.first?.isStarting == false }
        XCTAssertEqual(h.inbox.statusItems.map(\.isReconnecting), [true, false, false])
        await stop(h)
    }

    func testEmptyStateWhenNoNetworkIsLinked() async throws {
        let h = try await start(accounts: [
            account("whatsapp", "UNCONFIGURED"), account("telegram", "NOT_STARTED", notStarted: "Needs a key."),
        ], hasTelegramCredentials: { false })
        XCTAssertTrue(h.inbox.showsAddNetwork)
        // Telegram has no keys here yet: no banner, and no Set up button. Add a network asks for them.
        XCTAssertEqual(h.inbox.banners.map(\.network), [])
        var added = 0
        h.inbox.onAddNetwork = { added += 1 }
        h.inbox.addNetwork()
        XCTAssertEqual(added, 1)

        h.script.accounts = [account("whatsapp", "CONNECTED"), account("telegram", "NOT_STARTED")]
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await waitUntil { !h.inbox.showsAddNetwork }
        await stop(h)
    }

    func testNoEmptyStateBeforeTheAccountsAreRead() {
        let supervisor = EngineSupervisor(
            enginePath: "/x", dataDir: URL(fileURLWithPath: "/tmp/x"), environment: [:],
            launcher: FakeLauncher { _, _ in }, credentials: InMemoryCredentialStore(), clientName: "Courier/test")
        let store = TestDefaults()
        defer { store.remove() }
        let inbox = InboxModel(appModel: AppModel(supervisor: supervisor),
                               preferences: InboxPreferences(defaults: store.defaults))
        XCTAssertFalse(inbox.showsAddNetwork, "an engine that has not answered yet has not said there are no accounts")
        XCTAssertFalse(inbox.isLoaded)
    }
}

// MARK: - Harness

/// A suite-named UserDefaults of its own, so no test reads or writes the real settings.
final class TestDefaults {
    let name = "courier-tests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: name)! }

    func remove() { defaults.removePersistentDomain(forName: name) }
}

/// An inbox model on an app model on a stand-in engine. The window's and the toast's sleeps are the test's.
@MainActor
struct InboxHarness {
    let script: InboxScript
    let server: TestEngineServer
    let launcher: FakeLauncher
    let supervisor: EngineSupervisor
    let app: AppModel
    let inbox: InboxModel
    let sleeps: SleepControl
    let toastSleeps: SleepControl
    let preferences: InboxPreferences
    let store: TestDefaults

    func count(_ method: String) -> Int { server.receivedMethods().filter { $0 == method }.count }

    /// Stops the stand-in engine and drops the settings.
    func cleanUp() {
        server.stop()
        store.remove()
    }
}

/// Starts a harness and waits for the first inbox read.
@MainActor
func startInbox(rooms: [[String: Any]] = [], accounts: [[String: Any]] = [account("whatsapp", "CONNECTED")],
                autoRelease: Bool = false, failFirstReads: Int = 0,
                hasTelegramCredentials: @escaping @MainActor () -> Bool = { true },
                entitlement: any EntitlementProvider = AlwaysEntitled()) async throws -> InboxHarness {
    let script = InboxScript(rooms: rooms, accounts: accounts)
    script.failReads = failFirstReads
    let server = try TestEngineServer(handler: script.handle)
    let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
    let supervisor = EngineSupervisor(
        enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
        dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
        credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
    let app = AppModel(supervisor: supervisor)
    let sleeps = SleepControl()
    let toastSleeps = SleepControl()
    if autoRelease { await sleeps.releaseAlways() }
    let store = TestDefaults()
    let preferences = InboxPreferences(defaults: store.defaults)
    let inbox = InboxModel(appModel: app, hasTelegramCredentials: hasTelegramCredentials, preferences: preferences,
                           entitlement: entitlement, window: 0.1, retryDelay: 2, sleep: { await sleeps.sleep($0) },
                           toastSleep: { await toastSleeps.sleep($0) })
    app.start()
    try await waitUntil { inbox.isLoaded && !app.accounts.isEmpty }
    return InboxHarness(script: script, server: server, launcher: launcher, supervisor: supervisor, app: app,
                        inbox: inbox, sleeps: sleeps, toastSleeps: toastSleeps, preferences: preferences, store: store)
}

// MARK: - Fixtures

/// What the stand-in engine answers, which a test edits as the "engine" changes its mind. It pages `rooms` by
/// position (cursor "o:<offset>"), looks chats up by id in `rooms` and `archivedRooms`, and archives and
/// unarchives by moving rows between the two, as the engine's inbox space would show them.
final class InboxScript: @unchecked Sendable {
    private let lock = NSLock()
    private var _rooms: [[String: Any]]
    private var _archived: [[String: Any]] = []
    private var _accounts: [[String: Any]]
    private var _events: [String: [[String: Any]]] = [:]
    private var _hold = false
    private var _holdAccounts = false
    private var _failReads = 0
    private var _pageCap: Int?
    private var _errors: [String: Int] = [:]
    private var _onMarkRead: (@Sendable (String) -> Void)?
    private var _spaces: [[String: Any]] = []
    private var _rules: [[String: Any]] = []

    init(rooms: [[String: Any]], accounts: [[String: Any]]) {
        _rooms = rooms
        _accounts = accounts
    }

    /// What the inbox lists, in the engine's order.
    var rooms: [[String: Any]] {
        get { lock.withLock { _rooms } }
        set { lock.withLock { _rooms = newValue } }
    }

    /// Archived chats: not listed, but found by room_ids.
    var archivedRooms: [[String: Any]] {
        get { lock.withLock { _archived } }
        set { lock.withLock { _archived = newValue } }
    }

    var accounts: [[String: Any]] {
        get { lock.withLock { _accounts } }
        set { lock.withLock { _accounts = newValue } }
    }

    /// What spaces.list answers.
    var spaces: [[String: Any]] {
        get { lock.withLock { _spaces } }
        set { lock.withLock { _spaces = newValue } }
    }

    /// What autoArchive.list answers; autoArchive.set stores into it (a new rule gets the next rule_id).
    var rules: [[String: Any]] {
        get { lock.withLock { _rules } }
        set { lock.withLock { _rules = newValue } }
    }

    /// room.events' newest page, by room.
    var events: [String: [[String: Any]]] {
        get { lock.withLock { _events } }
        set { lock.withLock { _events = newValue } }
    }

    /// While set, inbox.list is not answered until the test calls `releaseHeld`.
    var holdInbox: Bool {
        get { lock.withLock { _hold } }
        set { lock.withLock { _hold = newValue } }
    }

    /// While set, accounts.list is not answered until the test calls `releaseHeld(method:with:)`.
    var holdAccounts: Bool {
        get { lock.withLock { _holdAccounts } }
        set { lock.withLock { _holdAccounts = newValue } }
    }

    /// The next this many inbox.list calls fail.
    var failReads: Int {
        get { lock.withLock { _failReads } }
        set { lock.withLock { _failReads = newValue } }
    }

    /// A page holds at most this many chats, and still has a cursor when there are more (a page that ended
    /// early, before 1 MiB).
    var pageCap: Int? {
        get { lock.withLock { _pageCap } }
        set { lock.withLock { _pageCap = newValue } }
    }

    /// Every call of the method fails with this code.
    func fail(_ method: String, code: Int) { lock.withLock { _errors[method] = code } }

    var onMarkRead: (@Sendable (String) -> Void)? {
        get { lock.withLock { _onMarkRead } }
        set { lock.withLock { _onMarkRead = newValue } }
    }

    /// A new message from someone else brings an archived chat back to the top.
    func bringBack(_ id: String) {
        lock.withLock {
            guard let index = _archived.firstIndex(where: { $0["room_id"] as? String == id }) else { return }
            var row = _archived.remove(at: index)
            row["archived"] = false
            _rooms.insert(row, at: 0)
        }
    }

    private func shouldFailRead() -> Bool {
        lock.withLock {
            guard _failReads > 0 else { return false }
            _failReads -= 1
            return true
        }
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        if let code = lock.withLock({ _errors[method] }) { return .error(code: code, message: "example failure") }
        let ids = params?["room_ids"] as? [String] ?? []
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return holdAccounts ? .later : .result(["accounts": accounts])
        case "inbox.list":
            if shouldFailRead() { return .error(code: -32000, message: "example failure") }
            if holdInbox { return .later }
            return .result(list(params ?? [:]))
        case "room.events":
            let room = params?["room_id"] as? String ?? ""
            return .result(["events": events[room] ?? [], "before": NSNull(), "after": NSNull()])
        case "room.markRead":
            let id = params?["room_id"] as? String ?? ""
            update(id) { $0["unread"] = 0; $0["marked_unread"] = false }
            onMarkRead?(id)
            return .result([String: Any]())
        case "room.setMarkedUnread":
            for id in ids { update(id) { $0["marked_unread"] = params?["on"] as? Bool ?? false } }
            return .result(["room_ids": ids])
        case "room.setArchived":
            return archive(ids, params?["archived"] as? Bool ?? false)
        case "inbox.archiveMatching":
            let matching = rooms.filter {
                $0["unread"] as? Int == 0 && $0["marked_unread"] as? Bool == false && $0["pinned"] as? Bool == false
            }.map { $0["room_id"] as! String }
            // A dry run says which chats, and changes nothing.
            if params?["dry_run"] as? Bool == true { return .result(["room_ids": matching]) }
            return archive(matching, true)
        case "inbox.markAllRead":
            let unread = rooms.filter { ($0["unread"] as? Int ?? 0) > 0 || $0["marked_unread"] as? Bool == true }
                .map { $0["room_id"] as! String }
            for id in unread { update(id) { $0["unread"] = 0; $0["marked_unread"] = false } }
            return .result(["room_ids": unread])
        case "spaces.list":
            return .result(["spaces": spaces])
        case "labels.create":
            return .result(["label_id": 7])
        case "autoArchive.list":
            return .result(["rules": rules])
        case "autoArchive.set":
            return .result(storeRule(params ?? [:]))
        case "autoArchive.delete":
            let id = params?["rule_id"] as? Int
            lock.withLock { _rules.removeAll { $0["rule_id"] as? Int == id } }
            return .result([String: Any]())
        case "room.setLowPriority", "room.setHidden", "room.setLabel":
            return .result(["room_ids": ids])
        default: return .result([String: Any]())
        }
    }

    /// Stores a rule as autoArchive.set does: rule_id 0 makes a new one, any other replaces it.
    private func storeRule(_ params: [String: Any]) -> [String: Any] {
        lock.withLock {
            var rule = params
            let id = rule["rule_id"] as? Int ?? 0
            if id == 0 {
                rule["rule_id"] = (_rules.compactMap { $0["rule_id"] as? Int }.max() ?? 0) + 1
                _rules.append(rule)
            } else if let index = _rules.firstIndex(where: { $0["rule_id"] as? Int == id }) {
                _rules[index] = rule
            }
            return rule
        }
    }

    private func list(_ params: [String: Any]) -> [String: Any] {
        lock.withLock {
            if let ids = params["room_ids"] as? [String] {
                let all = _rooms + _archived
                return ["rooms": ids.compactMap { id in all.first { $0["room_id"] as? String == id } },
                        "next_cursor": NSNull()]
            }
            let offset = (params["cursor"] as? String).flatMap { Int($0.dropFirst(2)) } ?? 0
            let limit = min(params["limit"] as? Int ?? 200, _pageCap ?? Int.max)
            let end = min(offset + limit, _rooms.count)
            let rooms = offset < end ? Array(_rooms[offset ..< end]) : []
            return ["rooms": rooms, "next_cursor": end < _rooms.count ? "o:\(end)" as Any : NSNull()]
        }
    }

    private func update(_ id: String, _ change: (inout [String: Any]) -> Void) {
        lock.withLock {
            if let index = _rooms.firstIndex(where: { $0["room_id"] as? String == id }) { change(&_rooms[index]) }
        }
    }

    /// Archives (leaving out pinned chats, -32021 when every one is) or unarchives, and answers the chats changed.
    private func archive(_ ids: [String], _ on: Bool) -> TestEngineServer.Reply {
        lock.withLock {
            var changed: [String] = []
            for id in ids {
                if on, let index = _rooms.firstIndex(where: { $0["room_id"] as? String == id }) {
                    guard _rooms[index]["pinned"] as? Bool != true else { continue }
                    var row = _rooms.remove(at: index)
                    row["archived"] = true
                    _archived.append(row)
                    changed.append(id)
                } else if !on, let index = _archived.firstIndex(where: { $0["room_id"] as? String == id }) {
                    var row = _archived.remove(at: index)
                    row["archived"] = false
                    _rooms.append(row)
                    changed.append(id)
                }
            }
            if on, changed.isEmpty, !ids.isEmpty { return .error(code: -32021, message: "a pinned chat can't be archived") }
            return .result(["room_ids": changed])
        }
    }
}

extension TestEngineServer {
    /// The params of every request for `method`, in order.
    func receivedParams(_ method: String) -> [[String: Any]] {
        received.filter { $0["method"] as? String == method }.map { $0["params"] as? [String: Any] ?? [:] }
    }

    /// Answers every inbox.list the handler held.
    func releaseHeld(with result: Any) {
        releaseHeld(method: "inbox.list", with: result)
    }

    /// Answers every request for `method` the handler held.
    func releaseHeld(method: String, with result: Any) {
        for request in received where request["method"] as? String == method {
            if let id = request["id"] as? Int { reply(to: id, with: result) }
        }
    }
}

/// The coalescing window's sleep: it waits until the test releases it.
actor SleepControl {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var alwaysOpen = false
    /// Every wait asked for, in order.
    private(set) var durations: [TimeInterval] = []

    var waiting: Int { waiters.count }

    func sleep(_ seconds: TimeInterval) async {
        durations.append(seconds)
        if alwaysOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseAll() {
        let all = waiters
        waiters = []
        for waiter in all { waiter.resume() }
    }

    func releaseAlways() {
        alwaysOpen = true
        releaseAll()
    }
}

/// Dictionaries, for comparing params as the wire had them.
func dicts(_ list: [[String: Any]]) -> [NSDictionary] { list.map { $0 as NSDictionary } }

/// An InboxResult as the engine writes it: the last page.
func page(_ rooms: [[String: Any]], next: String? = nil) -> [String: Any] {
    ["rooms": rooms, "next_cursor": next as Any? ?? NSNull()]
}

/// `count` chats r0, r1, … in the engine's order (newest first).
func manyRooms(_ count: Int) -> [[String: Any]] {
    (0 ..< count).map { room("!r\($0)", ts: Int64(1_000_000 - $0)) }
}

/// An InboxRow as the engine writes it.
func room(_ id: String, ts: Int64, unread: Int = 0, muted: Bool = false, network: String = "whatsapp",
          name: String? = nil, preview: String = "Hello", kind: String = "text", pinned: Bool = false,
          archived: Bool = false, markedUnread: Bool = false, draft: String = "",
          previewCall: [String: String]? = nil) -> [String: Any] {
    [
        "room_id": id, "network": network, "name": name ?? "Chat \(id)", "avatar_path": "", "is_direct": true,
        "last_ts": ts, "preview": preview, "preview_kind": kind, "preview_mine": false, "unread": unread,
        "muted": muted, "pinned": pinned, "archived": archived, "low_priority": false, "hidden": false,
        "marked_unread": markedUnread, "request": false, "draft": draft, "labels": [Int](), "muted_by": "",
        "muted_by_name": "", "reminder": NSNull(), "typing": [String](), "unread_mentions": 0,
        "preview_media_path": "", "preview_call": previewCall.map { $0 as Any } ?? NSNull(),
        "preview_status": "", "login_name": "",
    ]
}

/// An Account as the engine writes it.
func account(_ network: String, _ state: String, error: String = "", notStarted: String = "",
             logins: [[String: Any]] = []) -> [String: Any] {
    [
        "network": network, "display_name": "\(network) display", "flows": ["qr"], "state": state, "error": error,
        "remote_name": logins.first?["remote_name"] as? String ?? "", "not_started": notStarted,
        "syncs": [String](), "logins": logins,
    ]
}

/// A Login (one account on a network) as the engine writes it.
func login(_ accountID: String, _ remoteName: String, _ state: String, error: String = "") -> [String: Any] {
    ["account_id": accountID, "remote_name": remoteName, "state": state, "error": error]
}
