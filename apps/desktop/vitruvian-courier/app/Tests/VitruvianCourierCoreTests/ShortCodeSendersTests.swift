// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Verification-code senders (a chat titled "787473") are filed under Low Priority by default, once, and only when
/// the person has not already decided where the chat goes.
@MainActor
final class ShortCodeSendersTests: XCTestCase {
    private var harnesses: [InboxHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    private struct Denies: EntitlementProvider {
        let denied: Set<Feature>
        func isEntitled(_ feature: Feature) -> Bool { !denied.contains(feature) }
    }

    private func row(_ id: String, _ name: String, direct: Bool = true, pinned: Bool = false, archived: Bool = false,
                     lowPriority: Bool = false, hidden: Bool = false, request: Bool = false,
                     markedUnread: Bool = false, draft: String = "", labels: [Int64] = [], local: String = "",
                     mergeID: String = "") -> InboxRow {
        InboxRow(roomID: id, network: "gmessages", name: name, avatarPath: "", isDirect: direct, lastTS: 1, preview: "",
                 previewKind: .text, previewMine: false, unread: 1, muted: false, pinned: pinned, archived: archived,
                 lowPriority: lowPriority, hidden: hidden, markedUnread: markedUnread, request: request, draft: draft,
                 labels: labels, localName: local, mergeID: mergeID)
    }

    // MARK: - The rule

    func testOnlyAChatTitledWithAShortCodeIsOne() {
        for name in ["787473", "32665", "123", "12345678", "888-222", "5 5 5 0 1", "787473 (WA)"] {
            XCTAssertTrue(ShortCodeSenders.isShortCodeChat(row("!a", name)), name)
        }
        for name in ["Chase Bank", "Amazon", "12", "123456789", "Room 101", "+12134476502", "Alice", "", "1-800-FLOWERS"] {
            XCTAssertFalse(ShortCodeSenders.isShortCodeChat(row("!a", name)), "\(name) is not a short code")
        }
    }

    func testItIsTheSameRuleTheContactListUses() {
        for text in ["787473", "12", "123456789", "888-222", "abc", "Room 101"] {
            XCTAssertEqual(ShortCodeSenders.isShortCodeChat(row("!a", text)), ContactListOrdering.isShortCode(text), text)
        }
    }

    func testAGroupOrAMergedChatIsNeverOne() {
        XCTAssertFalse(ShortCodeSenders.isShortCodeChat(row("!a", "787473", direct: false)))
        XCTAssertFalse(ShortCodeSenders.isShortCodeChat(row("merge:1", "787473")))
        XCTAssertFalse(ShortCodeSenders.isShortCodeChat(row("!a", "787473", mergeID: "merge:1")))
    }

    func testAChatTheyRenamedIsNamedNotACode() {
        XCTAssertFalse(ShortCodeSenders.isShortCodeChat(row("!a", "787473", local: "Chase codes")))
    }

    func testNamedSendersAreNotFiledEvenIfTheirMessagesAreCodes() {
        let rows = [row("!bank", "Chase Bank"), row("!code", "787473")]
        XCTAssertEqual(ShortCodeSenders.evaluate(rows, isInbox: true, alreadySeen: []).toFile, ["!code"])
    }

    func testAnythingThePersonDidKeepsTheChatWhereItIs() {
        let rows = [
            row("!pinned", "10001", pinned: true),
            row("!labelled", "10002", labels: [3]),
            row("!unread", "10003", markedUnread: true),
            row("!draft", "10004", draft: "reply"),
            row("!renamed", "10005", local: "Verify"),
            row("!archived", "10006", archived: true),
            row("!hidden", "10007", hidden: true),
            row("!low", "10008", lowPriority: true),
            row("!request", "10009", request: true),
            row("!plain", "10010"),
        ]
        let evaluation = ShortCodeSenders.evaluate(rows, isInbox: true, alreadySeen: [])
        XCTAssertEqual(evaluation.toFile, ["!plain"])
        XCTAssertEqual(evaluation.newlySeen.count, 9, "every short-code chat is recorded, filed or not; the renamed one is no longer a code")
    }

    func testAChatSeenBeforeIsNeverFiledNorRecordedAgain() {
        let rows = [row("!seen", "787473"), row("!new", "32665")]
        let evaluation = ShortCodeSenders.evaluate(rows, isInbox: true, alreadySeen: ["!seen"])
        XCTAssertEqual(evaluation.toFile, ["!new"])
        XCTAssertEqual(evaluation.newlySeen, ["!new"])
    }

    func testAChatSeenOutsideTheInboxIsRecordedButNotFiled() {
        let rows = [row("!archived", "787473", archived: true), row("!low", "32665", lowPriority: true)]
        let evaluation = ShortCodeSenders.evaluate(rows, isInbox: false, alreadySeen: [])
        XCTAssertEqual(evaluation.newlySeen, ["!archived", "!low"])
        XCTAssertEqual(evaluation.toFile, [])
        // Even if one of them is later in the inbox, it was seen: it is left where the person put it.
        XCTAssertEqual(ShortCodeSenders.evaluate(rows, isInbox: true, alreadySeen: Set(evaluation.newlySeen)).toFile, [])
    }

    func testTheLedgerKeepsWhatWasSeen() {
        let store = TestDefaults()
        let preferences = InboxPreferences(defaults: store.defaults)
        XCTAssertEqual(preferences.evaluatedShortCodeRoomIDs, [])
        preferences.recordEvaluatedShortCodes(["!a", "!b"])
        preferences.recordEvaluatedShortCodes(["!b", "!c"])
        preferences.recordEvaluatedShortCodes([])
        XCTAssertEqual(InboxPreferences(defaults: store.defaults).evaluatedShortCodeRoomIDs, ["!a", "!b", "!c"])
    }

    // MARK: - In the inbox

    private func start(_ rooms: [[String: Any]], entitlement: any EntitlementProvider = AlwaysEntitled()) async throws
        -> InboxHarness {
        let harness = try await startInbox(rooms: rooms, accounts: [account("gmessages", "CONNECTED")],
                                           autoRelease: true, entitlement: entitlement)
        harnesses.append(harness)
        return harness
    }

    private func settle() async throws { try await Task.sleep(nanoseconds: 400_000_000) }

    func testTheInboxFilesCodeSendersUnderLowPriorityAndNobodyElse() async throws {
        var labelled = room("!labelled", ts: 90, name: "40404")
        labelled["labels"] = [5]
        let h = try await start([
            room("!code", ts: 100, name: "787473"), room("!short", ts: 99, name: "32665"),
            room("!bank", ts: 98, name: "Chase Bank"), room("!alice", ts: 97, name: "Alice"),
            room("!pinned", ts: 96, name: "55555", pinned: true), room("!marked", ts: 95, name: "66666", markedUnread: true),
            labelled,
        ])
        try await waitUntil { !h.server.receivedParams("room.setLowPriority").isEmpty }
        try await settle()
        let calls = h.server.receivedParams("room.setLowPriority")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(Set(calls[0]["room_ids"] as? [String] ?? []), ["!code", "!short"])
        XCTAssertEqual(calls[0]["on"] as? Bool, true)
        XCTAssertEqual(h.preferences.evaluatedShortCodeRoomIDs, ["!code", "!short", "!pinned", "!marked", "!labelled"],
                       "the chats the person had touched are recorded too, so they are never filed later")
        XCTAssertNil(h.inbox.toast, "it is a default, not an action the person took: no toast")
    }

    /// The person moves a filed chat back to the inbox: later reads leave it there.
    func testAChatMovedBackToTheInboxIsNotFiledAgain() async throws {
        let h = try await start([room("!code", ts: 100, name: "787473")])
        try await waitUntil { h.server.receivedParams("room.setLowPriority").count == 1 }
        try await waitUntil { h.preferences.evaluatedShortCodeRoomIDs == ["!code"] }

        // Back in the inbox (the stand-in engine never moved it): a new message, then a fresh read.
        await h.inbox.setLowPriority(false, ids: ["!code"])
        h.script.rooms = [room("!code", ts: 200, unread: 1, name: "787473")]
        h.server.notify(["kind": "event", "room_id": "!code", "event_id": "$1"])
        try await settle()
        let calls = h.server.receivedParams("room.setLowPriority")
        XCTAssertEqual(calls.compactMap { $0["on"] as? Bool }, [true, false], "filed once, moved back once, never filed again")
    }

    func testWithoutAPlanNothingIsFiled() async throws {
        let h = try await start([room("!code", ts: 100, name: "787473")], entitlement: Denies(denied: [.lowPriority]))
        try await settle()
        XCTAssertEqual(h.server.receivedParams("room.setLowPriority").count, 0)
        XCTAssertEqual(h.preferences.evaluatedShortCodeRoomIDs, ["!code"], "seen once: it is never filed later either")
    }

    /// Waits until the app has looked at `id`.
    private func waitUntilSeen(_ h: InboxHarness, _ id: String) async throws {
        try await waitUntil { h.preferences.evaluatedShortCodeRoomIDs.contains(id) }
    }

    /// The person moved the chat to Low Priority by hand, and later back to the inbox: the app saw it first in Low
    /// Priority, so it never files it.
    func testAChatMovedByHandToLowPriorityAndBackIsNotFiled() async throws {
        let h = try await start([])
        h.inbox.query.space = "low_priority"
        h.script.rooms = [room("!code", ts: 100, name: "787473")]
        h.server.notify(["kind": "room"])
        try await waitUntilSeen(h, "!code")

        h.inbox.query.space = "inbox"
        h.server.notify(["kind": "room"])
        try await settle()
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!code"], "it is back in the inbox")
        XCTAssertEqual(h.server.receivedParams("room.setLowPriority").count, 0)
    }

    func testAnUnarchivedShortCodeChatIsNotFiled() async throws {
        let h = try await start([])
        h.inbox.query.space = "archive"
        h.script.rooms = [room("!code", ts: 100, name: "787473", archived: true)]
        h.server.notify(["kind": "room"])
        try await waitUntilSeen(h, "!code")

        h.inbox.query.space = "inbox"
        h.script.rooms = [room("!code", ts: 100, name: "787473")]
        h.server.notify(["kind": "room"])
        try await settle()
        XCTAssertEqual(h.server.receivedParams("room.setLowPriority").count, 0)
    }

    /// A chat the person had pinned when the app first saw it, then unpinned, is left in the inbox.
    func testAChatTheyHadPinnedIsNotFiledOnceUnpinned() async throws {
        let h = try await start([room("!code", ts: 100, name: "787473", pinned: true)])
        try await waitUntilSeen(h, "!code")
        h.script.rooms = [room("!code", ts: 100, name: "787473")]
        h.server.notify(["kind": "room"])
        try await settle()
        XCTAssertEqual(h.server.receivedParams("room.setLowPriority").count, 0)
    }

    func testOtherPlacesAreNotFiled() async throws {
        let h = try await start([room("!code", ts: 100, name: "787473")])
        try await waitUntil { h.server.receivedParams("room.setLowPriority").count == 1 }
        h.inbox.query.space = "archive"
        h.script.rooms = [room("!other", ts: 50, name: "99999")]
        h.server.notify(["kind": "room"])
        try await waitUntilSeen(h, "!other")
        try await settle()
        XCTAssertEqual(h.server.receivedParams("room.setLowPriority").count, 1, "only the inbox's chats are filed")
    }
}
