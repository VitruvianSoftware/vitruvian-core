// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The inbox model against a stand-in engine. The engine's answers come from an `InboxScript` the test edits, and
/// the coalescing window's sleep is one the test opens.
@MainActor
final class InboxModelTests: XCTestCase {
    private var servers: [TestEngineServer] = []

    override func tearDown() async throws {
        for server in servers { server.stop() }
        servers = []
    }

    // MARK: - Harness

    private struct Harness {
        let script: InboxScript
        let server: TestEngineServer
        let launcher: FakeLauncher
        let supervisor: EngineSupervisor
        let app: AppModel
        let inbox: InboxModel
        let sleeps: SleepControl

        func count(_ method: String) -> Int { server.receivedMethods().filter { $0 == method }.count }
    }

    /// An app model on a stand-in engine, an inbox model on that, and the first inbox read done.
    private func start(rooms: [[String: Any]] = [], accounts: [[String: Any]] = [account("whatsapp", "CONNECTED")],
                       autoRelease: Bool = false, failFirstReads: Int = 0,
                       hasTelegramCredentials: @escaping @MainActor () -> Bool = { true }) async throws -> Harness {
        let script = InboxScript(rooms: rooms, accounts: accounts)
        script.failReads = failFirstReads
        let server = try TestEngineServer(handler: script.handle)
        servers.append(server)
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
            credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        let sleeps = SleepControl()
        if autoRelease { await sleeps.releaseAlways() }
        let inbox = InboxModel(appModel: app, hasTelegramCredentials: hasTelegramCredentials, window: 0.1,
                               retryDelay: 2, sleep: { await sleeps.sleep($0) })
        app.start()
        try await waitUntil { inbox.isLoaded && !app.accounts.isEmpty }
        return Harness(script: script, server: server, launcher: launcher, supervisor: supervisor, app: app,
                       inbox: inbox, sleeps: sleeps)
    }

    private func stop(_ harness: Harness) async {
        await harness.app.stop()
    }

    // MARK: - Order and selection

    func testOrderAndSelectionSurviveRefresh() async throws {
        // Not in order, as an engine that sorted nothing would send them.
        let h = try await start(rooms: [
            room("!a", ts: 100), room("!b", ts: 300), room("!c", ts: 200),
        ], autoRelease: true)
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!b", "!c", "!a"], "newest first")

        h.inbox.select("!c")
        XCTAssertEqual(h.app.selectedRoomID, "!c", "the selection lives on the app model")

        // A new message in the oldest chat moves it to the top, and an old chat's row changes.
        h.script.rooms = [room("!a", ts: 400, unread: 1), room("!b", ts: 300), room("!c", ts: 200, unread: 2)]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.inbox.rows.first?.roomID == "!a" }
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!a", "!b", "!c"])
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

    func testRowsWithTheSameTimeKeepAStableOrder() async throws {
        let h = try await start(rooms: [room("!b", ts: 100), room("!a", ts: 100), room("!c", ts: 100)])
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!b", "!a", "!c"], "a tie keeps the engine's order, not the ids'")
        await stop(h)
    }

