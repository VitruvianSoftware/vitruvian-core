// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The spaces bar's model against a stand-in engine.
@MainActor
final class SpacesModelTests: XCTestCase {
    private var harnesses: [InboxHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    /// The bar as the engine lists it: visible spaces first, then hidden ones.
    nonisolated(unsafe) private static let bar: [[String: Any]] = [
        spaceJSON("inbox"),
        spaceJSON("account:whatsapp", kind: "account", title: "WhatsApp", network: "whatsapp", showInInbox: "all"),
        spaceJSON("account:signal", kind: "account", title: "Signal", network: "signal", showInInbox: "all"),
        spaceJSON("label:1", kind: "label", title: "Work", labelID: 1, showInInbox: "all"),
        spaceJSON("archive", hidden: true),
        spaceJSON("label:2", kind: "label", title: "Home", labelID: 2, hidden: true, showInInbox: "none"),
    ]

    /// A spaces model on a started inbox. `autoRelease` opens the coalescing window.
    private func start(bar: [[String: Any]] = SpacesModelTests.bar, autoRelease: Bool = true,
                       rooms: [[String: Any]] = []) async throws -> (InboxHarness, SpacesModel, SleepControl) {
        let h = try await startInbox(rooms: rooms, autoRelease: true)
        harnesses.append(h)
        h.script.spaces = bar
        let sleeps = SleepControl()
        if autoRelease { await sleeps.releaseAlways() }
        let spaces = SpacesModel(appModel: h.app, inbox: h.inbox, sleep: { await sleeps.sleep($0) })
        try await waitUntil { !spaces.spaces.isEmpty }
        return (h, spaces, sleeps)
    }

    // MARK: - Reading

    func testSpacesAreReadWhenTheModelStartsInTheEnginesOrder() async throws {
        let (h, spaces, _) = try await start()
        XCTAssertEqual(spaces.spaces.map(\.spaceID),
                       ["inbox", "account:whatsapp", "account:signal", "label:1", "archive", "label:2"])
        XCTAssertEqual(spaces.visible.map(\.spaceID), ["inbox", "account:whatsapp", "account:signal", "label:1"])
        XCTAssertEqual(h.count("spaces.list"), 1)
    }

    func testASpacesChangeReadsAgainAndABurstOfRoomChangesReadsOnce() async throws {
        let (h, spaces, sleeps) = try await start(autoRelease: false)

        h.script.spaces = Array(SpacesModelTests.bar.prefix(2))
        h.server.notify(["kind": "spaces"])
        try await waitUntil { await sleeps.waiting == 1 }
        // Counts change with chats: a burst of them is read once, after the window.
        h.server.notify(["kind": "room", "room_id": "!a"])
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        h.server.notify(["kind": "read", "room_id": "!a"])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("spaces.list"), 1, "nothing is read inside the window")
        let waits = await sleeps.durations
        XCTAssertEqual(waits.count, 1, "one window for the whole burst")

        await sleeps.releaseAll()
        try await waitUntil { h.count("spaces.list") == 2 && spaces.spaces.count == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("spaces.list"), 2, "the burst was one read")
    }

