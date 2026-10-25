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

    func testSingleMergedChatsOwnerAcrossAppInboxAndConversation() async throws {
        let h = try await start()
        let conversation = ConversationModel(appModel: h.app)
        let merged = MergedChat(
            mergeID: "merge:1",
            name: "Alice Example",
            lastRoomID: "!tg-alice:courier.local",
            roomIDs: ["!wa-alice:courier.local", "!tg-alice:courier.local"],
            networks: ["whatsapp", "telegram"],
            createdTS: 100
        )
        h.app.mergedChats["merge:1"] = merged
        h.inbox.select("merge:1")
        XCTAssertTrue(h.app.isOpen(roomID: "!wa-alice:courier.local"))
        XCTAssertTrue(h.app.isOpen(roomID: "!tg-alice:courier.local"))
        XCTAssertEqual(conversation.mergedChat?.mergeID, "merge:1")

        // Unmerge while open:
        h.app.mergedChats.removeValue(forKey: "merge:1")
        XCTAssertNil(conversation.mergedChat)
        XCTAssertFalse(h.app.isOpen(roomID: "!wa-alice:courier.local"))
    }

    func testNoDirectSelectedRoomIDComparisonsInSources() throws {
        let fm = FileManager.default
        let candidates: [URL] = [
            ProcessInfo.processInfo.environment["TEST_SRCDIR"].map {
                URL(fileURLWithPath: $0).appendingPathComponent("_main/apps/desktop/courier/app/Sources")
            },
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // CourierCoreTests
                .deletingLastPathComponent() // Tests
                .deletingLastPathComponent() // app
                .appendingPathComponent("Sources"),
        ].compactMap { $0 }
        guard let sourcesRoot = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            XCTFail("Could not locate Sources directory in \(candidates.map(\.path))")
            return
        }
        // Reviewed exceptions, each named with the reason it is allowed.
        let allowedFiles: [String: String] = [
            "AppModel.swift": "AppModel.isOpen(roomID:) is the canonical entry point that checks selectedRoomID equality before checking mergedChats membership.",
        ]
        guard let enumerator = fm.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate \(sourcesRoot.path)")
            return
        }
        var violations: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard allowedFiles[fileURL.lastPathComponent] == nil else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            for (idx, line) in content.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                if trimmed.contains("selectedRoomID ==")
                    || trimmed.contains("== selectedRoomID")
                    || trimmed.contains("== inbox.selectedRoomID")
                    || trimmed.contains("== appModel.selectedRoomID")
                    || trimmed.contains("== model.selectedRoomID") {
                    violations.append("\(fileURL.lastPathComponent):\(idx + 1): \(trimmed)")
                }
            }
        }
        XCTAssertEqual(
            violations,
            [],
            "Direct selectedRoomID == comparisons bypass merged-chat membership; use AppModel.isOpen(roomID:) instead."
        )
    }

    func testEngineServerGuardRejectsMergeIDInRoomScopedRPC() async throws {
        let h = try await start()
        h.server.expectMergeIDRejection = true
        let client = try XCTUnwrap(h.app.client)
        _ = try? await client.call("room.events", ["room_id": "merge:alice"]) as EventsPage
        XCTAssertEqual(h.server.rejectedMergeIDs, ["room.events:merge:alice"])
    }
}