    /// Chats with no message yet all have time 0. The engine lists them newest created first; re-sorting them by
    /// id would put a chat made a minute ago anywhere among them.
    func testChatsWithNoMessagesKeepTheEnginesOrder() async throws {
        let h = try await start(rooms: [
            room("!x", ts: 50), room("!z-newest", ts: 0), room("!a-older", ts: 0), room("!m-oldest", ts: 0),
        ], autoRelease: true)
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!x", "!z-newest", "!a-older", "!m-oldest"])

        // A refresh in which the engine lists them in another order shows that order.
        h.script.rooms = [room("!x", ts: 50), room("!m-oldest", ts: 0), room("!z-newest", ts: 0)]
        h.server.notify(["kind": "room"])
        try await waitUntil { h.inbox.rows.count == 3 }
        XCTAssertEqual(h.inbox.rows.map(\.roomID), ["!x", "!m-oldest", "!z-newest"])
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

    // MARK: - Reading and muting

    func testToggleReadMarksAnUnreadChatRead() async throws {
        let h = try await start(rooms: [room("!a", ts: 200, unread: 4), room("!b", ts: 100)], autoRelease: true)
        h.inbox.select("!a")
        XCTAssertTrue(h.inbox.canToggleRead)
        h.script.onMarkRead = { [script = h.script] roomID in
            script.rooms = script.rooms.map { $0["room_id"] as? String == roomID ? room(roomID, ts: 200) : $0 }
        }
        await h.inbox.toggleRead()
        XCTAssertEqual(h.server.receivedParams("room.markRead").map { $0["room_id"] as? String }, ["!a"])
        try await waitUntil { h.inbox.selectedRow?.unread == 0 }
        XCTAssertFalse(h.inbox.canToggleRead)
        await stop(h)
    }

    func testToggleReadDoesNothingWhenNothingIsUnread() async throws {
        let h = try await start(rooms: [room("!a", ts: 200), room("!b", ts: 100, unread: 1)])
        // Nothing open.
        XCTAssertFalse(h.inbox.canToggleRead)
        await h.inbox.toggleRead()
        // A read chat open: marking it unread is milestone 4.
        h.inbox.select("!a")
        XCTAssertFalse(h.inbox.canToggleRead)
        await h.inbox.toggleRead()
        XCTAssertEqual(h.count("room.markRead"), 0)
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
        h.server.releaseHeld(with: ["rooms": [room("!a", ts: 100)]])

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
        let inbox = InboxModel(appModel: app, window: 0.1, sleep: { _ in })
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
        firstServer.releaseHeld(with: ["rooms": [room("!old", ts: 100)]])
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
        h.inbox.onReconnect = { reconnected.append($0) }
        for banner in h.inbox.banners { h.inbox.perform(banner) }
        XCTAssertEqual(reconnected, ["whatsapp", "signal", "gmessages"])

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
        let inbox = InboxModel(appModel: AppModel(supervisor: supervisor))
        XCTAssertFalse(inbox.showsAddNetwork, "an engine that has not answered yet has not said there are no accounts")
        XCTAssertFalse(inbox.isLoaded)
    }
}

// MARK: - Fixtures

/// What the stand-in engine answers, which a test edits as the "engine" changes its mind.
final class InboxScript: @unchecked Sendable {
    private let lock = NSLock()
    private var _rooms: [[String: Any]]
    private var _accounts: [[String: Any]]
    private var _hold = false
    private var _holdAccounts = false
    private var _failReads = 0
    private var _onMarkRead: (@Sendable (String) -> Void)?

    init(rooms: [[String: Any]], accounts: [[String: Any]]) {
        _rooms = rooms
        _accounts = accounts
    }

    var rooms: [[String: Any]] {
        get { lock.withLock { _rooms } }
        set { lock.withLock { _rooms = newValue } }
    }

    var accounts: [[String: Any]] {
        get { lock.withLock { _accounts } }
        set { lock.withLock { _accounts = newValue } }
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

    private func shouldFailRead() -> Bool {
        lock.withLock {
            guard _failReads > 0 else { return false }
            _failReads -= 1
            return true
        }
    }

    var onMarkRead: (@Sendable (String) -> Void)? {
        get { lock.withLock { _onMarkRead } }
        set { lock.withLock { _onMarkRead = newValue } }
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return holdAccounts ? .later : .result(["accounts": accounts])
        case "inbox.list":
            if shouldFailRead() { return .error(code: -32000, message: "example failure") }
            return holdInbox ? .later : .result(["rooms": rooms])
        case "room.markRead":
            if let id = params?["room_id"] as? String { onMarkRead?(id) }
            return .result([String: Any]())
        default: return .result([String: Any]())
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

/// An InboxRow as the engine writes it.
func room(_ id: String, ts: Int64, unread: Int = 0, muted: Bool = false, network: String = "whatsapp",
          name: String? = nil, preview: String = "Hello", kind: String = "text") -> [String: Any] {
    [
        "room_id": id, "network": network, "name": name ?? "Chat \(id)", "avatar_path": "", "is_direct": true,
        "last_ts": ts, "preview": preview, "preview_kind": kind, "preview_mine": false, "unread": unread,
        "muted": muted,
    ]
}

/// An Account as the engine writes it.
func account(_ network: String, _ state: String, error: String = "", notStarted: String = "") -> [String: Any] {
    [
        "network": network, "display_name": "\(network) display", "flows": ["qr"], "state": state, "error": error,
        "remote_name": "", "not_started": notStarted,
    ]
}
