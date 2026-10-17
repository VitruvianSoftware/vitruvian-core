// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Selecting several chats in the inbox and acting on them at once, against a stand-in engine.
@MainActor
final class InboxSelectionTests: XCTestCase {
    private var harnesses: [InboxHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    private func start() async throws -> InboxHarness {
        let h = try await startInbox(rooms: ["!a", "!b", "!c", "!d", "!e"].enumerated().map {
            room($0.element, ts: Int64(500 - $0.offset))
        }, autoRelease: true)
        harnesses.append(h)
        return h
    }

    func testBeginToggleExtendAndSelectAll() async throws {
        let h = try await start()
        h.inbox.select("!b")
        h.inbox.beginSelecting()
        XCTAssertTrue(h.inbox.isSelecting)
        XCTAssertEqual(h.inbox.selection, ["!b"], "the open chat is the first one selected")

        h.inbox.toggleSelected("!d")
        XCTAssertEqual(h.inbox.selection, ["!b", "!d"])
        h.inbox.toggleSelected("!b")
        XCTAssertEqual(h.inbox.selection, ["!d"])

        // Shift-click: everything from the last chat toggled to this one, in the list's order.
        h.inbox.extendSelection(to: "!a")
        XCTAssertEqual(h.inbox.selection, ["!a", "!b", "!c", "!d"])

        h.inbox.selectAll()
        XCTAssertEqual(h.inbox.selection, ["!a", "!b", "!c", "!d", "!e"])

        h.inbox.endSelecting()
        XCTAssertFalse(h.inbox.isSelecting)
        XCTAssertEqual(h.inbox.selection, [])
        XCTAssertEqual(h.inbox.selectedRoomID, "!b", "the open chat stays open")

        // Toggling a chat starts selecting.
        h.inbox.select(nil)
        h.inbox.toggleSelected("!e")
        XCTAssertTrue(h.inbox.isSelecting)
        XCTAssertEqual(h.inbox.selection, ["!e"])
    }

    func testTargetsAreTheSelectionWhileSelecting() async throws {
        let h = try await start()
        XCTAssertEqual(h.inbox.targets, [], "nothing open, nothing selected")
        h.inbox.select("!c")
        XCTAssertEqual(h.inbox.targets, ["!c"], "the open chat")

        h.inbox.beginSelecting()
        h.inbox.toggleSelected("!e")
        h.inbox.toggleSelected("!a")
        XCTAssertEqual(h.inbox.targets, ["!a", "!c", "!e"], "the selection, in the list's order")

        h.inbox.toggleSelected("!a")
        h.inbox.toggleSelected("!c")
        h.inbox.toggleSelected("!e")
        XCTAssertEqual(h.inbox.targets, [], "selecting with nothing selected acts on nothing, not the open chat")

        h.inbox.endSelecting()
        XCTAssertEqual(h.inbox.targets, ["!c"])
    }

    func testEscapeLeavesSelectionFirst() async throws {
        let h = try await start()
        h.inbox.select("!b")
        h.inbox.beginSelecting()
        h.inbox.toggleSelected("!c")
        XCTAssertTrue(h.inbox.escape(), "Escape ends selecting")
        XCTAssertFalse(h.inbox.isSelecting)
        XCTAssertEqual(h.inbox.selectedRoomID, "!b", "and leaves the open chat open")
        XCTAssertFalse(h.inbox.escape(), "a second Escape is the view's to use")
    }

    func testBulkArchiveSendsOneCall() async throws {
        let h = try await start()
        h.inbox.beginSelecting()
        for id in ["!d", "!a", "!c"] { h.inbox.toggleSelected(id) }
        await h.inbox.archive(true)

        XCTAssertEqual(dicts(h.server.receivedParams("room.setArchived")),
                       dicts([["room_ids": ["!a", "!c", "!d"], "archived": true]]), "one call for every chat selected")
        XCTAssertEqual(h.inbox.toast?.message, "Archived 3 chats")
        XCTAssertFalse(h.inbox.isSelecting, "done, so selecting ends")

        // Undo reverses the one call with one call.
        await h.inbox.undo()
        XCTAssertEqual(h.server.receivedParams("room.setArchived").last as NSDictionary?,
                       ["room_ids": ["!a", "!c", "!d"], "archived": false] as NSDictionary)
    }
}