    /// Protocol 4: Delete for Me and a failed or retried unsend change counts with only a status change, and the Send
    /// Later space's count moves with a scheduled change.
    func testStatusAndScheduledChangesReadSpaces() async throws {
        let (h, spaces, _) = try await start()
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.count("spaces.list") == 2 }
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { h.count("spaces.list") == 3 }
        XCTAssertFalse(spaces.spaces.isEmpty)
    }

    func testTypingAndBridgeChangesDoNotReadSpaces() async throws {
        let (h, _, _) = try await start()
        h.server.notify(["kind": "typing", "room_id": "!a"])
        h.server.notify(["kind": "bridge", "network": "whatsapp"])
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(h.count("spaces.list"), 1)
    }

    func testTheSpaceShownFallsBackToTheInboxWhenItIsGone() async throws {
        let (h, spaces, _) = try await start()
        spaces.select("label:1")
        XCTAssertEqual(h.inbox.query.space, "label:1")

        // The label was deleted: its space is not in the bar any more.
        h.script.spaces = SpacesModelTests.bar.filter { $0["space_id"] as? String != "label:1" }
        h.server.notify(["kind": "spaces"])
        try await waitUntil { h.inbox.query.space == "inbox" }

        // A hidden space is still a space.
        spaces.select("archive")
        h.server.notify(["kind": "spaces"])
        try await waitUntil { h.count("spaces.list") == 3 }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.inbox.query.space, "archive")
    }

    // MARK: - Choosing a space

    func testSelectNumberSkipsHiddenSpaces() async throws {
        let (h, spaces, _) = try await start()
        spaces.selectNumber(3)
        XCTAssertEqual(h.inbox.query.space, "account:signal", "⌘3 is the third visible space")
        spaces.selectNumber(1)
        XCTAssertEqual(h.inbox.query.space, "inbox")
        spaces.selectNumber(4)
        XCTAssertEqual(h.inbox.query.space, "label:1")

        // There are four visible spaces: ⌘5 is the hidden Archive's number, and does nothing.
        spaces.selectNumber(5)
        XCTAssertEqual(h.inbox.query.space, "label:1")
        spaces.selectNumber(0)
        spaces.selectNumber(-1)
        XCTAssertEqual(h.inbox.query.space, "label:1")
    }

    func testNextAccountWraps() async throws {
        let (h, spaces, _) = try await start()
        XCTAssertEqual(h.inbox.query.space, "inbox")
        spaces.selectNextAccount()
        XCTAssertEqual(h.inbox.query.space, "account:whatsapp")
        spaces.selectNextAccount()
        spaces.selectNextAccount()
        XCTAssertEqual(h.inbox.query.space, "label:1")
        spaces.selectNextAccount()
        XCTAssertEqual(h.inbox.query.space, "inbox", "after the last visible space, the first")

        spaces.selectPreviousAccount()
        XCTAssertEqual(h.inbox.query.space, "label:1", "before the first, the last")
        spaces.selectPreviousAccount()
        XCTAssertEqual(h.inbox.query.space, "account:signal")

        // From a hidden space: next is the first visible space, previous the last.
        spaces.select("archive")
        spaces.selectNextAccount()
        XCTAssertEqual(h.inbox.query.space, "inbox")
        spaces.select("archive")
        spaces.selectPreviousAccount()
        XCTAssertEqual(h.inbox.query.space, "label:1")
    }

    func testNothingMovesWithoutSpaces() async throws {
        let (h, spaces, _) = try await start(bar: [spaceJSON("inbox", hidden: true)])
        spaces.selectNextAccount()
        spaces.selectPreviousAccount()
        spaces.selectNumber(1)
        XCTAssertEqual(h.inbox.query.space, "inbox")
        XCTAssertTrue(spaces.visible.isEmpty)
    }

    func testSelectingASpaceClearsPlaceFilters() async throws {
        let (h, spaces, _) = try await start()
        h.inbox.query.filters = [.unread, .archived, .hidden, .lowPriority, .requests, .reminders, .sendLater, .dms]
        spaces.select("account:whatsapp")
        XCTAssertEqual(h.inbox.query.space, "account:whatsapp")
        XCTAssertEqual(h.inbox.query.filters, [.unread, .dms], "only the place filters go; the others stay")
        XCTAssertEqual(Set(SpacesModel.placeFilters),
                       [.archived, .lowPriority, .hidden, .requests, .reminders, .sendLater])

        // One new query: the first page of the space, narrowed by what stayed.
        try await waitUntil {
            h.server.receivedParams("inbox.list").last?["space"] as? String == "account:whatsapp"
        }
        let last = try XCTUnwrap(h.server.receivedParams("inbox.list").last)
        XCTAssertEqual(last["filters"] as? [String], ["unread", "dms"])
    }

    // MARK: - Changing the bar

    func testSavingLayoutShowsSidebarUpdated() async throws {
        let (h, spaces, _) = try await start()
        await spaces.saveLayout(order: ["inbox", "label:1", "account:whatsapp", "account:signal", "archive", "label:2"],
                                hidden: ["archive", "label:2", "account:signal"])
        XCTAssertEqual(dicts(h.server.receivedParams("spaces.setLayout")), dicts([[
            "order": ["inbox", "label:1", "account:whatsapp", "account:signal", "archive", "label:2"],
            "hidden": ["archive", "label:2", "account:signal"],
        ]]))
        XCTAssertEqual(h.inbox.toast?.message, "Sidebar updated")
        XCTAssertEqual(h.inbox.toast?.canUndo, false)
        try await waitUntil { h.count("spaces.list") == 2 }
    }

    func testALayoutTheEngineRefusesShowsWhy() async throws {
        let (h, spaces, _) = try await start()
        h.script.fail("spaces.setLayout", code: -32014)
        await spaces.saveLayout(order: ["label:1", "inbox"], hidden: [])
        XCTAssertEqual(h.inbox.toast?.message, "That isn’t accepted. Check it and try again.")
    }

    func testMutingAnAccountOrLabel() async throws {
        let (h, spaces, _) = try await start()
        await spaces.setMuted("label:1", true)
        await spaces.setMuted("account:whatsapp", false)
        XCTAssertEqual(dicts(h.server.receivedParams("spaces.update")), dicts([
            ["space_id": "label:1", "muted": true], ["space_id": "account:whatsapp", "muted": false],
        ]))
        try await waitUntil { h.count("spaces.list") >= 2 }
    }

    func testShowInInboxTakesOnlyTheValuesTheEngineTakes() async throws {
        let (h, spaces, _) = try await start()
        await spaces.setShowInInbox("account:signal", "dms")
        await spaces.setShowInInbox("account:signal", "none")
        await spaces.setShowInInbox("account:signal", "")
        await spaces.setShowInInbox("account:signal", "sometimes")
        XCTAssertEqual(dicts(h.server.receivedParams("spaces.update")), dicts([
            ["space_id": "account:signal", "show_in_inbox": "dms"],
            ["space_id": "account:signal", "show_in_inbox": "none"],
        ]), "\"\" and unknown values are never sent")
    }

    // MARK: - The Dock badge

    /// Ruling 36: the Dock badge and the menu bar count the engine's attention_chats on the inbox entry, so showing
    /// another space, a filter, or a page that doesn't hold every chat never changes them.
    func testTheBadgeFollowsTheInboxSpaceNotTheSpaceShown() async throws {
        var bar = SpacesModelTests.bar
        bar[0] = spaceJSON("inbox", chats: 300, unread: 9, attention: 5)
        // The page shown has two unread chats: counting it would say 2, not the engine's 5.
        let (h, spaces, _) = try await start(bar: bar, rooms: [room("!a", ts: 2, unread: 1), room("!b", ts: 1, unread: 3)])
        var badges: [Int] = []
        let watching = spaces.badgeCountPublisher.sink { badges.append($0) }
        defer { watching.cancel() }
        XCTAssertEqual(spaces.badgeCount, 5)
        XCTAssertEqual(badges, [5])

        // Archive, then a filter: the rows change, the badge doesn't.
        h.script.rooms = []
        spaces.select("archive")
        try await waitUntil { h.server.receivedParams("inbox.list").last?["space"] as? String == "archive" }
        try await waitUntil { h.inbox.rows.isEmpty }
        h.inbox.query.filters = [.unread]
        try await waitUntil { h.server.receivedParams("inbox.list").last?["filters"] as? [String] == ["unread"] }
        XCTAssertEqual(spaces.badgeCount, 5)
        XCTAssertEqual(NotificationPolicy.badgeLabel(count: spaces.badgeCount), "5")

        // The engine's count moves (a chat was read): the badge does.
        bar[0] = spaceJSON("inbox", chats: 300, unread: 8, attention: 4)
        h.script.spaces = bar
        h.server.notify(["kind": "read", "room_id": "!x"])
        try await waitUntil { spaces.badgeCount == 4 }
        XCTAssertEqual(badges, [5, 4], "one badge per change of the engine's count, none for switching spaces")

        // No inbox entry (not read yet): no badge.
        h.script.spaces = Array(bar.dropFirst())
        h.server.notify(["kind": "spaces"])
        try await waitUntil { spaces.badgeCount == 0 }
    }

    func testEditingSpacesIsAFlagTheViewsBindTo() async throws {
        let (_, spaces, _) = try await start()
        XCTAssertFalse(spaces.isEditing)
        spaces.isEditing = true
        XCTAssertTrue(spaces.isEditing)
    }

    func testBadgeCountModesUnreadChatsAllChatsAndNone() {
        let spaces = [
            Space(spaceID: "inbox", kind: .builtin, chats: 40, unreadChats: 9, attentionChats: 4),
            Space(spaceID: "archive", kind: .builtin, chats: 10, unreadChats: 2, attentionChats: 0),
        ]
        XCTAssertEqual(SpacesModel.badgeCount(of: spaces, mode: .unreadChats), 4)
        XCTAssertEqual(SpacesModel.badgeCount(of: spaces, mode: .allChats), 9)
        XCTAssertEqual(SpacesModel.badgeCount(of: spaces, mode: .none), 0)
        XCTAssertEqual(NotificationPolicy.badgeLabel(count: SpacesModel.badgeCount(of: spaces, mode: .none)), nil)
    }
}

/// A Space as the engine writes it.
func spaceJSON(_ id: String, kind: String = "builtin", title: String = "", network: String = "", labelID: Int = 0,
               color: Int = 0, icon: String = "", hidden: Bool = false, muted: Bool = false, showInInbox: String = "",
               chats: Int = 0, unread: Int = 0, attention: Int = 0) -> [String: Any] {
    [
        "space_id": id, "kind": kind, "title": title, "network": network, "label_id": labelID, "color": color,
        "icon": icon, "hidden": hidden, "muted": muted, "show_in_inbox": showInInbox, "chats": chats,
        "unread_chats": unread, "attention_chats": attention,
    ]
}
