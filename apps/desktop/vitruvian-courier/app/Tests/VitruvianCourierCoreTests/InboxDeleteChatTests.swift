// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// D1: Delete Chat… from the inbox's menu. What a chat's network can do is asked once and kept; Delete runs
/// room.delete, and a refusal leaves the chat and says so.
@MainActor
final class InboxDeleteChatTests: XCTestCase {
    private var harnesses: [InboxHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    private func start() async throws -> InboxHarness {
        let h = try await startInbox(rooms: ["!a", "!b", "!c"].enumerated().map {
            room($0.element, ts: Int64(500 - $0.offset))
        }, autoRelease: true)
        harnesses.append(h)
        return h
    }

    func testFeaturesAreAskedOnceAndKeptSoTheMenuCanReadThem() async throws {
        let h = try await start()
        h.script.deletable = ["!a"]
        XCTAssertNil(h.inbox.cachedFeatures(for: "!a"), "not asked yet: the menu claims nothing")

        await h.inbox.loadFeatures(for: "!a")
        XCTAssertEqual(h.inbox.cachedFeatures(for: "!a")?.canDelete, true)
        await h.inbox.loadFeatures(for: "!b")
        XCTAssertEqual(h.inbox.cachedFeatures(for: "!b")?.canDelete, false, "a network that can't delete says so")

        await h.inbox.loadFeatures(for: "!a")
        XCTAssertEqual(h.count("room.features"), 2, "!a was not asked again while its answer was fresh")

        let later = Date().addingTimeInterval(InboxModel.featuresFreshFor + 1)
        XCTAssertNil(h.inbox.cachedFeatures(for: "!a", now: later), "an old answer is not trusted")
    }

    func testAMergedChatHasNoFeaturesOfItsOwn() async throws {
        let h = try await start()
        await h.inbox.loadFeatures(for: "merge:1")
        XCTAssertEqual(h.count("room.features"), 0)
        XCTAssertNil(h.inbox.cachedFeatures(for: "merge:1"))
    }

    func testDeleteRunsRoomDeleteAndTheChatLeavesTheList() async throws {
        let h = try await start()
        h.script.deletable = ["!b"]
        await h.inbox.loadFeatures(for: "!b")
        XCTAssertNotNil(h.inbox.cachedFeatures(for: "!b"))

        let deleted = await h.inbox.deleteChat(roomID: "!b")
        XCTAssertTrue(deleted)
        XCTAssertEqual(dicts(h.server.receivedParams("room.delete")), dicts([["room_id": "!b"]]))
        XCTAssertEqual(h.inbox.toast?.message, "Chat deleted")
        XCTAssertNil(h.inbox.cachedFeatures(for: "!b"), "what was known about a deleted chat is dropped")
        try await waitUntil { !h.inbox.rows.contains { $0.roomID == "!b" } }
    }

    func testAnEngineRefusalKeepsTheChatAndSaysSo() async throws {
        let h = try await start()
        h.script.fail("room.delete", code: -32000)
        let deleted = await h.inbox.deleteChat(roomID: "!b")
        XCTAssertFalse(deleted)
        XCTAssertNotNil(h.inbox.toast)
        XCTAssertNotEqual(h.inbox.toast?.message, "Chat deleted")
        XCTAssertTrue(h.inbox.rows.contains { $0.roomID == "!b" })
    }

    func testAMergedChatIsNeverDeletedFromTheInbox() async throws {
        let h = try await start()
        let deleted = await h.inbox.deleteChat(roomID: "merge:1")
        XCTAssertFalse(deleted)
        XCTAssertEqual(h.count("room.delete"), 0)
    }
}
