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
        XCTAssertEqual(ShortCodeSenders.lowPriorityCandidates(in: rows, alreadyFiled: []), ["!code"])
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
        XCTAssertEqual(ShortCodeSenders.lowPriorityCandidates(in: rows, alreadyFiled: []), ["!plain"])
    }

    func testAChatTheAppFiledBeforeIsNotFiledAgain() {
        let rows = [row("!moved-back", "787473"), row("!new", "32665")]
        XCTAssertEqual(ShortCodeSenders.lowPriorityCandidates(in: rows, alreadyFiled: ["!moved-back"]), ["!new"])
    }

    func testTheLedgerKeepsWhatWasFiled() {
        let store = TestDefaults()
        let preferences = InboxPreferences(defaults: store.defaults)
        XCTAssertEqual(preferences.filedShortCodeRoomIDs, [])
        preferences.recordFiledShortCodes(["!a", "!b"])
        preferences.recordFiledShortCodes(["!b", "!c"])
        preferences.recordFiledShortCodes([])
        XCTAssertEqual(InboxPreferences(defaults: store.defaults).filedShortCodeRoomIDs, ["!a", "!b", "!c"])
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
        XCTAssertEqual(h.preferences.filedShortCodeRoomIDs, ["!code", "!short"])
        XCTAssertNil(h.inbox.toast, "it is a default, not an action the person took: no toast")
    }

    /// The person moves a filed chat back to the inbox: later reads leave it there.
    func testAChatMovedBackToTheInboxIsNotFiledAgain() async throws {
        let h = try await start([room("!code", ts: 100, name: "787473")])
        try await waitUntil { h.server.receivedParams("room.setLowPriority").count == 1 }
        try await waitUntil { h.preferences.filedShortCodeRoomIDs == ["!code"] }

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
        XCTAssertEqual(h.preferences.filedShortCodeRoomIDs, [])
    }

    func testOtherPlacesAreNotFiled() async throws {
        let h = try await start([room("!code", ts: 100, name: "787473")])
        try await waitUntil { h.server.receivedParams("room.setLowPriority").count == 1 }
        h.inbox.query.space = "archive"
        h.script.rooms = [room("!other", ts: 50, name: "99999")]
        h.server.notify(["kind": "room"])
        try await settle()
        XCTAssertEqual(h.server.receivedParams("room.setLowPriority").count, 1, "only the inbox's chats are looked at")
    }
}
